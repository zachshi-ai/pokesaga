#!/usr/bin/env python3
"""把关都/七岛地图上的东西补齐：训练家、告示牌、隐藏道具、地上的道具球、树果树，
外加每张图的天气、能不能骑车。

数据全部来自火红原版：object_events / bg_events / scripts.inc 里的中文台词 /
trainers_frlg.party 里的队伍。
用法: python3 tools/gen_world_extras.py
"""
import json
import os
import re

PJ = "/root/build/pokesaga"
ROOT = "/root/build/pokeemerald-expansion-master"
MD = os.path.join(ROOT, "data/maps")
EM = os.path.join(PJ, "content/emerald_maps")

ITEM_ZH = {
    "ITEM_POKE_BALL": ("精灵球", "ball", 200), "ITEM_GREAT_BALL": ("超级球", "ball", 600),
    "ITEM_ULTRA_BALL": ("高级球", "ball", 1200), "ITEM_NEST_BALL": ("巢穴球", "ball", 1000),
    "ITEM_NET_BALL": ("捕网球", "ball", 1000),
    "ITEM_POTION": ("伤药", "heal", 300), "ITEM_SUPER_POTION": ("好伤药", "heal", 700),
    "ITEM_HYPER_POTION": ("厉害伤药", "heal", 1200), "ITEM_MAX_POTION": ("全满药", "heal", 2500),
    "ITEM_FULL_RESTORE": ("全复药", "heal", 3000), "ITEM_REVIVE": ("活力碎片", "heal", 1500),
    "ITEM_MAX_REVIVE": ("活力块", "heal", 4000),
    "ITEM_ANTIDOTE": ("解毒药", "heal", 100), "ITEM_PARALYZE_HEAL": ("麻痹药", "heal", 200),
    "ITEM_BURN_HEAL": ("灼伤药", "heal", 250), "ITEM_ICE_HEAL": ("解冻药", "heal", 250),
    "ITEM_AWAKENING": ("解眠药", "heal", 250), "ITEM_FULL_HEAL": ("万灵药", "heal", 600),
    "ITEM_ETHER": ("PP 单项小补剂", "heal", 1200), "ITEM_MAX_ETHER": ("PP 单项全补剂", "heal", 2000),
    "ITEM_ELIXIR": ("PP 多项小补剂", "heal", 3000), "ITEM_MAX_ELIXIR": ("PP 多项全补剂", "heal", 4500),
    "ITEM_REPEL": ("除虫喷雾", "other", 350), "ITEM_SUPER_REPEL": ("白银喷雾", "other", 500),
    "ITEM_MAX_REPEL": ("黄金喷雾", "other", 700), "ITEM_ESCAPE_ROPE": ("离洞绳", "other", 550),
    "ITEM_LAVA_COOKIE": ("熔岩饼干", "heal", 200), "ITEM_SACRED_ASH": ("圣灰", "heal", 200),
    "ITEM_RARE_CANDY": ("神奇糖果", "other", 4800), "ITEM_PP_UP": ("PP 提升剂", "other", 9800),
    "ITEM_PP_MAX": ("PP 极限提升剂", "other", 9800),
    "ITEM_HP_UP": ("HP 增强剂", "other", 9800), "ITEM_PROTEIN": ("攻击增强剂", "other", 9800),
    "ITEM_IRON": ("防御增强剂", "other", 9800), "ITEM_CALCIUM": ("特攻增强剂", "other", 9800),
    "ITEM_ZINC": ("特防增强剂", "other", 9800), "ITEM_CARBOS": ("速度增强剂", "other", 9800),
    "ITEM_HEART_SCALE": ("心之鳞片", "other", 100), "ITEM_NUGGET": ("金珠", "other", 10000),
    "ITEM_BIG_NUGGET": ("巨大金珠", "other", 40000),
    "ITEM_PEARL": ("珍珠", "other", 1400), "ITEM_BIG_PEARL": ("大珍珠", "other", 7500),
    "ITEM_STARDUST": ("星砂", "other", 2000), "ITEM_STAR_PIECE": ("星之碎片", "other", 9800),
    "ITEM_TINY_MUSHROOM": ("小蘑菇", "other", 500), "ITEM_BIG_MUSHROOM": ("大蘑菇", "other", 5000),
    "ITEM_FIRE_STONE": ("火之石", "other", 2100), "ITEM_WATER_STONE": ("水之石", "other", 2100),
    "ITEM_THUNDER_STONE": ("雷之石", "other", 2100), "ITEM_LEAF_STONE": ("叶之石", "other", 2100),
    "ITEM_MOON_STONE": ("月之石", "other", 2100), "ITEM_SUN_STONE": ("日之石", "other", 2100),
    "ITEM_EVERSTONE": ("不变之石", "held", 3000), "ITEM_SOOTHE_BELL": ("安抚之铃", "held", 4000),
    "ITEM_MACHO_BRACE": ("强制锻炼器", "held", 3000), "ITEM_LEFTOVERS": ("吃剩的东西", "held", 4000),
    "ITEM_BLACK_GLASSES": ("黑色眼镜", "held", 1000), "ITEM_SILPH_SCOPE": ("西尔佛检视镜", "key", 0),
    "ITEM_LIFT_KEY": ("电梯钥匙", "key", 0), "ITEM_KEY_TO_ROOM_1": ("1 号房间钥匙", "key", 0),
    "ITEM_KEY_TO_ROOM_2": ("2 号房间钥匙", "key", 0), "ITEM_KEY_TO_ROOM_4": ("4 号房间钥匙", "key", 0),
    "ITEM_KEY_TO_ROOM_6": ("6 号房间钥匙", "key", 0),
    "ITEM_RED_SHARD": ("红色碎片", "other", 300), "ITEM_BLUE_SHARD": ("蓝色碎片", "other", 300),
    "ITEM_GREEN_SHARD": ("绿色碎片", "other", 300), "ITEM_YELLOW_SHARD": ("黄色碎片", "other", 300),
}
BERRY_ZH = {
    "ITEM_CHERI_BERRY": "樱子果", "ITEM_CHESTO_BERRY": "零余子果", "ITEM_PECHA_BERRY": "桃桃果",
    "ITEM_RAWST_BERRY": "莓莓果", "ITEM_ASPEAR_BERRY": "利木果", "ITEM_LEPPA_BERRY": "苹野果",
    "ITEM_ORAN_BERRY": "橙橙果", "ITEM_PERSIM_BERRY": "柿仔果", "ITEM_LUM_BERRY": "木子果",
    "ITEM_SITRUS_BERRY": "文柚果", "ITEM_RAZZ_BERRY": "蔓莓果", "ITEM_BLUK_BERRY": "墨莓果",
    "ITEM_NANAB_BERRY": "蕉香果", "ITEM_WEPEAR_BERRY": "西梨果", "ITEM_PINAP_BERRY": "凰梨果",
    "ITEM_POMEG_BERRY": "石榴果", "ITEM_KELPSY_BERRY": "比巴果", "ITEM_QUALOT_BERRY": "哈密果",
    "ITEM_HONDEW_BERRY": "萄葡果", "ITEM_GREPA_BERRY": "茄番果", "ITEM_TAMATO_BERRY": "茄番果",
}

WEATHER_ZH = {
    "WEATHER_NONE": "", "WEATHER_RAIN": "雨", "WEATHER_SNOW": "雪", "WEATHER_THUNDERSTORM": "雷雨",
    "WEATHER_FOG_HORIZONTAL": "雾", "WEATHER_SHADE": "阴", "WEATHER_SANDSTORM": "沙尘",
    "WEATHER_VOLCANIC_ASH": "火山灰", "WEATHER_SUNNY": "晴", "WEATHER_UNDERWATER": "",
}


def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("frlg", ""))


def zh_item(key):
    m = re.match(r"ITEM_(TM|HM)(\d+)$", str(key))
    if m:
        n = int(m.group(2))
        if m.group(1) == "TM":
            return "招式学习器 %02d" % n, "tm", 3000
        return "秘传学习器 %02d" % n, "tm", 0
    if key in BERRY_ZH:
        return BERRY_ZH[key], "berry", 100
    if key in ITEM_ZH:
        return ITEM_ZH[key]
    return None


def parse_text(label, text):
    i = text.find(label + "::")
    if i < 0:
        return ""
    seg = text[i + len(label) + 2:]
    j = seg.find("::")
    if j >= 0:
        # 遇到下一个标签就停，只保留 .string 行
        head = seg[:j]
        if ".string" not in head:
            seg = seg
        else:
            seg = head
    out = []
    for line in seg.split("\n"):
        line = line.strip()
        if not line.startswith(".string"):
            continue
        s = line[line.find('"') + 1:]
        if s.endswith('"'):
            s = s[:-1]
        out.append(s)
    doc = "".join(out)
    doc = doc.replace("\\n", "\n").replace("\\p", "\n").replace("\\l", "").replace("$", "")
    doc = doc.replace('\\"', '"').strip()
    return doc


def parse_party(path):
    """trainers_frlg.party -> {TRAINER_ID: {"name":..,"class":..,"party":[(species,level)]}}"""
    out = {}
    cur = None
    if not os.path.exists(path):
        return out
    for raw in open(path, errors="ignore"):
        line = raw.rstrip("\n")
        if line.startswith("=== "):
            cur = {"name": "", "class": "", "party": []}
            out[line.strip("= ").strip()] = cur
            continue
        if cur is None:
            continue
        line = line.strip()
        if line.startswith("Name:"):
            cur["name"] = line.split(":", 1)[1].strip()
        elif line.startswith("Class:"):
            cur["class"] = line.split(":", 1)[1].strip()
        elif re.match(r"^Level:\s*\d+", line):
            lv = int(re.findall(r"\d+", line)[0])
            if cur.get("_last"):
                cur["party"].append((cur["_last"], lv))
        elif line.strip() and ":" not in line:
            cur["_last"] = line.strip()
    return out


def main():
    species = {norm(s["key"]): s["id"] for s in json.load(open(os.path.join(PJ, "content/species.json")))}
    alias = {"nidoranf": "NIDORAN_F", "nidoranm": "NIDORAN_M", "mrmime": "MR_MIME",
             "farfetchd": "FARFETCHD", "hooh": "HO_OH"}
    parties = parse_party(os.path.join(ROOT, "src/data/trainers_frlg.party"))
    battle_inc = open(os.path.join(ROOT, "data/scripts/trainers_frlg.inc"), errors="ignore").read()
    ball_inc = ""
    bp = os.path.join(ROOT, "data/scripts/item_ball_scripts_frlg.inc")
    if os.path.exists(bp):
        ball_inc = open(bp, errors="ignore").read()

    # 训练家脚本 -> (TRAINER_ID, intro label, post label)
    trainer_scripts = {}
    for m in re.finditer(r"^(\w+)::\n((?:\t.*\n)+)", battle_inc, re.M):
        lab, body = m.group(1), m.group(2)
        tm = re.search(r"trainerbattle_single\s+(TRAINER_\w+),\s*(\w+),\s*(\w+)", body)
        if not tm:
            continue
        post = ""
        pm = re.search(r"msgbox\s+(\w+),\s*MSGBOX_AUTOCLOSE", body)
        if pm:
            post = pm.group(1)
        trainer_scripts[lab] = (tm.group(1), tm.group(2), post)

    rooms = {}
    for rid in ("kanto", "sevii"):
        d = os.path.join(PJ, "content/regions", rid, "maps")
        for f in os.listdir(d):
            if f.endswith(".json") and f != "kanto_main.json":
                rooms[(rid, f[:-5])] = json.load(open(os.path.join(d, f)))

    by_norm = {}
    for (rid, gid) in rooms:
        by_norm[norm(gid)] = (rid, gid)
    # 大图上那 38 块室外图：往 kanto_main 上摆，坐标要加偏移
    host_off = json.load(open(os.path.join(EM, "kanto_main.json")))["member_maps"]
    hosts = {norm(k): (k, v) for k, v in host_off.items()}
    bigp = os.path.join(PJ, "content/regions/kanto/maps/kanto_main.json")
    big_room = json.load(open(bigp))
    rooms[("kanto", "kanto_main")] = big_room
    berry_list = ["ORAN_BERRY", "CHERI_BERRY", "PECHABERRY", "RAWST_BERRY", "LEPPA_BERRY",
                  "SITRUS_BERRY", "LUM_BERRY", "PINAP_BERRY", "RAZZ_BERRY", "NANAB_BERRY"]

    trainers_db = {}
    stats = {"trainer": 0, "sign": 0, "hidden": 0, "ball": 0, "berry": 0}
    for d in sorted(os.listdir(MD)):
        if not d.endswith("_Frlg"):
            continue
        key = norm(d[:-5])
        hit = by_norm.get(key) or by_norm.get("map" + key)
        off = None
        if hit:
            rid, gid = hit
            room = rooms[(rid, gid)]
        elif key in hosts:
            rid, gid = "kanto", "kanto_main"
            room = big_room
            off = hosts[key][1]
        else:
            continue
        mp = os.path.join(MD, d, "map.json")
        sp = os.path.join(MD, d, "scripts.inc")
        m = json.load(open(mp))
        text = open(sp, errors="ignore").read() if os.path.exists(sp) else ""

        objs = []
        for oe in m.get("object_events", []):
            g = str(oe.get("graphics_id", ""))
            lab = str(oe.get("script", ""))
            at = [int(oe["x"]), int(oe["y"])]
            if off:
                at = [at[0] + off[0], at[1] + off[1]]
            if "ITEM_BALL" in g:
                seg = ""
                for src in (text, ball_inc):
                    i = src.find(lab + "::")
                    if i >= 0:
                        seg = src[i:i + 500]
                        break
                mm = re.search(r"finditem\s+(ITEM_[A-Z_0-9]+)", seg)
                if mm:
                    k = mm.group(1)
                    info = zh_item(k)
                    name = info[0] if info else k
                    cat = info[1] if info else "other"
                    objs.append({"at": at, "kind": "item", "item": k, "name": name,
                                 "category": cat, "sprite": "ball"})
                    stats["ball"] += 1
                continue
            if "BERRY_TREE" in g:
                bk = berry_list[len(objs) % len(berry_list)]
                objs.append({"at": at, "kind": "berry_tree", "sprite": "tree", "berry": bk})
                stats["berry"] += 1
                continue
            if oe.get("trainer_type", "TRAINER_TYPE_NONE") == "TRAINER_TYPE_NONE":
                continue
            entry = trainer_scripts.get(lab)
            if not entry:
                continue
            tid, intro, post = entry
            pty = parties.get(tid)
            if not pty or not pty["party"]:
                continue
            party = []
            for sp_name, lv in pty["party"][:6]:
                sid = species.get(norm(sp_name)) or species.get(norm(alias.get(norm(sp_name), "")))
                if sid:
                    party.append({"species": sid, "level": lv})
            if not party:
                continue
            intro_text = parse_text(intro, text)
            post_text = parse_text(post, text) if post else ""
            trainers_db[tid] = {"name": pty["name"], "class": pty["class"], "party": party}
            gfx_map = {
                "YOUNGSTER": "youngster", "LASS": "lass", "BUG_CATCHER": "bug_catcher",
                "HIKER": "hiker", "CAMPER": "camper", "SAILOR": "sailor",
                "SCIENTIST": "scientist", "BLACKBELT": "blackbelt", "SUPER_NERD": "scientist",
                "COOLTRAINER": "cooltrainer_m", "TEAM_ROCKET": "team_rocket_m",
                "PICNICKER": "lass", "FISHER": "sailor", "PSYCHIC": "expert_m",
                "GENTLEMAN": "old_man", "BEAUTY": "lass", "BIKER": "hiker",
            }
            gid_s = "man"
            for k, v in gfx_map.items():
                if k in str(oe.get("graphics_id", "")).upper():
                    gid_s = v
                    break
            room.setdefault("npcs", []).append({
                "at": at, "name": "%s 的 %s" % (pty["class"].replace(" Frlg", ""), pty["name"]),
                "gfx": gid_s, "lines": [intro_text] if intro_text else ["……"],
                "battle": {"trainer": tid, "party": party, "name": pty["name"],
                           "class": pty["class"].replace(" Frlg", "")},
                "post": [post_text] if post_text else [],
                "sight": int(oe.get("trainer_sight_or_berry_tree_id", 0) or 0)})
            stats["trainer"] += 1

        for be in m.get("bg_events", []):
            at = [int(be["x"]), int(be["y"])]
            if off:
                at = [at[0] + off[0], at[1] + off[1]]
            if be.get("type") == "sign":
                t = parse_text(str(be.get("script", "")), text)
                if t:
                    objs.append({"at": at, "kind": "sign", "sprite": "sign", "text": t})
                    stats["sign"] += 1
            elif be.get("type") == "hidden_item":
                k = str(be.get("item", ""))
                if k in ("", "ITEM_NONE"):
                    continue
                info = zh_item(k)
                if not info:
                    continue
                objs.append({"at": at, "kind": "hidden", "item": k, "name": info[0],
                             "category": info[1], "flag": str(be.get("flag", "")),
                             "count": int(be.get("quantity", 1) or 1)})
                stats["hidden"] += 1

        if objs:
            room.setdefault("objects", []).extend(objs)
        room["weather"] = str(m.get("weather", "WEATHER_NONE")).replace("WEATHER_", "").lower()
        room["weather_name"] = WEATHER_ZH.get(str(m.get("weather", "")), "")
        room["cycling"] = bool(m.get("allow_cycling", False))
        rooms[(rid, gid)] = room
        if rid == "kanto" and gid == "kanto_main":
            big_room = room

    # 写回
    for (rid, gid), room in rooms.items():
        p = os.path.join(PJ, "content/regions", rid, "maps", gid + ".json")
        json.dump(room, open(p, "w"), ensure_ascii=False, indent=1)

    json.dump(trainers_db, open(os.path.join(PJ, "content/trainers_db.json"), "w"),
              ensure_ascii=False, indent=1)
    print("训练家 %d，告示牌 %d，隐藏道具 %d，道具球 %d，树果树 %d"
          % (stats["trainer"], stats["sign"], stats["hidden"], stats["ball"], stats["berry"]))
    print("训练家队伍表 %d 条" % len(trainers_db))


if __name__ == "__main__":
    main()
