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
        self.crystal = data.get("emerald", "").startswith("johto_")
        self.grid = {k: [int(v) for row in arr for v in row] for k, arr in meta.items()
                     if k in ("collision", "water", "elevation", "ledge", "dirblock", "counter", "grass", "whirl", "waterfall", "slide", "current", "climb") and arr}
        self.doors = {}
        for door in data.get("warps", []):
            self.doors.setdefault(tuple(door["at"]), door)
        self.blockers = {tuple(o["at"]): o["kind"] for o in data.get("objects", [])
                         if o.get("kind") in ("cut", "boulder", "rock", "berry_tree")}

    def get(self, key, x, y):
        a = self.grid.get(key)
        return a[y * self.w + x] if a else 0


class Routes:
    def __init__(self, regions=("kanto", "sevii")):
        self.regions = regions
        self.fields = {}
        for region in regions:
            if region in ("hoenn","sinnoh"):
                native = "hoenn_native" if region=="hoenn" else "platinum_native"
                for path in (ROOT / "content" / native / "maps").glob("*.json"):
                    data = read(path)
                    self.fields[path.stem] = Field(data,data["physics"])
                continue
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
        self.elevation = 0

    def projection(self, dest):
        if self.regions == ("johto",) and dest.get("map") == "johto_pokecenter_2f":
            return None  # The cable-club upstairs always returns to the same local Center.
        if dest.get("recall_passage") in self.history:
            dest = self.history[dest["recall_passage"]]
        if dest.get("region") in self.regions and dest.get("map") in self.fields:
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
            cliff = f.get("climb",nx,ny)
            if cliff:
                if 431 not in self.field_moves or (dx and cliff!=76) or (dy and cliff!=75): continue
                while 0<=nx<f.w and 0<=ny<f.h and f.get("climb",nx,ny)==cliff:
                    nx,ny=nx+dx,ny+dy
                if 0<=nx<f.w and 0<=ny<f.h and not f.get("collision",nx,ny):
                    edges.append((key,(mid,nx,ny)))
                continue
            if f.crystal or f.data.get("emerald_original") or f.data.get("platinum_native"):
                if f.get("whirl",nx,ny) and 250 not in self.field_moves and (mid,nx,ny) not in self.cleared:
                    continue
                if key!="d" and (f.get("waterfall",nx,ny) or f.get("waterfall",x,y)):
                    if key!="u" or not f.get("waterfall",nx,ny) or not {57,127} <= self.field_moves: continue
                    # The A action ascends the full cascade and one accessible cell of bank.
                    top=ny
                    while top>0 and f.get("waterfall",nx,top-1): top-=1
                    if top>0 and (f.get("water",nx,top-1) or not f.get("collision",nx,top-1)): top-=1
                    edges.append((key,(mid,nx,top)))
                    continue
            jump = f.get("ledge", nx, ny)
            if jump:
                if jump & bit:
                    for offset in (range(1, 5) if f.crystal else (1,)):
                        lx, ly = nx + dx * offset, ny + dy * offset
                        if 0 <= lx < f.w and 0 <= ly < f.h and not f.get("collision", lx, ly):
                            nx, ny = lx, ly
                            break
                    else:
                        continue
                elif not f.crystal or not ((dx and jump in (1,2)) or (dy and jump in (4,8))):
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
            surfable = f.crystal and f.get("water", nx, ny) and 57 in self.field_moves
            if f.get("collision", nx, ny) and not surfable and (nx, ny) not in f.blockers and (mid, nx, ny) not in self.cleared:
                continue
            step = f.doors.get((nx, ny), {})
            dest = step["to"] if step and step.get("trigger", "step") == "step" else (mid, nx, ny)
            if isinstance(dest,tuple) and getattr(self,"pillar_clean",False):
                lower = f.data.get("mechanisms",{}).get("hole_return")
                if lower and f.data["physics"]["behavior"][ny][nx] in (0x66,0xd2):
                    if (nx,ny) not in getattr(f,"repaired_floor",()):
                        dest={"map":lower,"region":"hoenn","at":[nx,ny]}
            edges.append((key, dest))
        if f.data.get("emerald_original"):
            forced = f.get("current", x, y)
            downstream = [edge for edge in edges if VECTORS[edge[0]][2] == forced]
            if downstream:
                return downstream
        return edges

    def path(self, start, goals):
        # A multi-level tile keeps the walker's previous height. Two people on the
        # same 119 bridge square may therefore have different legal next steps.
        hoenn = self.regions == ("hoenn",)
        first = (*start, self.elevation if hoenn and self.fields[start[0]].get("elevation",*start[1:])==15 else 0)
        pending = deque([first])
        prev = {first: None}
        while pending:
            node = pending.popleft()
            here = node[:3]
            if here in goals:
                steps = []
                while prev[node] is not None:
                    before, key = prev[node]
                    steps.append((before[:3], key, node[:3]))
                    node = before
                return steps[::-1]
            for key, dest in self.edges(here):
                passage = isinstance(dest, dict)
                if passage:
                    dest = self.projection(dest)
                if (dest is None or (here, key) in self.denied or
                        dest[1:] in self.occupied.get(dest[0], ())):
                    continue
                layer = 0
                if hoenn:
                    origin = self.fields[here[0]].get("elevation",*here[1:])
                    height = self.fields[dest[0]].get("elevation",*dest[1:])
                    if origin == 15: origin = node[3]
                    if height == 15: layer = origin
                    elif not passage and node[3] and height not in (0, origin):
                        shore = (57 in self.field_moves and {height,origin} == {1,3} and
                                 bool(self.fields[dest[0]].get("water",*dest[1:])) == (height==1))
                        if not shore: continue
                nxt = (*dest,layer)
                if nxt not in prev:
                    prev[nxt] = (node, key)
                    pending.append(nxt)
        raise ValueError(f"No walk from {start} to {goals}")
