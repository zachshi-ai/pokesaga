#!/usr/bin/env python3
"""导入「战斗内形态切换」用到的多形态数据。

主角是那些靠特性（或携带物）在战斗里变形态的宝可梦：
坚盾剑怪（战斗切换）、达摩狒狒（达摩模式）、弱丁鱼（鱼群）、
莫鲁贝可（饱了又饿）、谜拟丘（画皮·破损）、小陨星（界限盾壳）、
飘浮泡泡（阴晴不定）、银伴战兽（ＡＲ系统）、基格尔德（群聚变形）、
古月鸟（一口导弹）、太乐巴戈斯（太晶变形）、厄诡椪（面具）。

数据全部取自已开源的 pokeemerald-expansion 源码块，立绘取同一套素材，
不另绘、不杜撰。已有同名形态的跳过。
"""
import os
import re
import json
import sys
import glob

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_forms as F

OUT = "/root/build/pokesaga/content"
ART = F.ART
SPRITE_OUT = F.SPRITE_OUT

# 前缀：同一只宝可梦的所有形态块都以它开头
PREFIX = {
    351: "CASTFORM",
    386: "DEOXYS",
    555: "DARMANITAN",
    681: "AEGISLASH",
    746: "WISHIWASHI",
    773: "SILVALLY",
    774: "MINIOR",
    778: "MIMIKYU",
    877: "MORPEKO",
    1017: "OGERPON",
    1024: "TERAPAGOS",
    718: "ZYGARDE",
    845: "CRAMORANT",
    964: "PALAFIN",
    479: "ROTOM",
    492: "SHAYMIN",
    493: "ARCEUS",
    649: "GENESECT",
    888: "ZACIAN",
    889: "ZAMAZENTA",
}

# 立绘目录和 key 对不上时单独指路（相对 graphics/pokemon）
SPRITE_DIR = {
    "DARMANITAN_ZEN": "darmanitan/zen",
    "DARMANITAN_GALAR_STANDARD": "darmanitan/galar_standard",
    "DARMANITAN_GALAR_ZEN": "darmanitan/galar_zen",
    "CASTFORM_SUNNY": "castform/sunny",
    "CASTFORM_RAINY": "castform/rainy",
    "CASTFORM_SNOWY": "castform/snowy",
    "ZYGARDE_10": "zygarde/10_percent",
    "ZYGARDE_10_POWER_CONSTRUCT": "zygarde/10_percent",
    "ZYGARDE_COMPLETE": "zygarde/complete",
    "OGERPON_WELLSPRING": "ogerpon/wellspring",
    "OGERPON_HEARTHFLAME": "ogerpon/hearthflame",
    "OGERPON_CORNERSTONE": "ogerpon/cornerstone",
    "OGERPON_TEAL": "ogerpon",
    "PALAFIN_HERO": "palafin/hero",
    "SHAYMIN_SKY": "shaymin/sky",
    "ZACIAN_CROWNED": "zacian/crowned_sword",
    "ZAMAZENTA_CROWNED": "zamazenta/crowned_shield",
    "GENESECT_DOUSE": "genesect/douse_drive",
    "GENESECT_SHOCK": "genesect/shock_drive",
    "GENESECT_BURN": "genesect/burn_drive",
    "GENESECT_CHILL": "genesect/chill_drive",
}

# 这些形态是战斗里才会变的，编辑器里不该当普通形态选
BATTLE_ONLY = {
    "AEGISLASH_BLADE", "DARMANITAN_ZEN", "DARMANITAN_GALAR_ZEN",
    "WISHIWASHI_SCHOOL", "MORPEKO_HANGRY", "MIMIKYU_BUSTED",
    "CASTFORM_SUNNY", "CASTFORM_RAINY", "CASTFORM_SNOWY",
    "ZYGARDE_COMPLETE", "ZYGARDE_10", "ZYGARDE_10_POWER_CONSTRUCT",
    "CRAMORANT_GULPING", "CRAMORANT_GORGING",
    "TERAPAGOS_TERASTAL", "TERAPAGOS_STELLAR",
    "OGERPON_TEAL", "OGERPON_WELLSPRING", "OGERPON_HEARTHFLAME", "OGERPON_CORNERSTONE",
    "PALAFIN_HERO",
}

# 形态后缀的中文说法，缺的补在这里
EXTRA_CN = {
    "SUNNY": "晴天", "COMPLETE": "完全体", "CORE": "核心", "METEOR": "陨石",
    "10_PERCENT": "10%", "50": "50%", "POWER_CONSTRUCT": "群聚变形",
    "AURA_BREAK": "气场破坏", "ATTACK": "攻击", "DEFENSE": "防御",
    "SPEED": "速度", "STANDARD": "普通", "FULL_BELLY": "满腹",
    "HANGRY": "空腹", "DISGUISED": "化装", "BUSTED": "破损",
    "TERASTAL": "太晶", "STELLAR": "星晶", "TEAL": "碧草",
    "WELLSPRING": "水井", "HEARTHFLAME": "炉火", "CORNERSTONE": "础石",
    "BLADE": "刀剑", "SCHOOL": "群聚", "ZEN": "达摩",
    "SNOWY": "雪天", "AURA_BREAK": "气场破坏",
    "BUG": "虫", "DARK": "恶", "DRAGON": "龙", "ELECTRIC": "电", "FAIRY": "妖精",
    "FIGHTING": "格斗", "FIRE": "火", "FLYING": "飞行", "GHOST": "幽灵",
    "GRASS": "草", "GROUND": "地面", "ICE": "冰", "NORMAL": "一般",
    "POISON": "毒", "PSYCHIC": "超能力", "ROCK": "岩石", "STEEL": "钢",
    "WATER": "水", "FULL_BELLY": "满腹", "HERO": "全能", "ZERO": "零", "SKY": "天空", "CROWNED": "王冠", "DOUSE": "水滴",
    "SHOCK": "闪电", "BURN": "火焰", "CHILL": "冰冻",
}

# 这些块不进形态表：本身就和基础物种重复，或者只是配色变体
DROP = {
    "ZYGARDE_10_AURA_BREAK",
    "MINIOR_CORE_ORANGE", "MINIOR_CORE_YELLOW", "MINIOR_CORE_GREEN",
    "MINIOR_CORE_BLUE", "MINIOR_CORE_INDIGO", "MINIOR_CORE_VIOLET",
}



def load_macro_defs():
    """#define Xxx_SPECIES_INFO(...) 这种整块宏：形态块只是调用它，得展开才看得到种族值"""
    out = {}
    for path in sorted(glob.glob(F.SRC + "/gen_*_families.h")):
        text = open(path, errors="ignore").read()
        text = text.replace("\\\n", "\n")
        for m in re.finditer(r"#define\s+(\w+)\(([^)]*)\)\s*\n?(\{.*?\n\s*\},?)", text, re.S):
            params = [x.strip() for x in m.group(2).split(",") if x.strip()]
            out[m.group(1)] = (params, m.group(3))
    return out


def expand(body, defs, depth=0):
    if depth > 3:
        return body
    m = re.search(r"\b(\w+)\(([^()]*)\)", body)
    if not m or m.group(1) not in defs:
        return body
    name, argstr = m.group(1), m.group(2)
    params, tpl = defs[name]
    args = [a.strip() for a in argstr.split(",")]
    out = tpl
    for i, p in enumerate(params):
        if i < len(args):
            out = re.sub(r"\b%s\b" % re.escape(p), args[i], out)
    out = out.replace("##", "")
    return expand(out, defs, depth + 1)


def label_of(key, prefix):
    suffix = key[len(prefix):].lstrip("_")
    if not suffix:
        return ""
    parts = []
    for p in suffix.split("_"):
        cn = EXTRA_CN.get(p) or F.TOKEN_CN.get(p) or p.capitalize()
        if cn:
            parts.append(cn)
    return "·".join(parts)


def blocks_of(prefix, blocks, dex, dex_no):
    out = {}
    for key, body in blocks.items():
        if key != prefix and not key.startswith(prefix + "_"):
            continue
        m = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", body)
        if m and dex.get(m.group(1)) != dex_no:
            continue
        out[key] = body
    return out


def main():
    blocks, macros, type_macros = F.load_blocks()
    defs = load_macro_defs()
    dex = F.load_dex_order()
    idx = F.graphics_index()
    path = os.path.join(OUT, "species.json")
    species = json.load(open(path))
    by_id = {int(s["id"]): s for s in species}

    # 774 的基础 key 之前被错填成 SILVALLY_FAIRY，改回 MINIOR
    if str(by_id[774].get("key", "")) != "MINIOR":
        print("修正 774 key:", by_id[774].get("key"), "-> MINIOR")
        by_id[774]["key"] = "MINIOR"

    added = 0
    sprites = 0
    for dex_no, prefix in sorted(PREFIX.items()):
        sp = by_id.get(dex_no)
        if sp is None:
            continue
        forms = sp.setdefault("forms", [])
        have = {str(f.get("key", "")) for f in forms}
        group = blocks_of(prefix, blocks, dex, dex_no)
        for key in sorted(group):
            if key in have:
                continue
            if "TOTEM" in key or key.endswith("_TERA") or "_MEGA" in key:
                continue
            if key in DROP or key == sp.get("key") or "_METEOR_" in key:
                continue
            body = expand(group[key], defs)
            tm = re.search(r"\.types\s*=\s*MON_TYPES\(([^)]*)\)", body)
            texpr = tm.group(1) if tm else ""
            if not texpr:
                raw = (re.search(r"\.types\s*=\s*([^,\n]+)", body) or [None, ""])[1].strip()
                texpr = type_macros.get(raw, "")
            types = []
            for t in texpr.split(","):
                t = t.strip().replace("TYPE_", "")
                if t in F.TYPE_MAP:
                    types.append(F.TYPE_MAP[t])
            base = {}
            for f, k in (("baseHP", "hp"), ("baseAttack", "atk"), ("baseDefense", "def"),
                         ("baseSpAttack", "spa"), ("baseSpDefense", "spd"), ("baseSpeed", "spe")):
                fm = re.search(r"\.%s\s*=\s*([^,\n]+)" % f, body)
                base[k] = F.resolve(fm.group(1) if fm else None, macros)
            types = list(dict.fromkeys(types))
            if not all(base.values()):
                print("跳过（种族值没解析出来）", key)
                continue
            abil = []
            am = re.search(r"\.abilities\s*=\s*\{\s*([^}]*)\}", body)
            if am:
                for a in am.group(1).split(","):
                    a = a.strip().replace("ABILITY_", "")
                    if a and a != "NONE":
                        abil.append(a)
            # 立绘
            sprite = ""
            fm = re.search(r"\.frontPic\s*=\s*gMonFrontPic_(\w+)", body)
            rel = SPRITE_DIR.get(key)
            if rel is None and fm:
                rel = idx.get(F.norm(fm.group(1)))
            if rel:
                d = os.path.join(ART, rel)
                name = "%d_%s.png" % (dex_no, key[len(prefix) + 1:].lower())
                dst = os.path.join(SPRITE_OUT, name)
                ok = False
                if os.path.exists(os.path.join(d, "anim_front.png")):
                    ok = F.convert_pal(os.path.join(d, "anim_front.png"),
                                       os.path.join(d, "normal.pal"), dst)
                elif os.path.exists(os.path.join(d, "front.png")):
                    ok = F.convert_plain(os.path.join(d, "front.png"), dst)
                elif os.path.exists(os.path.join(d, "normal.pal")):
                    # 只有配色、正脸图沿用本体（阿尔宙斯 / 盖诺赛克特这类换色形态）
                    par = os.path.dirname(d)
                    for src in ("anim_front.png", "front.png"):
                        sp0 = os.path.join(par, src)
                        if os.path.exists(sp0):
                            ok = F.convert_pal(sp0, os.path.join(d, "normal.pal"), dst)
                            break
                if ok:
                    sprite = "res://assets/mon/forms/" + name
                    sprites += 1
            kind = "form"
            if re.search(r"_(ALOLA|HISUI|GALAR|PALDEA)", key):
                kind = "regional"
            forms.append({
                "key": key,
                "label": label_of(key, prefix) or key,
                "types": types or sp.get("types", []),
                "base": base,
                "abilities": abil,
                "kind": kind,
                "battle": key in BATTLE_ONLY,
                "sprite": sprite,
                "evolves": [],
            })
            added += 1

    for sp in species:
        fs = sp.get("forms") or []
        fs.sort(key=lambda f: (f.get("kind") != "regional", str(f.get("key", ""))))
        if fs:
            sp["forms"] = fs

    json.dump(species, open(path, "w"), ensure_ascii=False, indent=1)
    total = sum(len(s.get("forms", [])) for s in species)
    kinds = {}
    for s in species:
        for f in s.get("forms", []):
            kinds[f.get("kind")] = kinds.get(f.get("kind"), 0) + 1
    print("新增形态 %d 个，立绘 %d 张；现有 %d 个形态 %s" % (added, sprites, total, kinds))


if __name__ == "__main__":
    main()
