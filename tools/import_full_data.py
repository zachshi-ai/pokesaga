#!/usr/bin/env python3
"""从 pokeemerald-expansion 源码抽出完整对战数据：招式、特性、物种、招式学习表。

之前 species.json 里每只宝可梦的 moves 只有「撞击 / 叫声」，moves.json 只有 23 条，
abilities.json 和 items.json 是空的，所以打起来所有宝可梦都一样。
这里把源码里的真数据全搬过来：

  src/data/moves_info.h                  -> content/moves.json
  src/data/abilities.h                   -> content/abilities.json
  src/data/pokemon/species_info/*.h      -> content/species.json（含特性/经验值/进化）
  src/data/pokemon/level_up_learnsets/*  -> 每只的升级招式表
"""
import re, json, glob, os

ROOT = "/root/build/pokeemerald-expansion-master"
OUT = "/root/build/pokesaga/content"

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

TYPE_MAP = {
    "NORMAL": "normal", "FIGHTING": "fighting", "FLYING": "flying", "POISON": "poison",
    "GROUND": "ground", "ROCK": "rock", "BUG": "bug", "GHOST": "ghost", "STEEL": "steel",
    "FIRE": "fire", "WATER": "water", "GRASS": "grass", "ELECTRIC": "electric",
    "PSYCHIC": "psychic", "ICE": "ice", "DRAGON": "dragon", "DARK": "dark", "FAIRY": "fairy",
    "MYSTERY": "normal", "STELLAR": "normal",
}
GROWTH_MAP = {
    "FAST": "fast", "MEDIUM_FAST": "medium_fast", "MEDIUM_SLOW": "medium_slow",
    "SLOW": "slow", "ERRATIC": "erratic", "FLUCTUATING": "fluctuating",
}


# ---------- 通用小工具 ----------

def read(path):
    return open(path, errors="ignore").read()


def pick_num(expr):
    """条件表达式取现代值：P_UPDATED_STATS >= GEN_2 ? 80 : 65 -> 80"""
    if expr is None:
        return None
    expr = expr.strip()
    if "?" in expr:
        tail = expr.split("?", 1)[1]
        m = re.search(r"\b(\d+)\b", tail)
        if m:
            return int(m.group(1))
    nums = re.findall(r"\b(\d+)\b", expr)
    return int(nums[0]) if nums else None


def field(body, key):
    m = re.search(r"\." + key + r"\s*=\s*([^,\n]+)", body)
    return m.group(1).strip() if m else None


def defines(text):
    """收集 #define XXX 值 形式的常量（数字或条件表达式），第一条即最高世代分支"""
    out = {}
    for m in re.finditer(r"^\s*#define\s+([A-Z0-9_]+)\s+(\(?[^\n/]+?\)?)\s*$", text, re.M):
        name, val = m.group(1), m.group(2).strip()
        if val.startswith("_"):
            continue
        out.setdefault(name, val)
    return out


def resolve_num(expr, macro_table, depth=0):
    """把字段值解成数字：直接数字 / 条件表达式 / 宏名（宏可能再指向宏）"""
    if expr is None or depth > 6:
        return None
    expr = expr.strip().strip("()")
    if expr.isdigit():
        return int(expr)
    if expr in macro_table:
        val = macro_table[expr]
        if isinstance(val, int):
            return val
        return resolve_num(val, macro_table, depth + 1)
    n = pick_num(expr)
    return n


def split_blocks(text, head_re):
    marks = [(m.start(), m.group(1)) for m in head_re.finditer(text)]
    out = []
    for i, (pos, key) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        out.append((key, text[pos:end]))
    return out


# ---------- 招式 ----------

def load_move_ids():
    """按枚举顺序推招式编号。源码里有别名（MOVE_VICEGRIP = MOVE_VISE_GRIP），
    也有把整段 Z 招式 / 极巨招式接在普通招式后面的写法，都得照顺序数。"""
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


def import_moves():
    ids = load_move_ids()
    text = read(os.path.join(ROOT, "src/data/moves_info.h"))
    out = []
    for key, body in split_blocks(text, re.compile(r"\n\s*\[MOVE_(\w+)\]\s*=")):
        if key == "NONE":
            continue
        mid = ids.get(key)
        if not mid:
            continue
        desc = ""
        m = re.search(r"\.description\s*=\s*COMPOUND_STRING\(\s*((?:\"[^\"]*\"\s*)+)\)", body, re.S)
        if m:
            desc = "".join(re.findall(r"\"([^\"]*)\"", m.group(1)))
            desc = desc.replace("\\n", "").replace("\\p", "\n")
        cat = field(body, "category") or "DAMAGE_CATEGORY_PHYSICAL"
        cat = cat.replace("DAMAGE_CATEGORY_", "").lower()
        etype = (field(body, "type") or "TYPE_NORMAL").replace("TYPE_", "")
        eff = field(body, "effect") or "EFFECT_HIT"
        eff = re.sub(r"^EFFECT_", "", eff)
        # 附加效果：麻痹/中毒/灼伤/冰冻/睡眠、能力升降
        add = {}
        am = re.search(r"ADDITIONAL_EFFECTS\(\{(.*?)\}\)", body, re.S)
        if am:
            blk = am.group(1)
            ch = re.search(r"\.chance\s*=\s*(\d+)", blk)
            chance = int(ch.group(1)) if ch else 100
            me = re.search(r"\.moveEffect\s*=\s*(\w+)", blk)
            kind = me.group(1) if me else ""
            low = kind.lower()
            st = None
            for k, v in (("paralysis", "par"), ("burn", "brn"), ("poison", "psn"),
                         ("toxic", "tox"), ("sleep", "slp"), ("freeze", "frz"),
                         ("confusion", "conf")):
                if k in low:
                    st = v
            if st:
                add = {"status": st, "chance": chance}
            elif "stat_change" in low:
                sign = -1 if "minus" in low else 1
                for stat_key, out_key in (("attack", "atk"), ("defense", "def"),
                                          ("speed", "spe"), ("spAttack", "spa"),
                                          ("spDefense", "spd"), ("accuracy", "acc"),
                                          ("evasion", "eva")):
                    sm = re.search(r"\.%s\s*=\s*(\d+)" % stat_key, blk)
                    if sm:
                        add = {"stat": out_key, "delta": sign * int(sm.group(1)), "chance": chance}
                        break
            elif "flinch" in low:
                add = {"flinch": True, "chance": chance}
        # 状态类招式：.argument = { .nonVolatileStatus = MOVE_EFFECT_TOXIC }
        if not add:
            sm = re.search(r"\.nonVolatileStatus\s*=\s*MOVE_EFFECT_(\w+)", body)
            if sm:
                low = sm.group(1).lower()
                for k, v in (("paralysis", "par"), ("burn", "brn"), ("poison", "psn"),
                             ("toxic", "tox"), ("sleep", "slp"), ("freeze", "frz")):
                    if k in low:
                        add = {"status": v, "chance": 100}
        flags = {}
        if ".ignoresKingsRock" not in body:
            pass
        if re.search(r"\.makesContact\s*=\s*TRUE", body):
            flags["contact"] = True
        if re.search(r"\.sheerForceBoost\s*=\s*TRUE", body):
            flags["sheer_force"] = True
        out.append({
            "id": mid,
            "key": key,
            "name": NAME_FIX.get(key,
                (re.search(r"\.name\s*=\s*COMPOUND_STRING\(\"([^\"]+)\"", body) or [None, key])[1]),
            "type": TYPE_MAP.get(etype, "normal"),
            "category": cat if cat in ("physical", "special", "status") else "physical",
            "power": resolve_num(field(body, "power"), {}) or 0,
            "accuracy": resolve_num(field(body, "accuracy"), {}) or 0,
            "pp": resolve_num(field(body, "pp"), {}) or 5,
            "priority": resolve_num(field(body, "priority"), {}) or 0,
            "effect": eff,
            "desc": desc,
            **({"extra": add} if add else {}),
            **({"flags": flags} if flags else {}),
        })
    out.sort(key=lambda x: x["id"])
    # 标出战斗变化用的招式：Z 招式 / 极巨招式 / 超极巨招式
    for mv in out:
        key = mv["key"]
        mid = mv["id"]
        if key.startswith("G_MAX_"):
            mv["kind"] = "gmax"
        elif key.startswith("MAX_"):
            mv["kind"] = "max"
        elif mid >= 848:
            mv["kind"] = "z"
        if mv.get("kind") in ("z", "max", "gmax"):
            # 这几类招式源码里的 power 是占位值，真实威力按基础招式算
            mv["computed_power"] = True
            mv["accuracy"] = 0
            mv["desc"] = mv.get("desc", "").replace("\\n", "")
    json.dump(out, open(os.path.join(OUT, "moves.json"), "w"), ensure_ascii=False, indent=1)
    print("moves:", len(out), "max id", out[-1]["id"],
          "z/max/gmax:", len([m for m in out if m.get("kind")]))
    return out


# ---------- 特性 ----------

def load_ability_ids():
    text = read(os.path.join(ROOT, "include/constants/abilities.h"))
    ids = {}
    cur = 0
    for line in text.splitlines():
        line = line.split("//")[0].strip()
        m = re.match(r"ABILITY_([A-Z0-9_]+)\s*=\s*([A-Z0-9_]+|\d+)\s*,", line)
        if m:
            key, val = m.group(1), m.group(2)
            if val.isdigit():
                cur = int(val)
            if key not in ids:
                ids[key] = cur
            cur += 1
    return ids


# 少数特性源码里没中文名，补官方/直译名
ABILITY_FIX = {
    "AS_ONE_ICE_RIDER": "合一（冰）",
    "AS_ONE_SHADOW_RIDER": "合一（幽）",
    "EELEVATE": "电气浮游",
    "FIRE_MANE": "炎之鬃",
    "AURA_GUARD": "气场防守",
}


def import_abilities():
    ids = load_ability_ids()
    text = read(os.path.join(ROOT, "src/data/abilities.h"))
    out = []
    for key, body in split_blocks(text, re.compile(r"\n\s*\[ABILITY_(\w+)\]\s*=")):
        if key == "NONE":
            continue
        aid = ids.get(key)
        if not aid:
            continue
        nm = re.search(r"\.name\s*=\s*_\(\"([^\"]+)\"", body)
        ds = re.search(r"\.description\s*=\s*COMPOUND_STRING\(\s*((?:\"[^\"]*\"\s*)+)\)", body, re.S)
        desc = ""
        if ds:
            desc = "".join(re.findall(r"\"([^\"]*)\"", ds.group(1))).replace("\\n", "")
        aname = nm.group(1) if nm else key
        if aname in ("-------", "") or not re.search(r"[\u4e00-\u9fff]", aname):
            aname = ABILITY_FIX.get(key, aname if aname != "-------" else "无")
        out.append({"id": aid, "key": key, "name": aname, "desc": desc})
    out.sort(key=lambda x: x["id"])
    json.dump(out, open(os.path.join(OUT, "abilities.json"), "w"), ensure_ascii=False, indent=1)
    print("abilities:", len(out))
    return out


# ---------- 升级招式表 ----------

def load_learnsets():
    """sBulbasaurLevelUpLearnset -> [(level, moveKey), ...]"""
    table = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "src/data/pokemon/level_up_learnsets/*.h"))):
        text = read(path)
        for m in re.finditer(r"static const struct LevelUpMove s(\w+)LevelUpLearnset\[\]\s*=\s*\{(.*?)\};", text, re.S):
            name, body = m.group(1), m.group(2)
            rows = []
            for lm in re.finditer(r"LEVEL_UP_MOVE\(\s*(\d+)\s*,\s*MOVE_(\w+)\s*\)", body):
                rows.append((int(lm.group(1)), lm.group(2)))
            table[name] = rows
    return table


# ---------- 物种 ----------

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


def load_type_macros(files):
    """#define CLEFAIRY_FAMILY_TYPES MON_TYPES(TYPE_FAIRY) 这类家族属性宏"""
    out = {}
    for path in files:
        txt = read(path)
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPES)\s+MON_TYPES\(([^)]*)\)", txt):
            out.setdefault(m.group(1), m.group(2))
        # 另一种写法：{ TYPE_A, TYPE_B }，第一条是最高世代分支
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPES)\s*\{([^}]*)\}", txt):
            out.setdefault(m.group(1), m.group(2))
        # 单属性家族宏：TOGEPI_FAMILY_TYPE1 (P_UPDATED_TYPES >= GEN_6 ? TYPE_FAIRY : TYPE_NORMAL)
        for m in re.finditer(r"#define\s+(\w*FAMILY_TYPE1)\s+\(([^)]*)\)", txt):
            branch = m.group(2).split("?")[1] if "?" in m.group(2) else m.group(2)
            t = re.search(r"TYPE_(\w+)", branch)
            if t:
                out.setdefault(m.group(1), t.group(1))
    return out


def load_body_macros(files):
    """把 #define XXX_SPECIES_INFO \ ... 这种多行结构体宏接成一行，供后续按字段解析"""
    out = {}
    for path in files:
        txt = read(path)
        # 把续行拼起来
        joined = re.sub(r"\\\n", " ", txt)
        for m in re.finditer(r"#define\s+(\w+)\s+(\{(?:[^\n]*))", joined):
            out.setdefault(m.group(1), m.group(2))
    return out


def import_species(move_ids, ability_ids):
    dex = load_dex_order()
    learns = load_learnsets()
    rows = {}
    macros = {}
    files = sorted(glob.glob(os.path.join(ROOT, "src/data/pokemon/species_info/gen_*_families.h")))
    type_macros = load_type_macros(files)
    for path in files:
        text = read(path)
        macros.update(defines(text))
        for key, body in split_blocks(text, re.compile(r"\n\s*\[SPECIES_(\w+)\]\s*=")):
            rows[key] = body

    body_macros = load_body_macros(files)
    # 形如 [SPECIES_GENESECT] = GENESECT_SPECIES_INFO(Genesect), 的条目，用宏体当结构体
    for key, body in list(rows.items()):
        if ".baseHP" in body:
            continue
        m = re.search(r"\]\s*=\s*(\w+)\s*[,(]", body)
        if m and m.group(1) in body_macros:
            rows[key] = body + "\n" + body_macros[m.group(1)]

    out = []
    seen = set()
    for key, body in rows.items():
        m = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", body)
        dex_key = m.group(1) if m else ""
        num = dex.get(dex_key)
        if not num or num <= 0 or num > 1025 or num in seen:
            continue

        base = {
            "hp": resolve_num(field(body, "baseHP"), macros),
            "atk": resolve_num(field(body, "baseAttack"), macros),
            "def": resolve_num(field(body, "baseDefense"), macros),
            "spa": resolve_num(field(body, "baseSpAttack"), macros),
            "spd": resolve_num(field(body, "baseSpDefense"), macros),
            "spe": resolve_num(field(body, "baseSpeed"), macros),
        }
        if any(v is None for v in base.values()):
            continue

        tm = re.search(r"\.types\s*=\s*MON_TYPES\(([^)]*)\)", body)
        type_expr = tm.group(1) if tm else ""
        if not type_expr:
            # 家族属性宏：.types = CLEFAIRY_FAMILY_TYPES
            raw = field(body, "types") or ""
            type_expr = type_macros.get(raw.strip(), "")
        types = []
        if type_expr:
            for t in type_expr.split(","):
                t = t.strip().replace("TYPE_", "")
                if t in TYPE_MAP:
                    types.append(TYPE_MAP[t])
        if not types:
            continue

        nm = re.search(r"\.speciesName\s*=\s*_\(\"([^\"]+)\"", body)
        growth = re.search(r"\.growthRate\s*=\s*GROWTH_(\w+)", body)

        # 特性：前两个是普通特性，第三个是隐藏特性
        abil = []
        am = re.search(r"\.abilities\s*=\s*\{\s*([^}]*)\}", body)
        if am:
            for a in am.group(1).split(","):
                a = a.strip().replace("ABILITY_", "")
                if a and a != "NONE":
                    abil.append(ability_ids.get(a, 0))

        # 进化：EVOLUTION({EVO_LEVEL, 16, SPECIES_X}, {EVO_ITEM, ITEM_Y, SPECIES_Z}, ...)
        evos = []
        em = re.search(r"\.evolutions\s*=\s*EVOLUTION\((.*)\)", body, re.S)
        if em:
            for one in re.finditer(r"\{\s*EVO_(\w+)\s*,\s*([^,]+),\s*SPECIES_(\w+)\s*\}", em.group(1)):
                kind, arg, target = one.group(1), one.group(2).strip(), one.group(3)
                tbody = rows.get(target, "")
                tm2 = re.search(r"\.natDexNum\s*=\s*NATIONAL_DEX_(\w+)", tbody)
                tdex = dex.get(tm2.group(1)) if tm2 else None
                if not tdex:
                    continue
                item = {"to": tdex, "how": kind.lower()}
                if kind == "LEVEL":
                    item["at"] = int(re.findall(r"\d+", arg)[0]) if re.findall(r"\d+", arg) else 0
                elif kind == "ITEM":
                    item["item"] = arg.replace("ITEM_", "")
                evos.append(item)

        # 升级招式表
        ls_key = None
        lm = re.search(r"\.levelUpLearnset\s*=\s*s(\w+)LevelUpLearnset", body)
        if lm:
            ls_key = lm.group(1)
        moves = []
        for lvl, mkey in learns.get(ls_key or "", []):
            mid_ = move_ids.get(mkey)
            if mid_:
                moves.append([lvl, mid_])

        gender = 127
        gm = re.search(r"\.genderRatio\s*=\s*PERCENT_FEMALE\(([\d.]+)\)", body)
        if gm:
            gender = int(float(gm.group(1)) * 255 / 100)
        elif "MON_GENDERLESS" in body or ".genderRatio = MON_GENDERLESS" in body:
            gender = -1

        out.append({
            "id": num,
            "key": key,
            "name": nm.group(1) if nm else key,
            "types": types,
            "base": base,
            "catch_rate": resolve_num(field(body, "catchRate"), macros) or 45,
            "exp_yield": resolve_num(field(body, "expYield"), macros) or 60,
            "growth": GROWTH_MAP.get(growth.group(1), "medium_fast") if growth else "medium_fast",
            "gender": gender,
            "abilities": abil,
            "evolves": evos,
            "learnset": moves,
        })
        seen.add(num)

    out.sort(key=lambda x: x["id"])
    # 兼容旧字段：单一进化目标
    for s in out:
        for e in s["evolves"]:
            if e["how"] == "level" and e.get("at"):
                s["evolves_to"] = e["to"]
                s["evolves_at"] = e["at"]
                break
        s["moves"] = [m[1] for m in s["learnset"][:4]] or [33]

    json.dump(out, open(os.path.join(OUT, "species.json"), "w"), ensure_ascii=False, indent=1)
    print("species:", len(out), "缺号", [i for i in range(1, 1026) if i not in seen][:20])
    empty = [s["id"] for s in out if not s["learnset"]]
    print("没招式表的:", len(empty), empty[:15])
    return out


# ---------- 补缺口：源码里没有条目的少数物种 ----------

POKEAPI = "https://pokeapi.co/api/v2"
CACHE = "/tmp/pokeapi_cache"
GROWTH_ALIAS = {
    "fast": "fast", "medium": "medium_fast", "medium-fast": "medium_fast",
    "medium-slow": "medium_slow", "slow": "slow", "erratic": "erratic",
    "fluctuating": "fluctuating", "slow-then-very-fast": "erratic",
    "fast-then-very-slow": "fluctuating",
}


def fetch(url):
    import urllib.request, hashlib
    os.makedirs(CACHE, exist_ok=True)
    key = hashlib.md5(url.encode()).hexdigest()
    path = os.path.join(CACHE, key)
    if os.path.exists(path):
        return json.load(open(path))
    import time
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (compatible; pokesaga-import/1.0)"})
    last = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                data = json.loads(r.read().decode())
            break
        except Exception as e:
            last = e
            time.sleep(1.5 * (attempt + 1))
    else:
        raise last
    json.dump(data, open(path, "w"))
    return data


def key_of(name):
    return re.sub(r"[^A-Z0-9]+", "_", name.upper()).strip("_")


def fill_missing(species, move_ids):
    """源码 species_info 里没写条目的物种，用官方接口补基础数据，招式取 all_learnables"""
    have = {s["id"] for s in species}
    gaps = [i for i in range(1, 1026) if i not in have]
    if not gaps:
        return species
    learn_all = json.load(open(os.path.join(ROOT, "src/data/pokemon/all_learnables.json")))
    for sid in gaps:
        try:
            mon = fetch("%s/pokemon/%d" % (POKEAPI, sid))
            spec = fetch("%s/pokemon-species/%d" % (POKEAPI, sid))
        except Exception as e:
            print("!! 补 %d 失败 %s" % (sid, e))
            continue
        # 优先简体，没有再退繁体
        name = ""
        for want_lang in ("zh-hans", "zh-hant"):
            for n in spec.get("names", []):
                if n.get("language", {}).get("name", "").lower() == want_lang:
                    name = n["name"]
                    break
            if name:
                break
        stats = {x["stat"]["name"]: x["base_stat"] for x in mon["stats"]}
        base = {
            "hp": stats.get("hp", 50), "atk": stats.get("attack", 50),
            "def": stats.get("defense", 50), "spa": stats.get("special-attack", 50),
            "spd": stats.get("special-defense", 50), "spe": stats.get("speed", 50),
        }
        types = [t["type"]["name"] for t in mon["types"]]
        types = [t if t in TYPE_MAP.values() else "normal" for t in types]
        k = key_of(mon["name"])
        # 优先用官方接口的升级招式表（带等级），拿不到再退回全招式池
        moves = []
        for mv in mon.get("moves", []):
            for vg in mv.get("version_group_details", []):
                if vg.get("move_learn_method", {}).get("name") != "level-up":
                    continue
                lvl = int(vg.get("level_learned_at", 0) or 0)
                if lvl <= 0:
                    continue
                mid = move_ids.get(key_of(mv["move"]["name"]))
                if mid and [lvl, mid] not in moves:
                    moves.append([lvl, mid])
        moves.sort()
        if not moves:
            raw = learn_all.get(k) or learn_all.get(mon["name"].upper()) or []
            got = [move_ids.get(m.replace("MOVE_", "")) for m in raw]
            got = [m for m in got if m]
            for i, m in enumerate(got[:10]):
                moves.append([1 + i * 5, m])
        # 特性
        ab_here = []
        for a in mon.get("abilities", []):
            an = key_of(a["ability"]["name"])
            for ab in json.load(open(os.path.join(OUT, "abilities.json"))):
                if ab["key"] == an:
                    ab_here.append(ab["id"])
                    break
        species.append({
            "id": sid, "key": k, "name": name or mon["name"],
            "types": types, "base": base,
            "catch_rate": spec.get("capture_rate", 45),
            "exp_yield": mon.get("base_experience") or 60,
            "growth": GROWTH_ALIAS.get((spec.get("growth_rate") or {}).get("name", ""), "medium_fast"),
            "gender": 127, "abilities": ab_here, "evolves": [],
            "learnset": moves, "moves": [m[1] for m in moves[:4]] or [33],
        })
    species.sort(key=lambda x: x["id"])
    return species


def main():
    moves = import_moves()
    abils = import_abilities()
    move_ids = {m["key"]: m["id"] for m in moves}
    move_ids.setdefault("NONE", 0)
    ability_ids = {a["key"]: a["id"] for a in abils}
    species = import_species(move_ids, ability_ids)
    species = fill_missing(species, move_ids)
    json.dump(species, open(os.path.join(OUT, "species.json"), "w"), ensure_ascii=False, indent=1)
    print("补齐后 species:", len(species),
          "缺号", [i for i in range(1, 1026) if i not in {s["id"] for s in species}])


if __name__ == "__main__":
    main()
