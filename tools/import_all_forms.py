#!/usr/bin/env python3
"""把剩余的外观/体型形态一次补齐（花色、造型、体型、季节、花纹等）。
种族值默认沿用本体；体型有差异的（南瓜精/南瓜怪人）单独给。
用法: python3 tools/import_all_forms.py
"""
from asset_paths import project_path, source_path

import json
import os
import sys

ROOT = project_path()
GFX = source_path("emerald", "graphics/pokemon")
OUT = os.path.join(ROOT, "assets/mon/forms")

sys.path.insert(0, os.path.join(ROOT, "tools"))
from import_forms import convert_pal, convert_plain, load_pal  # noqa: E402

CN = {
    "clover": "三叶草", "rainbow_swirl": "彩虹旋涡", "berry": "浆果", "strawberry": "草莓",
    "caramel_swirl": "焦糖旋涡", "star": "星星", "ribbon": "缎带", "flower": "花朵", "love": "爱心",
    "sandy": "沙", "trash": "垃圾", "plant": "草木",
    "summer": "夏", "autumn": "秋", "winter": "冬", "spring": "春",
    "blue": "蓝", "yellow": "黄", "white": "白", "orange": "橙", "red": "红",
    "eternal": "永恒", "mega": "Mega",
    "kabuki": "歌舞伎", "matron": "贵妇", "diamond": "菱形", "la_reine": "淑女", "debutante": "初入社交",
    "heart": "心形", "dandy": "绅士", "pharaoh": "法老",
    "small": "小型", "large": "大型", "super": "特大型",
    "pom_pom": "啪滋啪滋", "sensu": "轻飘飘", "pau": "呼啦呼啦",
    "blue_striped": "蓝条纹", "white_striped": "白条纹", "hisui": "洗翠",
    "f": "雌性", "three_segment": "三段", "four": "四只", "roaming": "漫游",
    "droopy": "下垂", "stretchy": "伸展", "spots": "斑点",
    "active": "活跃", "resolute": "觉悟", "original_color": "原始颜色",
    "therian": "灵兽", "east": "东之海", "rapid_strike": "连击",
    "partner": "搭档", "low_key": "低调", "teal_tera": "碧草太晶",
    "hearthflame_tera": "炉火太晶", "wellspring_tera": "水井太晶", "cornerstone_tera": "础石太晶",
    "y": "Y", "e": "E", "question": "问号", "b": "B", "z": "Z", "i": "I", "m": "M", "g": "G",
    "d": "D", "q": "Q", "t": "T", "l": "L", "exclamation": "感叹号", "u": "U", "r": "R", "j": "J",
    "n": "N", "w": "W", "h": "H", "v": "V", "c": "C", "x": "X", "o": "O", "s": "S", "p": "P",
    "k": "K", "f_": "F",
    "savanna": "热带草原", "tundra": "冰雪", "polar": "雪原", "sun": "太阳", "marine": "大海",
    "jungle": "热带雨林", "high_plains": "荒野", "monsoon": "季风", "sandstorm": "沙尘",
    "meadow": "草地", "ocean": "大洋", "elegant": "高雅", "continental": "大陆", "garden": "花园",
    "river": "大河", "archipelago": "群岛", "fancy": "缤纷", "modern": "现代", "poke_ball": "球球",
}

# 图鉴号: 子目录列表（本体已有，不重复）
PLAN = {
    869: ["clover", "rainbow_swirl", "berry", "strawberry", "caramel_swirl", "star", "ribbon", "flower", "love"],
    676: ["kabuki", "matron", "diamond", "la_reine", "debutante", "heart", "star", "dandy", "pharaoh"],
    669: ["blue", "yellow", "white", "orange"],
    670: ["blue", "yellow", "white", "orange", "eternal"],
    671: ["blue", "yellow", "white", "orange"],
    412: ["sandy", "trash"],
    413: ["sandy", "trash"],
    585: ["summer", "autumn", "winter"],
    586: ["summer", "autumn", "winter"],
    710: ["small", "large", "super"],
    711: ["small", "large", "super"],
    741: ["pom_pom", "pau", "sensu"],
    550: ["blue_striped", "white_striped", "hisui"],
    902: ["f"],
    982: ["three_segment"],
    925: ["four"],
    999: ["roaming"],
    931: ["blue", "yellow", "white"],
    978: ["droopy", "stretchy"],
    327: ["spots"],
    876: ["f"],
    916: ["f"],
    716: ["active"],
    647: ["resolute"],
    801: ["original_color"],
    905: ["therian"],
    422: ["east"],
    423: ["east"],
    892: ["rapid_strike"],
    133: ["partner"],
    849: ["low_key"],
    201: ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r",
          "s", "t", "u", "v", "w", "x", "y", "z", "exclamation", "question"],
    666: ["meadow", "polar", "tundra", "continental", "garden", "elegant", "modern", "marine",
          "archipelago", "high_plains", "sandstorm", "river", "monsoon", "savanna", "sun", "ocean",
          "jungle", "fancy", "poke_ball"],
}

# 体型会影响种族值的，按 Showdown 的数来
SIZE_STATS = {
    (710, "small"): {"hp": 44, "atk": 70, "def": 70, "spa": 44, "spd": 55, "spe": 56},
    (710, "large"): {"hp": 49, "atk": 66, "def": 70, "spa": 44, "spd": 55, "spe": 51},
    (710, "super"): {"hp": 59, "atk": 66, "def": 70, "spa": 44, "spd": 55, "spe": 41},
    (711, "small"): {"hp": 44, "atk": 85, "def": 122, "spa": 55, "spd": 75, "spe": 99},
    (711, "large"): {"hp": 54, "atk": 90, "def": 122, "spa": 58, "spd": 75, "spe": 84},
    (711, "super"): {"hp": 64, "atk": 90, "def": 122, "spa": 58, "spd": 75, "spe": 69},
}

# 目录名前缀和 key 不一致的
DIR_ALIAS = {666: "vivillon", 670: "floette", 671: "florges", 710: "pumpkaboo", 711: "gourgeist",
             201: "unown", 133: "eevee"}


def pick_pal(d, parent=None):
    for name in ("normal.pal",):
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        if f.endswith("_default.pal"):
            return os.path.join(d, f)
    if parent:
        pp = os.path.join(parent, "normal.pal")
        if os.path.exists(pp):
            return pp
    return None


def make_sprite(sid, key, dirname, sub):
    d = os.path.join(GFX, dirname, sub)
    dst = os.path.join(OUT, "%d_%s.png" % (sid, key.lower()))
    parent = os.path.join(GFX, dirname)
    anim = os.path.join(d, "anim_front.png")
    front = os.path.join(d, "front.png")
    pal = pick_pal(d, parent)
    if os.path.exists(anim) and pal:
        return convert_pal(anim, pal, dst)
    if os.path.exists(front):
        return convert_plain(front, dst)
    for src in ("anim_front.png", "front.png"):
        s0 = os.path.join(parent, src)
        if os.path.exists(s0):
            if pal:
                return convert_pal(s0, pal, dst)
            return convert_plain(s0, dst)
    return False


def main():
    path = os.path.join(ROOT, "content/species.json")
    species = json.load(open(path))
    byid = {s["id"]: s for s in species}
    os.makedirs(OUT, exist_ok=True)
    added = 0
    missing = []
    for sid, subs in PLAN.items():
        sp = byid.get(sid)
        if not sp:
            print("!! 物种缺", sid)
            continue
        dirname = DIR_ALIAS.get(sid, sp["key"].split("_")[0].lower())
        for sub in subs:
            key = "%s_%s" % (sp["key"].split("_")[0], sub.upper())
            have = [f for f in (sp.get("forms") or []) if f["key"] == key]
            if have:
                # 之前只补了数据没配到图，这里再试一次
                if not have[0].get("sprite") and make_sprite(sid, key, dirname, sub):
                    have[0]["sprite"] = "res://assets/mon/forms/%d_%s.png" % (sid, key.lower())
                    print("补图", sid, key)
                continue
            base = SIZE_STATS.get((sid, sub)) or sp.get("base")
            if not base:
                print("!! 没有种族值", sid, sub)
                continue
            label = CN.get(sub, sub)
            form = {
                "key": key,
                "label": label,
                "types": list(sp.get("types", [])),
                "base": dict(base),
                "abilities": list(sp.get("abilities", [])),
                "kind": "form",
            }
            ok = make_sprite(sid, key, dirname, sub)
            if ok:
                form["sprite"] = "res://assets/mon/forms/%d_%s.png" % (sid, key.lower())
            else:
                missing.append((sid, key))
            sp.setdefault("forms", []).append(form)
            added += 1
    json.dump(species, open(path, "w"), ensure_ascii=False, indent=1)
    total = sum(len(s.get("forms") or []) for s in species)
    print("新增 %d 个形态，现有 %d 个" % (added, total))
    if missing:
        print("没配上立绘 %d 个：" % len(missing), missing[:10])


if __name__ == "__main__":
    main()
