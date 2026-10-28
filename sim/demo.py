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
        text = {"old_path": "gammal väg använd", "decoy": "lockbete använt",
                "map_denied": "obehörig försökte hämta kartan"}[e["kind"]]
        say("LARM", f"{text}: {e['path']}")
        if e["window"]:
            a, b = e["window"]
            say("SPÅRNING", f"vägen {e['path']} fanns bara {rel(a)} till {rel(b)}, så läckan skedde då")

    server = CloudMazeServer(("127.0.0.1", 0), maze, {"partner-1": client_key}, map_key, on_alarm)
    base = f"http://127.0.0.1:{server.server_address[1]}"
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def on_move(kind: str, path) -> None:
        if kind == "opened":
            say("MOTOR", f"öppnar ny väg {path.id} och publicerar kartan")
        else:
            say("MOTOR", f"stänger {path.id}, den är nu en snubbeltråd")

    print("\nCloud Maze, lokal demo")
    print(f"Vägen byts var {args.interval:g}:e sekund, med {args.overlap:g} s överlapp.\n")
    say("MOTOR", f"första vägen är {maze.current.id}")
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
                    say("KLIENT", f"använder väg {path} enligt kartan, fick ordrarna")
                    last = path
            except Exception as error:
                stats["failed"] += 1
                say("KLIENT", f"MISSLYCKADES: {error}")
            stop.wait(0.25)

    def run_attacker() -> None:
        stop.wait(1.0)
        leaked = maze.current.id
        decoy = sorted(maze.decoys)[0]
        say("ANGRIPARE", f"hittar väg {leaked} i en läckt logg och sparar den")
        say("ANGRIPARE", f"hittar väg {decoy} i en konfigurationsfil (ett planterat lockbete)")
        status, _ = attacker_get(base, f"/v1/{leaked}/orders")
        say("ANGRIPARE", f"testar {leaked} direkt: svar {status}, vägen fungerar")
        say("ANGRIPARE", "förbereder angreppet ...")

        stop.wait(max(0.0, START + 2.2 * args.interval - time.time()))
        status, body = attacker_get(base, f"/v1/{leaked}/orders")
        stolen.append(len(json.loads(body).get("orders", [])))
        say("ANGRIPARE", f"angriper via {leaked}: svar {status}, {body}")

        stop.wait(1.0)
        status, body = attacker_get(base, f"/v1/{decoy}/orders")
        stolen.append(len(json.loads(body).get("orders", [])))
        say("ANGRIPARE", f"provar {decoy}: svar {status}, {body}")

        stop.wait(1.0)
        status, _ = attacker_get(base, "/map")
        say("ANGRIPARE", f"försöker hämta kartan utan nycklar: svar {status}")

        guess = secrets.token_hex(3)
        status, _ = attacker_get(base, f"/v1/{guess}/orders")
        say("ANGRIPARE", f"gissar en väg, {guess}: svar {status}")

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
    print("\nResultat")
    print(f"  Behörig klient:   {stats['ok']} av {stats['calls']} anrop lyckades, "
          f"{stats['failed']} misslyckades, bytte väg {stats['switches']} gånger")
    print(f"  Larm:             {len(alarms)}, varav {false_alarms} falsklarm")
    print(f"  Angriparen:       fick {sum(stolen)} ordrar via gamla vägar och lockbeten")
    print(f"  Kartans livslängd: högst {args.interval + args.overlap:g} s\n")


if __name__ == "__main__":
    main()
