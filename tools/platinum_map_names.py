"""Simplified Chinese names for Platinum map headers, including rooms and variants."""
import re

# Gen IV location names use the Simplified Chinese location tables published by PKHeX
# (Resources/text/locations/gen4 and gen8b). Individual rooms follow the Platinum headers.
PLACES = {
    "twinleaf_town": "双叶镇", "sandgem_town": "真砂镇", "floaroma_town": "花苑镇",
    "solaceon_town": "随意镇", "celestic_town": "神和镇", "jubilife_city": "祝庆市",
    "canalave_city": "水脉市", "oreburgh_city": "黑金市", "eterna_city": "百代市",
    "hearthome_city": "家缘市", "pastoria_city": "野原市", "veilstone_city": "帷幕市",
    "sunyshore_city": "滨海市", "snowpoint_city": "雪峰市", "pokemon_league": "神奥联盟",
    "oreburgh_mine": "黑金炭坑", "valley_windworks": "山谷发电厂", "eterna_forest": "百代森林",
    "fuego_ironworks": "多多罗钢铁厂", "mt_coronet": "天冠山", "spear_pillar": "枪之柱",
    "great_marsh": "大湿地", "solaceon_ruins": "随意遗迹", "victory_road": "冠军之路",
    "pal_park": "伙伴公园", "amity_square": "互动广场", "ravaged_path": "荒芜小道",
    "floaroma_meadow": "花苑花田", "oreburgh_gate": "黑金闸口", "fullmoon_island": "满月岛",
    "sendoff_spring": "送行之泉", "turnback_cave": "归途洞窟", "flower_paradise": "花之乐园",
    "snowpoint_temple": "雪峰神殿", "wayward_cave": "迷幻洞窟", "ruin_maniac_cave": "遗迹迷洞穴",
    "maniac_tunnel": "遗迹迷隧道", "trophy_garden": "自豪的后院", "iron_island": "钢铁岛",
    "old_chateau": "森之洋馆", "galactic_hq": "银河队基地", "verity_lakefront": "心齐湖畔",
    "valor_lakefront": "立志湖畔", "acuity_lakefront": "睿智湖畔", "spring_path": "隐泉之路",
    "lake_verity": "心齐湖", "lake_valor": "立志湖", "lake_acuity": "睿智湖",
    "newmoon_island": "新月岛", "battle_tower": "对战塔", "fight_area": "战斗区",
    "survival_area": "生存区", "resort_area": "名胜区", "stark_mountain": "严酷山",
    "seabreak_path": "破海之路", "hall_of_origin": "起始之殿", "verity_cavern": "心齐湖洞窟",
    "valor_cavern": "立志湖洞窟", "acuity_cavern": "睿智湖洞窟", "jubilife_tv": "祝庆电视台",
    "poketch_co": "宝可表公司", "trainers_school": "训练家学校", "mining_museum": "黑金炭坑博物馆",
    "flower_shop": "花苑花店", "cycle_shop": "自行车店", "contest_hall": "华丽大赛会场",
    "poffin_house": "宝芬料理厨房", "foreign_building": "异文化建筑", "pokemon_day_care": "宝可梦培育屋",
    "veilstone_store": "帷幕百货", "game_corner": "帷幕游戏城", "canalave_library": "水脉图书馆",
    "vista_lighthouse": "导航灯塔", "sunyshore_market": "滨海市场", "pokemon_mansion": "宝可梦屋",
    "footstep_house": "足迹博士的家", "cafe": "山间小屋咖啡馆", "grand_lake": "湖畔大饭店",
    "restaurant": "七星餐厅", "battle_frontier": "对战开拓区", "battle_factory": "对战工厂",
    "battle_castle": "对战城堡", "battle_arcade": "对战轮盘", "battle_hall": "对战舞台",
    "distortion_world": "毁坏的世界", "global_terminal": "全球终端", "villa": "名胜区别墅",
    "battleground": "对决场", "rotoms_room": "洛托姆的房间", "team_galactic_eterna_building": "银河百代大厦",
    "iron_ruins": "黑金遗迹", "iceberg_ruins": "冰山遗迹", "rock_peak_ruins": "岩山遗迹",
    "wifi_plaza_entrance": "无线广场入口", "union_room": "联合交谊厅", "underground": "地下通道",
    "communication_club_colosseum_2p": "通信俱乐部·双人竞技场", "communication_club_colosseum_4p": "通信俱乐部·四人竞技场",
    "record_mixing_room": "混合记录室",
}

DIRECTIONS = {
    "north": "北", "east": "东", "south": "南", "west": "西", "middle": "中央",
    "northeast": "东北", "northwest": "西北", "southeast": "东南", "southwest": "西南",
}

ROOMS = {
    "pokecenter": "宝可梦中心", "north_pokecenter": "北侧宝可梦中心", "south_pokecenter": "南侧宝可梦中心",
    "mart": "友好商店", "harbor_inn": "海港旅馆", "sailor_eldritch_house": "水手的家",
    "gym": "道馆", "dp_gym": "旧道馆", "cave": "洞窟", "trainer_room": "训练家室",
    "gym_entrance_room": "道馆入口", "gym_leader_room": "道馆馆主室", "dp_gym_leader_room": "旧道馆馆主室",
    "stage_no_contest": "舞台", "stage_ongoing_contest": "比赛舞台", "lobby": "大厅",
    "turnback_cave_room": "归途洞窟入口", "giratina_room": "骑拉帝纳所在之处",
    "condominiums": "公寓", "herb_shop": "草药店", "underground_man_house": "地下大叔的家",
    "outside": "外围", "house": "民居", "building": "厂房", "forest": "林深处",
    "control_room": "控制室", "hall": "集会厅", "laboratory": "实验室", "elevator": "升降机",
    "pokemon_fan_club": "宝可梦爱好俱乐部", "east_gate_to_amity_square": "互动广场东门",
    "west_gate_to_amity_square": "互动广场西门", "gallery": "展示厅", "global_ranking_room": "世界排名室",
    "group_ranking_room": "团体排名室", "low_water": "浅水区", "drained": "干涸的湖床",
    "outside_north": "北侧山腰", "outside_south": "南侧山腰", "tunnel_room": "隧道",
    "back_east_room": "后廊东室", "back_middle_east_room": "后廊中东室", "back_middle_room": "后廊中央室",
    "back_middle_west_room": "后廊中西室", "back_west_room": "后廊西室", "corridor": "走廊",
    "dining_area": "餐厅", "side_rooms": "侧翼客房", "left_room": "左侧洞室", "right_room": "右侧洞室",
    "observatory_gate": "大湿地展望台", "dp_great_marsh": "旧大湿地", "hall_of_fame": "名人堂",
    "hallway_to_hall_of_fame": "通往名人堂的走廊", "maids_room": "女仆休息室", "office": "办公室",
    "ribbon_syndicate": "奖章联合组织", "cycling_road_north_gate": "自行车道北门",
    "cycling_road_south_gate": "自行车道南门", "grandma_wilma_house": "龙婆婆的家", "lost_tower": "迷失塔",
    "short": "开掘处", "long": "洞穴深处", "counterpart_house": "小光的家",
    "pokemon_research_lab": "山梨博士研究所", "maniac_tunnel_room": "遗迹迷隧道尽头",
    "pokemon_news_press": "宝可梦报社", "dialga": "帝牙卢卡的裂隙", "palkia": "帕路奇亚的裂隙",
    "distorted": "时空裂隙", "entrance": "入口", "pillar_room": "石柱室", "player_house": "小悠的家",
    "rival_house": "阿驯的家", "galactic_warehouse": "银河队仓库", "prize_exchange": "奖品兑换处",
    "battle_room": "对战室", "battle_salon": "对战沙龙", "corridor_multi": "多人对战走廊",
    "multi_battle_room": "多人对战室", "iceberg_ruins": "冰山遗迹", "rock_peak_ruins": "岩山遗迹",
    "iron_ruins": "黑金遗迹", "aaron_room": "阿柳之室", "bertha_room": "菊野之室",
    "flint_room": "大叶之室", "lucian_room": "悟松之室", "champion_room": "冠军室",
}

# These headers have no field names in the disassembly. Its mapGroup/locationName identifies
# their actual areas; do not surface UNKNOWN_ identifiers as place names.
UNNAMED = {
    197: "黑金炭坑·1层", 250: "伙伴公园", 255: "花苑花田", 275: "民居",
    304: "互动广场关口", 324: "神秘地带", 325: "神秘地带", 511: "起始之殿",
    561: "对战塔", 570: "毁坏的世界", 572: "银河百代大厦·1层", 578: "毁坏的世界",
}

def _place(key):
    if match := re.match(r"route_(\d+)(?:_|$)", key):
        return f"{match[1]}号道路", key[match.end():]
    for place in PLACES:
        if key == place or key.startswith(place + "_"):
            return PLACES[place], key[len(place):].lstrip("_")
    raise ValueError(f"Unknown Platinum location: {key}")

def _room(key):
    if key in ROOMS:
        return ROOMS[key]
    if key in DIRECTIONS:
        return DIRECTIONS[key] + "段"
    if match := re.fullmatch(r"(\w+)_house", key):
        side = DIRECTIONS[match[1]]
        return side + ("民居" if side == "中央" else "侧民居")
    if match := re.fullmatch(r"(b?)(\d+)f", key):
        return ("地下" if match[1] else "") + match[2] + "层"
    if match := re.fullmatch(r"(?:([a-z_]+)_)?(b?\d+f)(?:_(.+))?", key):
        return "·".join(_room(part) for part in match.groups() if part)
    if match := re.fullmatch(r"(.+)_elevator", key):
        return _room(match[1]) + "升降机"
    if match := re.fullmatch(r"elevator_to_(.+)", key):
        return "通往" + _room(match[1]) + "的升降机"
    if match := re.fullmatch(r"gate_to_(.+)", key):
        return "通往" + map_name("MAP_HEADER_" + match[1].upper()) + "的关口"
    if match := re.fullmatch(r"(dp_gym_elevator_room|dp_gym_trainer_room|gym_trainer_room|gym_room|room|north_room)_(\d+)", key):
        titles = {"dp_gym_elevator_room": "旧道馆升降室", "dp_gym_trainer_room": "旧道馆训练家室",
                  "gym_trainer_room": "道馆训练家室", "gym_room": "道馆大厅", "room": "洞室", "north_room": "北侧洞室"}
        return f"{titles[match[1]]}{match[2]}"
    if match := re.fullmatch(r"rooms_(\d+)_and_(\d+)", key):
        return f"相连洞室（{match[1]}、{match[2]}）"
    if match := re.fullmatch(r"room_(\d+)_(\w+)_dead_?end", key):
        return f"第{match[1]}室·{DIRECTIONS[match[2]]}侧尽头"
    if match := re.fullmatch(r"pillar_(\d+)_room_(\d+)", key):
        return f"第{match[1]}石柱区·洞室{match[2]}"
    raise ValueError(f"Unknown Platinum room: {key}")

def map_name(source_id):
    key = source_id.removeprefix("MAP_HEADER_").lower()
    if match := re.fullmatch(r"unknown_(\d+)", key):
        number = int(match[1])
        return "归途洞窟·迷宫" if 533 <= number <= 557 else UNNAMED[number]
    base, detail = _place(key)
    if not detail:
        return base
    if base == "大湿地":
        return f"大湿地·第{int(detail)}区"
    if base == "湖畔大饭店":
        area, detail = _place(detail)
        if detail == "lobby":
            return base + "·接待大厅"
        side = DIRECTIONS[detail.removesuffix("_house")]
        return f"{base}·{area}{side}侧客房"
    if key.endswith("_city_gym"):
        return base.removesuffix("市") + "道馆"
    if key.startswith(("hearthome_city_gym_", "sunyshore_city_gym_")):
        return base.removesuffix("市") + "道馆·" + _room(detail).removeprefix("道馆")
    return base + "·" + _room(detail)
