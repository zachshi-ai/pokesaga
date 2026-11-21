extends RefCounted
## Roles retain FireRed's local object positions. Visibility feeds field rendering and collision together.
const OUTDOOR := {
	"80,387":{"add":true,"flag":"FLAG_HIDE_CINNABAR_BILL","role":"sevii_bill_outside","gfx":"fr_bill","name":"正辉"},
	"83,387":{"add":true,"flag":"FLAG_HIDE_CINNABAR_SEAGALLOP","gfx":"fr_seagallop","name":"海烈焰马号","in_water_pose":true,"lines":["海烈焰马号正在等乘客登船。"]},
	"284,234":{"add":true,"flag":"sevii_hide_vermilion_ferry","gfx":"fr_seagallop","name":"海烈焰马号","in_water_pose":true,"lines":["开往七岛的联络船停在水手身旁。"]},
	"288,233":{"add":true,"role":"sevii_ferry","gfx":"sailor","name":"码头水手","lines":["欢迎来到枯叶码头。"]},
}
const SPEAKERS := {
	"four_island":{"8,25":["sevii_rival_four","小茂","fr_blue","四之岛的培育屋很有名。"]},
	"six_island_pokemon_center_1f":{"5,5":["sevii_rival_six","小茂","fr_blue","这里的宝可梦都很有趣。"]},
	"five_island_lost_cave_room10":{"5,5":["selphy_lost","阿姿莎","lass","我在找回家的路。"]},
	"five_island_resort_gorgeous":{"39,9":["selphy_returning","阿姿莎","lass","到家了。"]},
	"five_island_resort_gorgeous_house":{
		"4,4":["selphy_home","阿姿莎","lass","你今天带了哪只宝可梦？"],
		"6,2":["selphy_butler","管家","man","小姐的谢礼都已经准备好了。"]},
	"cinnabarisland_pokemoncenter_1f":{"11,5":["sevii_bill_port","正辉","fr_bill","准备好了的话，我们就坐船去一之岛。"]},
	"one_island_pokemon_center_1f":{"14,6":["sevii_bill_lab","正辉","fr_bill","我来处理接线。二之岛的游戏厅老板正等着那块陨石。"]},
	"two_island_joyful_game_corner":{
		"5,5":["lostelle_father","游戏厅老板","pokemaniac","她平安回来，店里才又有笑声。"],
		"6,5":["lostelle_reunited","迷失妹","fr_little_girl","下次去摘树果，我会先告诉爸爸。"]},
	"three_island_berry_forest":{"4,8":["lostelle_forest","迷失妹","fr_little_girl","树丛里有声音……"]},
	"three_island_house1":{"3,4":["lostelle_home","迷失妹","fr_little_girl","你尝尝我采的树果。"]},
	"five_island_rocket_warehouse":{
		"6,6":["warehouse_grunt1","火箭队手下·入口","team_rocket_f","货单上的宝可梦一只也不能少。"],
		"15,11":["warehouse_grunt2","火箭队手下·货架","team_rocket_m","干部在仓库里头。"],
		"17,15":["warehouse_grunt3","火箭队手下·通道","team_rocket_m","谁放你进来的？"],
		"27,16":["warehouse_admin1","火箭队女干部","team_rocket_f","去吧，另一位干部在里面。"],
		"25,11":["warehouse_admin2","火箭队男干部","team_rocket_m","遇到另一位干部之后，再来找我。"],
		"27,4":["gideon","研究员·基甸","scientist","这里的货已经出手了。"]},
	"six_island_dotted_hole_sapphire_room":{"7,7":["sapphire","蓝宝石","fr_sapphire","蓝色的石头在微微发光。"]},
	"four_island_loreleis_house":{"7,4":["lorelei_home","科拿","fr_lorelei","看到岛上的宝可梦平安，我就放心了。"]},
}
const PORTS := {"one_island_harbor":"一之岛","two_island_harbor":"二之岛","three_island_harbor":"三之岛",
	"four_island_harbor":"四之岛","five_island_harbor":"五之岛","six_island_harbor":"六之岛","seven_island_harbor":"七之岛",
	"navel_rock_harbor":"肚脐岩","birth_island_harbor":"诞生岛"}
const BILL_CROSSOVER := "res://content/regions/sevii/kanto_events.json"

static func sync(save: Dictionary) -> void:
	var flags: Dictionary = save.get("flags",{})
	if "深红徽章" in save.get("badges",[]): flags.sevii_blaine_badge = true
	if flags.get("kanto_champion",false) and not flags.get("sevii_dex_ready",false):
		if preload("res://core/kanto_campaign.gd").caught_species_count(save) >= 60:
			flags.sevii_dex_ready = true
	# 4.52 allowed the Ruby to be picked up without hearing the warehouse password.
	if flags.get("story_ember_warehouse_password",false) or flags.get("beat_ember_grunt_1",false) or flags.get("beat_ember_grunt_2",false):
		flags.sevii_password_one = true
	if flags.get("got_ember_ruby",false) or flags.get("delivered_ember_ruby",false):
		flags.sevii_password_one = true
		flags.ember_ruby_requested = true
	save.flags = flags

static func speaker(map_id: String, at: Array, spec: Dictionary, flags: Dictionary) -> Dictionary:
	var definition: Array = SPEAKERS.get(map_id,{}).get("%d,%d" % at,[])
	if map_id.ends_with("_island_pokemon_center_1f"):
		var nurse_x := 5 if map_id.begins_with("one_") else 7
		if int(at[0])==nurse_x and int(at[1])==2: return spec.merged({"name":"护士","gfx":"nurse","heal":true},true)
	if map_id == "one_island_pokemon_center_2f" and int(at[0])==1 and int(at[1])==2:
		return {"role":"sevii_gift_clerk","gfx":"sailor","name":"神秘礼物配送员","lines":["两张特别船票请妥善保管。下楼到码头就能乘船。"],"flag":"sevii_hide_gift_clerk"}
	if PORTS.has(map_id) and int(at[0]) == 8 and int(at[1]) == 6:
		definition = ["sevii_ferry","海烈焰马号船员","sailor","请出示通行证。"]
	if map_id == "three_island":
		match spec.get("flag",""):
			"FLAG_HIDE_THREE_ISLAND_BIKERS":
				definition = ["sevii_biker","暴走族","fr_biker","前面有人拦路，车队正在镇子里。"]
			"FLAG_HIDE_THREE_ISLAND_ANTIBIKERS":
				definition = ["sevii_defender","岛民","man","索桥往西，树果森林就在尽头。"]
	if definition.is_empty(): return spec
	var line: String = definition[3]
	if definition[0] == "lostelle_father" and not flags.get("sevii_lostelle_rescued",false):
		line = "我在等女儿回来。"
	return spec.merged({"role":definition[0],"name":definition[1],"gfx":definition[2],"lines":[line]},true)

static func hidden(flag: String, flags: Dictionary) -> Variant:
	var visiting: bool = flags.get("sevii_visit_started",false)
	var detour_done: bool = flags.get("sevii_detour_finished",false)
	var rainbow: bool = flags.get("delivered_ember_ruby",false) and flags.get("national_dex",false) and detour_done
	match flag:
		"FLAG_HIDE_CINNABAR_BILL","FLAG_HIDE_CINNABAR_SEAGALLOP": return not flags.get("sevii_blaine_badge",false) or visiting or flags.get("sevii_bill_waits",false)
		"FLAG_HIDE_CINNABAR_POKECENTER_BILL": return not flags.get("sevii_bill_waits",false) or visiting
		"sevii_hide_vermilion_ferry": return not flags.get("sevii_meteorite_errand",false)
		"FLAG_HIDE_FOUR_ISLAND_RIVAL": return not rainbow or flags.get("sevii_rival_four",false) or flags.get("sevii_rival_six",false)
		"FLAG_HIDE_SIX_ISLAND_POKECENTER_RIVAL": return not rainbow or flags.get("sevii_rival_six",false)
		"FLAG_HIDE_LOST_CAVE_SELPHY": return not rainbow or flags.get("sevii_selphy_found",false)
		"FLAG_HIDE_RESORT_GORGEOUS_SELPHY": return not flags.get("sevii_selphy_found",false) or flags.get("sevii_selphy_home",false)
		"FLAG_HIDE_RESORT_GORGEOUS_INSIDE_SELPHY","FLAG_HIDE_SELPHYS_BUTLER": return not flags.get("sevii_selphy_home",false)
		"sevii_hide_gift_clerk": return not flags.get("sevii_network_online",false)
		"FLAG_HIDE_RIVAL_IN_LAB":
			if flags.get("sevii_lab_reunion",false): return false
		"FLAG_HIDE_OAK_IN_PALLET_TOWN":
			if flags.get("sevii_home_oak",false): return false
		"FLAG_HIDE_ONE_ISLAND_BILL": return true # The visit lands inside the Network Center.
		"FLAG_HIDE_ONE_ISLAND_POKECENTER_BILL": return not visiting or detour_done
		"FLAG_HIDE_ONE_ISLAND_POKECENTER_CELIO": return false
		"FLAG_HIDE_TWO_ISLAND_GAME_CORNER_LOSTELLE": return not flags.get("sevii_lostelle_rescued",false) or detour_done
		"FLAG_HIDE_LOSTELLE_IN_HER_HOME": return not detour_done
		"FLAG_HIDE_LOSTELLE_IN_BERRY_FOREST": return not flags.get("sevii_lostelle_missing",false) or flags.get("sevii_lostelle_rescued",false)
		"FLAG_HIDE_THREE_ISLAND_BIKERS": return not flags.get("sevii_meteorite_errand",false) or flags.get("sevii_bikers_left",false)
		"FLAG_HIDE_THREE_ISLAND_ANTIBIKERS": return not flags.get("sevii_lostelle_missing",false) or flags.get("sevii_lostelle_rescued",false)
		"FLAG_HIDE_THREE_ISLAND_LONE_BIKER": return true
		"FLAG_HIDE_ICEFALL_CAVE_ROCKETS","FLAG_HIDE_ICEFALL_CAVE_LORELEI": return not rainbow or flags.get("rescued_icefall",false)
		"FLAG_HIDE_LORELEI_IN_HER_HOUSE": return not flags.get("rescued_icefall",false) or flags.get("sevii_network_online",false)
		"FLAG_HIDE_SAPPHIRE": return not rainbow or flags.get("sevii_password_two",false)
		"FLAG_HIDE_FIVE_ISLAND_ROCKETS": return not rainbow or flags.get("sevii_warehouse_cleared",false)
	return null

static func passage_message(source: Dictionary, target: Dictionary, flags: Dictionary) -> String:
	if target.get("region","") != "sevii": return ""
	var from: String = source.get("id","")
	var to: String = target.get("map","")
	if to == "five_island_rocket_warehouse" and from != to and not (flags.get("sevii_password_one",false) and flags.get("sevii_password_two",false)):
		return "门上的话筒要听两句口令。一句来自灯火山，另一句还在研究员手里。"
	if to == "six_island_dotted_hole_sapphire_room" and from == "six_island_dotted_hole_1f" and not flags.get("sevii_password_two",false):
		return "这条捷径只能从宝石室一侧打开。石板的点字标出了各层洞口的方向。"
	return ""


static func reconcile_pass(flags: Dictionary, bag: Array) -> void:
	if not flags.get("delivered_ember_ruby",false): return
	# Older saves could complete the Ruby before taking Bill's first trip.
	for i in range(bag.size()-1,-1,-1):
		if bag[i].get("name","") == "三岛通行证": bag.remove_at(i)
	if not bag.any(func(row): return row.get("name","")=="彩虹通行证" and int(row.get("count",0))>0):
		bag.append({"id":0,"name":"彩虹通行证","category":"key","count":1})

static func destinations(bag: Array) -> Array:
	var tickets := {}
	for row in bag:
		if int(row.get("count",0))>0: tickets[row.get("name","")]=true
	if tickets.has("彩虹通行证"):
		var ports := PORTS.keys().slice(0,7)
		if tickets.has("神秘船票"): ports.append("navel_rock_harbor")
		if tickets.has("极光船票"): ports.append("birth_island_harbor")
		return ports
	return PORTS.keys().slice(0,3) if tickets.has("三岛通行证") else []

static func ferry_message(source: Dictionary, target: Dictionary, bag: Array) -> String:
	var from: String = source.get("id","")
	var to: String = target.get("map","")
	var inter_island := PORTS.has(from) and PORTS.has(to)
	var entering := from == "kanto_main" and to == "one_island_harbor"
	if not (inter_island or entering) or to in destinations(bag): return ""
	if to == "navel_rock_harbor": return "肚脐岩航线需要神秘船票。联网后请去一之岛网络中心二楼找配送员。"
	if to == "birth_island_harbor": return "诞生岛航线需要极光船票。联网后请去一之岛网络中心二楼找配送员。"
	if to in PORTS.keys().slice(0,3): return "船员正在验三岛通行证。红莲岛的正辉知道怎样去一之岛。"
	return "四至七之岛航线需要彩虹通行证。请向一之岛网络中心的锦辉询问。"


static func request_step(save: Dictionary) -> void:
	var request: Dictionary = save.get("selphy_request",{})
	if request.is_empty() or request.get("expired",false): return
	request.steps = int(request.get("steps",0)) + 1
	if request.steps >= 250: request.expired = true

static func show_partner(save: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var request: Dictionary = save.get("selphy_request",{})
	if request.is_empty() or request.get("expired",false):
		var seen: Array = save.get("dex",{}).get("seen",[])
		if seen.is_empty(): return {}
		var deluxe := ["大珍珠","珍珠","星星沙子","星星碎片","金珠","神奇糖果"]
		var reward: String = "豪华球"
		if rng.randf() < 0.30: reward = deluxe[rng.randi_range(0,deluxe.size()-1)]
		request = {"species":int(seen[rng.randi_range(0,seen.size()-1)]),"steps":0,"reward":reward}
		save.selphy_request=request
		return {"species":request.species}
	if save.get("party",[]).any(func(mon): return mon is Dictionary and int(mon.get("species_id",0))==int(request.species)):
		save.erase("selphy_request")
		save["selphy_thanked"]=true
		return request
	return {"species":request.species}
