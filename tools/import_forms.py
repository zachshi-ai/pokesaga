#!/usr/bin/env python3
"""把「形态」从物种表里拆出来，单独作为一只宝可梦的 forms。

极巨化、Mega、地区形态（阿罗拉/洗翠/伽勒尔/帕底亚）、皮卡丘的各种帽子，
在原版都是同一只宝可梦的不同形态，不是新的图鉴编号。之前导入时这些块
被当成重复图鉴号直接丢掉了，等于整块内容缺失。

这里做两件事：
  1. 从 species_info 里把同图鉴号的其余结构体抽成 forms（带属性/种族值/特性/立绘）
  2. 按目录结构导出形态立绘到 assets/mon/forms/<图鉴号>_<形态>.png
"""
from asset_paths import project_path, source_path

import re, glob, os, json

ROOT = source_path("emerald")
ART = os.path.join(ROOT, "graphics/pokemon")
SRC = os.path.join(ROOT, "src/data/pokemon/species_info")
OUT = project_path("content")
SPRITE_OUT = project_path("assets/mon/forms")

TYPE_MAP = {
    "NORMAL": "normal", "FIGHTING": "fighting", "FLYING": "flying", "POISON": "poison",
    "GROUND": "ground", "ROCK": "rock", "BUG": "bug", "GHOST": "ghost", "STEEL": "steel",
    "FIRE": "fire", "WATER": "water", "GRASS": "grass", "ELECTRIC": "electric",
    "PSYCHIC": "psychic", "ICE": "ice", "DRAGON": "dragon", "DARK": "dark", "FAIRY": "fairy",
}

# 形态后缀的中文说法
TOKEN_CN = {
    "MEGA": "Mega", "MEGA_X": "Mega X", "MEGA_Y": "Mega Y", "GMAX": "超极巨",
    "ALOLA": "阿罗拉", "HISUI": "洗翠", "GALAR": "伽勒尔", "PALDEA": "帕底亚",
    "TOTEM": "霸主", "ORIGIN": "起源", "SKY": "天空", "LAND": "陆地",
    "BLACK": "黑", "WHITE": "白", "THERIAN": "灵兽", "INCARNATE": "化身",
    "ATTACK": "攻击", "DEFENSE": "防御", "SPEED": "速度", "NORMAL": "普通",
    "HEAT": "加热", "WASH": "清洗", "FROST": "结冰", "FAN": "旋转", "MOW": "切割",
    "SUNSHINE": "晴天", "OVERCAST": "阴天", "SNOW": "雪天", "RAINY": "雨天",
    "EAST": "东", "WEST": "西", "NORTH": "北", "SOUTH": "南",
    "PLANT": "植物", "SANDY": "砂土", "TRASH": "垃圾",
    "SMALL": "小", "LARGE": "大", "SUPER": "超大", "AVERAGE": "普通",
    "COSPLAY": "换装", "ROCK_STAR": "硬摇滚", "BELLE": "偶像", "POP_STAR": "贵妇",
    "PHD": "博士", "LIBRE": "自由", "ORIGINAL": "初始帽子", "HOENN": "丰缘帽子",
    "SINNOH": "神奥帽子", "UNOVA": "合众帽子", "KALOS": "卡洛斯帽子",
    "ALOLA_CAP": "阿罗拉帽子", "PARTNER": "搭档", "WORLD": "世界帽子",
    "STARTER": "最初伙伴", "COMBAT": "斗", "BLAZE": "火", "AQUA": "水",
    "ICE_RIDER": "白", "SHADOW_RIDER": "黑", "NOICE": "无冰块", "HANGREE": "空腹",
    "HERO": "英雄", "ROOK": "塔", "NAIVE": "朴素", "DROOPY": "下垂", "STRETCHY": "伸展",
    "CURLY": "卷曲", "THREE": "三节", "FOUR": "四节", "FAMILY": "一家",
    "MALE": "雄性", "FEMALE": "雌性", "BUSTED": "破损", "BLADE": "刀剑",
    "SHIELD": "盾牌", "ZEN": "达摩", "SCHOOL": "群聚", "SOLO": "单独",
    "MIDNIGHT": "黑夜", "MIDDAY": "白昼", "DUSK": "黄昏", "BLUE": "蓝",
    "RED": "红", "YELLOW": "黄", "ORANGE": "橙", "GREEN": "绿", "INDIGO": "靛",
    "VIOLET": "紫", "LOW_KEY": "低调", "HIGH_KEY": "高调", "AMPED": "高调电",
    "SPARKING": "闪耀", "GULPING": "吞", "GORGING": "吞食", "CROWNED": "王冠",
    "ETERNAL": "永恒", "ZENITH": "巅峰", "RAPID_STRIKE": "连击", "SINGLE_STRIKE": "一击",
    "NOICE_FACE": "无冰块", "TERASTAL": "太晶", "STELLAR": "星晶",
    "TWO": "双", "CURLY_FORMS": "", "BLOODMOON": "血月", "WELLSPRING": "水井",
    "HEARTHFLAME": "炉火", "CORNERSTONE": "础石", "TEAL": "碧草",
    "MASK": "面具", "DEPLOYED": "展开", "DROOPY_FORMS": "", "SON": "儿子",
}


def read(p):
    return open(p, errors="ignore").read()


def norm(x):
    return "".join(c for c in x.lower() if c.isalnum())


def pick_num(expr):
    if expr is None:
        return None
    expr = expr.strip()
    if "?" in expr:
        m = re.search(r"\b(\d+)\b", expr.split("?", 1)[1])
        if m:
            return int(m.group(1))
    nums = re.findall(r"\b(\d+)\b", expr)
    return int(nums[0]) if nums else None


def define_table(text):
    out = {}
    for m in re.finditer(r"^\s*#define\s+([A-Z0-9_]+)\s+(\(?[^\n/]+?\)?)\s*$", text, re.M):
        if m.group(2).startswith("_"):
            continue
        out.setdefault(m.group(1), m.group(2).strip())
    return out


def resolve(expr, macros, depth=0):
    if expr is None or depth > 6:
        return None
    expr = expr.strip().strip("()")
    if expr.isdigit():
        return int(expr)
    if expr in macros:
        return resolve(macros[expr], macros, depth + 1)
    return pick_num(expr)


def load_blocks():
    """key -> (body, file)"""
    out = {}
    macros = {}
    type_macros = {}
    for p in sorted(glob.glob(SRC + "/gen_*_families.h")):
        t = read(p)
        macros.update(define_table(t))
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPES)\s+MON_TYPES\(([^)]*)\)", t):
            type_macros.setdefault(m.group(1), m.group(2))
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPES)\s*\{([^}]*)\}", t):
            type_macros.setdefault(m.group(1), m.group(2))
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPE1)\s+\(([^)]*)\)", t):
            branch = m.group(2).split("?")[1] if "?" in m.group(2) else m.group(2)
            tm = re.search(r"TYPE_(\w+)", branch)
            if tm:
                type_macros.setdefault(m.group(1), tm.group(1))
        joined = re.sub(r"\\\n", " ", t)
        for m in re.finditer(r"#define\s+(\w+)\s+(\{(?:[^\n]*))", joined):
            macros.setdefault(m.group(1), m.group(2))
        marks = [(mm.start(), mm.group(1)) for mm in re.finditer(r"\n\s*\[SPECIES_(\w+)\]\s*=", t)]
        for i, (pos, key) in enumerate(marks):
            end = marks[i + 1][0] if i + 1 < len(marks) else len(t)
            out[key] = t[pos:end]
    return out, macros, type_macros


def graphics_index():
    """normalize(相对路径) -> 目录，用于把 gMonFrontPic_XxxYyy 对到具体文件夹"""
    idx = {}
    for dirpath, dirnames, filenames in os.walk(ART):
        if "anim_front.png" in filenames or "front.png" in filenames:
            rel = os.path.relpath(dirpath, ART).replace(os.sep, "/")
            idx[norm(rel)] = rel
    return idx


# 少数形态的立绘目录名和 key 对不上，单独指路（相对 graphics/pokemon）
DIR_ALIAS = {
    "MAGEARNA_ORIGINAL": "magearna/original_color",
    "MAGEARNA_ORIGINAL_MEGA": "magearna/mega",
    "TATSUGIRI_CURLY_MEGA": "tatsugiri/mega",
    "ZYGARDE_50_POWER_CONSTRUCT": "zygarde",
}


def form_label(key, base_key):
    suffix = key[len(base_key):].lstrip("_")
    if not suffix:
        return ""
    parts = [TOKEN_CN.get(p, p.capitalize()) for p in suffix.split("_")]
    return "·".join([p for p in parts if p])


def load_dex_order():
    order = {}
    n = 0
    started = False
    for line in read(os.path.join(ROOT, "include/constants/pokedex.h")).splitlines():
        ln = line.split("//")[0]
        if "enum NationalDexOrder" in ln:
            started = True
            continue
        if not started:
            continue
        m = re.match(r"\s*NATIONAL_DEX_(\w+)\s*,?\s*$", ln)
        if m:
            order[m.group(1)] = n
            n += 1
    return order


def main():
    blocks, macros, type_macros = load_blocks()
    dex_order = load_dex_order()
    species = json.load(open(os.path.join(OUT, "species.json")))
    by_id = {int(s["id"]): s for s in species}
    base_key = {int(s["id"]): str(s.get("key", "")) for s in species}

    idx = graphics_index()
    os.makedirs(SPRITE_OUT, exist_ok=True)

    count = 0
    sprite_ok = 0
    per_species = {}
    for key, body in blocks.items():
        m = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", body)
        if not m:
            continue
        dex = dex_order.get(m.group(1))
        if not dex or dex not in by_id:
            continue
        bk = base_key[dex]
        if key == bk or not key.startswith(bk + "_"):
            continue
        # 属性
        tm = re.search(r"\.types\s*=\s*MON_TYPES\(([^)]*)\)", body)
        texpr = tm.group(1) if tm else ""
        if not texpr:
            raw = (re.search(r"\.types\s*=\s*([^,\n]+)", body) or [None, ""])[1].strip()
            texpr = type_macros.get(raw, "")
        types = []
        for t in texpr.split(","):
            t = t.strip().replace("TYPE_", "")
            if t in TYPE_MAP:
                types.append(TYPE_MAP[t])
        base = {}
        for f, k in (("baseHP", "hp"), ("baseAttack", "atk"), ("baseDefense", "def"),
                     ("baseSpAttack", "spa"), ("baseSpDefense", "spd"), ("baseSpeed", "spe")):
            fm = re.search(r"\.%s\s*=\s*([^,\n]+)" % f, body)
            base[k] = resolve(fm.group(1) if fm else None, macros)
        abil = []
        am = re.search(r"\.abilities\s*=\s*\{\s*([^}]*)\}", body)
        if am:
            for a in am.group(1).split(","):
                a = a.strip().replace("ABILITY_", "")
                if a and a != "NONE":
                    abil.append(a)
        kind = "form"
        if "_MEGA" in key:
            kind = "mega"
        elif "_GMAX" in key:
            kind = "gmax"
        elif re.search(r"_(ALOLA|HISUI|GALAR|PALDEA)", key):
            kind = "regional"
        # 立绘
        fm = re.search(r"\.frontPic\s*=\s*gMonFrontPic_(\w+)", body)
        sprite = ""
        if fm:
            token = fm.group(1)
            rel = DIR_ALIAS.get(key) or idx.get(norm(token))
            if rel:
                d = os.path.join(ART, rel)
                name = "%d_%s.png" % (dex, key[len(bk) + 1:].lower())
                dst = os.path.join(SPRITE_OUT, name)
                if os.path.exists(os.path.join(d, "anim_front.png")):
                    ok = convert_pal(os.path.join(d, "anim_front.png"),
                                     os.path.join(d, "normal.pal"), dst)
                else:
                    ok = convert_plain(os.path.join(d, "front.png"), dst)
                if ok:
                    sprite = "res://assets/mon/forms/" + name
                    sprite_ok += 1
        # 形态自己的进化链：地区形态进化成对应的地区形态（阿罗拉小拉达 → 阿罗拉拉达）
        evos = []
        em = re.search(r"\.evolutions\s*=\s*EVOLUTION\((.*)\)", body, re.S)
        if em:
            for one in re.finditer(r"\{\s*EVO_(\w+)\s*,\s*([^,]+),\s*SPECIES_(\w+)", em.group(1)):
                ehow, arg, target = one.group(1).lower(), one.group(2).strip(), one.group(3)
                item = {"key": target, "how": ehow}
                nums = re.findall(r"\d+", arg)
                if ehow == "level" and nums:
                    item["at"] = int(nums[0])
                elif ehow == "item":
                    item["item"] = arg.replace("ITEM_", "")
                evos.append(item)
        per_species.setdefault(dex, []).append({
            "key": key,
            "evolves": evos,
            "label": form_label(key, bk),
            "types": types or by_id[dex]["types"],
            "base": base if all(v for v in base.values()) else by_id[dex]["base"],
            "abilities": abil,
            "kind": kind,
            "sprite": sprite,
        })
        count += 1

    # 进化目标写的是 SPECIES 键（PERRSERKER / RATICATE_ALOLA），解析成 图鉴号 + 形态键
    key_to = {}
    for dex, forms in per_species.items():
        for f in forms:
            key_to[f["key"]] = (dex, f["key"])
    for dex, forms in per_species.items():
        for f in forms:
            fixed = []
            for e in f.get("evolves", []):
                tgt = key_to.get(e["key"])
                if tgt is None:
                    tgt = (dex_order.get(str(e["key"])), "")
                if not tgt or not tgt[0]:
                    continue
                item = {"to": int(tgt[0]), "form": String if False else (tgt[1] if tgt[1] != f["key"] else "")}
                item["how"] = e["how"]
                if "at" in e:
                    item["at"] = e["at"]
                if "item" in e:
                    item["item"] = e["item"]
                fixed.append(item)
            f["evolves"] = fixed

    for dex, forms in per_species.items():
        forms.sort(key=lambda f: (f["kind"] != "regional", f["key"]))
        by_id[dex]["forms"] = forms

    json.dump(species, open(os.path.join(OUT, "species.json"), "w"), ensure_ascii=False, indent=1)
    kinds = {}
    for forms in per_species.values():
        for f in forms:
            kinds[f["kind"]] = kinds.get(f["kind"], 0) + 1
    print("forms:", count, "带立绘", sprite_ok, kinds)
    print("有形态的物种:", len(per_species))


def load_pal(path):
    cols = []
    for ln in read(path).replace("\r", "").split("\n")[3:]:
        p = ln.strip().split()
        if len(p) >= 3:
            cols.append((int(p[0]), int(p[1]), int(p[2])))
    while len(cols) < 16:
        cols.append((0, 0, 0))
    return cols


def convert_pal(anim, pal_path, dst):
    from PIL import Image
    if not (os.path.exists(anim) and os.path.exists(pal_path)):
        return False
    frame = Image.open(anim).convert("P")
    pal = load_pal(pal_path)
    px = frame.load()
    out = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    op = out.load()
    for y in range(min(64, frame.size[1])):
        for x in range(min(64, frame.size[0])):
            v = px[x, y] & 0xF
            if v == 0:
                continue
            r, g, b = pal[v]
            op[x, y] = (r, g, b, 255)
    out.save(dst)
    return True


def convert_plain(src, dst):
    from PIL import Image
    if not os.path.exists(src):
        return False
    im = Image.open(src).convert("RGBA")
    if im.size[0] != 64:
        k = 64.0 / im.size[0]
        im = im.resize((64, max(1, int(im.size[1] * k))), Image.NEAREST)
    canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    canvas.paste(im.crop((0, 0, 64, min(64, im.size[1]))), (0, 0))
    canvas.save(dst)
    return True


if __name__ == "__main__":
    main()
