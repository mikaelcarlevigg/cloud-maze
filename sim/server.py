"""A local stand-in for the AWS side of Cloud Maze.

    /map                  The map service. Requires a signed request.
                          (AWS: API Gateway with mTLS or SigV4, map signed by KMS.)
    /v1/<path>/orders     The protected service behind the rotating path.
                          (AWS: CloudFront + WAF + API Gateway.)

Requests to closed paths and decoys get a plausible, empty answer and raise an
alarm. (AWS: a decoy Lambda that reports to CloudWatch and Security Hub.)

Run it on its own with:  python3 server.py
"""
from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

from maze import Engine, Maze

ORDERS = [
    {"id": "A-1001", "customer": "Nordvind AB", "amount_sek": 12400},
    {"id": "A-1002", "customer": "Fjällkraft AB", "amount_sek": 3150},
]
MAX_CLOCK_SKEW = 30


def sign(key: bytes, message: str) -> str:
    return hmac.new(key, message.encode(), hashlib.sha256).hexdigest()


def canonical(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"))


class CloudMazeServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, maze: Maze, clients: dict[str, bytes], map_key: bytes,
                 on_alarm: Callable[[dict], None] = lambda _: None):
        super().__init__(address, Handler)
        self.maze = maze
        self.clients = clients
        self.map_key = map_key
        self.on_alarm = on_alarm
        self.alarms: list[dict] = []
        self._alarm_lock = threading.Lock()

    def alarm(self, kind: str, path_id: str, source: str, agent: str,
              window: Optional[tuple[float, float]] = None) -> None:
        event = {"time": time.time(), "kind": kind, "path": path_id,
                 "source": source, "agent": agent, "window": window}
        with self._alarm_lock:
            self.alarms.append(event)
        self.on_alarm(event)


class Handler(BaseHTTPRequestHandler):
    server: CloudMazeServer

    def log_message(self, *args) -> None:
        pass

    def send_json(self, status: int, body: dict) -> None:
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self) -> None:
        if self.path == "/map":
            return self.serve_map()
        match = re.fullmatch(r"/v1/([0-9a-f]+)/orders", self.path)
        if match:
            return self.serve_orders(match.group(1))
        self.send_json(404, {"error": "not found"})

    def serve_map(self) -> None:
        client = self.headers.get("X-Client", "")
        stamp = self.headers.get("X-Time", "")
        signature = self.headers.get("X-Signature", "")
        key = self.server.clients.get(client)
        try:
            fresh = abs(time.time() - float(stamp)) < MAX_CLOCK_SKEW
        except ValueError:
            fresh = False
        if not key or not fresh or not hmac.compare_digest(sign(key, f"{client}:{stamp}"), signature):
            self.server.alarm("map_denied", "-", self.client_address[0], self.headers.get("User-Agent", ""))
            return self.send_json(401, {"error": "unauthorized"})
        doc = self.server.maze.map()
        self.send_json(200, {"map": doc, "signature": sign(self.server.map_key, canonical(doc))})

    def serve_orders(self, path_id: str) -> None:
        maze = self.server.maze
        status = maze.status(path_id)
        if status == "open":
            return self.send_json(200, {"orders": ORDERS})
        if status in ("closed", "decoy"):
            closed = maze.closed_path(path_id)
            window = (closed.opened, closed.closed) if closed and closed.closed else None
            self.server.alarm("old_path" if status == "closed" else "decoy", path_id,
                              self.client_address[0], self.headers.get("User-Agent", ""), window)
            # Look plausible, give nothing away.
            return self.send_json(200, {"orders": []})
        self.send_json(404, {"error": "not found"})


def main() -> None:
    parser = argparse.ArgumentParser(description="Run a local Cloud Maze server.")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--interval", type=float, default=20, help="seconds between moves")
    parser.add_argument("--overlap", type=float, default=5, help="seconds both paths work")
    args = parser.parse_args()

    maze = Maze("orders-api", args.interval, args.overlap)
    client_key = secrets.token_hex(16)
    map_key = secrets.token_hex(16)

    def show_alarm(e: dict) -> None:
        text = {"old_path": "gammal väg", "decoy": "lockbete", "map_denied": "nekad karta"}[e["kind"]]
        print(f"  LARM    {text:<12} väg {e['path']}  från {e['source']}", flush=True)

    server = CloudMazeServer(("127.0.0.1", args.port), maze, {"partner-1": bytes.fromhex(client_key)},
                             bytes.fromhex(map_key), on_alarm=show_alarm)
    base = f"http://127.0.0.1:{args.port}"

    def show_move(kind: str, path) -> None:
        if kind == "opened":
            print(f"  ÖPPNAD  {base}/v1/{path.id}/orders", flush=True)
        else:
            print(f"  STÄNGD  /v1/{path.id}/orders  (nu en snubbeltråd)", flush=True)

    Engine(maze, show_move).start()
    print(f"Cloud Maze körs på {base}")
    print(f"Väg just nu:  {base}/v1/{maze.current.id}/orders")
    print(f"Lockbeten:    {', '.join(sorted(maze.decoys))}")
    print("\nKör en behörig klient i ett annat fönster:")
    print(f"  python3 client.py --url {base} --client partner-1 --key {client_key} --map-key {map_key}")
    print("\nProva att vara angripare: kopiera en väg nu, vänta tills den stängts och kör curl mot den.\n", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nAvslutar.")


if __name__ == "__main__":
    main()
