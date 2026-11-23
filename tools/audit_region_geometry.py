#!/usr/bin/env python3
"""Count the runtime map records and distinguish door destinations from boundary cells."""
import argparse
import json
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGIONS = {
    "丰缘": "hoenn_native/maps", "城都（含关都）": "hgss/maps",
    "神奥": "platinum_native/maps", "合众 BW": "unova_native/bw",
    "合众 B2": "unova_native/b2", "卡洛斯": "regions/kalos/maps",
    "阿罗拉": "regions/alola/maps", "伽勒尔": "regions/galar/maps",
    "洗翠": "regions/hisui/maps", "帕底亚": "regions/paldea/maps",
}
SAMPLES = {
    "littleroot_town", "hoenn_119", "sinnoh_twinleaf", "sinnoh_sandgem",
    "unova_nuvema", "unova_aspertia", "kalos_vaniville", "kalos_aquacorde",
    "alola_iki", "alola_hauoli", "galar_postwick", "hisui_jubilife", "paldea_cabo",
}

def map_records(source, folder):
    path = "content/" + folder + "/"
    if isinstance(source, zipfile.ZipFile):
        prefix = "assets/" if "assets/project.binary" in source.namelist() else ""
        for name in sorted(source.namelist()):
            if name.startswith(prefix + path) and name.endswith(".json"):
                yield Path(name).stem, json.loads(source.read(name))
    else:
        for file in sorted((source / path).glob("*.json")):
            yield file.stem, json.loads(file.read_bytes())

def report(source):
    print("地区 | 地图文件 | 宽高组合 | 定向出口格记录 | 标记为技术场景")
    samples = []
    for region, folder in REGIONS.items():
        maps = dict(map_records(source, folder))
        if not maps:
            raise ValueError("No map records in " + folder)
        sizes = {tuple(m["size"]) for m in maps.values()}
        warps = sum(len(m.get("warps", [])) for m in maps.values())
        technical = sum(bool(m.get("unova_technical")) for m in maps.values()) if folder.startswith("unova_native/") else "—"
        print(f"{region} | {len(maps)} | {len(sizes)} | {warps} | {technical}")
        for key in sorted(SAMPLES.intersection(maps)):
            m = maps[key]
            targets = {w["to"].get("map") for w in m.get("warps", []) if isinstance(w.get("to"), dict)}
            samples.append((region, m["name"], "×".join(map(str,m["size"])), len(m.get("warps", [])), ", ".join(sorted(t for t in targets if t))))
    print("\n地区 | 地点 | 尺寸 | 定向出口格记录 | 直接目的地 ID")
    for sample in samples:
        print(" | ".join(map(str, sample)))

def emerald_reference(root):
    src = root / "data"
    groups = json.loads((src / "maps/map_groups.json").read_bytes())
    layouts = json.loads((src / "layouts/layouts.json").read_bytes())["layouts"]
    by_id = {layout["id"]: layout for layout in layouts}
    count = sum(len(groups[key]) for key in groups["group_order"])
    print(f"\n绿宝石 | {len(groups['group_order'])} 组 | {count} 地图 ID | {len(layouts)} 布局")
    print("地点 | 宽×高 | 地图内传送点 | 相邻地图连接 | 对象事件 | 不同 metatile")
    for key in ["LittlerootTown", "Route101", "Route119", "RustboroCity", "SlateportCity"]:
        m = json.loads((src / "maps" / key / "map.json").read_bytes())
        layout = by_id[m["layout"]]
        raw = (root / layout["blockdata_filepath"]).read_bytes()
        tiles = {word & 0x3ff for (word,) in struct.iter_unpack("<H", raw)}
        print(f"{key} | {layout['width']}×{layout['height']} | {len(m['warp_events'])} | {len(m['connections'] or [])} | {len(m['object_events'])} | {len(tiles)}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, help="Released APK or extracted Godot resource ZIP")
    parser.add_argument("--emerald-source", type=Path, help="Local checkout of pret/pokeemerald")
    args = parser.parse_args()
    if args.pack:
        with zipfile.ZipFile(args.pack) as pack:
            report(pack)
    else:
        report(ROOT)
    if args.emerald_source:
        emerald_reference(args.emerald_source)
