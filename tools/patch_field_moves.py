#!/usr/bin/env python3
"""把天气 / 场地 / 屏障 / 撒菱 / 重力 这些「场地类」招式的参数补进 moves.json。

源码里这些信息在 .effect 与 .argument 里：
  .effect = EFFECT_WEATHER, .argument = { .weatherType = BATTLE_WEATHER_RAIN }
只会写「是什么效果」，不会写在哪个属性上，所以这里统一翻译成自己的字段：
  {"field": {"kind": "weather", "weather": "rain"}}
"""
from asset_paths import project_path, source_path

import re, json, os

ROOT = source_path("emerald")
OUT = project_path("content/moves.json")

WEATHER = {
    "SANDSTORM": "sandstorm", "RAIN": "rain", "SUN": "sun",
    "HAIL": "hail", "SNOW": "snow", "FOG": "fog",
}
TERRAIN = {
    "ELECTRIC": "electric", "GRASSY": "grassy",
    "MISTY": "misty", "PSYCHIC": "psychic",
}
SCREENS = {
    "EFFECT_REFLECT": "reflect",
    "EFFECT_LIGHT_SCREEN": "light_screen",
    "EFFECT_AURORA_VEIL": "aurora_veil",
}
HAZARDS = {
    "EFFECT_SPIKES": "spikes",
    "EFFECT_STEALTH_ROCK": "stealth_rock",
    "EFFECT_TOXIC_SPIKES": "toxic_spikes",
    "EFFECT_STICKY_WEB": "sticky_web",
}


def read(p):
    return open(p, errors="ignore").read()


def main():
    moves = json.load(open(OUT))
    by_key = {m["key"]: m for m in moves}

    text = read(os.path.join(ROOT, "src/data/moves_info.h"))
    marks = [(mm.start(), mm.group(1)) for mm in re.finditer(r"\n\s*\[MOVE_(\w+)\]\s*=", text)]
    blocks = {}
    for i, (pos, key) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        blocks[key] = text[pos:end]

    patched = 0
    for key, body in blocks.items():
        mv = by_key.get(key)
        if mv is None:
            continue
        eff_m = re.search(r"\.effect\s*=\s*(EFFECT_\w+)", body)
        eff = eff_m.group(1) if eff_m else ""
        field = {}

        if eff in SCREENS:
            field = {"kind": "screen", "screen": SCREENS[eff]}
        elif eff in HAZARDS:
            field = {"kind": "hazard", "hazard": HAZARDS[eff]}
        elif eff == "EFFECT_GRAVITY":
            field = {"kind": "gravity"}
        elif eff in ("EFFECT_WEATHER", "EFFECT_WEATHER_AND_SWITCH"):
            # 冰系天气写成三元表达式（冰雹/雪景二选一），取第二种也就是雪景
            wm = re.search(r"\.weatherType\s*=\s*(.+?)\n", body)
            expr = wm.group(1) if wm else ""
            if "?" in expr:
                tail = expr.split("?")[1]
                m2 = re.search(r"BATTLE_WEATHER_(\w+)", tail)
                w = WEATHER.get(m2.group(1), "snow") if m2 else "snow"
            else:
                m3 = re.search(r"BATTLE_WEATHER_(\w+)", expr)
                w = WEATHER.get(m3.group(1), m3.group(1).lower()) if m3 else ""
            # 冰系天气统一按现代的「雪」处理，冰雹招式也算下雪
            if w in ("snow", "hail"):
                w = "snow"
            if w:
                field = {"kind": "weather", "weather": w}
        elif eff == "EFFECT_TERRAIN":
            tm = re.search(r"\.terrainType\s*=\s*B_TERRAIN_(\w+)", body)
            if tm:
                t = TERRAIN.get(tm.group(1), tm.group(1).lower())
                field = {"kind": "terrain", "terrain": t}
        elif eff == "EFFECT_TERA_BLAST":
            field = {"kind": "tera_blast"}

        if field:
            mv["field"] = field
            patched += 1

    json.dump(moves, open(OUT, "w"), ensure_ascii=False, indent=1)
    kinds = {}
    for m in moves:
        f = m.get("field", {})
        if f:
            kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
    print("场地类招式:", patched, kinds)


if __name__ == "__main__":
    main()
