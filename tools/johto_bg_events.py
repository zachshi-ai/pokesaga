#!/usr/bin/env python3
"""Localize Crystal bg_events and rebuild the background objects of existing Johto maps.

POKESAGA_CRYSTAL=/path/to/pokecrystal python3 tools/johto_bg_events.py [--check]
"""
import argparse
import json
import re
from collections import Counter
from functools import lru_cache
from pathlib import Path

from asset_paths import project_path, source_path
from gen_world_extras import zh_item


@lru_cache(None)
def translations():
    result = {}
    with Path(__file__).with_name("locales").joinpath("johto_bg_zh.tsv").open(encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            keys, text = line.rstrip("\n").split("\t")
            for key in keys.split():
                if key in result:
                    raise ValueError(f"Duplicate localization for {key}")
                result[key] = text
    return result


@lru_cache(None)
def commands(root):
    """Read the first instruction after a global map-script label, including shared scripts."""
    asm_files = sorted((Path(root) / "maps").glob("*.asm"))
    if not asm_files:
        raise FileNotFoundError(f"No pokecrystal map scripts in {root}/maps")
    out = {}
    pattern = re.compile(r"^(\w+)::?[^\n]*\n(?:[ \t]*(?:;[^\n]*)?\n)*"
                         r"[ \t]+(hiddenitem|jumpstd)\s+(\w+)(?:,\s*(\w+))?", re.M)
    for path in asm_files:
        for label, command, arg, flag in pattern.findall(path.read_text()):
            out[label] = (command, arg, flag)
    return out


# Different item constants were used by the Gen II and Gen III disassemblies.
ALIASES = {"PARLYZ_HEAL": "PARALYZE_HEAL", "ELIXER": "ELIXIR", "MAX_ELIXER": "MAX_ELIXIR"}
EXTRA_ITEMS = {
    "BERSERK_GENE": ("破坏基因", "held"),
    "DIRE_HIT": ("要害攻击", "battle"),
    "X_ACCURACY": ("命中强化", "battle"),
    "X_DEFEND": ("防御强化", "battle"),
    "X_SPECIAL": ("特攻强化", "battle"),
}


def background_object(event, pos, root):
    script = event["script"]
    instruction, arg, flag = commands(root).get(script, ("", "", ""))
    obj = {"at": pos, "source_script": script}
    if event["type"] == "BGEVENT_ITEM":
        if instruction != "hiddenitem" or not flag:
            raise ValueError(f"Missing hidden item instruction for {script}")
        item = "ITEM_" + ALIASES.get(arg, arg)
        info = zh_item(item) or EXTRA_ITEMS.get(arg)
        if not info:
            raise ValueError(f"Missing item localization for {arg} in {script}")
        obj.update(kind="hidden", item=item, name=info[0], category=info[1], flag="johto:" + flag, count=1)
        if info[1] == "held":
            obj["held"] = arg
    elif script in ("GoldenrodDeptStoreElevatorScript", "CeladonDeptStoreElevatorScript"):
        obj["kind"] = "elevator"
    else:
        text_key = arg if instruction == "jumpstd" else script
        text = translations().get(text_key)
        if not text:
            raise ValueError(f"Missing bg_event localization for {script} ({text_key})")
        obj.update(kind="sign", sprite="sign", text=text)
    return obj


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="report any maps out of sync without writing")
    args = parser.parse_args()
    from gen_johto import parse_map_events, snap

    root = source_path("crystal")
    commands(root)
    counts = Counter()
    changed = 0
    for path in sorted(Path(project_path("content/regions/johto/maps")).glob("*.json")):
        room = json.loads(path.read_text())
        objects = room.get("objects", [])
        targets = [i for i, obj in enumerate(objects) if obj.get("source_script")
                   or "城都地区的告示牌" in obj.get("text", "")]
        if not targets:
            continue
        meta = json.loads(Path(project_path("content/emerald_maps"), room["emerald"] + ".json").read_text())
        events = parse_map_events(meta["map"], {})[2]
        at_pos = {}
        for event in events:
            pos = tuple(snap(meta, event["at8"], False))
            at_pos.setdefault(pos, event)
        by_script = {event["script"]: event for event in events}
        modified = False
        for i in targets:
            obj = objects[i]
            script = obj.get("source_script")
            event = by_script[script] if script else at_pos[tuple(obj["at"])]
            update = background_object(event, obj["at"], root)
            counts[update["kind"]] += 1
            if update != obj:
                objects[i] = update
                modified = True
        if modified:
            changed += 1
            if not args.check:
                path.write_text(json.dumps(room, ensure_ascii=False, indent=1) + "\n")
    print(f"{sum(counts.values())} objects: {dict(counts)}, {changed} changed maps")
    return int(args.check and changed > 0)


if __name__ == "__main__":
    raise SystemExit(main())
