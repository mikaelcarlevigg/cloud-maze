"""An authorized client: fetches the map, verifies it, and always uses the current path.

Stand-in for the small client library described in the concept.

Run it against a running server with the command server.py prints.
"""
from __future__ import annotations

import argparse
import hmac
import json
import time
import urllib.error
import urllib.request
from typing import Optional

from server import canonical, sign

USER_AGENT = "cloudmaze-client"


class MapError(Exception):
    pass


class Client:
    def __init__(self, base_url: str, client_id: str, key: bytes, map_key: bytes):
        self.base_url = base_url.rstrip("/")
        self.client_id = client_id
        self.key = key
        self.map_key = map_key
        self.map: Optional[dict] = None

    def _get(self, path: str, headers: Optional[dict] = None) -> tuple[int, dict]:
        request = urllib.request.Request(self.base_url + path,
                                         headers={"User-Agent": USER_AGENT, **(headers or {})})
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                return response.status, json.loads(response.read())
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read() or b"{}")

    def fetch_map(self) -> dict:
        stamp = str(time.time())
        status, body = self._get("/map", {
            "X-Client": self.client_id,
            "X-Time": stamp,
            "X-Signature": sign(self.key, f"{self.client_id}:{stamp}"),
        })
        if status != 200:
            raise MapError(f"map service answered {status}")
        doc = body["map"]
        if not hmac.compare_digest(sign(self.map_key, canonical(doc)), body["signature"]):
            raise MapError("map signature does not match, refusing to use it")
        self.map = doc
        return doc

    def orders(self) -> list:
        if self.map is None or time.time() >= self.map["refresh_at"]:
            self.fetch_map()
        status, body = self._get(f"/v1/{self.map['path']}/orders")
        if status == 404:
            # The path moved earlier than expected: get a new map and try once more.
            self.fetch_map()
            status, body = self._get(f"/v1/{self.map['path']}/orders")
        if status != 200:
            raise RuntimeError(f"orders answered {status}")
        return body["orders"]


def main() -> None:
    parser = argparse.ArgumentParser(description="Run an authorized Cloud Maze client.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--client", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--map-key", required=True)
    parser.add_argument("--every", type=float, default=1.0, help="seconds between calls")
    args = parser.parse_args()

    client = Client(args.url, args.client, bytes.fromhex(args.key), bytes.fromhex(args.map_key))
    last_path = None
    while True:
        try:
            orders = client.orders()
            path = client.map["path"]
            note = "  <- new path from the map" if last_path and path != last_path else ""
            print(f"{time.strftime('%H:%M:%S')}  OK  /v1/{path}/orders  {len(orders)} orders{note}", flush=True)
            last_path = path
        except Exception as error:
            print(f"{time.strftime('%H:%M:%S')}  ERROR  {error}", flush=True)
        time.sleep(args.every)


if __name__ == "__main__":
    main()
