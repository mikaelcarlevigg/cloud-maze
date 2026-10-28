"""Cloud Maze in 20 seconds: one authorized client, one attacker, one maze.

    python3 demo.py

Everything runs locally. No AWS account and no extra packages are needed.
"""
from __future__ import annotations

import argparse
import json
import secrets
import threading
import time
import urllib.error
import urllib.request

from client import USER_AGENT, Client
from maze import Engine, Maze
from server import CloudMazeServer

START = time.time()
print_lock = threading.Lock()


def say(who: str, text: str) -> None:
    with print_lock:
        print(f"  {time.time() - START:5.1f} s  {who:<10} {text}")


def rel(t: float) -> str:
    return f"{t - START:.1f} s"


def attacker_get(base: str, path: str) -> tuple[int, str]:
    request = urllib.request.Request(base + path, headers={"User-Agent": "curl/8.5.0"})
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the Cloud Maze demo.")
    parser.add_argument("--interval", type=float, default=4.0, help="seconds between moves")
    parser.add_argument("--overlap", type=float, default=1.5, help="seconds both paths work")
    parser.add_argument("--duration", type=float, default=20.0, help="how long the demo runs")
    args = parser.parse_args()

    maze = Maze("orders-api", args.interval, args.overlap)
    client_key, map_key = secrets.token_bytes(16), secrets.token_bytes(16)
    alarms: list[dict] = []

    def on_alarm(e: dict) -> None:
        alarms.append(e)
        text = {"old_path": "old path used", "decoy": "decoy used",
                "map_denied": "unauthorized attempt to fetch the map"}[e["kind"]]
        say("ALARM", f"{text}: {e['path']}")
        if e["window"]:
            a, b = e["window"]
            say("TRACE", f"path {e['path']} only existed {rel(a)} to {rel(b)}, so that is when it leaked")

    server = CloudMazeServer(("127.0.0.1", 0), maze, {"partner-1": client_key}, map_key, on_alarm)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def on_move(kind: str, path) -> None:
        if kind == "opened":
            say("ENGINE", f"opens new path {path.id} and publishes the map")
        else:
            say("ENGINE", f"closes {path.id}, it is now a tripwire")

    print("\nCloud Maze, local demo")
    print(f"The path moves every {args.interval:g} s, with {args.overlap:g} s of overlap.\n")
    say("ENGINE", f"the first path is {maze.current.id}")
    engine = Engine(maze, on_move)
    engine.start()

    stop = threading.Event()
    stats = {"calls": 0, "ok": 0, "failed": 0, "switches": 0}
    stolen: list[int] = []

    def run_client() -> None:
        client = Client(base, "partner-1", client_key, map_key)
        last = None
        while not stop.is_set():
            stats["calls"] += 1
            try:
                client.orders()
                stats["ok"] += 1
                path = client.map["path"]
                if path != last:
                    if last:
                        stats["switches"] += 1
                    say("CLIENT", f"uses path {path} from the map, got the orders")
                    last = path
            except Exception as error:
                stats["failed"] += 1
                say("CLIENT", f"FAILED: {error}")
            stop.wait(0.25)

    def run_attacker() -> None:
        stop.wait(1.0)
        leaked = maze.current.id
        decoy = sorted(maze.decoys)[0]
        say("ATTACKER", f"finds path {leaked} in a leaked log and saves it")
        say("ATTACKER", f"finds path {decoy} in a config file (a planted decoy)")
        status, _ = attacker_get(base, f"/v1/{leaked}/orders")
        say("ATTACKER", f"tries {leaked} right away: answer {status}, the path works")
        say("ATTACKER", "prepares the attack ...")

        stop.wait(max(0.0, START + 2.2 * args.interval - time.time()))
        status, body = attacker_get(base, f"/v1/{leaked}/orders")
        stolen.append(len(json.loads(body).get("orders", [])))
        say("ATTACKER", f"attacks through {leaked}: answer {status}, {body}")

        stop.wait(1.0)
        status, body = attacker_get(base, f"/v1/{decoy}/orders")
        stolen.append(len(json.loads(body).get("orders", [])))
        say("ATTACKER", f"tries {decoy}: answer {status}, {body}")

        stop.wait(1.0)
        status, _ = attacker_get(base, "/map")
        say("ATTACKER", f"tries to fetch the map without keys: answer {status}")

        guess = secrets.token_hex(3)
        status, _ = attacker_get(base, f"/v1/{guess}/orders")
        say("ATTACKER", f"guesses a path, {guess}: answer {status}")

    threads = [threading.Thread(target=run_client, daemon=True),
               threading.Thread(target=run_attacker, daemon=True)]
    for t in threads:
        t.start()
    stop.wait(args.duration)
    stop.set()
    engine.stop()
    for t in threads:
        t.join(timeout=6)
    server.shutdown()

    false_alarms = sum(1 for a in alarms if a["agent"] == USER_AGENT)
    print("\nResult")
    print(f"  Authorized client: {stats['ok']} of {stats['calls']} requests succeeded, "
          f"{stats['failed']} failed, switched paths {stats['switches']} times")
    print(f"  Alarms:            {len(alarms)}, of which {false_alarms} false alarms")
    print(f"  Attacker:          got {sum(stolen)} orders through old paths and decoys")
    print(f"  Map lifetime:      at most {args.interval + args.overlap:g} s\n")


if __name__ == "__main__":
    main()
