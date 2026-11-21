extends RefCounted
## Crystal's Kanto year has its own map ids, badge victories, ship, and power network.
const CONTENT := "res://content/regions/johto/postgame.json"
const SHIP := "johto_fast_ship_1f"
const OLIVINE := "johto_olivine_port"
const VERMILION := "johto_vermilion_port"
const CABIN := "johto_fast_ship_cabins_sw_ssw_nw"
static var _book: Dictionary = {}

static func data() -> Dictionary:
	if _book.is_empty():
		_book = JSON.parse_string(FileAccess.get_file_as_string(CONTENT))
	return _book

static func visible(rule: Dictionary, flags: Dictionary) -> bool:
	for key in rule.get("all",[]):
		if not flags.get(key,false): return false
	for key in rule.get("none",[]):
		if flags.get(key,false): return false
	return true

static func roster(map: Dictionary, flags: Dictionary, rows: Array) -> Array:
	var room: String = map.get("id","")
	var specs: Array = data().actors.get(room,[])
	if specs.is_empty() and not room.begins_with("johto_fast_ship"): return rows
	var out := []
	for row in rows:
		var gate: String = row.get("j2_voyage","")
		if gate != "":
			var trip := "first" if not flags.get("j2_ship_landed",false) else ("west" if flags.get("j2_westbound",false) else "east")
			if gate != trip: continue
		var base: Dictionary = row
		for rule in specs:
			if rule.at != row.at or rule.get("add",false): continue
			if not visible(rule,flags): base = {}; break
			base = row.merged(rule,true)
			if not rule.get("keep_battle",false):
				base.erase("battle")
				base.erase("sight")
			break
		if not base.is_empty(): out.append(base)
	for rule in specs:
		if rule.get("add",false) and visible(rule,flags): out.append(rule.duplicate(true))
	return out

static func passage_message(game, target: Dictionary) -> String:
	if target.get("region","") != "johto": return ""
	var room: String = game.world.map_data.get("id","")
	var to: String = target.get("map","")
	var flags: Dictionary = game._flags()
	if to == SHIP and room in [OLIVINE,VERMILION]:
		if game._bag_count("高速船船票") == 0: return "水流号需要高速船船票。登记名人堂后，回若叶镇找空木博士吧。"
		if room == VERMILION and not flags.get("j2_ship_landed",false): return "水流号的首航从浅葱港出发。"
		if flags.get("j2_ship_landed",false):
			var weekday := int(Time.get_date_dict_from_system().weekday)
			if room == OLIVINE and weekday not in [Time.WEEKDAY_MONDAY,Time.WEEKDAY_FRIDAY]:
				return "前往枯叶港的水流号在周一、周五出发。"
			if room == VERMILION and weekday not in [Time.WEEKDAY_WEDNESDAY,Time.WEEKDAY_SUNDAY]:
				return "前往浅葱港的水流号在周三、周日出发。"
			flags.erase("j2_ship_rested")
		flags.j2_westbound = room == VERMILION
	if room == SHIP and to in [OLIVINE,VERMILION]:
		if flags.get("j2_ship_landed",false) and not flags.get("j2_ship_rested",false): return "还在航行中。到自己的客舱床边休息一会儿吧。"
		if not flags.get("j2_girl_found",false): return "船还没有靠岸。老爷爷正在寻找孙女，去下层甲板问问吧。"
	if room == SHIP and to == "johto_fast_ship_cabins_se_sse_captains_cabin" and target.at[1] > 10 and not flags.get("j2_sailor_back",false):
		return "船长室还不能通行。去下层甲板找值班水手。"
	if room.ends_with("magnet_train_station") and to.ends_with("magnet_train_station") and room != to:
		if not flags.get("j2_power",false): return "电力中断，磁浮列车停驶。"
		if game._bag_count("磁浮列车通行证") == 0: return "乘车需要磁浮列车通行证。金黄市的模仿少女也许有线索。"
	if to in ["johto_route_28","johto_silver_cave_outside","johto_silver_cave_room_1","johto_silver_cave_room_2","johto_silver_cave_room_3"] and not flags.get("j2_silver_pass",false):
		return "西侧是白银山。集齐城都和关都的十六枚徽章，再到真新镇向大木博士取得许可。"
	if (room == "johto_victory_road_gate" and to == "johto_route_22") or (room == "johto_vermilion_city" and to == "johto_digletts_cave"):
		if not flags.get("j2_snorlax", false): return "东侧通路还没有开放。枯叶市地鼠洞入口旁，一只卡比兽睡得正香。"
	return ""

static func destination(room: String, target: Dictionary, flags: Dictionary, local_time: Dictionary={}) -> Dictionary:
	if target.has("clefairy_night"):
		var now:=Time.get_datetime_dict_from_system() if local_time.is_empty() else local_time
		if (now.weekday==Time.WEEKDAY_MONDAY and now.hour>=20) or (now.weekday==Time.WEEKDAY_TUESDAY and now.hour<4):
			return target.clefairy_night
	if target.has("until_power") and not flags.get("j2_power",false): return target.until_power
	if room == "johto_hall_of_fame" and target.get("map","") == "johto_lances_room" and flags.get("johto_champion",false):
		return {"region":"johto","map":"johto_players_house_2f","at":[6,6],"hgss":true}
	if room == SHIP and target.get("map","") in [OLIVINE,VERMILION]:
		var east: bool = not flags.get("j2_westbound",false)
		if target.get("hgss",false):
			return {"region":"johto","map":VERMILION if east else OLIVINE,"at":[23,18] if east else [27,21],"hgss":true}
		return {"region":"johto","map":VERMILION if east else OLIVINE,"at":[3,7] if east else [3,8]}
	return target

static func radio(game) -> bool:
	if game._bag_count("收音机扩充卡") <= 0: return false
	if is_instance_valid(game._bag_ui): game._bag_ui.handle_back()
	game._flags().j2_flute = true
	game._persist()
	game._dialog(["收音机调到了「宝可梦之笛」。曲子响起，附近的宝可梦好像动了一下。"],"关都电台")
	return true

static func use_item(game, item: String) -> bool:
	if item == "收音机扩充卡": return radio(game)
	var hints := {
		"高速船船票":"在浅葱港或枯叶港的舷梯验票登船。浅葱港周一、周五开船，枯叶港周三、周日开船，第一次去关都不限日期。",
		"发电机零件":"把这个沉重的零件送回关都发电厂，亲手交给厂长。",
		"遗失玩偶":"这只皮皮玩偶属于金黄市的模仿少女。去她家二楼归还吧。",
		"磁浮列车通行证":"在金黄市或满金市的磁浮列车车站，走上站台就能凭证乘车。"
	}
	if not hints.has(item): return false
	game._dialog([hints[item]],item)
	return true

static func field_action(game) -> bool:
	var ahead: Vector2i = game.world.player_pos + game.world._dir_vec()
	if game.world.map_data.get("id","") == CABIN and ahead in [preload("res://core/hgss_field.gd").position(game.world.map_data,Vector2i(3,0)),preload("res://core/hgss_field.gd").position(game.world.map_data,Vector2i(3,1))]:
		game._flags().j2_ship_rested = true
		game._heal_party()
		game._persist()
		var message := "睡了一觉，伙伴的精神都恢复了。"
		if game._flags().get("j2_ship_landed",false): message += " 船内广播响起，水流号已抵达目的港。"
		game._dialog([message],"水流号客舱")
		return true
	if game.world.map_data.get("id","") != "johto_cerulean_gym": return false
	var part := preload("res://core/hgss_field.gd").position(game.world.map_data,Vector2i(1,4))
	if ahead != part and game.world.player_pos != part: return false
	return game._story_fire("talk",{"map":"johto_cerulean_gym","actor":"j2_part"})

static func leave_league(room: String, target: String, save: Dictionary) -> void:
	var flags: Dictionary = save.get("flags",{})
	if room == "johto_indigo_plateau_pokecenter_1f" and target == "johto_wills_room" and flags.get("johto_champion",false):
		flags.erase("j2_press_done")
		for round_name in ["will","koga","bruno","karen","lance"]:
			flags.erase("johto_league_"+round_name)
	if room == "johto_lances_room" and target == "johto_hall_of_fame":
		flags.erase("j2_red_away")
