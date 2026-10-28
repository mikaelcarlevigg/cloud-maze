"""The maze: which paths are open, which are closed, and which are decoys.

Stand-in for the DynamoDB table that holds the maze state in the AWS design.
"""
from __future__ import annotations

import secrets
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional


def new_path_id() -> str:
    return secrets.token_hex(3)


@dataclass
class Path:
    id: str
    opened: float
    closed: Optional[float] = None


class Maze:
    """Keeps the three rules from the concept:

    1. There is always an open path for authorized clients: a new path opens
       before the old one closes, and both work during the overlap.
    2. Every map has a best-before time.
    3. Closed paths and decoys are remembered so that using them raises an alarm.
    """

    def __init__(self, service: str, interval: float, overlap: float,
                 decoys: int = 3, clock: Callable[[], float] = time.time):
        if overlap >= interval:
            raise ValueError("overlap must be shorter than interval")
        self.service = service
        self.interval = interval
        self.overlap = overlap
        self.clock = clock
        self._lock = threading.Lock()
        self.current = Path(new_path_id(), clock())
        self.previous: Optional[Path] = None
        self.closed: dict[str, Path] = {}
        self.decoys = {new_path_id() for _ in range(decoys)}
        self.version = 1

    def open_new(self) -> Path:
        """Steps 1 and 2: open a new path and publish it on the map.

        The previous path stays open until close_previous() is called.
        """
        with self._lock:
            if self.previous:
                self._close(self.previous)
            self.previous = self.current
            self.current = Path(new_path_id(), self.clock())
            self.version += 1
            return self.current

    def close_previous(self) -> Optional[Path]:
        """Step 4: close the previous path once the overlap is over."""
        with self._lock:
            old = self.previous
            if old:
                self._close(old)
                self.previous = None
            return old

    def _close(self, path: Path) -> None:
        path.closed = self.clock()
        self.closed[path.id] = path

    def status(self, path_id: str) -> str:
        with self._lock:
            if path_id == self.current.id or (self.previous and path_id == self.previous.id):
                return "open"
            if path_id in self.closed:
                return "closed"
            if path_id in self.decoys:
                return "decoy"
            return "unknown"

    def closed_path(self, path_id: str) -> Optional[Path]:
        with self._lock:
            return self.closed.get(path_id)

    def map(self) -> dict:
        """The map an authorized client receives.

        The client should fetch a new map shortly after the next move. The old
        path keeps working until valid_until, which covers any delay.
        """
        with self._lock:
            next_move = self.current.opened + self.interval
            return {
                "service": self.service,
                "path": self.current.id,
                "version": self.version,
                "refresh_at": round(next_move + self.overlap * 0.25, 3),
                "valid_until": round(next_move + self.overlap, 3),
            }


class Engine(threading.Thread):
    """The maze engine: moves the walls on a schedule.

    Stand-in for EventBridge Scheduler plus the Step Functions workflow
    open -> publish -> wait -> close.
    """

    def __init__(self, maze: Maze, on_event: Callable[[str, Path], None] = lambda *_: None):
        super().__init__(daemon=True)
        self.maze = maze
        self.on_event = on_event
        self._stop = threading.Event()

    def run(self) -> None:
        m = self.maze
        while True:
            next_move = m.current.opened + m.interval
            if self._stop.wait(max(0.0, next_move - m.clock())):
                break
            new = m.open_new()
            self.on_event("opened", new)
            if self._stop.wait(m.overlap):
                break
            old = m.close_previous()
            if old:
                self.on_event("closed", old)

    def stop(self) -> None:
        self._stop.set()
