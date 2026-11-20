#!/usr/bin/env python3
"""抽取战斗中的变化系统数据：Mega / 极巨化 / Z 招式 / 太晶化 用到的表。

原版这几套东西都不在图鉴里，而是战斗内的临时变化，数据分散在几个 C 文件：
  include/constants/moves.h     招式编号（含 Z / Max / G-Max 招式）
  src/data/moves_info.h         招式属性与说明
  src/battle_dynamax.c          超极巨招式表、极巨招式威力档
  src/battle_z_move.c           Z 招式威力档

产物：
  content/moves.json            补齐 Z / 极巨 / 超极巨招式
  content/gimmicks.json         变化系统表
"""
import re, json, os

ROOT = "/root/build/pokeemerald-expansion-master"
OUT = "/root/build/pokesaga/content"

TYPE_MAP = {
    "NORMAL": "normal", "FIGHTING": "fighting", "FLYING": "flying", "POISON": "poison",
    "GROUND": "ground", "ROCK": "rock", "BUG": "bug", "GHOST": "ghost", "STEEL": "steel",
    "FIRE": "fire", "WATER": "water", "GRASS": "grass", "ELECTRIC": "electric",
    "PSYCHIC": "psychic", "ICE": "ice", "DRAGON": "dragon", "DARK": "dark", "FAIRY": "fairy",
}

# 招式中文名：源码里有几条没翻译，这里按官方中文补
NAME_FIX = {
    "VISE_GRIP": "紧束",
    "BREAKNECK_BLITZ": "究极无敌大冲撞",
    "SUPERSONIC_SKYSTRIKE": "极速俯冲轰烈撞",
    "ALL_OUT_PUMMELING": "全力无双激烈拳",
    "ACID_DOWNPOUR": "强酸剧毒灭绝雨",
    "TECTONIC_RAGE": "地隆啸天大灭绝",
    "CONTINENTAL_CRUSH": "毁天灭地巨岩坠",
    "SAVAGE_SPIN_OUT": "绝对捕食回旋斩",
    "NEVER_ENDING_NIGHTMARE": "无尽暗夜之诱惑",
    "CORKSCREW_CRASH": "超绝螺旋连击",
    "INFERNO_OVERDRIVE": "超强极限爆炎弹",
    "HYDRO_VORTEX": "超级水流大漩涡",
    "BLOOM_DOOM": "绚烂缤纷花怒放",
    "GIGAVOLT_HAVOC": "终极伏特狂雷闪",
    "SHATTERED_PSYCHE": "至高精神破坏波",
    "SUBZERO_SLAMMER": "激狂大地万里冰",
    "DEVASTATING_DRAKE": "究极巨龙震天地",
    "BLACK_HOLE_ECLIPSE": "黑洞吞噬万物灭",
    "TWINKLE_TACKLE": "可爱星星飞天撞",
    "CATASTROPIKA": "究极伏特狂雷",
    "10000000_VOLT_THUNDERBOLT": "千万伏特",
    "STOKED_SPARKSURFER": "驾雷驭电戏冲浪",
    "EXTREME_EVOBOOST": "九彩升华齐聚顶",
    "PULVERIZING_PANCAKE": "认真起来大爆击",
    "GENESIS_SUPERNOVA": "起源超新星大爆炸",
    "SINISTER_ARROW_RAID": "遮天蔽日暗影箭",
    "MALICIOUS_MOONSAULT": "极恶飞跃粉碎击",
    "OCEANIC_OPERETTA": "海神庄严交响乐",
    "SPLINTERED_STORMSHARDS": "狼啸石牙飓风暴",
    "LETS_SNUGGLE_FOREVER": "亲密无间大乱揍",
    "CLANGOROUS_SOULBLAZE": "炽魂热舞烈音爆",
    "GUARDIAN_OF_ALOLA": "彻夜狂舞守护神",
    "SEARING_SUNRAZE_SMASH": "日光回旋下苍穹",
    "MENACING_MOONRAZE_MAELSTROM": "月华飞溅落灵霄",
    "LIGHT_THAT_BURNS_THE_SKY": "焚天灭世炽光爆",
    "SOUL_STEALING_7_STAR_STRIKE": "七星夺魂腿",
    "MALICIOUS_MOONSAULT_": "极恶飞跃粉碎击",
    "G_MAX_VINE_LASH": "超极巨灰飞鞭灭",
    "G_MAX_WILDFIRE": "超极巨地狱灭焰",
    "G_MAX_CANNONADE": "超极巨水炮轰灭",
    "G_MAX_BEFUDDLE": "超极巨蝶影蛊惑",
    "G_MAX_VOLT_CRASH": "超极巨万雷轰顶",
    "G_MAX_GOLD_RUSH": "超极巨金币滚滚",
    "G_MAX_CHI_STRIKE": "超极巨会心一击",
    "G_MAX_TERROR": "超极巨幻影幽魂",
    "G_MAX_FOAM_BURST": "超极巨泡沫阵",
    "G_MAX_RESONANCE": "超极巨极光旋律",
    "G_MAX_CUDDLE": "超极巨亲密无间",
    "G_MAX_REPLENISH": "超极巨资源再生",
    "G_MAX_MALODOR": "超极巨臭气冲天",
    "G_MAX_MELTDOWN": "超极巨液金熔击",
    "G_MAX_DRUM_SOLO": "超极巨狂擂乱打",
    "G_MAX_FIREBALL": "超极巨炎石喷发",
    "G_MAX_HYDROSNIPE": "超极巨水之狙击",
    "G_MAX_WIND_RAGE": "超极巨旋风袭卷",
    "G_MAX_GRAVITAS": "超极巨天道引力",
    "G_MAX_STONESURGE": "超极巨岩阵以待",
    "G_MAX_VOLCALITH": "超极巨炎石喷发",
    "G_MAX_TARTNESS": "超极巨酸不溜丢",
    "G_MAX_SWEETNESS": "超极巨甘甜甘露",
    "G_MAX_SANDBLAST": "超极巨沙尘漫天",
    "G_MAX_STUN_SHOCK": "超极巨异电毒电",
    "G_MAX_CENTIFERNO": "超极巨百火燎原",
    "G_MAX_SMITE": "超极巨天谴雷霆",
    "G_MAX_SNOOZE": "超极巨睡魔降临",
    "G_MAX_FINALE": "超极巨幸福圆满",
    "G_MAX_STEELSURGE": "超极巨钢铁阵",
    "G_MAX_DEPLETION": "超极巨龙骑绝命",
    "G_MAX_ONE_BLOW": "超极巨暗冥灭杀",
    "G_MAX_RAPID_FLOW": "超极巨流水连击",
}

# 专属 Z 招式：只属于某一只，用技能时不按属性走
EXCLUSIVE_Z = {
    "PIKACHU": "CATASTROPIKA",
    "PIKACHU_ALOLA": "STOKED_SPARKSURFER",
    "EEVEE": "EXTREME_EVOBOOST",
    "SNORLAX": "PULVERIZING_PANCAKE",
    "MEW": "GENESIS_SUPERNOVA",
    "DECIDUEYE": "SINISTER_ARROW_RAID",
    "INCINEROAR": "MALICIOUS_MOONSAULT",
    "PRIMARINA": "OCEANIC_OPERETTA",
    "LYCANROC_MIDDAY": "SPLINTERED_STORMSHARDS",
    "LYCANROC_MIDNIGHT": "SPLINTERED_STORMSHARDS",
    "LYCANROC_DUSK": "SPLINTERED_STORMSHARDS",
    "MIMIKYU": "LETS_SNUGGLE_FOREVER",
    "KOMMOO": "CLANGOROUS_SOULBLAZE",
    "TAPU_KOKO": "GUARDIAN_OF_ALOLA",
    "SOLGALEO": "SEARING_SUNRAZE_SMASH",
    "LUNALA": "MENACING_MOONRAZE_MAELSTROM",
    "NECROZMA": "LIGHT_THAT_BURNS_THE_SKY",
    "MARSHADOW": "SOUL_STEALING_7_STAR_STRIKE",
}


def read(p):
    return open(p, errors="ignore").read()


def load_move_ids():
    """按枚举顺序推招式编号，处理 MOVE_X = MOVE_Y 这类别名"""
    text = read(os.path.join(ROOT, "include/constants/moves.h"))
    cur = 0
    out = {}
    for line in text.splitlines():
        line = line.split("//")[0].strip()
        m = re.match(r"MOVE_([A-Z0-9_]+)\s*(?:=\s*([A-Za-z0-9_]+))?\s*,", line)
        if not m:
            continue
        name, val = m.group(1), m.group(2)
        if val:
            cur = int(val) if val.isdigit() else out.get(val, cur)
        out[name] = cur
        cur += 1
    return out


def move_blocks():
    text = read(os.path.join(ROOT, "src/data/moves_info.h"))
    marks = [(m.start(), m.group(1)) for m in re.finditer(r"\n\s*\[MOVE_(\w+)\]\s*=", text)]
    out = {}
    for i, (pos, key) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        out[key] = text[pos:end]
    return out


def parse_move(key, body, mid):
    name = NAME_FIX.get(key)
    if not name:
        m = re.search(r"\.name\s*=\s*COMPOUND_STRING\(\"([^\"]+)\"", body)
        name = m.group(1) if m else key
    desc = ""
    dm = re.search(r"\.description\s*=\s*COMPOUND_STRING\(\s*((?:\"[^\"]*\"\s*)+)\)", body, re.S)
    if dm:
        desc = "".join(re.findall(r"\"([^\"]*)\"", dm.group(1))).replace("\\n", "")
    cat = (re.search(r"\.category\s*=\s*DAMAGE_CATEGORY_(\w+)", body) or [None, "PHYSICAL"])[1].lower()
    typ = (re.search(r"\.type\s*=\s*TYPE_(\w+)", body) or [None, "NORMAL"])[1]
    return {
        "id": mid,
        "key": key,
        "name": name,
        "type": TYPE_MAP.get(typ, "normal"),
        "category": cat if cat in ("physical", "special", "status") else "physical",
        "power": int((re.search(r"\.power\s*=\s*(\d+)", body) or [None, 1])[1]),
        "accuracy": 0,
        "pp": int((re.search(r"\.pp\s*=\s*(\d+)", body) or [None, 1])[1]),
        "priority": 0,
        "effect": "HIT",
        "desc": desc,
    }


def main():
    ids = load_move_ids()
    blocks = move_blocks()
    moves = {m["id"]: m for m in json.load(open(os.path.join(OUT, "moves.json")))}

    # 1) Z 招式 / 极巨招式 / 超极巨招式：编号在普通招式之后，之前整段都没导进来
    added = 0
    for key, mid in ids.items():
        if mid < 848 or key not in blocks:
            continue
        if mid in moves:
            continue
        mv = parse_move(key, blocks[key], mid)
        if key.startswith("G_MAX_"):
            mv["kind"] = "gmax"
        elif key.startswith("MAX_"):
            mv["kind"] = "max"
        else:
            mv["kind"] = "z"
        # 这些招式的威力是算出来的，源码里写 1 只是占位
        mv["computed_power"] = True
        moves[mid] = mv
        added += 1

    out_moves = sorted(moves.values(), key=lambda x: x["id"])
    json.dump(out_moves, open(os.path.join(OUT, "moves.json"), "w"), ensure_ascii=False, indent=1)

    # 2) 属性 → 通用 Z 招式（每个属性一条，专属招式另算）
    z_by_type = {}
    for key, mid in ids.items():
        if not (848 <= mid <= 883) or key not in blocks:
            continue
        mv = moves[mid]
        if mv["name"] == "":
            continue
        z_by_type.setdefault(mv["type"], mid)

    # 3) 属性 → 极巨招式
    max_by_type = {}
    for key, mid in ids.items():
        if not key.startswith("MAX_") or key not in blocks:
            continue
        mv = moves[mid]
        max_by_type.setdefault(mv["type"], mid)

    # 4) 超极巨专属招式：物种 → 属性 → 招式
    dyn = read(os.path.join(ROOT, "src/battle_dynamax.c"))
    gmax = {}
    for sp, ty, mo in re.findall(r"\{SPECIES_(\w+),\s*TYPE_(\w+),\s*MOVE_(\w+)\}", dyn):
        gmax.setdefault(sp, {})[TYPE_MAP.get(ty, "normal")] = ids.get(mo, 0)

    # 5) 专属 Z 招式
    exclusive = {}
    for sp, mo in EXCLUSIVE_Z.items():
        mid = ids.get(mo)
        if mid:
            exclusive[sp] = mid

    gimmicks = {
        "z_by_type": z_by_type,
        "z_exclusive": exclusive,
        "max_by_type": max_by_type,
        "gmax_by_species": gmax,
        "z_power": [[140, 200], [130, 195], [120, 190], [110, 185], [100, 180],
                    [90, 175], [80, 160], [70, 140], [60, 120], [0, 100]],
        "max_power": {"tier_up": [[140, 7], [130, 7], [120, 6], [110, 5], [100, 4],
                                  [90, 3], [80, 3], [70, 2], [60, 1], [0, 1]],
                      "normal": [90, 100, 110, 120, 130, 140, 130, 140],
                      "weak": [70, 75, 80, 85, 90, 95, 100, 100]},
    }
    json.dump(gimmicks, open(os.path.join(OUT, "gimmicks.json"), "w"), ensure_ascii=False, indent=1)
    print("moves total", len(out_moves), "新增", added)
    print("z_by_type", len(z_by_type), "max_by_type", len(max_by_type),
          "gmax species", len(gmax), "exclusive z", len(exclusive))


if __name__ == "__main__":
    main()
