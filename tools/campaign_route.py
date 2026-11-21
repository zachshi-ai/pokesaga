"""Plan controller inputs against the shipped FireRed/LeafGreen collision and warp tables."""
import json
from collections import deque
from functools import lru_cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VECTORS = {"u": (0, -1, 1, 2), "d": (0, 1, 2, 1), "l": (-1, 0, 8, 4), "r": (1, 0, 4, 8)}
NAMES = {"up": "u", "down": "d", "left": "l", "right": "r"}


def read(path):
    return json.loads(path.read_text())


class Field:
    def __init__(self, data, meta):
        self.data = data
        self.w, self.h = meta.get("size", data["size"])
        self.grid = {k: [int(v) for row in arr for v in row] for k, arr in meta.items()
                     if k in ("collision", "water", "elevation", "ledge", "dirblock", "counter") and arr}
        self.doors = {}
        for door in data.get("warps", []):
            self.doors.setdefault(tuple(door["at"]), door)
        self.blockers = {tuple(o["at"]): o["kind"] for o in data.get("objects", [])
                         if o.get("kind") in ("cut", "boulder", "rock", "berry_tree")}

    def get(self, key, x, y):
        a = self.grid.get(key)
        return a[y * self.w + x] if a else 0


class Routes:
    def __init__(self):
        self.fields = {}
        for region in ("kanto", "sevii"):
            for path in (ROOT / "content/regions" / region / "maps").glob("*.json"):
                data = read(path)
                meta_path = ROOT / "content/emerald_maps" / (str(data.get("emerald", "")) + ".json")
                if meta_path.is_file():
                    self.fields[path.stem] = Field(data, read(meta_path))
        self.denied = set()
        self.occupied = {}
        self.history = {}
        self.cleared = set()
        self.field_moves = frozenset()

    def projection(self, dest):
        if dest.get("recall_passage") in self.history:
            dest = self.history[dest["recall_passage"]]
        if dest.get("region") in ("kanto", "sevii") and dest.get("map") in self.fields:
            return (dest["map"], *map(int, dest["at"]))
        return None

    @lru_cache(maxsize=300000)
    def edges(self, loc):
        mid, x, y = loc
        f = self.fields[mid]
        edges = []
        for key, (dx, dy, bit, reverse) in VECTORS.items():
            nx, ny = x + dx, y + dy
            door = f.doors.get((x, y), {})
            ahead = f.doors.get((nx, ny), {})
            if NAMES.get(door.get("trigger")) == key or (key == "u" and ahead.get("trigger") == "door"):
                row = door if NAMES.get(door.get("trigger")) == key else ahead
                edges.append((key, row["to"]))
                continue
            if not (0 <= nx < f.w and 0 <= ny < f.h):
                continue
            jump = f.get("ledge", nx, ny)
            if jump:
                if not jump & bit:
                    continue
                nx, ny = nx + dx, ny + dy
                if not (0 <= nx < f.w and 0 <= ny < f.h):
                    continue
            if not jump:
                if f.get("dirblock", nx, ny) & bit or f.get("dirblock", x, y) & reverse:
                    continue
                a, b = f.get("elevation", x, y), f.get("elevation", nx, ny)
                if a not in (0, 15) and b not in (0, 15, a) and {a, b} != {1, 3}:
                    continue
            if f.get("water", nx, ny) and 57 not in self.field_moves:
                continue
            required = {"cut": 15, "rock": 249, "boulder": 70}.get(f.blockers.get((nx, ny)))
            if required and required not in self.field_moves and (mid, nx, ny) not in self.cleared:
                continue
            if f.get("collision", nx, ny) and (nx, ny) not in f.blockers and (mid, nx, ny) not in self.cleared:
                continue
            step = f.doors.get((nx, ny), {})
            dest = step["to"] if step and step.get("trigger", "step") == "step" else (mid, nx, ny)
            edges.append((key, dest))
        return edges

    def path(self, start, goals):
        pending = deque([start])
        prev = {start: None}
        while pending:
            here = pending.popleft()
            if here in goals:
                steps = []
                while prev[here] is not None:
                    before, key = prev[here]
                    steps.append((before, key, here))
                    here = before
                return steps[::-1]
            for key, dest in self.edges(here):
                if isinstance(dest, dict):
                    dest = self.projection(dest)
                if (dest is None or dest in prev or (here, key) in self.denied or
                        dest[1:] in self.occupied.get(dest[0], ())):
                    continue
                prev[dest] = (here, key)
                pending.append(dest)
        raise ValueError(f"No walk from {start} to {goals}")
