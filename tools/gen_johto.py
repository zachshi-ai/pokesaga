#!/usr/bin/env python3
"""把 pokecrystal 的整个城都地区接进游戏。

数据全部取自原版反汇编：
  data/maps/maps.asm            地图名 / tileset / 环境
  constants/map_constants.asm    地图尺寸（块）
  maps/<Name>.blk                方块数据 -> 渲染成 PNG
  maps/<Name>.asm                warp_events / object_events / bg_events
  data/tilesets/*                metatile + 碰撞 + 调色板

输出：
  content/emerald_maps/johto_<id>.png / .json   整图 + 碰撞（与关都同一套格式）
  content/regions/johto/maps/<id>.json          地图（npc / warp / spawn）
  content/regions/johto/region.json             地区索引
"""
import json
import os
import re
import sys

sys.path.insert(0, "/root/build/pokesaga/tools")
from render_crystal_maps import render_map  # noqa: E402

ROOT = "/root/build/pokecrystal"
EMAPS = "/root/build/pokesaga/content/emerald_maps"
REG = "/root/build/pokesaga/content/regions/johto"

# 镇/市/地点中文名
PLACE = {
    "NewBarkTown": "若叶镇", "CherrygroveCity": "樱花镇", "VioletCity": "桔梗市",
    "AzaleaTown": "桧皮镇", "GoldenrodCity": "满金市", "EcruteakCity": "圆朱市",
    "OlivineCity": "浅葱市", "CianwoodCity": "湛蓝市", "MahoganyTown": "卡吉镇",
    "BlackthornCity": "烟墨市", "SilverCave": "白银山", "SilverCaveOutside": "白银山",
    "SilverCaveRoom1": "白银山", "SilverCaveRoom2": "白银山", "SilverCaveRoom3": "白银山",
    "SilverCaveItemRooms": "白银山", "MtMoon": "月见山", "DarkCaveVioletEntrance": "黑暗洞窟",
    "DarkCaveBlackthornEntrance": "黑暗洞窟", "UnionCave1F": "互联洞窟",
    "UnionCaveB1F": "互联洞窟", "UnionCaveB2F": "互联洞窟",
    "IlexForest": "桐树林", "NationalPark": "自然公园",
    "NationalParkBugContest": "自然公园", "SproutTower": "喇叭芽之塔",
    "BellchimeTrail": "铃音小道", "TinTower": "铃铛塔", "BurnedTower": "烧焦塔",
    "WhirlIsland": "涡卷岛", "WhirlIslandNE": "涡卷岛", "WhirlIslandSW": "涡卷岛",
    "WhirlIslandSE": "涡卷岛", "WhirlIslandNW": "涡卷岛", "WhirlIslandB1F": "涡卷岛",
    "WhirlIslandB2F": "涡卷岛", "WhirlIslandLugiaChamber": "涡卷岛· Lugia 之间",
    "RuinsOfAlph": "阿尔夫遗迹", "RuinsOfAlphOutside": "阿尔夫遗迹",
    "RuinsOfAlphHoOhChamber": "阿尔夫遗迹", "RuinsOfAlphKabutoChamber": "阿尔夫遗迹",
    "RuinsOfAlphOmanyteChamber": "阿尔夫遗迹", "RuinsOfAlphAerodactylChamber": "阿尔夫遗迹",
    "RuinsOfAlphInnerChamber": "阿尔夫遗迹", "RuinsOfAlphResearchCenter": "阿尔夫遗迹·研究所",
    "SlowpokeWell": "呆呆兽之井", "TeamRocketBaseB1F": "火箭队基地",
    "LakeOfRage": "愤怒之湖", "DragonShrine": "龙之圣祠", "DragonsDen": "龙穴",
    "DragonsDenB1F": "龙穴", "IcePath": "冰雪小径", "MtMortar": "擂钵山",
    "Route22": "22 号道路", "TohjoFalls": "都汇瀑布", "MystriStage": "神秘舞台",
    "EcruteakDanceTheater": "圆朱舞剧场", "OlivineLighthouse": "浅葱灯塔",
    "RadioTower": "无线电塔", "GoldenrodUnderground": "满金地下通道",
    "GoldenrodUndergroundSwitchRoomEntrances": "满金地下通道",
    "GoldenrodUndergroundWarehouse": "满金地下仓库",
    "GoldenrodDeptStore": "满金百货", "GoldenrodGameCorner": "满金游戏城",
    "GoldenrodMagnetTrainStation": "满金磁浮列车站", "GoldenrodFlowerShop": "满金花店",
    "GoldenrodBikeShop": "满金自行车店", "GoldenrodHarbor": "满金港",
    "BattleTower": "对战塔", "BattleTowerOutside": "对战塔",
    "Pokecenter": "宝可梦中心", "Mart": "友好商店", "Gym": "道馆",
    "EliteFour": "石英高原·四天王", "ChampionsRoom": "石英高原·冠军房间",
    "LancesRoom": "石英高原·龙使房间", "KogasRoom": "石英高原·毒使房间",
    "BrunosRoom": "石英高原·格斗房间", "KarensRoom": "石英高原·恶使房间",
    "WillsRoom": "石英高原·超能房间", "HallOfFame": "名人堂",
    "ElmsLab": "空木研究所", "PlayersHouse1F": "自己家 1F", "PlayersHouse2F": "自己家 2F",
    "PlayersNeighborsHouse": "邻居家", "ElmsHouse": "空木家", "MrPokemonsHouse": "宝可梦爷爷家",
    "BillsHouse": "正辉家", "BillsFamilysHouse": "正辉老家", "BillsOlderSistersHouse": "正辉姐姐家",
    "DayCare": "培育屋", "MrPsychicsHouse": "超能先生家", "MoveDeletersHouse": "招式遗忘屋",
    "MoveManiacsHouse": "舞者之家", "NameRatersHouse": "改名屋",
    "HerbShop": "药草店", "PhotographyStudio": "照相馆", "HarborMailHouse": "港口小屋",
    "BluesHouse": "小茂家", "RedsHouse1F": "赤红家 1F", "RedsHouse2F": "赤红家 2F",
    "OaksLab": "大木研究所", "ViridianGym": "常磐道馆",
    "SilphCo": "西尔佛公司", "CeladonMansion": "玉虹大厦", "CeladonDeptStore": "玉虹百货",
    "CeladonGameCorner": "玉虹游戏城", "CeladonCafe": "玉虹咖啡厅",
    "CeladonHotel": "玉虹饭店", "CeladonPokecenter": "宝可梦中心",
    "UndergroundPath": "地下通道", "DiglettsCave": "地鼠洞", "RockTunnel": "岩山隧道",
    "TohjoFalls1": "都汇瀑布", "FastShip": "快速船",
    "MagnetTrain": "磁浮列车", "TrainerHouse": "训练家之家",
    "PokecomCenter": "宝可梦通信中心", "MobileCenter": "移动通信中心",
}

SUFFIX = [
    ("Pokecenter1F", "宝可梦中心 1F"), ("PokecenterB1F", "宝可梦中心 B1F"),
    ("Pokecenter2F", "宝可梦中心 2F"), ("Pokecenter", "宝可梦中心"),
    ("Mart", "友好商店"), ("Gym", "道馆"), ("Gym1F", "道馆 1F"),
    ("Gate", "关卡"), ("Barn", "谷仓"), ("Farmhouse", "农舍"),
    ("House", "民宅"), ("Houses", "民宅"), ("House1F", "民宅 1F"),
    ("HouseBeta", "民宅"), ("Cafe", "咖啡厅"), ("Theater", "剧场"),
    ("Lab", "研究所"), ("Tower1F", "塔 1F"), ("Tower", "塔"),
    ("Cave1F", "洞窟 1F"), ("CaveB1F", "洞窟 B1F"), ("Cave2F", "洞窟 2F"),
    ("Cave3F", "洞窟 3F"), ("Cave", "洞窟"), ("Forest", "森林"),
    ("Park", "公园"), ("Path", "小道"), ("Corridor", "回廊"),
    ("Room", "房间"), ("Rooms", "房间"), ("Stage", "舞台"),
    ("Shop", "商店"), ("SafariZoneGate", "狩猎区关卡"),
]

# 坐标单位：原版 object_event / warp_event 用的是 8x8 小格，
# 而一张地图的「块」是 16x16，正好等于我们引擎的一格，所以坐标统一除以 2。
# 原版人物图形 -> (我的贴图, 中文称呼)
GFX = {
    "SPRITE_TEACHER": ("lass", "老师"), "SPRITE_FISHER": ("sailor", "钓鱼人"),
    "SPRITE_RIVAL": ("youngster", "劲敌"), "SPRITE_MOM": ("mom", "妈妈"),
    "SPRITE_ELM": ("scientist", "空木博士"), "SPRITE_OAK": ("oak", "大木博士"),
    "SPRITE_NURSE": ("nurse", "护士"), "SPRITE_CLERK": ("clerk", "店员"),
    "SPRITE_MART_CLERK": ("clerk", "店员"), "SPRITE_MAN": ("man", "大叔"),
    "SPRITE_WOMAN": ("lass", "大姐"), "SPRITE_YOUNGSTER": ("youngster", "短裤小子"),
    "SPRITE_LASS": ("lass", "少女"), "SPRITE_BUG_CATCHER": ("bug_catcher", "捕虫少年"),
    "SPRITE_HIKER": ("hiker", "登山男"), "SPRITE_SAILOR": ("sailor", "水手"),
    "SPRITE_SUPER_NERD": ("scientist", "理科男"), "SPRITE_SCIENTIST": ("scientist", "研究员"),
    "SPRITE_POKEFAN_M": ("man", "宝可梦迷"), "SPRITE_POKEFAN_F": ("old_woman", "宝可梦迷"),
    "SPRITE_COOLTRAINER_M": ("cooltrainer_m", "训练家"),
    "SPRITE_COOLTRAINER_F": ("teala", "训练家"),
    "SPRITE_BLACK_BELT": ("blackbelt", "空手道王"),
    "SPRITE_KIMONO_GIRL": ("teala", "舞女"),
    "SPRITE_GRAMPS": ("old_man", "老爷爷"), "SPRITE_GRANNY": ("old_woman", "老奶奶"),
    "SPRITE_POKE_BALL": ("man", "道具球"), "SPRITE_GENTLEMAN": ("man", "绅士"),
    "SPRITE_OFFICER": ("clerk", "巡警"), "SPRITE_ROCKET": ("team_rocket_m", "火箭队队员"),
    "SPRITE_ROCKET_GIRL": ("team_rocket_f", "火箭队队员"),
    "SPRITE_EXECUTIVE_M": ("team_rocket_m", "火箭队干部"),
    "SPRITE_EXECUTIVE_F": ("team_rocket_f", "火箭队干部"),
    "SPRITE_GIOVANNI": ("giovanni", "坂木"),
    "SPRITE_BROCK": ("brock", "馆主 小刚"), "SPRITE_MISTY": ("teala", "馆主 小霞"),
    "SPRITE_LANCE": ("cooltrainer_m", "龙使者 阿渡"),
    "SPRITE_WHITNEY": ("teala", "馆主 小茜"),
    "SPRITE_MORTY": ("youngster", "馆主 松叶"),
    "SPRITE_CHUCK": ("blackbelt", "馆主 阿四"),
    "SPRITE_JASMINE": ("teala", "馆主 阿蜜"),
    "SPRITE_PRYCE": ("old_man", "馆主 柳伯"),
    "SPRITE_CLAIR": ("teala", "馆主 小椿"),
    "SPRITE_FALKNER": ("youngster", "馆主 阿速"),
    "SPRITE_BUGSY": ("bug_catcher", "馆主 阿笔"),
    "SPRITE_KURT": ("old_man", "阿西"), "SPRITE_MARY": ("teala", "主播 玛莉"),
    "SPRITE_BUENA": ("teala", "主播"), "SPRITE_EUSINE": ("youngster", "米那君"),
    "SPRITE_BILL": ("scientist", "正辉"), "SPRITE_KURT1": ("old_man", "阿西"),
    "SPRITE_SILVER": ("youngster", "银"), "SPRITE_KRIS": ("teala", "克丽丝"),
    "SPRITE_CHRIS": ("youngster", "克里斯"), "SPRITE_MONSTER": ("man", "宝可梦"),
    "SPRITE_FAIRY": ("teala", "妖精"), "SPRITE_BIRD": ("man", "鸟"),
    "SPRITE_DRAGON": ("man", "龙"), "SPRITE_BIG_SNORLAX": ("man", "卡比兽"),
    "SPRITE_WEIRD_TREE": ("man", "怪树"), "SPRITE_SUDOWOODO": ("man", "树才怪"),
    "SPRITE_BOULDER": ("man", "岩石"),
    "SPRITE_CUT_TREE": ("man", "小树"),
    "SPRITE_FRUIT_TREE": ("man", "果树"),
    "SPRITE_POKECOM_NURSE": ("nurse", "护士"),
    "SPRITE_SAGE": ("old_man", "和尚"), "SPRITE_MEDIUM": ("teala", "灵媒"),
    "SPRITE_TEACHER_F": ("lass", "老师"), "SPRITE_TWIN": ("lass", "双胞胎"),
    "SPRITE_CAMPER": ("camper", "露营少年"), "SPRITE_PICNICKER": ("lass", "野餐少女"),
    "SPRITE_SWIMMER_M": ("sailor", "游泳男"), "SPRITE_SWIMMER_F": ("teala", "游泳女"),
    "SPRITE_BURGLAR": ("man", "小偷"), "SPRITE_PLAYER": ("youngster", "训练家"),
}

LINES = {
    "lass": ["这条路我闭着眼都能走。", "听说北边的塔里住着传说中的宝可梦。", "天快黑了，早点回去吧。"],
    "man": ["哟，眼生得很啊。", "城都这地方，慢慢逛才有味道。", "出远门记得带足伤药。"],
    "olds": ["我年轻的时候，也到处跑。", "现在腿脚不行了，就在这里看风景。"],
    "clerk": ["欢迎光临，随便看看。", "货都在货架上，别客气。"],
    "nurse": ["欢迎来到宝可梦中心。", "需要休息的话，随时来找我。"],
    "youngster": ["我以后也要当很强的训练家！", "你的宝可梦看起来很精神。"],
    "sailor": ["海风今天不错。", "船期？看天，也看运气。"],
    "scientist": ["研究数据是不会骗人的。", "宝可梦的行为比人想的复杂得多。"],
    "bug_catcher": ["虫子是最棒的！", "草丛里能碰到不少好东西。"],
    "hiker": ["山路我熟，跟着我走不会错。", "洞窟里黑，注意脚下。"],
    "teala": ["你今天也很有精神呢。", "慢慢来，不用急。"],
    "cooltrainer_m": ["要不要来一场？", "我可是练了很久的。"],
    "blackbelt": ["心技体，缺一不可！", "来，跟我练两招。"],
    "team_rocket_m": ["别挡路。", "这里没你的事。"],
    "team_rocket_f": ["看什么看。", "识相的赶紧走开。"],
    "giovanni": ["……"],
    "brock": ["岩石的坚硬，就是我的信念。"],
    "mom": ["记得按时吃饭。", "累了就回来。"],
    "oak": ["宝可梦和人的关系，值得研究一辈子。"],
    "camper": ["露营最棒了！", "晚上能看到很多星星。"],
    "default": ["你好。", "路上小心。"],
}


def read(path):
    with open(path, "r", errors="ignore") as f:
        return f.read().replace("\r", "")


def camel_to_id(name):
    """NewBarkTown -> new_bark_town；PlayersHouse1F -> players_house_1f"""
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    s = re.sub(r"(?<=[a-z])(?=\d)", "_", s)
    s = re.sub(r"_(\d)_([A-Z])(?![a-z])", r"_\1\2", s)
    return s.lower()


def cn_name(label):
    if label in PLACE:
        return PLACE[label]
    m = re.match(r"^Route(\d+)(.*)$", label)
    if m:
        tail = m.group(2)
        return "%s 号道路%s" % (m.group(1), "（东）" if tail == "East" else "")
    # 城市/镇 + 后缀
    for town, cn in PLACE.items():
        if label.startswith(town) and label != town:
            rest = label[len(town):]
            for suf, scn in SUFFIX:
                if rest == suf:
                    return "%s·%s" % (cn, scn)
            if rest.startswith("Gate"):
                return "%s·关卡" % cn
            if re.match(r"^(B1F|1F|2F|3F|4F|5F)$", rest):
                return "%s·%s" % (cn, rest)
            return "%s·%s" % (cn, rest)
    for suf, scn in SUFFIX:
        if label.endswith(suf) and len(label) > len(suf):
            return scn
    return label


def parse_maps():
    txt = read(os.path.join(ROOT, "data/maps/maps.asm"))
    out = []
    for m in re.finditer(r"^\s*map\s+(\w+),\s*(\w+),\s*(\w+),", txt, re.M):
        out.append({"label": m.group(1), "tileset": m.group(2), "env": m.group(3)})
    return out


def parse_sizes():
    txt = read(os.path.join(ROOT, "constants/map_constants.asm"))
    sizes = {}
    for m in re.finditer(r"^\s*map_const\s+(\w+),\s*(\d+),\s*(\d+)", txt, re.M):
        sizes[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return sizes


_CONST_OF = None


def const_map():
    """maps.asm 与 map_constants.asm 的顺序一一对应，按位置建表最稳。"""
    global _CONST_OF
    if _CONST_OF is None:
        consts = [m.group(1) for m in re.finditer(
            r"^\tmap_const\s+(\w+),", read(os.path.join(ROOT, "constants/map_constants.asm")), re.M)]
        labels = [m.group(1) for m in re.finditer(
            r"^\s*map\s+(\w+),\s*\w+,\s*\w+,", read(os.path.join(ROOT, "data/maps/maps.asm")), re.M)]
        _CONST_OF = {lab: consts[i] for i, lab in enumerate(labels) if i < len(consts)}
    return _CONST_OF


def const_of(label):
    return const_map().get(label, label.upper())


def parse_map_events(label, sizes):
    path = os.path.join(ROOT, "maps", label + ".asm")
    if not os.path.exists(path):
        return [], [], []
    txt = read(path)
    warps, objs, signs = [], [], []
    for m in re.finditer(r"^\s*warp_event\s+(\d+),\s*(\d+),\s*(\w+),\s*(\d+)", txt, re.M):
        warps.append({"at8": [int(m.group(1)), int(m.group(2))],
                      "to": m.group(3), "idx": int(m.group(4))})
    for m in re.finditer(r"^\s*object_event\s+(.+)$", txt, re.M):
        p = [x.strip() for x in m.group(1).split(",")]
        if len(p) < 12:
            continue
        try:
            x, y = int(p[0]), int(p[1])
        except ValueError:
            continue
        objs.append({"at8": [x, y], "sprite": p[2], "move": p[3],
                     "color": p[8], "script": p[11] if len(p) > 11 else ""})
    for m in re.finditer(r"^\s*bg_event\s+(\d+),\s*(\d+),\s*(\w+),\s*(\w+)", txt, re.M):
        signs.append({"at8": [int(m.group(1)), int(m.group(2))],
                      "type": m.group(3), "script": m.group(4)})
    return warps, objs, signs


def snap(meta, at8, want_door=True):
    """原版坐标是 8x8 小格，一块 16x16 = 2x2 小格。
    先按 2x2 里的四种取整方式各试一次，优先落在门上，其次落在可走格。"""
    x8, y8 = at8
    coll = meta["collision"]
    door = meta.get("door") or []
    cands = []
    for dx in (0, 1):
        for dy in (0, 1):
            bx = (x8 - dx) // 2
            by = (y8 - dy) // 2
            if 0 <= by < len(coll) and 0 <= bx < len(coll[0]):
                cands.append((bx, by))
    seen = []
    for bx, by in cands:
        if (bx, by) in seen:
            continue
        seen.append((bx, by))
    if want_door and door:
        for bx, by in seen:
            if int(door[by][bx]) == 1:
                return [bx, by]
    for bx, by in seen:
        if int(coll[by][bx]) == 0:
            return [bx, by]
    # 都不行就在周围一圈找可走格
    if seen:
        return find_spawn(coll, list(seen[0]))
    return [0, 0]


def walkable(coll, x, y):
    if y < 0 or y >= len(coll):
        return False
    row = coll[y]
    if x < 0 or x >= len(row):
        return False
    return int(row[x]) == 0


def find_spawn(coll, prefer):
    if walkable(coll, prefer[0], prefer[1]):
        return prefer
    for r in range(1, 8):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if walkable(coll, prefer[0] + dx, prefer[1] + dy):
                    return [prefer[0] + dx, prefer[1] + dy]
    return prefer


def nearest_free(coll, pos, taken):
    h = len(coll)
    w = len(coll[0])
    for r in range(1, 5):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                x, y = pos[0] + dx, pos[1] + dy
                if 0 <= y < h and 0 <= x < w and int(coll[y][x]) == 0 and (x, y) not in taken:
                    return [x, y]
    return None


def nearest_in(reached, pos):
    best = None
    bestd = 1e9
    for p in reached:
        d = abs(p[0] - pos[0]) + abs(p[1] - pos[1])
        if d < bestd:
            bestd = d
            best = p
    return best


def reachable_set(coll, size, spawn, npcs, objects):
    w, h = size
    blocked = {(n["at"][0], n["at"][1]) for n in npcs}
    blocked |= {(o["at"][0], o["at"][1]) for o in objects}
    seen = {(spawn[0], spawn[1])}
    q = [tuple(spawn)]
    while q:
        x, y = q.pop()
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and 0 <= ny < h):
                continue
            if int(coll[ny][nx]) != 0:
                continue
            if (nx, ny) in blocked or (nx, ny) in seen:
                continue
            seen.add((nx, ny))
            q.append((nx, ny))
    return seen


def ensure_reach(coll, size, spawn, warps, npcs, objects):
    """门必须走得到：被 NPC 或告示牌堵住的门，把挡路的那一个撤掉。
    原版里人站着的地方确实会挡路，但城都这批图有的 NPC 正好卡在门口，
    不撤掉的话那一扇门永远进不去。"""
    w, h = size
    blocked = {}
    for n in npcs:
        blocked[(n["at"][0], n["at"][1])] = ("npc", n)
    for o in objects:
        blocked[(o["at"][0], o["at"][1])] = ("obj", o)

    def reachable(start):
        seen = {(start[0], start[1])}
        q = [tuple(start)]
        while q:
            x, y = q.pop()
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < w and 0 <= ny < h):
                    continue
                if int(coll[ny][nx]) != 0:
                    continue
                if (nx, ny) in blocked:
                    continue
                if (nx, ny) in seen:
                    continue
                seen.add((nx, ny))
                q.append((nx, ny))
        return seen

    for _ in range(400):
        seen = reachable(spawn)
        fixed = False
        for wp in warps:
            key = (wp["at"][0], wp["at"][1])
            if key in seen:
                continue
            # 门本身也可能是被挡住的：先看门四周有没有挡路的
            cands = [key]
            for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                cands.append((key[0] + dx, key[1] + dy))
            for c in cands:
                if c in blocked:
                    kind, item = blocked.pop(c)
                    if kind == "npc" and item in npcs:
                        npcs.remove(item)
                    elif kind == "obj" and item in objects:
                        objects.remove(item)
                    fixed = True
                    break
            if fixed:
                break
        if not fixed:
            break
    return npcs, objects


def lines_for(sprite, cn):
    key = "default"
    for k, (gfx, _name) in GFX.items():
        if k == sprite:
            key = gfx
            break
    pool = LINES.get(key) or LINES["default"]
    if key.startswith("old"):
        pool = LINES["olds"]
    return list(pool)


def main():
    os.makedirs(EMAPS, exist_ok=True)
    os.makedirs(os.path.join(REG, "maps"), exist_ok=True)
    maps = parse_maps()
    sizes = parse_sizes()
    by_const = {const_of(mp["label"]): mp for mp in maps}
    print("地图 %d 张" % len(maps))

    metas = {}
    made = 0
    for mp in maps:
        label = mp["label"]
        cst = const_of(label)
        if cst not in sizes:
            continue
        w, h = sizes[cst]
        ts = mp["tileset"].replace("TILESET_", "").lower()
        mid = "johto_" + camel_to_id(label)
        try:
            if not render_map(label, ts, w, h, out_dir=EMAPS, out_id=mid):
                continue
        except Exception:
            continue
        metas[label] = json.load(open(os.path.join(EMAPS, mid + ".json")))
        made += 1
        if made % 100 == 0:
            print("  渲染 %d" % made)
    print("渲染完成 %d" % made)

    # 第一遍：定门格、NPC 站位，并把走不到的门挪到最近能站的格子
    events, state = {}, {}
    for mp in maps:
        label = mp["label"]
        if label not in metas:
            continue
        warps, objs, signs = parse_map_events(label, sizes)
        meta = metas[label]
        coll = meta["collision"]
        h = len(coll)
        w = len(coll[0])
        wpos = [snap(meta, wp["at8"]) for wp in warps]
        taken = {tuple(p) for p in wpos}
        npcs = []
        for o in objs:
            gfx, nm = GFX.get(o["sprite"], ("man", "居民"))
            pos = snap(meta, o["at8"], want_door=False)
            if tuple(pos) in taken:
                pos = nearest_free(coll, pos, taken) or pos
            taken.add(tuple(pos))
            npcs.append({"at": pos, "name": nm, "gfx": gfx,
                         "lines": lines_for(o["sprite"], nm)})
        objects = []
        for sg in signs:
            pos = snap(meta, sg["at8"], want_door=False)
            if tuple(pos) in taken:
                continue
            taken.add(tuple(pos))
            objects.append({"at": pos, "kind": "sign", "sprite": "sign",
                            "text": "%s\\n（城都地区的告示牌）" % cn_name(label)})
        sp = find_spawn(coll, [w // 2, h // 2])
        npcs, objects = ensure_reach(coll, [w, h], sp, [{"at": p} for p in wpos], npcs, objects)
        reached = reachable_set(coll, [w, h], sp, npcs, objects)
        for i, p in enumerate(wpos):
            if tuple(p) not in reached:
                near = nearest_in(reached, p)
                if near:
                    wpos[i] = list(near)
        events[label] = {"warps": warps, "wpos": wpos, "signs": signs}
        state[label] = {"npcs": npcs, "objects": objects, "spawn": sp}

    # 第二遍：算落点（落点不能停在门上或人身上）
    occ = {lab: ({tuple(p) for p in ev["wpos"]} | {tuple(n["at"]) for n in st["npcs"]})
           for lab, (ev, st) in ((k, (events[k], state[k])) for k in events)}

    def arrival(tlabel, idx):
        if idx - 1 >= len(events[tlabel]["wpos"]):
            return None
        at = events[tlabel]["wpos"][idx - 1]
        coll = metas[tlabel]["collision"]
        blocked = occ.get(tlabel, set())
        for d in [(0, 1), (0, -1), (1, 0), (-1, 0), (0, 2), (0, -2), (1, 1), (-1, 1)]:
            x, y = at[0] + d[0], at[1] + d[1]
            if 0 <= y < len(coll) and 0 <= x < len(coll[0]):
                if int(coll[y][x]) == 0 and (x, y) not in blocked:
                    return [x, y]
        for r in range(1, 4):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    x, y = at[0] + dx, at[1] + dy
                    if 0 <= y < len(coll) and 0 <= x < len(coll[0]):
                        if int(coll[y][x]) == 0 and (x, y) not in blocked:
                            return [x, y]
        return None

    out_maps = []
    for mp in maps:
        label = mp["label"]
        if label not in metas:
            continue
        mid = "johto_" + camel_to_id(label)
        meta = metas[label]
        w, h = meta["size"]
        ev, st = events[label], state[label]
        out_warps = []
        for wp, pos in zip(ev["warps"], ev["wpos"]):
            tgt = by_const.get(wp["to"])
            if not tgt or tgt["label"] not in metas:
                continue
            t_at = arrival(tgt["label"], wp["idx"])
            if t_at is None:
                continue
            out_warps.append({"at": pos,
                              "to": {"region": "johto",
                                     "map": "johto_" + camel_to_id(tgt["label"]),
                                     "at": t_at}})
        data = {
            "name": cn_name(label),
            "emerald": mid,
            "size": [w, h],
            "spawn": st["spawn"],
            "npcs": st["npcs"],
            "warps": out_warps,
            "encounters": [],
            "encounter_rate": 0.0,
            "objects": st["objects"],
            "weather": "",
            "weather_name": "",
            "cycling": mp["env"] == "ROUTE",
        }
        json.dump(data, open(os.path.join(REG, "maps", mid + ".json"), "w"),
                  ensure_ascii=False, separators=(",", ":"))
        out_maps.append(mid)

    region = {
        "id": "johto",
        "name": "城都",
        "tileset": "johto_general",
        "music": "route",
        "maps": sorted(out_maps),
        "start": "johto_new_bark_town",
        "encounters": [],
        "encounter_rate": 0.0,
    }
    json.dump(region, open(os.path.join(REG, "region.json"), "w"),
              ensure_ascii=False, indent=1)
    print("地图数 %d，NPC %d" % (len(out_maps), sum(len(s["npcs"]) for s in state.values())))


if __name__ == "__main__":
    main()
