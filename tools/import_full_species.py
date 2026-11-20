#!/usr/bin/env python3
"""从 pokeemerald-expansion 的 C 源码里抽出全世代物种表，生成 content/species.json。

数据源：src/data/pokemon/species_info/gen_*_families.h
每个物种是一个 [SPECIES_XXX] = { ... } 块，里面有 base 六维、属性、捕获率、
成长曲线、中文名、全国图鉴号、以及 evolutions 里的升级进化。
"""
from asset_paths import project_path, source_path

import re, json, glob, os

SRC = source_path("emerald", "src/data/pokemon/species_info")
OUT = project_path("content/species.json")

TYPE_MAP = {
    "NORMAL": "normal", "FIGHTING": "fighting", "FLYING": "flying", "POISON": "poison",
    "GROUND": "ground", "ROCK": "rock", "BUG": "bug", "GHOST": "ghost", "STEEL": "steel",
    "FIRE": "fire", "WATER": "water", "GRASS": "grass", "ELECTRIC": "electric",
    "PSYCHIC": "psychic", "ICE": "ice", "DRAGON": "dragon", "DARK": "dark", "FAIRY": "fairy",
}
GROWTH_MAP = {
    "FAST": "fast", "MEDIUM_FAST": "medium_fast", "MEDIUM_SLOW": "medium_slow",
    "SLOW": "slow", "ERRATIC": "erratic", "FLUCTUATING": "fluctuating",
}

HEAD_RE = re.compile(r"\n\s*\[SPECIES_(\w+)\]\s*=")


def split_blocks(text):
    """按 [SPECIES_XXX] = 切块：块尾就是下一个 [SPECIES_ 或文件结尾。"""
    marks = [(m.start(), m.group(1)) for m in HEAD_RE.finditer(text)]
    out = []
    for i, (pos, key) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        out.append((key, text[pos:end]))
    return out


def parse_block(body):
    def num(key):
        # 有些字段是条件表达式：.baseSpAttack = P_UPDATED_STATS >= GEN_2 ? 60 : 50,
        m = re.search(r"\.%s\s*=\s*([^,\n]+)" % key, body)
        if not m:
            return None
        expr = m.group(1)
        nums = re.findall(r"\b(\d+)\b", expr)
        if not nums:
            return None
        return int(nums[-1])

    base = {
        "hp": num("baseHP"), "atk": num("baseAttack"), "def": num("baseDefense"),
        "spa": num("baseSpAttack"), "spd": num("baseSpDefense"), "spe": num("baseSpeed"),
    }
    if any(v is None for v in base.values()):
        return None

    m = re.search(r"\.types\s*=\s*MON_TYPES\(([^)]*)\)", body)
    types = []
    if m:
        for t in m.group(1).split(","):
            t = t.strip().replace("TYPE_", "")
            if t in TYPE_MAP:
                types.append(TYPE_MAP[t])
    if not types:
        return None

    m = re.search(r"\.speciesName\s*=\s*_\s*\(\s*\"([^\"]+)\"", body)
    name = m.group(1) if m else ""

    m = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", body)
    dex_key = m.group(1) if m else ""

    catch = num("catchRate") or 45

    m = re.search(r"\.growthRate\s*=\s*GROWTH_(\w+)", body)
    growth = GROWTH_MAP.get(m.group(1), "medium_fast") if m else "medium_fast"

    # 升级进化：{EVO_LEVEL, 16, SPECIES_IVYSAUR} ；同一条里可能有多个条件
    evo = None
    for em in re.finditer(r"\{\s*EVO_LEVEL\s*,\s*(\d+)\s*,\s*SPECIES_(\w+)", body):
        evo = (int(em.group(1)), em.group(2))
        break

    return {
        "name": name, "types": types, "base": base, "catch_rate": catch,
        "growth": growth, "dex_key": dex_key, "evo": evo,
    }


def main():
    rows = {}
    for path in sorted(glob.glob(os.path.join(SRC, "gen_*_families.h"))):
        text = open(path, errors="ignore").read()
        for key, body in split_blocks(text):
            parsed = parse_block(body)
            if parsed:
                rows[key] = parsed

    # 找全国图鉴号：用 include/constants/pokedex.h 里的 NATIONAL_DEX_XXX 枚举顺序
    # 全国图鉴号是隐式枚举（没有显式值），按出现顺序数
    dex_order = {}
    pdex = source_path("emerald", "include/constants/pokedex.h")
    if os.path.exists(pdex):
        n = 0
        started = False
        for line in open(pdex, errors="ignore"):
            ln = line.split("//")[0]
            if "enum NationalDexOrder" in ln:
                started = True
                continue
            if not started:
                continue
            mm = re.match(r"\s*NATIONAL_DEX_(\w+)\s*,?\s*$", ln)
            if mm:
                dex_order[mm.group(1)] = n
                n += 1
    print("dex entries:", len(dex_order))

    out = []
    for key, row in rows.items():
        dex = dex_order.get(row["dex_key"])
        if not dex or dex <= 0 or dex > 1025:
            continue
        # 同一图鉴号只留第一只（后面的都是形态）
        if any(o["id"] == dex for o in out):
            continue
        item = {
            "id": dex,
            "name": row["name"],
            "types": row["types"],
            "base": row["base"],
            "catch_rate": row["catch_rate"],
            "growth": row["growth"],
        }
        if row["evo"]:
            lv, target = row["evo"]
            trow = rows.get(target)
            tdex = dex_order.get(trow["dex_key"]) if trow else None
            if tdex and lv > 0:
                item["evolves_to"] = tdex
                item["evolves_at"] = lv
        out.append(item)

    out.sort(key=lambda x: x["id"])
    # 默认招式：撞击 / 叫声，保证任何一只都能进战斗
    for item in out:
        item["moves"] = [33, 45]
    json.dump(out, open(OUT, "w"), ensure_ascii=False, indent=1)
    print("species exported:", len(out), "max id", out[-1]["id"] if out else 0)


if __name__ == "__main__":
    main()
