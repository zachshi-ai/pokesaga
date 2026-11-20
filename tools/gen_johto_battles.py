#!/usr/bin/env python3
"""城都：把原版 pokecrystal 的训练家队伍与野生遭遇写进我们的地图 json。

数据来源（全部取自 pokecrystal 开源工程，不自己编）：
  data/trainers/parties.asm        训练家队伍
  maps/*.asm                       object_event 里 OBJECTTYPE_TRAINER 的位置与脚本名
  data/wild/johto_grass.asm        草丛
  data/wild/johto_water.asm        水面

坐标：原版 8x8 小格 / 2 = 我们的一格，跟 gen_johto.py 用同一套吸附规则。
"""
import json
import os
import re
import sys

ROOT = "/root/build/pokecrystal"
PROJ = "/root/build/pokesaga"
MAPSDIR = os.path.join(PROJ, "content/regions/johto/maps")
EMAPS = os.path.join(PROJ, "content/emerald_maps")

SLOT_W = [30, 30, 20, 10, 5, 4, 1]
WATER_W = [60, 30, 10]

# 训练家职业 -> 中文称呼（用于 NPC 显示名与开场白）
CLASS_CN = {
    "LEADER": "馆主", "YOUNGSTER": "短裤小子", "SCHOOLBOY": "学生",
    "BIRD_KEEPER": "养鸟人", "LASS": "少女", "COOLTRAINER": "精英训练家",
    "BEAUTY": "大姐姐", "POKEMANIAC": "宝可梦狂", "GRUNTM": "火箭队队员",
    "GRUNTF": "火箭队队员", "SCIENTIST": "研究员", "SWIMMERM": "游泳者",
    "SWIMMERF": "游泳者", "SAILOR": "水手", "SUPER_NERD": "理科男",
    "HIKER": "登山男", "BIKER": "暴走族", "PICNICKER": "野餐少女",
    "CAMPER": "露营少年", "FISHER": "钓鱼人", "TWINS": "双胞胎",
    "POKEFANM": "宝可梦迷", "POKEFANF": "宝可梦迷", "KIMONO_GIRL": "舞女",
    "SAGE": "和尚", "MEDIUM": "灵媒", "GENTLEMAN": "绅士",
    "TEACHER": "老师", "PSYCHIC_T": "超能力者", "JUGGLER": "杂技师",
    "BOARDER": "滑板少年", "SKIER": "滑雪者", "FIREBREATHER": "喷火者",
    "BLACKBELT": "空手道王", "PSYCHIC": "超能力者", "BUG_CATCHER": "捕虫少年",
    "OFFICER": "巡警", "MILITARY": "军人", "MUSICIAN": "音乐家",
    "EXECUTIVEM": "火箭队干部", "EXECUTIVEF": "火箭队干部", "POKEMON_PROF": "博士",
    "RIVAL": "劲敌", "CHAMPION": "冠军", "ELITE_FOUR": "四天王",
    "PKMN_TRAINER": "宝可梦训练家", "MYSTICALMAN": "神秘男", "PASSERBY": "旅人",
}

# 道馆馆主是 OBJECTTYPE_SCRIPT 的对象，脚本名不带 Trainer 前缀，
# 只能按原版精灵名认人；徽章名沿用中文译名。
LEADERS = {
    "SPRITE_FALKNER": ("Falkner", "飞翼徽章"),
    "SPRITE_BUGSY": ("Bugsy", "昆虫徽章"),
    "SPRITE_WHITNEY": ("Whitney", "标准徽章"),
    "SPRITE_MORTY": ("Morty", "魅影徽章"),
    "SPRITE_CHUCK": ("Chuck", "打击徽章"),
    "SPRITE_JASMINE": ("Jasmine", "矿物徽章"),
    "SPRITE_PRYCE": ("Pryce", "冰川徽章"),
    "SPRITE_CLAIR": ("Clair", "升龙徽章"),
}

LEADER_CN = {"Falkner": "阿速", "Bugsy": "阿笔", "Whitney": "小茜",
             "Morty": "松叶", "Chuck": "阿四", "Jasmine": "阿蜜",
             "Pryce": "柳伯", "Clair": "小椿"}

INTRO = ["来一场吧！", "正好手痒。", "我的宝可梦可不弱。"]
LOSE = ["输得心服口服。", "你比我想的强。", "再练练吧，我。"]


def read(p):
    with open(p, encoding="utf-8", errors="ignore") as f:
        return f.read()


def camel(s):
    out = ""
    for w in re.split(r"[^A-Za-z0-9]+", s):
        if w:
            out += w[0].upper() + w[1:].lower()
    return out


# ---------- 名称表 ----------
def norm_keys(rows, field="key"):
    out = {}
    for r in rows:
        if isinstance(r, dict) and field in r:
            out[re.sub(r"[^A-Z0-9]", "", str(r[field]).upper())] = r
    return out


SPECIES = norm_keys(json.load(open(os.path.join(PROJ, "content/species.json"))))
MOVES = norm_keys(json.load(open(os.path.join(PROJ, "content/moves.json"))))
ITEMS = norm_keys(json.load(open(os.path.join(PROJ, "content/items.json"))))


def sid(name):
    r = SPECIES.get(re.sub(r"[^A-Z0-9]", "", name.upper()))
    return int(r["id"]) if r else 0


def mid(name):
    r = MOVES.get(re.sub(r"[^A-Z0-9]", "", name.upper()))
    return int(r["id"]) if r else 0


def iid(name):
    r = ITEMS.get(re.sub(r"[^A-Z0-9]", "", name.upper()))
    return int(r["id"]) if r else 0


# ---------- 训练家队伍 ----------
GROUPS = {}


def parse_parties():
    GROUPS.clear()
    txt = read(os.path.join(ROOT, "data/trainers/parties.asm"))
    out = {}
    group = None
    cur = None
    for raw in txt.splitlines():
        line = raw.split(";")[0].rstrip()
        if not line.strip():
            continue
        m = re.match(r"^(\w+)Group:\s*$", line)
        if m:
            group = m.group(1)
            cur = None
            continue
        m = re.match(r'^\s*db\s+"([^"@]*)@",\s*TRAINERTYPE_(\w+)', line)
        if m and group:
            cur = {"name": m.group(1).strip(), "type": m.group(2), "team": [],
                   "group": group}
            key = group + camel(m.group(1))
            # 同组同名的（火箭队杂兵、双胞胎）按顺序存成列表
            GROUPS.setdefault(group, []).append(cur)
            # 同名训练家（同一人不同时期队伍）只保留第一次出现的那套
            if key not in out:
                out[key] = cur
            continue
        m = re.match(r"^\s*db\s+-1", line)
        if m:
            cur = None
            continue
        if cur is None:
            continue
        m = re.match(r"^\s*db\s+(.+)$", line)
        if not m:
            continue
        parts = [x.strip() for x in m.group(1).split(",")]
        try:
            lv = int(parts[0])
        except (ValueError, IndexError):
            continue
        if len(parts) < 2:
            continue
        mon = {"level": lv, "species": sid(parts[1])}
        t = cur["type"]
        idx = 2
        if "ITEM" in t and idx < len(parts):
            it = iid(parts[idx])
            if it:
                mon["item"] = it
            idx += 1
        if "MOVES" in t:
            mvs = []
            for p in parts[idx:idx + 4]:
                if p.upper() == "NO_MOVE":
                    continue
                v = mid(p)
                if v:
                    mvs.append(v)
            if mvs:
                mon["moves"] = mvs
        if mon["species"]:
            cur["team"].append(mon)
    return {k: v for k, v in out.items() if v["team"]}


def class_of(label):
    """从 object_event 的脚本名反推训练家职业：拿已知职业名做最长前缀匹配。"""
    lab = label[7:] if label.startswith("Trainer") else label
    best = ""
    for g in GROUPS:
        if lab.lower().startswith(g.lower()) and len(g) > len(best):
            best = g
    if best:
        return best
    m = re.match(r"^([A-Z][a-z]+)", lab)
    return m.group(1) if m else ""


def camel_group(g):
    return re.sub(r"[^A-Za-z0-9]", "", g)


def match_trainer(label, parties):
    """TrainerYoungsterJoey -> parties['YoungsterJoey']"""
    lab = label
    if lab.startswith("Trainer"):
        lab = lab[7:]
    lab = re.sub(r"_\w+$", "", lab)
    if lab in parties:
        return lab
    low = lab.lower()
    for k in parties:
        if k.lower() == low:
            return k
    # 杂兵/双胞胎：TrainerGruntM13 = GruntM 组第 13 个
    m = re.match(r"^([A-Za-z]+?)(\d+)$", lab)
    if m:
        pref = m.group(1).lower()
        idx = int(m.group(2))
        for g, lst in GROUPS.items():
            if g.lower() == pref and 0 < idx <= len(lst):
                return g + "#%d" % idx
    # 再退一步：按职业分组内按名字前缀匹配
    for k in parties:
        if low.startswith(k.lower()) or k.lower().startswith(low):
            return k
    return ""


# ---------- 坐标吸附（与 gen_johto.py 一致） ----------
def snap(meta, at8, door_hint=None):
    coll = meta["collision"]
    door = meta.get("door") or []
    cands = []
    for dx in (0, 1):
        for dy in (0, 1):
            bx = (at8[0] - dx) // 2
            by = (at8[1] - dy) // 2
            if 0 <= by < len(coll) and 0 <= bx < len(coll[0]):
                if (bx, by) not in cands:
                    cands.append((bx, by))
    if door:
        for bx, by in cands:
            if int(door[by][bx]) == 1:
                return [bx, by]
    for bx, by in cands:
        if int(coll[by][bx]) == 0:
            return [bx, by]
    return list(cands[0]) if cands else [0, 0]


def snake(label):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", label)
    s = re.sub(r"(?<=[A-Za-z])(?=[0-9])", "_", s)
    return s.lower()


_IDS = {}


def norm_id(s):
    return re.sub(r"[^a-z0-9]", "", s)


def map_id(label):
    """CamelCase 转 snake 时会和已有文件名差一个下划线（b1f / b1_f），按去下划线匹配。"""
    if not _IDS:
        for f in os.listdir(MAPSDIR):
            if f.endswith(".json"):
                _IDS[norm_id(f[:-5])] = f[:-5]
    cand = "johto_" + snake(label)
    if os.path.exists(os.path.join(MAPSDIR, cand + ".json")):
        return cand
    return _IDS.get(norm_id(cand), cand)


_CONST_OF = {}


def const_of(label):
    global _CONST_OF
    if not _CONST_OF:
        txt = read(os.path.join(ROOT, "data/maps/maps.asm"))
        labels = [m.group(1) for m in re.finditer(r"^\s*map\s+(\w+),", txt, re.M)]
        consts = [l for l in read(os.path.join(ROOT, "constants/map_constants.asm")).splitlines()]
        out = []
        for line in consts:
            m = re.match(r"^\s*map_const\s+(\w+),", line)
            if m:
                out.append(m.group(1))
        _CONST_OF = {lab: out[i] for i, lab in enumerate(labels) if i < len(out)}
    return _CONST_OF.get(label, label.upper())


def emerald_meta(label):
    p = os.path.join(EMAPS, map_id(label) + ".json")
    if not os.path.exists(p):
        return None
    return json.load(open(p))


# ---------- 野生遭遇 ----------
def parse_wild(fname, water=False):
    txt = read(os.path.join(ROOT, "data/wild", fname))
    out = {}
    cur = None
    slots = None
    for raw in txt.splitlines():
        line = raw.split(";")[0].strip()
        if not line:
            continue
        m = re.match(r"def_(?:grass|water)_wildmons\s+(\w+)", line)
        if m:
            cur = m.group(1)
            slots = {"rate": [0, 0, 0], "day": []}
            continue
        if line.startswith("end_grass_wildmons") or line.startswith("end_water_wildmons"):
            if cur:
                out[cur] = slots
            cur = None
            continue
        if cur is None:
            continue
        m = re.match(r"db\s+(\d+)\s+percent,\s*(\d+)\s+percent,\s*(\d+)\s+percent", line)
        if m:
            slots["rate"] = [int(m.group(1)), int(m.group(2)), int(m.group(3))]
            continue
        m = re.match(r"db\s+(\d+)\s+percent$", line)
        if m:
            v = int(m.group(1))
            slots["rate"] = [v, v, v]
            continue
        m = re.match(r"db\s+(\d+),\s*([A-Z0-9_]+)$", line)
        if m:
            slots["day"].append((int(m.group(1)), m.group(2)))
    return out


def wild_pool(slots, water=False):
    """三个时段取并集，权重按原版槽位概率。同物种同等级累加权重。"""
    w = WATER_W if water else SLOT_W
    acc = {}
    n = len(slots["day"]) // 3 if slots["day"] else 0
    if water:
        n = len(slots["day"])
    for t in range(1 if water else 3):
        chunk = slots["day"][t * n:(t + 1) * n]
        for i, (lv, name) in enumerate(chunk):
            s = sid(name)
            if not s:
                continue
            k = (s, lv)
            acc[k] = acc.get(k, 0) + (w[i] if i < len(w) else 1)
    pool = [{"species": k[0], "min": k[1], "max": k[1], "weight": v}
            for k, v in sorted(acc.items(), key=lambda kv: -kv[1])]
    rate = max(slots["rate"]) / 100.0
    return pool, round(min(0.55, rate), 3)


# ---------- 主流程 ----------
def main():
    parties = parse_parties()
    print("训练家队伍 %d 组" % len(parties))
    grass = parse_wild("johto_grass.asm")
    water = parse_wild("johto_water.asm", water=True)
    print("草丛 %d 张图，水面 %d 张图" % (len(grass), len(water)))

    maps = sorted(f for f in os.listdir(os.path.join(ROOT, "maps")) if f.endswith(".asm"))
    stat = {"maps": 0, "trainers": 0, "miss": 0, "wild": 0, "water": 0,
            "npc_hit": 0, "npc_miss": 0, "npc_added": 0}

    for f in maps:
        label = f[:-4]
        mj = os.path.join(MAPSDIR, map_id(label) + ".json")
        if not os.path.exists(mj):
            continue
        meta = emerald_meta(label)
        data = json.load(open(mj))
        npcs = data.get("npcs", [])
        if meta is None:
            continue
        stat["maps"] += 1

        # ---- 训练家 ----
        changed = False
        txt = read(os.path.join(ROOT, "maps", f))
        used = set()
        for m in re.finditer(r"^\s*object_event\s+(.+)$", txt, re.M):
            p = [x.strip() for x in m.group(1).split(",")]
            if len(p) < 12:
                continue
            if "OBJECTTYPE_TRAINER" not in p[9].upper():
                continue
            try:
                at8 = [int(p[0]), int(p[1])]
            except ValueError:
                continue
            script = p[11]
            key = match_trainer(script, parties)
            if not key:
                stat["miss"] += 1
                continue
            if "#" in key:
                g, idx = key.split("#")
                tr = GROUPS[g][int(idx) - 1]
            else:
                tr = parties[key]
            pos = snap(meta, at8)
            # 找同格 NPC；找不到就找最近同 gfx 的
            target = None
            for i, n in enumerate(npcs):
                if i in used:
                    continue
                if n.get("at") == pos:
                    target = i
                    break
            if target is None:
                best = None
                for i, n in enumerate(npcs):
                    if i in used:
                        continue
                    at = n.get("at") or [0, 0]
                    d = abs(at[0] - pos[0]) + abs(at[1] - pos[1])
                    if d <= 2 and (best is None or d < best[1]):
                        best = (i, d)
                if best:
                    target = best[0]
            if target is None:
                # 我们的 NPC 表里没有这个训练家（多半是当初被"清障"挪走了），
                # 直接在原版位置补一个，位置以可走格为准。
                # 不补 NPC：新加的站位会挡路（连通性/门可达自检会挂），
                # 宁可少 11 个训练家，也不破坏已经验证过的通行性
                coll = meta["collision"]
                if os.environ.get("ADD_MISSING") == "1" and 0 <= pos[1] < len(coll) and 0 <= pos[0] < len(coll[0]) and int(coll[pos[1]][pos[0]]) == 0:
                    cls0 = class_of(script)
                    cn0 = CLASS_CN.get(re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", cls0).upper(), CLASS_CN.get(cls0.upper(), "训练家"))
                    gfx0 = ("man", "训练家")
                    try:
                        import gen_johto as GJ
                        gfx0 = GJ.GFX.get(p[2], gfx0)
                    except Exception:
                        pass
                    npc_new = {"at": pos, "name": "%s %s" % (cn0, tr["name"].title()),
                               "gfx": gfx0[0], "lines": list(INTRO),
                               "battle": {"team": tr["team"]}}
                    npcs.append(npc_new)
                    used.add(len(npcs) - 1)
                    stat["npc_added"] = stat.get("npc_added", 0) + 1
                    stat["trainers"] += 1
                    moved = True
                    continue
                stat["npc_miss"] += 1
                continue
            used.add(target)
            npc = npcs[target]
            cls = class_of(script)
            cn = CLASS_CN.get(re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", cls).upper(), CLASS_CN.get(cls.upper(), "训练家"))
            nm = "%s %s" % (cn, tr["name"].title())
            if "#" in key:  # 火箭队杂兵这种同名训练家，带上编号免得"已击败"记串
                nm += " %s" % key.split("#")[1]
            npc["name"] = nm
            npc["lines"] = list(INTRO)
            npc["battle"] = {"team": tr["team"]}
            npc["trainer"] = key
            stat["trainers"] += 1
            stat["npc_hit"] += 1
            changed = True

        # ---- 道馆馆主 ----
        for m in re.finditer(r"^\s*object_event\s+(.+)$", txt, re.M):
            p = [x.strip() for x in m.group(1).split(",")]
            if len(p) < 12:
                continue
            spr = p[2]
            if spr not in LEADERS:
                continue
            grp, badge_cn = LEADERS[spr]
            lst = GROUPS.get(grp) or []
            if not lst:
                stat["leader_miss"] = stat.get("leader_miss", 0) + 1
                continue
            at8 = [int(p[0]), int(p[1])]
            pos = snap(meta, at8)
            target = None
            for i, n in enumerate(npcs):
                if i in used:
                    continue
                if n.get("at") == pos:
                    target = i
                    break
            if target is None:
                best = None
                for i, n in enumerate(npcs):
                    if i in used:
                        continue
                    at = n.get("at") or [0, 0]
                    d = abs(at[0] - pos[0]) + abs(at[1] - pos[1])
                    if d <= 3 and (best is None or d < best[1]):
                        best = (i, d)
                target = best[0] if best else None
            if target is None:
                stat["leader_miss"] = stat.get("leader_miss", 0) + 1
                continue
            used.add(target)
            npc = npcs[target]
            lead = lst[0]
            npc["name"] = "馆主 " + LEADER_CN.get(grp, lead["name"].title())
            npc["lines"] = ["想挑战道馆，先过我这关。", "让我看看你的实力。"]
            npc["battle"] = {"team": lead["team"]}
            npc["badge"] = badge_cn
            npc["trainer"] = grp
            stat["leaders"] = stat.get("leaders", 0) + 1
            changed = True

        # ---- 野生 ----
        const = const_of(label)
        if const in grass:
            pool, rate = wild_pool(grass[const])
            if pool:
                data["encounters"] = pool
                data["encounter_rate"] = rate
                stat["wild"] += 1
                changed = True
        if const in water:
            pool, rate = wild_pool(water[const], water=True)
            if pool:
                data["water_encounters"] = pool
                data["water_encounter_rate"] = rate
                stat["water"] += 1
                changed = True

        if changed:
            json.dump(data, open(mj, "w"), ensure_ascii=False, indent=1)

    print(json.dumps(stat, ensure_ascii=False))


if __name__ == "__main__":
    main()
