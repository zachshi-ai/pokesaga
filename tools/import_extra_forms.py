#!/usr/bin/env python3
"""补齐一批还没进表的多形态：起源、解放、灵兽、舞步、晴天、解冻、午夜黄昏。
种族值/属性取自 Showdown pokedex，立绘从 pokeemerald-expansion 图形目录转。
用法: python3 tools/import_extra_forms.py
"""
from asset_paths import cache_path, project_path, source_path

import json
import os
import sys

ROOT = project_path()
GFX = source_path("emerald", "graphics/pokemon")
OUT = os.path.join(ROOT, "assets/mon/forms")
DEX = cache_path("showdown_dex.json")

# (图鉴号, showdown key, 图形子目录, key 后缀, 中文标签, 是否战斗内触发)
TARGETS = [
    (487, "giratinaorigin", "giratina/origin", "GIRATINA_ORIGIN", "起源", False),
    (720, "hoopaunbound", "hoopa/unbound", "HOOPA_UNBOUND", "解放", False),
    (641, "tornadustherian", "tornadus/therian", "TORNADUS_THERIAN", "灵兽", False),
    (642, "thundurustherian", "thundurus/therian", "THUNDURUS_THERIAN", "灵兽", False),
    (645, "landorustherian", "landorus/therian", "LANDORUS_THERIAN", "灵兽", False),
    (648, "meloettapirouette", "meloetta/pirouette", "MELOETTA_PIROUETTE", "舞步", True),
    (421, "cherrimsunshine", "cherrim/sunshine", "CHERRIM_SUNSHINE", "晴天", True),
    (875, "eiscuenoice", "eiscue/noice_face", "EISCUE_NOICE", "解冻", True),
    (745, "lycanrocmidnight", "lycanroc/midnight", "LYCANROC_MIDNIGHT", "午夜", False),
    (745, "lycanrocdusk", "lycanroc/dusk", "LYCANROC_DUSK", "黄昏", False),
]

sys.path.insert(0, os.path.join(ROOT, "tools"))
from import_forms import convert_pal, convert_plain  # noqa: E402


def main():
    dex = json.load(open(DEX))
    path = os.path.join(ROOT, "content/species.json")
    species = json.load(open(path))
    by_id = {s["id"]: s for s in species}
    os.makedirs(OUT, exist_ok=True)
    added = []
    for sid, skey, sub, key, label, battle in TARGETS:
        d = dex.get(skey)
        if not d:
            print("!! showdown 缺", skey)
            continue
        sp = by_id.get(sid)
        if not sp:
            print("!! 物种缺", sid)
            continue
        exists = any(f["key"] == key for f in (sp.get("forms") or []))
        if exists:
            print("skip 已存在", key)
            continue
        d = dict(d)
        st = d["baseStats"]
        base = {"hp": st["hp"], "atk": st["atk"], "def": st["def"],
                "spa": st["spa"], "spd": st["spd"], "spe": st["spe"]}
        types = [t.lower() for t in d["types"]]
        src_dir = os.path.join(GFX, sub)
        dst = os.path.join(OUT, "%d_%s.png" % (sid, key.lower()))
        ok = False
        anim = os.path.join(src_dir, "anim_front.png")
        pal = os.path.join(src_dir, "normal.pal")
        front = os.path.join(src_dir, "front.png")
        if os.path.exists(anim) and os.path.exists(pal):
            ok = convert_pal(anim, pal, dst)
        elif os.path.exists(front):
            ok = convert_plain(front, dst)
        form = {
            "key": key,
            "label": label,
            "types": types,
            "base": base,
            "abilities": sp.get("abilities", []),
            "kind": "form",
        }
        if battle:
            form["battle"] = True
        if ok:
            form["sprite"] = "res://assets/mon/forms/%d_%s.png" % (sid, key.lower())
        sp.setdefault("forms", []).append(form)
        added.append((sid, key, ok))
        print("add", sid, key, "立绘" if ok else "缺图")
    json.dump(species, open(path, "w"), ensure_ascii=False, indent=1)
    total = sum(len(s.get("forms") or []) for s in species)
    print("新增 %d 个形态，现有 %d 个" % (len(added), total))


if __name__ == "__main__":
    main()
