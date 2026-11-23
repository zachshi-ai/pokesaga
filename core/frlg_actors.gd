extends RefCounted
## Project the original ObjectEvent visibility into both the live field and its collision roster.
static var catalog: Dictionary

static func data() -> Dictionary:
	if catalog.is_empty():
		catalog = JSON.parse_string(FileAccess.get_file_as_string("res://content/frlg_actors.json"))
		catalog.maps["kanto/kanto_main"].merge(preload("res://core/sevii_campaign.gd").OUTDOOR,true)
		for mid: String in preload("res://core/kanto_campaign.gd").data().actors:
			if not catalog.maps.has(mid): catalog.maps[mid]={}
			for xy: String in preload("res://core/kanto_campaign.gd").data().actors[mid]:
				var spec: Dictionary = catalog.maps[mid].get(xy,{})
				spec.merge(preload("res://core/kanto_campaign.gd").data().actors[mid][xy],true)
				catalog.maps[mid][xy] = spec
	return catalog

static func migrate_progress(save: Dictionary) -> void:
	preload("res://core/sevii_campaign.gd").sync(save)
	var flags: Dictionary = save.get("flags", {})
	var badges: Array = preload("res://core/region_journey.gd").badges(save,"kanto")
	if flags.get("kanto_champion",false) and not flags.has("fr_hof_count"):flags.fr_hof_count=2 if flags.get("kanto_rematch_complete",false) else 1
	if "灰色徽章" in badges:
		flags.beat_brock = true
	if "绿色徽章" in badges:
		flags.beat_giovanni = true
	var needed := ["蓝色徽章","橙色徽章","彩虹徽章","粉红徽章","金色徽章","深红徽章"]
	if needed.all(func(badge): return badge in badges):
		flags.viridian_gym_open = true
	save.flags = flags
	preload("res://core/kanto_campaign.gd").migrate(save)

static func hidden(flag: String, flags: Dictionary) -> bool:
	var sevii_visibility = preload("res://core/sevii_campaign.gd").hidden(flag,flags)
	if sevii_visibility != null: return sevii_visibility
	match flag:
		"FLAG_HIDE_POSTGAME_GOSSIPERS":return not flags.get("kanto_champion",false)
		"FLAG_HIDE_MT_EMBER_EXTERIOR_ROCKETS":
			return flags.get("beat_ember_grunt_1",false) and flags.get("beat_ember_grunt_2",false)
		"FLAG_HIDE_RUIN_VALLEY_SCIENTIST","FLAG_HIDE_ICEFALL_CAVE_ROCKETS","FLAG_HIDE_ICEFALL_CAVE_LORELEI":
			return flags.get("rescued_icefall",false)
		"FLAG_HIDE_RUBY": return flags.get("got_ember_ruby",false)
		"FLAG_HIDE_OAK_IN_HIS_LAB": return not (flags.get("oak_in_lab",false) or flags.get("got_starter",false))
		"FLAG_HIDE_OAK_IN_PALLET_TOWN": return not flags.get("oak_approaching",false)
		"FLAG_HIDE_RIVAL_IN_LAB": return flags.get("beat_rival",false) or flags.get("rival_left_lab",false)
		"FLAG_HIDE_POKEDEX": return flags.get("got_dex",false)
		"FLAG_HIDE_PEWTER_CITY_GYM_GUIDE": return flags.get("beat_brock",false)
		"FLAG_HIDE_PEWTER_CITY_RUNNING_SHOES_GUY": return not flags.get("beat_brock",false) or flags.get("received_running_shoes",false)
		"FLAG_HIDE_BILL_HUMAN_SEA_COTTAGE": return not flags.get("helped_bill",false)
		"FLAG_HIDE_BILL_CLEFAIRY": return flags.get("bill_in_machine",false) or flags.get("helped_bill",false)
		"FLAG_HIDE_NUGGET_BRIDGE_ROCKET": return flags.get("ss_ticket",false)
		"FLAG_HIDE_CERULEAN_ROCKET": return flags.get("beat_cerulean_rocket",false)
		"FLAG_HIDE_SAFFRON_ROCKETS","FLAG_HIDE_SILPH_ROCKETS": return flags.get("freed_silph",false)
		"FLAG_HIDE_SAFFRON_CIVILIANS": return not flags.get("freed_silph",false)
		"FLAG_HIDE_TOWER_FUJI": return flags.get("rescued_fuji",false)
		"FLAG_HIDE_POKEHOUSE_FUJI": return not flags.get("rescued_fuji",false)
		"FLAG_HIDE_TOWER_ROCKET_1","FLAG_HIDE_TOWER_ROCKET_2","FLAG_HIDE_TOWER_ROCKET_3":
			return flags.get("rescued_fuji",false) or flags.get("beat_tower_grunt_"+flag.right(1),false)
		"FLAG_HIDE_VIRIDIAN_GIOVANNI": return not flags.get("viridian_gym_open",false) or flags.get("beat_giovanni",false)
	return flags.get(flag,flag in data().initial)

static func actor(row: Dictionary, spec: Dictionary, flags: Dictionary) -> Dictionary:
	if spec.has("flag") and hidden(spec.flag,flags):
		return {}
	for required in spec.get("appear",[]):
		if not flags.get(required,false): return {}
	if spec.has("disappear") and flags.get(spec.disappear,false): return {}
	var out := row.duplicate(true)
	for key in ["name","gfx","role","field_art","in_water_pose","battle","lines","heal"]:
		if spec.has(key): out[key]=spec[key]
	match str(spec.get("role","")):
		"pallet_oak":
			if flags.get("sevii_home_oak",false): out.at=[66,269]
		"ember_grunt_1","ember_grunt_2":
			out.lines = ["我们还在这里挖。走开！"] if not flags.get("beat_"+out.role,false) else ["你赢了我，可我的同伴还在！"]
		"ruin_scientist":
			out.lines = ["先别打扰我。我正在研究门上的点字。"]
		"celio":
			out.lines = ["我正在修宝可梦网络机器。"]
			if flags.get("ember_ruby_requested",false): out.lines = ["请帮我寻找适合这台机器的红宝石。"]
			if flags.get("delivered_ember_ruby",false): out.lines = ["两个插槽只装好一个。四之岛的科拿也许有蓝宝石的消息。"]
			if flags.get("sevii_network_online",false): out.lines = ["丰缘的信号很稳定。两地的宝可梦网络已经接通了！"]
		"parcel_clerk":
			out.shop=flags.get("got_dex",false)
		"silph_guard":
			if not flags.get("rescued_fuji",false): out.at=[int(out.at[0])-1,out.at[1]]
		"old_man":
			if not flags.get("got_dex",false):
				out.at=[69,191]
				out.gfx="fr_old_man_lying_down"
			else:
				out.at=[69,188] if not flags.get("old_man_met",false) else [69,186]
		"sign_lady":
			if not flags.get("read_sign_lady",false): out.at=[65,275]
		"police":
			if not flags.get("ss_ticket",false): out.at=[294,52]
		"slowbro":
			if not flags.get("ss_ticket",false): out.at=[290,71]
		"slowbro_friend":
			if not flags.get("ss_ticket",false): out.at=[291,71]
		"bill":
			if not flags.get("ss_ticket",false): out.at=[3,4]
	return out

static func roster(map: Dictionary, flags: Dictionary) -> Array:
	var base: Array = map.get("npcs",[])
	if map.get("region","")=="galar":
		return load("res://core/galar_campaign.gd").roster(map,flags,base) + load("res://core/galar_gym.gd").actors(map,flags)
	if map.get("region","")=="alola" and map.has("alola_native"):
		var residents:Array=load("res://core/alola_routes.gd").roster(map,flags,base)
		var cast:Array=load("res://core/alola_campaign.gd").roster(map,flags,residents)
		var islanders:Array=load("res://core/alola_side.gd").roster(map,flags,cast)
		return load("res://core/alola_machines.gd").roster(map,flags,islanders)
	if map.get("region","")=="kalos" and map.has("kalos_zone"):
		var residents: Array=load("res://core/kalos_trainers.gd").roster(map,flags,base)
		residents=load("res://core/kalos_lumiose.gd").roster(map,flags,residents)
		var cast: Array=load("res://core/kalos_campaign.gd").roster(map,flags,residents)
		return load("res://core/kalos_opowers.gd").roster(map,flags,load("res://core/kalos_side.gd").decorate(map,flags,cast))
	if map.get("region","")=="unova":
		var residents: Array=load("res://core/unova_trainers.gd").roster(map,flags,base)
		var cast: Array=load("res://core/unova_campaign.gd").roster(map,flags,residents)
		return load("res://core/unova_side.gd").decorate(map,flags,cast)
	if map.has("platinum_native"):
		var rows: Array = load("res://core/sinnoh_campaign.gd").roster(map,flags,base)
		var side = load("res://core/sinnoh_side.gd")
		rows=side.roster(map,flags,rows)
		if map.has("platinum_cycling"):
			var deck: bool=flags.get("platinum_cycling_deck",false)
			rows=rows.filter(func(row):return str(row.get("platinum_gfx","")).begins_with("OBJ_EVENT_GFX_CYCLIST")==deck)
		return rows
	if map.has("emerald_original"):
		return preload("res://core/hoenn_campaign.gd").roster(map,flags,base)
	if map.get("region","")=="johto":
		var rows := preload("res://core/johto_campaign.gd").roster(map,flags)
		rows = preload("res://core/johto_items.gd").roster(map,flags,rows)
		rows = preload("res://core/johto_postgame.gd").roster(map,flags,rows)
		if map.has("hgss"): rows.append_array(preload("res://core/hgss_field.gd").foreign_actors(map,flags))
		return preload("res://core/hgss_field.gd").roster(map,rows)
	if not str(map.get("region","")) in ["kanto","sevii"]:
		return base.duplicate(true)
	var specs: Dictionary = data().maps.get("%s/%s" % [map.get("region",""),map.get("id","")],{})
	var result := []
	for row in base:
		var at: Array = row.at
		var spec: Dictionary = specs.get("%d,%d" % at,{})
		spec = preload("res://core/sevii_campaign.gd").speaker(map.get("id",""),at,spec,flags)
		var item := actor(row,spec,flags) if not spec.is_empty() else (row as Dictionary).duplicate(true)
		if not item.is_empty(): result.append(item)
	for key: String in specs:
		var spec: Dictionary = specs[key]
		if not spec.get("add",false): continue
		var xy := key.split(",")
		var item := actor({"at":[int(xy[0]),int(xy[1])]},spec,flags)
		if not item.is_empty(): result.append(item)
	return load("res://core/frlg_sidequests.gd").roster(map,flags,result)
