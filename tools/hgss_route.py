"""Resolve the same HGSS terrain, doors and event anchors used by the Android field."""
import base64
import json
import struct

from campaign_route import ROOT, Field, Routes


def read(path):
    return json.loads(path.read_text())


class NativeField(Field):
    def __init__(self, old, table, bindings, permissions):
        self.data = {**old, "warps":table["warps"], "spawn":table["spawn"], "size":table["size"]}
        self.w, self.h = table["size"]
        self.crystal = True
        self.doors = {tuple(r["at"]):r for r in table["warps"]}
        self.blockers = {}
        self.header = table["header"]
        self.bindings = bindings
        self.old_size = table["legacy_size"]
        self.conversion = base64.b64decode(table["legacy_xy"])
        self.spawn = tuple(table["spawn"])
        self.grid = {}
        words = list(struct.iter_unpack("<H", base64.b64decode(table["terrain"])))
        self.grid["collision"] = bytearray((w & 32768) != 0 for w, in words)
        behaviors = bytes(w & 255 for w, in words)
        cascades = bytearray(b==19 or (b==34 and i+self.w<len(behaviors) and behaviors[i+self.w]==19)
                             for i,b in enumerate(behaviors))
        self.grid["water"] = bytearray(cascades[i] or b==17 or
                                      (b in permissions["surfable"] and not self.grid["collision"][i])
                                      for i,b in enumerate(behaviors))
        self.grid["grass"] = bytearray(b in permissions["encounter"] for b in behaviors)
        self.grid["ledge"] = bytearray({56:4,57:8,58:1,59:2}.get(b,0) for b in behaviors)
        self.grid["counter"] = bytearray(b==128 for b in behaviors)
        self.grid["whirl"] = bytearray(b==17 for b in behaviors)
        self.grid["waterfall"] = cascades
        self.grid["climb"] = bytes(b if b in (75,76) else 0 for b in behaviors)
        for obj in old.get("objects", []):
            if obj.get("kind") in ("cut","boulder","rock","berry_tree"):
                entry = bindings.get("objects",{}).get(obj.get("source_script",obj.get("flag","")),{})
                if entry.get("header",self.header) == self.header:
                    pos = tuple(entry["at"]) if entry else self.position(obj["at"])
                    self.blockers[pos] = obj["kind"]

    def position(self, old):
        site = self.bindings.get("sites",{}).get(f"{old[0]},{old[1]}",{})
        if site.get("header") == self.header: return tuple(site["at"])
        w,h = self.old_size
        x,y = old
        if 0<=x<w and 0<=y<h:
            return struct.unpack_from("<HH",self.conversion,4*(w*y+x))
        return self.spawn


class JohtoRoutes(Routes):
    def __init__(self):
        super().__init__(("johto",))
        root = ROOT/"content/hgss"
        self.index = {header:mid for mid,header in read(root/"map_index.json").items()}
        bindings = read(root/"anchors.json")["maps"]
        permissions = read(root/"events.json")["permissions"]
        wild = read(root/"wild.json")
        for header,mid in self.index.items():
            old = self.fields[mid].data if mid in self.fields else {}
            table=read(root/"maps"/(mid+".json"))
            if not old and table.get("encounter_bank") in wild:
                old={"encounters":wild[table["encounter_bank"]]["land"]["day"]}
            self.fields[mid] = NativeField(old,table,bindings.get(mid,{}),permissions)

    def projection(self,dest):
        if "until_power" in dest and not getattr(self,"powered",False):
            dest=dest["until_power"]
        return super().projection(dest)

    def path(self,start,goals):
        # The elevator's exit is set on entry, so its next floor cannot be
        # known from a static warp graph before the player actually boards.
        deck=self.index["MAP_GOLDENROD_RADIO_TOWER_OBSERVATION_DECK"]
        lift=self.index["MAP_GOLDENROD_RADIO_TOWER_ELEVATOR"]
        if start[0] not in (deck,lift) and goals and all(g[0]==deck for g in goals):
            return super().path(start,{(lift,3,4)})
        if start[0]==deck and goals and all(g[0]!=deck for g in goals):
            return super().path(start,{(lift,3,4)})
        return super().path(start,goals)
