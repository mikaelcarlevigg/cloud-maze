"""Tests for the three rules of the maze.  Run with:  python3 -m unittest"""
from __future__ import annotations

import secrets
import threading
import time
import unittest
import urllib.request

from client import Client, MapError
from maze import Engine, Maze
from server import CloudMazeServer


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class MazeRules(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.maze = Maze("orders-api", interval=10, overlap=3, clock=self.clock)

    def test_old_path_works_during_overlap(self) -> None:
        old = self.maze.current.id
        new = self.maze.open_new().id
        self.assertEqual(self.maze.status(old), "open")
        self.assertEqual(self.maze.status(new), "open")

    def test_old_path_becomes_tripwire_after_close(self) -> None:
        old = self.maze.current.id
        self.maze.open_new()
        self.clock.now += 3
        self.maze.close_previous()
        self.assertEqual(self.maze.status(old), "closed")
        closed = self.maze.closed_path(old)
        self.assertEqual((closed.opened, closed.closed), (1000.0, 1003.0))

    def test_there_is_always_an_open_path(self) -> None:
        for _ in range(50):
            self.assertEqual(self.maze.status(self.maze.current.id), "open")
            self.maze.open_new()
            self.assertEqual(self.maze.status(self.maze.current.id), "open")
            self.maze.close_previous()

    def test_map_refresh_falls_inside_overlap(self) -> None:
        doc = self.maze.map()
        next_move = self.maze.current.opened + 10
        self.assertGreater(doc["refresh_at"], next_move)
        self.assertLess(doc["refresh_at"], doc["valid_until"])
        self.assertEqual(doc["valid_until"], next_move + 3)

    def test_decoys_and_unknown_paths(self) -> None:
        self.assertEqual(self.maze.status(next(iter(self.maze.decoys))), "decoy")
        self.assertEqual(self.maze.status("ffffff0"), "unknown")

    def test_overlap_must_be_shorter_than_interval(self) -> None:
        with self.assertRaises(ValueError):
            Maze("x", interval=2, overlap=2)


class EndToEnd(unittest.TestCase):
    def setUp(self) -> None:
        self.maze = Maze("orders-api", interval=1.0, overlap=0.4)
        self.key, self.map_key = secrets.token_bytes(16), secrets.token_bytes(16)
        self.server = CloudMazeServer(("127.0.0.1", 0), self.maze, {"p1": self.key}, self.map_key)
        self.base = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.engine = Engine(self.maze)
        self.engine.start()

    def tearDown(self) -> None:
        self.engine.stop()
        self.server.shutdown()
        self.server.server_close()

    def test_authorized_client_never_fails_across_moves(self) -> None:
        client = Client(self.base, "p1", self.key, self.map_key)
        paths = set()
        deadline = time.time() + 4
        while time.time() < deadline:
            self.assertEqual(len(client.orders()), 2)
            paths.add(client.map["path"])
            time.sleep(0.05)
        self.assertGreaterEqual(len(paths), 3)
        self.assertEqual(self.server.alarms, [])

    def test_wrong_key_is_refused_and_raises_alarm(self) -> None:
        client = Client(self.base, "p1", secrets.token_bytes(16), self.map_key)
        with self.assertRaises(MapError):
            client.fetch_map()
        self.assertEqual(self.server.alarms[0]["kind"], "map_denied")

    def test_forged_map_is_rejected(self) -> None:
        client = Client(self.base, "p1", self.key, secrets.token_bytes(16))
        with self.assertRaises(MapError):
            client.fetch_map()

    def test_stale_path_gets_nothing_and_raises_alarm(self) -> None:
        stale = self.maze.current.id
        while self.maze.status(stale) != "closed":
            time.sleep(0.05)
        with urllib.request.urlopen(f"{self.base}/v1/{stale}/orders") as response:
            self.assertIn(b'"orders": []', response.read())
        self.assertEqual(self.server.alarms[-1]["kind"], "old_path")
        self.assertIsNotNone(self.server.alarms[-1]["window"])


if __name__ == "__main__":
    unittest.main()
