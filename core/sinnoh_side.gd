extends RefCounted
## Platinum field interactions. Source object IDs also identify persistent pickups.
const DayCare := preload("res://core/sinnoh_day_care.gd")
const Restaurant := preload("res://core/sinnoh_restaurant.gd")
const Dailies := preload("res://core/sinnoh_dailies.gd")
const Arcade := preload("res://core/sinnoh_arcade.gd")
const PalPark := preload("res://core/sinnoh_pal_park.gd")
const Services := preload("res://core/sinnoh_services.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const Party := preload("res://core/party.gd")
const Encounter := preload("res://core/encounter.gd")
const Dex := preload("res://core/dex_variants.gd")
const HM_KEYS := ["CUT","FLY","SURF","STRENGTH","DEFOG","ROCK_SMASH","WATERFALL","ROCK_CLIMB"]
const HM_BADGES := [2,4,5,6,3,1,8,7]
static var catalog: Dictionary
static var map_ids: Dictionary
static var source_by_map: Dictionary

static func data() -> Dictionary:
	if catalog.is_empty():
		catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_side.json"))
	return catalog

static func learnset(species: int, form := "") -> Array:
	if not form.is_empty(): return []
	return data().level_moves.get(str(species),[])

static func moves_for(species: int, level: int, form := "") -> Array:
	return Encounter.moves_for(species,level,learnset(species,form))

static func maps() -> Dictionary:
	if map_ids.is_empty():
		map_ids=JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/index.json"))
		for key in map_ids: source_by_map[map_ids[key]]=key
	return map_ids

static func script_of(row: Dictionary) -> String:
	var script := str(row.get("source_script",""))
	return script if script!="" else str(row.get("hidden_item",""))

static func item_name(key: String) -> String:
	if not data().items.has(key) and Data.evo_item_key(key)!="":return Data.evo_item_name(key)
	return str(data().items[key][0])

static func has(g,name: String) -> bool:
	for row in g.bag_items:
		if row.get("name","")==name and int(row.get("count",0))>0: return true
	return false

static func give_machine(g, number: int) -> void:
	if number<1 or number>8: return
	var key := "HM%02d"%number
	var name := item_name(key)
	if not has(g,name): g._give_item(name,1,"tm")
	g._flags()["s_hm_%d"%number]=true

static func field_unlocked(g, key: String) -> bool:
	var idx := HM_KEYS.find(key.to_upper())
	if idx<0: return false
	if not g._flags().get("s_hm_%d"%(idx+1),false) or not g._flags().get("s_badge_%d"%HM_BADGES[idx],false): return false
	var move := int(data().machines["HM%02d"%(idx+1)].move)
	for mon in g.save_data.get("party",[]):
		if mon is Dictionary and mon.get("moves",[]).any(func(id): return int(id)==move): return true
	return false

static func teach(g, number: int) -> void:
	if number==5 and field_unlocked(g,"DEFOG"):
		g._pick("清除浓雾",["在这里使用","教给队员"],func(i):
			if i==0:clear_fog(g)
			else:teach_key(g,"HM05"))
	elif number>=1 and number<=8: teach_key(g,"HM%02d"%number)

static func teach_key(g,key: String) -> void:
	var name := item_name(key)
	if not has(g,name): return
	var machine: Dictionary=data().machines[key]
	var move := int(machine.move)
	var title := str(Data.move_of(move).name)
	FR.pick_party(g,"让谁学习「%s」？"%title,func(mon):
		var id := int(mon.get("species_id",0))
		var compatible: bool=machine.species.has(float(id)) if id<=493 else g._can_learn_move(id,move)
		return compatible and not mon.get("moves",[]).any(func(m):return int(m)==move),
		func(slot):g._tm_teach_one(move,slot,title,true,func():
			if key.begins_with("TM"):g._consume_item(name)))

static func give(g,key: String,count:=1) -> void:
	if key.begins_with("HM") and key.right(2).is_valid_int():
		give_machine(g,int(key.right(2)))
		return
	if not data().items.has(key) and Data.evo_item_key(key)!="":
		g._give_item(Data.evo_item_name(key),count,"evo")
		return
	var item: Array=data().items[key]
	for i in count:
		if item[1]=="held":g._give_bag_item(item[0],"held",key)
		elif item[1]=="berry":g._give_bag_item(item[0],"berry","",key.trim_suffix("_BERRY").to_lower())
		else:g._give_item(item[0],1,item[1])

static func change(g,flag: String,value=true) -> void:
	g._flags()[flag]=value
	g.world.refresh_story_actors(g._flags())
	g._apply_defeated()
	g._persist()

static func receive(g,flag: String,key: String,count:=1, who:="") -> void:
	if g._flags().get(flag,false):
		FR.say(g,"你已经领过%s了。"%item_name(key),who)
		return
	give(g,key,count)
	change(g,flag)
	FR.say(g,"获得了%s%s。"%[item_name(key)," ×%d"%count if count>1 else ""],who)

static func pickup(g,script: String) -> bool:
	var row: Array=data().pickups.get(script,[])
	if row.is_empty(): return false
	var flag := "s_pick_"+script
	if script=="VisibleItems_FullmoonIslandForest_LunarWing" and not g._flags().get("s_cresselia_roaming",false): return true
	if not g._flags().get(flag,false): receive(g,flag,row[0],int(row[1]))
	return true

static func visibility(row: Dictionary,flags: Dictionary) -> int:
	var script := script_of(row)
	if script=="PokemonDayCare_GymGuide":return int(flags.get("s_daycare_used",false))
	var dining:=Restaurant.visible(str(row.get("source_flag","")),flags)
	if dining>=0:return dining
	var staged := legend_visibility(row,flags)
	if staged>=0:return staged
	if data().pickups.has(script): return int(not flags.get("s_pick_"+script,false))
	if script=="IronIsland_Riley":return int(not flags.get("s_hm_4",false))
	return -1

static func trade(g,who: String,row: Dictionary,flag: String) -> void:
	if g._flags().get(flag,false):
		FR.say(g,"你交换给我的伙伴过得很好。",who)
		return
	var requested := int(row.requestedSpecies)
	FR.pick_party(g,"用%s交换%s？"%[Data.species_of(requested).name,Data.species_of(int(row.species)).name],
		func(mon):return int(mon.get("species_id",0))==requested,
		func(slot):
			var level := int(g.save_data.party[slot].level)
			var mon := Party.make(int(row.species),level,moves_for(int(row.species),level))
			mon.name=row.name
			mon.ot_name=row.otName
			mon.ot_id=int(row.otID)
			mon.trade_foreign=true
			mon.held=str(row.heldItem).trim_prefix("ITEM_")
			mon.ivs={"hp":int(row.hpIV),"atk":int(row.atkIV),"def":int(row.defIV),"spa":int(row.spAtkIV),"spd":int(row.spDefIV),"spe":int(row.speedIV)}
			Party.recalc(mon,false)
			mon.hp=mon.max_hp
			g.save_data.party[slot]=mon
			Dex.record(g.save_data,mon,true)
			change(g,flag)
			FR.say(g,"请多关照%s！"%mon.name,who))

static func talk(g,npc: Dictionary) -> bool:
	if g.world.map_data.get("region","")!="sinnoh": return false
	var script := script_of(npc)
	if DayCare.talk(g,load("res://core/sinnoh_side.gd"),script) or Restaurant.talk(g,load("res://core/sinnoh_side.gd"),npc):return true
	if pickup(g,script): return true
	if special(g,script,npc):return true
	if data().trades.has(script):
		trade(g,str(npc.get("name","交换伙伴")),data().trades[script],"s_trade_"+script)
		return true
	if data().gifts.has(script):
		var gift: Array=data().gifts[script]
		receive(g,"s_gift_"+script,gift[0],int(gift[1]),str(npc.get("name","")))
		return true
	match script:
		"OreburghGate1F_Hiker":receive(g,"s_hm_6","HM06",1,"登山男")
		"IronIsland_Riley":receive(g,"s_hm_4","HM04",1,"亚玄")
		"HearthomeCityNorthwestHouse_Bebe":
			if g._flags().get("s_bebe_eevee",false): FR.say(g,"我的伊布已经找到好搭档了。","水木")
			elif Party.occupied(g.save_data.party)>=Party.MAX_SIZE: FR.say(g,"先在队伍里给伊布留一个空位吧。","水木")
			else:g._pick("带上这只 20 级的伊布吗？",["好","下次再来"],func(i):
				if i==0:
					g._add_to_team(133,20)
					change(g,"s_bebe_eevee")
					FR.say(g,"伊布加入了队伍！","水木"))
		_:return false
	return true

static func object_action(g,obj: Dictionary) -> bool:
	if g.world.map_data.get("region","")!="sinnoh":return false
	return pickup(g,script_of(obj)) or special(g,script_of(obj),obj)

static func use(g,name: String) -> bool:
	if name=="ＰＰ提升剂":
		g._item_ppup(name)
		return true
	if field_item(g,name):return true
	for prefix in ["神奥秘传学习器 ","神奥招式学习器 "]:
		if name.begins_with(prefix):
			var key: String=("HM" if prefix=="神奥秘传学习器 " else "TM")+name.trim_prefix(prefix)
			if data().machines.has(key):teach_key(g,key)
			return true
	return false


const STATIONARY := {
	"AcuityCavern_Uxie":[480,50,"s_giratina"],"ValorCavern_Azelf":[482,50,"s_giratina"],
	"SnowpointTempleB5F_Regigigas":[486,1,"s_national_dex"],
	"StarkMountainRoom3_Heatran":[485,50,"s_stark_finished"],
	"NewmoonIslandForest_Darkrai":[491,50,"s_darkrai_dream"],
	"FlowerParadise_Shaymin":[492,30,"s_flower_path"],
	"SpearPillarDialga_Rift":[483,70,"s_spear_history"],"SpearPillarPalkia_Rift":[484,70,"s_spear_history"]}
const FOSSILS := {"SKULL_FOSSIL":408,"ARMOR_FOSSIL":410,"HELIX_FOSSIL":138,"DOME_FOSSIL":140,"OLD_AMBER":142,"ROOT_FOSSIL":345,"CLAW_FOSSIL":347}
const APPLIANCES := {"Microwave":["ROTOM_HEAT",315],"Fan":["ROTOM_FAN",403],"Refrigerator":["ROTOM_FROST",59],"WashingMachine":["ROTOM_WASH",56],"LawnMower":["ROTOM_MOW",437]}
const SAIL_PORTS := {
	"CANALAVE_CITY":[45,751],"IRON_ISLAND":[100,502],"FULLMOON_ISLAND":[41,277],
	"NEWMOON_ISLAND":[152,277],"FIGHT_AREA":[620,435],"SNOWPOINT_CITY":[357,247]}

static func source(g) -> String:
	return str(g.world.map_data.get("source_id","")).trim_prefix("MAP_HEADER_")

static func go(g,header: String,raw: Array=[]) -> void:
	var mid := str(maps().get("MAP_HEADER_"+header,""))
	if mid=="":return
	var map: Dictionary=Data.load_map("sinnoh",mid)
	var at: Array=map.get("spawn",[1,1]).duplicate()
	if raw.size()==2:
		var origin: Array=map.get("platinum_origin",[0,0])
		at=[int(raw[0])-int(origin[0]),int(raw[1])-int(origin[1])]
	g._do_warp({"region":"sinnoh","map":mid,"at":at})

static func sail(g) -> void:
	var labels := []
	var destinations := []
	match source(g):
		"CANALAVE_CITY":
			labels.append("钢铁岛")
			destinations.append("IRON_ISLAND")
			if g._flags().get("s_sailor_son",false):
				labels.append("满月岛")
				destinations.append("FULLMOON_ISLAND")
		"SNOWPOINT_CITY":
			if not g._flags().get("s_champion",false):
				FR.say(g,"等你登上名人堂，我就载你去对战区。","船员")
				return
			labels.append("对战区")
			destinations.append("FIGHT_AREA")
		"FIGHT_AREA":
			labels.append("雪峰市")
			destinations.append("SNOWPOINT_CITY")
		_:
			labels.append("水脉市")
			destinations.append("CANALAVE_CITY")
	labels.append("暂时不上船")
	g._pick("要前往哪里？",labels,func(i):
		if i<destinations.size():go(g,destinations[i],SAIL_PORTS[destinations[i]]))

static func regional_seen(g) -> int:
	var seen := {}
	for id in g.save_data.get("dex",{}).get("seen",[]): seen[int(id)]=true
	var n:=0
	for id in data().dex:
		if seen.has(int(id)):n+=1
	return n

static func give_egg(g,species_id: int,source_flag: String) -> bool:
	if g._flags().get(source_flag,false):return false
	if Party.occupied(g.save_data.get("party",[]))+egg_count(g.save_data)>=Party.MAX_SIZE:
		FR.say(g,"请先腾出一个队伍位置，再来领取蛋。","宝可梦蛋")
		return false
	var eggs: Array=g.save_data.get_or_add("sinnoh_eggs",[])
	eggs.append({"species":species_id,"steps":256*(25 if species_id==447 else 10)})
	g._give_item("神奥的蛋",1,"key")
	change(g,source_flag)
	FR.say(g,"你小心地接过了宝可梦蛋。带着它继续旅行吧。","宝可梦蛋")
	return true

static func egg_count(save: Dictionary) -> int:
	return save.get("sinnoh_eggs",[]).size()

static func tick_eggs(g) -> void:
	var cycle:=DayCare.tick(g,load("res://core/sinnoh_side.gd"))
	var eggs: Array=g.save_data.get("sinnoh_eggs",[])
	var hatched := []
	var pace := 1
	for mon in g.save_data.get("party",[]):
		if mon is Dictionary and int(mon.get("ability",0)) in [40,49]:pace=2
	for i in range(eggs.size()-1,-1,-1):
		var egg: Dictionary=eggs[i]
		if egg.has("mon"):
			if not DayCare.ready(egg,cycle,pace):continue
		else:
			egg.steps=int(egg.steps)-pace
			if int(egg.steps)>0:continue
		eggs.remove_at(i)
		g._consume_item("神奥的蛋")
		g._record_hatch()
		g.save_data.s_eggs_hatched=int(g.save_data.get("s_eggs_hatched",0))+1
		var dest: String=g._store_mon(egg.mon) if egg.has("mon") else g._add_to_team(int(egg.species),1,"",Party.roll_shiny(g.appearance_rng))
		hatched.append("%s孵出来了！%s"%[Data.species_of(int(egg.species)).name,"已送入电脑。" if dest!="party" else ""])
	if not hatched.is_empty():
		g._persist()
		g._dialog(hatched,"宝可梦蛋")

static func with_species(g,id: int) -> bool:
	for mon in g.save_data.party:
		if mon is Dictionary and int(mon.get("species_id",0))==id:return true
	return false

static func legend_visibility(row: Dictionary,flags: Dictionary) -> int:
	var script:=script_of(row)
	if script=="VisibleItems_FullmoonIslandForest_LunarWing":return int(flags.get("s_cresselia_roaming",false) and not flags.get("s_pick_"+script,false))
	match str(row.get("source_flag","")):
		"FLAG_HIDE_MART_MYSTERY_GIFT_DELIVERYMAN":
			return int(flags.get("s_dex",false) and not (flags.get("s_secret_key",false) and flags.get("s_member_card",false) and flags.get("s_letter",false) and (not flags.get("s_champion",false) or flags.get("s_event_regigigas",false)) and (not flags.get("s_national_dex",false) or flags.get("s_azure",false))))
		"FLAG_HIDE_PAL_PARK_LOBBY_PROF_OAK":return int(flags.get("s_national_dex",false) and not flags.get("s_oak_park",false))
		"FLAG_HIDE_VALOR_LAKEFRONT_BEAUTY":return int(not flags.get("s_suite_returned",false))
		"FLAG_HIDE_GRAND_LAKE_VALOR_LAKEFRONT_EAST_HOUSE_BEAUTY":return int(flags.get("s_suite_returned",false))
		"FLAG_HIDE_STARK_MOUNTAIN_ROOM_1_TEAM_GALACTIC":return int(flags.get("s_national_dex",false) and not flags.get("s_stark_jupiter",false))
		"FLAG_HIDE_STARK_MOUNTAIN_ROOM_2_BUCK":return int(flags.get("s_stark_jupiter",false) and not flags.get("s_charon_arrested",false))
		"FLAG_HIDE_NEWMOON_ISLAND_SAILOR":return int(flags.get("s_caught_491",false) or flags.get("s_darkrai_left",false))
	if script.begins_with("Battleground_Trainer"):
		var slot:=int(script.trim_prefix("Battleground_Trainer"))-1
		return int(slot>=0 and slot<4 and int(lineup(flags)[slot])>=0 and flags.get("s_stark_finished",false))
	if row.get("source_flag","")=="FLAG_HIDE_HALL_OF_ORIGIN_ARCEUS":return int(flags.get("s_flute_played",false) and not flags.get("s_caught_493",false))
	if script=="TurnbackCaveGiratinaRoom_Giratina":return int(flags.get("s_champion",false) and not flags.get("s_caught_487",false))
	if script=="TurnbackCaveGiratinaRoom_Portal":return int(flags.get("s_champion",false) and flags.get("s_caught_487",false))
	if script=="PoketchCo1F_PoketchCoPresident":return int(flags.get("s_poketch",false))
	if script=="WaywardCave1F_Mira":return int(not flags.get("s_mira_done",false))
	if script=="FollowerPartners_Marley":return int(flags.get("s_national_dex",false) and not flags.get("s_marley_done",false))
	if STATIONARY.has(script):
		var row_data: Array=STATIONARY[script]
		return int(flags.get(row_data[2],false) and not flags.get("s_caught_%d"%int(row_data[0]),false))
	match script:
		"ValleyWindworksOutside_Drifloon":
			return int(flags.get("s_mars_wind",false) and int(Time.get_date_dict_from_system().weekday)==5 and flags.get("s_drifloon_day","")!=Time.get_date_string_from_system())
		"VerityCavern_Mesprit":return int(flags.get("s_giratina",false) and not flags.get("s_mesprit_roaming",false))
		"FullmoonIslandForest_Cresselia":return int(flags.get("s_sailor_son",false) and not flags.get("s_cresselia_roaming",false))
		"Route224_ProfOak":return int(flags.get("s_letter",false) and not flags.get("s_flower_path",false))
		"EternaCitySouthHouse_ProfOak":return int(flags.get("s_oak_park",false))
		"IronIslandB2FLeftRoom_Riley":return int(flags.get("s_hm_4",false) and not flags.get("s_riolu",false))
		"IronIslandB2FLeftRoom_CoordEvent_Grunts":return int(not flags.get("s_iron_won",false))
		"SurvivalArea_Buck":return int(flags.get("s_charon_arrested",false) and not flags.get("s_stark_finished",false))
	return -1

static func wild(g,id: int,lv: int) -> void:
	if g._flags().get("s_caught_%d"%id,false):return
	g._start_wild_battle(id,lv,"",func(outcome):
		if outcome=="caught":change(g,"s_caught_%d"%id)
		if id==491 and outcome in ["caught","a","run"]:
			change(g,"s_darkrai_left")
			go(g,"CANALAVE_CITY_HARBOR_INN",[7,4])
		elif outcome=="b" and g._party_fainted():g._blackout())

static func roam(g,id: int,level: int) -> void:
	var mons: Dictionary=g.save_data.get_or_add("sinnoh_roamers",{})
	if not mons.has(str(id)) and not g._flags().get("s_caught_%d"%id,false):
		var mon:=Party.make(id,level,moves_for(id,level))
		Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
		mons[str(id)]={"mon":mon,"route":g.rng.randi_range(201,222)}

static func try_roamer(g) -> bool:
	if not source(g).begins_with("ROUTE_") or not g.world.wild_tile_here():return false
	var route := int(source(g).trim_prefix("ROUTE_").split("_")[0])
	for key in g.save_data.get("sinnoh_roamers",{}):
		var r: Dictionary=g.save_data.sinnoh_roamers[key]
		if int(r.route)!=route or g.rng.randi_range(0,49)!=0:continue
		var mon: Dictionary=r.mon
		g._start_wild_battle(int(key),int(mon.level),"",func(outcome):
			if outcome=="caught":
				g.save_data.sinnoh_roamers.erase(key)
				change(g,"s_caught_"+key)
			elif outcome=="a":
				g.save_data.sinnoh_roamers.erase(key)
				g._persist()
			else:
				r.route=g.rng.randi_range(201,222)
				g._persist()
				if outcome=="b" and g._party_fainted():g._blackout(),Party.shiny_kind(mon),0,mon)
		return true
	return false

static func fossil(g) -> void:
	var waiting := int(g._flags().get("s_fossil_pending",0))
	if waiting>0:
		if not g._flags().get("s_fossil_ready",false):
			FR.say(g,"复原需要一些时间。你先到博物馆外面走走吧。","化石研究员")
		elif Party.occupied(g.save_data.party)>=Party.MAX_SIZE:FR.say(g,"复原已完成。请先给宝可梦留一个空位。","化石研究员")
		else:
			g._add_to_team(waiting,20)
			change(g,"s_fossil_pending",0)
			FR.say(g,"复原成功！请照顾好这只%s。"%Data.species_of(waiting).name,"化石研究员")
		return
	var choices := []
	var keys := []
	for key in FOSSILS:
		if has(g,item_name(key)):
			keys.append(key)
			choices.append(item_name(key))
	if choices.is_empty():
		FR.say(g,"把在地下挖到的化石交给我，我就能让里面的宝可梦重获新生。","化石研究员")
		return
	choices.append("取消")
	g._pick("要复原哪块化石？",choices,func(i):
		if i>=keys.size():return
		g._consume_item(item_name(keys[i]))
		g._flags().s_fossil_ready=false
		change(g,"s_fossil_pending",FOSSILS[keys[i]])
		FR.say(g,"化石收到了。稍后再来取吧。","化石研究员"))

static func form(g,suffix: String) -> void:
	if not APPLIANCES.has(suffix):return
	var appliance: Array=APPLIANCES[suffix]
	FR.pick_party(g,"让哪只洛托姆进入家电？",func(mon):return int(mon.get("species_id",0))==479,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var next := "" if mon.get("form","")==appliance[0] else str(appliance[0])
		var old := -1
		for a in APPLIANCES.values():
			if mon.get("form","")==a[0]:old=int(a[1])
		var change_form := func():
			Party.evolve(mon,479,next)
			Dex.record(g.save_data,mon,true)
			g._persist()
		for i in range(mon.moves.size()-1,-1,-1):
			if int(mon.moves[i])==old:
				if next!="":
					mon.moves[i]=int(appliance[1])
					mon.pp[i]=int(Data.move_of(int(appliance[1])).pp)
				else:
					mon.moves.remove_at(i)
					mon.pp.remove_at(i)
				change_form.call()
				FR.say(g,"洛托姆变换了形态。","洛托姆")
				return
		if next!="" and not mon.moves.has(int(appliance[1])):g._tm_teach_one(int(appliance[1]),slot,Data.move_of(int(appliance[1])).name,true,change_form)
		else:
			change_form.call()
			FR.say(g,"洛托姆变换了形态。","洛托姆"))

static func battle(g, trainers: Array, ally: String, title: String, won: Callable) -> void:
	var team := []
	for i in trainers.size():
		var members: Array=data().trainers[trainers[i]].duplicate(true)
		for mon in members:
			mon.trainer_group="first" if i==0 else "second"
			if mon.moves.is_empty():mon.moves=moves_for(int(mon.species),int(mon.level))
			team.append(mon)
	var cfg := {"team":team}
	if ally!="":
		var partners: Array=data().trainers[ally].duplicate(true)
		for mon in partners:
			if mon.moves.is_empty():mon.moves=moves_for(int(mon.species),int(mon.level))
		cfg.merge({"double":true,"ally":"sinnoh","ally_team":partners})
	g._start_battle({"name":title,"battle":cfg,"lines":[]},func(result):
		if result=="a": won.call()
		elif result=="b" and g._party_fainted():g._blackout())

static func local_delivery(g) -> void:
	var options := []
	var keys := []
	for pair in [["SECRET_KEY","s_secret_key"],["OAKS_LETTER","s_letter"],["MEMBER_CARD","s_member_card"]]:
		if not g._flags().get(pair[1],false):
			keys.append(pair)
			options.append(item_name(pair[0]))
	if g._flags().get("s_national_dex",false) and not g._flags().get("s_azure",false):
		keys.append(["AZURE_FLUTE","s_azure"])
		options.append(item_name("AZURE_FLUTE")+" · 未发行活动")
	if g._flags().get("s_champion",false) and not g._flags().get("s_event_regigigas",false):
		keys.append(["EVENT_REGIGIGAS","s_event_regigigas"])
		options.append("命运相遇的雷吉奇卡斯")
	if keys.is_empty():
		FR.say(g,"你的神奥活动礼物都领取过了。","神秘礼物配送员")
		return
	options.append("下次再领")
	g._pick("神秘礼物 · 本地领取",options,func(i):
		if i>=keys.size():return
		if keys[i][0]=="EVENT_REGIGIGAS":
			var mon:=Party.make(486,100,[442,157,196,462])
			mon.fateful_encounter=true
			mon.held="CUSTAP_BERRY"
			g._store_mon(mon)
			change(g,"s_event_regigigas")
			FR.say(g,"这只雷吉奇卡斯是一次命运般的相遇。带它到三座遗迹调查地面。","神秘礼物配送员")
		else:receive(g,keys[i][1],keys[i][0],1,"神秘礼物配送员"))

static func special(g,script: String,row: Dictionary) -> bool:
	var f: Dictionary=g._flags()
	var place := source(g)
	if Dailies.talk(g,load("res://core/sinnoh_side.gd"),script):return true
	if Arcade.interact(g,load("res://core/sinnoh_side.gd"),script) or PalPark.talk(g,load("res://core/sinnoh_side.gd"),script):return true
	if Services.talk(g,load("res://core/sinnoh_side.gd"),script):return true
	if row.has("s_club"):
		clubhouse(g,row)
		return true
	if extra_activity(g,script,row):return true
	if STATIONARY.has(script):
		var entry: Array=STATIONARY[script]
		if not f.get(entry[2],false):return true
		if int(entry[0])==486 and not (with_species(g,377) and with_species(g,378) and with_species(g,379)):
			FR.say(g,"岩石、冰与钢的三只伙伴聚集时，巨人才会觉醒。","古代石像")
			return true
		if (int(entry[0])==483 and not has(g,item_name("ADAMANT_ORB"))) or (int(entry[0])==484 and not has(g,item_name("LUSTROUS_ORB"))):return true
		wild(g,int(entry[0]),int(entry[1]))
		return true
	if str(row.get("local_id","")).begins_with("LOCALID_BERRY_SOIL"):
		berry_plot(g,row,false)
		return true
	if place=="PAL_PARK_LOBBY" and row.get("local_id")=="LOCALID_PROF_OAK":script="PalParkLobby_ProfOak"
	if script.begins_with("RotomsRoom_") and APPLIANCES.has(script.get_slice("_",1)):
		form(g,script.get_slice("_",1))
		return true
	if script=="MysteryGiftDeliveryman_Deliveryman":
		local_delivery(g)
		return true
	match script:
		"SandgemTownLab_ProfRowan":
			# Rowan reviews a complete local Dex after the first arrival in Eterna.
			# Existing regional champions can also return with older save formats.
			if not f.get("s_dex",false) or not (f.get("s_visited_sinnoh_eterna",false) or f.get("s_champion",false)):return false
			var n:=regional_seen(g)
			if n<210:FR.say(g,"神奥图鉴已见到 %d／210 种。来给我看看你接下来的发现。" % n,"山梨博士")
			elif not f.get("s_national_dex",false):
				give(g,"POKE_RADAR")
				change(g,"s_national_dex")
				g._dialog(["你观察到了神奥图鉴里的全部 210 种宝可梦。","大木博士为图鉴增加了全国模式。山梨博士把宝可追踪交给了你。"],"山梨博士")
			else:FR.say(g,"全国图鉴记录着你在所有地区真正见到的伙伴。","山梨博士")
		"PokemonMansionOffice_Book":
			Dex.record(g.save_data,{"species_id":490},false)
			g._persist()
			FR.say(g,"书上画着一只蓝色的宝可梦。玛纳霏的样子登记进了图鉴。","古书")
		"ValleyWindworksOutside_Drifloon":
			if legend_visibility(row,f)==1:
				g._start_wild_battle(425,15,"",func(result):
					if result in ["a","caught"]:change(g,"s_drifloon_day",Time.get_date_string_from_system())
					elif result=="b" and g._party_fainted():g._blackout())
		"OldChateauBackMiddleWestRoom_TV":
			var hour:=int(Time.get_time_dict_from_system().hour)
			var today:=Time.get_date_string_from_system()
			if f.get("s_caught_479",false) or f.get("s_rotom_day","")==today or (hour>=4 and hour<20):
				FR.say(g,"电视屏幕闪着雪花。","旧电视")
			else:g._pick("电视机里似乎有什么东西。拍一下吗？",["拍一下","离开"],func(i):
				if i==0:
					change(g,"s_rotom_day",today)
					wild(g,479,20))
		"VerityCavern_Mesprit","FullmoonIslandForest_Cresselia":
			if legend_visibility(row,f)!=1:return true
			var id:=481 if script.begins_with("Verity") else 488
			Dex.record(g.save_data,{"species_id":id},false)
			roam(g,id,50)
			change(g,"s_mesprit_roaming" if id==481 else "s_cresselia_roaming")
			FR.say(g,"%s飞向了神奥的道路。%s"%[Data.species_of(id).name,"林间留下了一片新月之羽。" if id==488 else ""],"")
		"CanalaveCitySailorEldritchHouse_LittleBoy":
			if not f.get("s_national_dex",false):FR.say(g,"我以后也要当一名水手！","水手的儿子")
			elif f.get("s_son_cured",false):FR.say(g,"谢谢你！那些可怕的噩梦终于消失了。","水手的儿子")
			elif f.get("s_cresselia_roaming",false) and has(g,item_name("LUNAR_WING")):
				g._consume_item(item_name("LUNAR_WING"))
				change(g,"s_son_cured")
				FR.say(g,"新月之羽发出微光，孩子从噩梦中醒来了。","水手的儿子")
			else:
				change(g,"s_sailor_son")
				FR.say(g,"孩子被噩梦缠住了。请到码头找他的父亲，去满月岛寻找新月之羽。","水手的妻子")
		"CanalaveCity_SailorEldritch","IronIsland_Sailor","FullmoonIsland_Sailor","NewmoonIsland_Sailor","SnowpointCity_SailorSSSpiral","FightArea_Sailor2":sail(g)
		"CelesticTownNorthHouse_Elder":
			if not f.get("s_champion",false):return false
			change(g,"s_spear_history")
			FR.say(g,"传说携带金刚宝珠或白玉宝珠登上枪之柱，便能在那里感受到时间与空间的裂隙。","神和镇长老")
		"Route224_ProfOak":
			if not f.get("s_letter",false) or not f.get("s_national_dex",false):return true
			change(g,"s_flower_path")
			FR.say(g,"你在白色岩石前表达了谢意。花朵绽放，一条海上花道延伸向远方。","大木博士")
		"MiningMuseum_FossilResearcher":fossil(g)
		"PastoriaCityObservatoryGate1F_CashierM":admit_marsh(g)
		"PastoriaCityEastHouse_MoveManiac":move_tutor(g,"REMINDER")
		"CanalaveCityEastHouse_MoveDeleter":move_tutor(g,"FORGET")
		"Route212House_Hiker":move_tutor(g,"ROUTE_212")
		"SnowpointCityEastHouse_Hiker":move_tutor(g,"SNOWPOINT_CITY")
		"SurvivalAreaNorthHouse_Hiker":move_tutor(g,"SURVIVAL_AREA")
		"Platinum_HoneyTree":honey_tree(g)
		"FloaromaMeadow_PokefanM":
			if not f.get("s_mars_wind",false):return false
			honey_shop(g)
		"ValorLakefront_Beauty":
			if has(g,item_name("SUITE_KEY")):
				g._consume_item(item_name("SUITE_KEY"))
				change(g,"s_suite_returned")
				FR.say(g,"是我的房间钥匙！回房间后我有谢礼要给你。","女游客")
			else: FR.say(g,"刚才在湖畔酒店的接待处附近弄丢了房间钥匙……","女游客")
		"GrandLakeValorLakefrontEastHouse_Beauty":
			if f.get("s_suite_returned",false):receive(g,"s_white_flute","WHITE_FLUTE",1,"女游客")
		"FloaromaTown_Beauty":
			if with_species(g,492) and f.get("s_caught_492",false):receive(g,"s_gracidea","GRACIDEA",1,"花苑镇的女孩")
			else:FR.say(g,"这里的花叫葛拉西蒂亚。有人会把它送给想要感谢的人。","花苑镇的女孩")
		"PalParkLobby_ProfOak":
			if not f.get("s_national_dex",false):return false
			change(g,"s_oak_park")
			FR.say(g,"我还会去百代市的住处，记得到那里找我。","大木博士")
		"EternaCitySouthHouse_ProfOak":
			if not f.get("s_oak_park",false):return false
			if not f.get("s_birds_roaming",false):
				give(g,"UPGRADE")
				for id in [144,145,146]:roam(g,id,60)
				change(g,"s_birds_roaming")
			FR.say(g,"急冻鸟、闪电鸟和火焰鸟正在神奥各条道路间巡游。","大木博士")
		"Route218GateToJubilifeCity_Fisherman":receive(g,"s_old_rod","OLD_ROD",1,"垂钓者")
		"Route209_Fisherman":receive(g,"s_good_rod","GOOD_ROD",1,"垂钓者")
		"FightArea_Fisherman":
			if not f.get("s_national_dex",false):FR.say(g,"全国图鉴拿到了再来找我。","垂钓者")
			else:receive(g,"s_super_rod","SUPER_ROD",1,"垂钓者")
		"IronIslandB2FLeftRoom_Riley","FollowerPartners_Riley":
			if not f.get("s_hm_4",false):return true
			if f.get("s_iron_won",false):give_egg(g,447,"s_riolu")
			else:
				change(g,"s_riley_joined")
				FR.say(g,"这里的宝可梦很不安。一起去深处看看，我会照顾你的伙伴。","亚玄")
		"IronIslandB2FLeftRoom_CoordEvent_Grunts":
			if f.get("s_iron_won",false):return true
			if not f.get("s_riley_joined",false):FR.say(g,"先到入口找亚玄吧。","银河队")
			else:battle(g,["galactic_grunt_iron_island_1","galactic_grunt_iron_island_2"],"riley_iron_island","银河队手下",func():
				change(g,"s_iron_won")
				give_egg(g,447,"s_riolu"))
		"EternaCityUndergroundManHouse_UndergroundMan":receive(g,"s_explorer","EXPLORER_KIT",1,"地下大叔")
		"Route209_HallowedTower":
			if not f.get("s_keystone_placed",false):
				if not has(g,item_name("ODD_KEYSTONE")):FR.say(g,"古井的石壁上留着一个放置楔石的缺口。","御灵塔")
				else:g._pick("将楔石嵌入御灵塔？",["嵌入","离开"],func(i):
					if i==0:
						g._consume_item(item_name("ODD_KEYSTONE"))
						change(g,"s_keystone_placed")
						FR.say(g,"楔石嵌进石塔。地下通道的交谈声会唤醒它。","御灵塔"))
			elif int(f.get("s_underground_greetings",0))>=32:
				g._start_wild_battle(442,25,"",func(result):
					if result in ["a","caught"]:
						f.s_underground_greetings=0
						change(g,"s_keystone_placed",false)
					elif result=="b" and g._party_fainted():g._blackout())
			else:FR.say(g,"井中隐约传出低语。地下通道已经回应了 %d／32 次。"%int(f.get("s_underground_greetings",0)),"御灵塔")
		"SurvivalArea_Buck":
			if f.get("s_charon_arrested",false):
				change(g,"s_stark_finished")
				FR.say(g,"火山镇石已经放回原处，席多蓝恩应该也回到了山里。","麦可")
			else:return false
		"FollowerPartners_Buck":
			change(g,"s_buck_joined")
			FR.say(g,"我们一起进火山。不能让银河队带走火山镇石。","麦可")
		_:
			var lid:=str(row.get("local_id",""))
			if place=="STARK_MOUNTAIN_ROOM_1" and lid in ["LOCALID_MARS","LOCALID_JUPITER","LOCALID_CHARON"]:stark_battle(g)
			elif place=="STARK_MOUNTAIN_ROOM_3" and lid=="LOCALID_CHARON":arrest(g)
			else:return false
	return true

static func stark_battle(g) -> void:
	if not g._flags().get("s_national_dex",false) or g._flags().get("s_stark_jupiter",false):return
	var mars: bool=not g._flags().get("s_stark_mars",false)
	battle(g,["commander_mars_stark_mountain" if mars else "commander_jupiter_stark_mountain"],"","伙星" if mars else "岁星",func():
		change(g,"s_stark_mars" if mars else "s_stark_jupiter")
		if mars:stark_battle(g)
		else:FR.say(g,"伙星和岁星放弃了银河队。冥王独自逃向山洞深处。",""))

static func arrest(g) -> void:
	if not g._flags().get("s_stark_jupiter",false) or not g._flags().get("s_buck_joined",false) or g._flags().get("s_charon_arrested",false):return
	change(g,"s_charon_arrested")
	FR.say(g,"不良蛙截下火山镇石，帅哥带走了冥王。麦可请你到生存区找他。","帅哥")

static func gate(g,target: Dictionary) -> String:
	maps()
	var dest:=str(source_by_map.get(target.get("map",""),"")).trim_prefix("MAP_HEADER_")
	var f: Dictionary=g._flags()
	if dest=="":return ""
	if dest=="RESTAURANT" and not Restaurant.open_at(Restaurant.now()):return "七星餐厅每天 09:00 至 23:00 营业。现在已经打烊了。"
	if dest=="PAL_PARK" and (not f.get("s_national_dex",false) or not g.save_data.has("s_park_show")):return "请到伙伴公园大厅报名捕捉秀。"
	if dest.begins_with("GREAT_MARSH_") and not g.save_data.has("s_marsh"):return "先到大湿地入口购票，领取这次使用的原野球。"
	if dest=="DISTORTION_WORLD_TURNBACK_CAVE_ROOM" and not (f.get("s_champion",false) and f.get("s_caught_487",false)):return "裂缝还没有打开。"
	if dest.begins_with("RESORT_AREA_RIBBON_SYNDICATE") and not f.get("s_ribbon_club",false):
		if Services.types_of_ribbons(g)<10:return "奖章联合组织只接待队伍合计拥有十种不同奖章的训练家。"
		g._flags().s_ribbon_club=true
	if dest=="SOLACEON_RUINS_MANIAC_TUNNEL_ROOM" and Services.unown_seen(g.save_data).size()<26:return "遗迹迷还在挖掘。"
	if dest=="BATTLEGROUND" and not f.get("s_stark_finished",false):return "先帮麦可平息严酷山上的风波，之后再来。"
	if dest=="HALL_OF_ORIGIN" and not f.get("s_flute_played",false):return "眼前还没有通往神殿的阶梯。"
	if dest=="ROTOMS_ROOM" and not f.get("s_secret_key",false):return "这面墙后有一扇门，需要秘密钥匙。"
	if dest.begins_with("FULLMOON_ISLAND") and not f.get("s_sailor_son",false):return "先去水脉市看看水手生病的孩子。"
	if dest=="CANALAVE_CITY_HARBOR_INN" and not (f.get("s_member_card",false) and f.get("s_son_cured",false)):return "旅馆锁着。"
	if dest.begins_with("NEWMOON_ISLAND") and not f.get("s_darkrai_dream",false):return "还没有通往新月岛的船。"
	if dest in ["SEABREAK_PATH","FLOWER_PARADISE"] and not f.get("s_flower_path",false):return "海面挡住去路。"
	if dest.begins_with("SPEAR_PILLAR_DIALGA") and not (f.get("s_spear_history",false) and has(g,item_name("ADAMANT_ORB"))):return "这里尚未出现时间的裂隙。"
	if dest.begins_with("SPEAR_PILLAR_PALKIA") and not (f.get("s_spear_history",false) and has(g,item_name("LUSTROUS_ORB"))):return "这里尚未出现空间的裂隙。"
	if dest.begins_with("SNOWPOINT_TEMPLE") and not f.get("s_national_dex",false):return "守卫只让持有全国图鉴的训练家进入。"
	if dest in ["FIGHT_AREA","BATTLE_FRONTIER"] and not f.get("s_champion",false):return "登上神奥名人堂后，雪峰市的船才会开往对战区。"
	if (dest.begins_with("ROUTE_22") and dest.substr(6,3).to_int()>=225 or dest.begins_with("STARK_MOUNTAIN") or dest in ["SURVIVAL_AREA","RESORT_AREA","ROUTE_230"]) and not f.get("s_national_dex",false):return "先把完成的神奥图鉴交给山梨博士评定。"
	if dest=="STARK_MOUNTAIN_ROOM_2" and not f.get("s_stark_jupiter",false):return "银河队的干部挡住了山道。"
	if dest=="STARK_MOUNTAIN_ROOM_3" and not f.get("s_buck_joined",false):return "先在洞里与麦可会合。"
	return ""

static func step(g) -> bool:
	var place:=source(g)
	var f: Dictionary=g._flags()
	update_partner(g)
	g.save_data.s_pedometer=int(g.save_data.get("s_pedometer",0))+1
	if place=="RESTAURANT" and Restaurant.closing(g,load("res://core/sinnoh_side.gd")):return true
	if place=="PAL_PARK":return PalPark.step(g,load("res://core/sinnoh_side.gd"))
	if extra_step(g,place,f):return true
	if g.save_data.has("s_marsh"):
		if place.begins_with("GREAT_MARSH_"):
			g.save_data.s_marsh.steps=int(g.save_data.s_marsh.steps)-1
			if int(g.save_data.s_marsh.steps)<=0:
				finish_marsh(g,"计步器响了。今天的游猎到此结束。")
				return true
		elif place!="":
			g.save_data.erase("s_marsh")
			g._persist()
	if not place.is_empty() and place!="MINING_MUSEUM" and int(f.get("s_fossil_pending",0))>0 and not f.get("s_fossil_ready",false):
		change(g,"s_fossil_ready")
	if place=="CANALAVE_CITY_HARBOR_INN" and not f.get("s_darkrai_dream",false):
		change(g,"s_darkrai_dream")
		go(g,"NEWMOON_ISLAND",SAIL_PORTS.NEWMOON_ISLAND)
		FR.say(g,"你躺下后做了一个怪梦。醒来时，已在一座陌生岛屿的岸边。","")
		return true
	if place=="IRON_ISLAND_B2F_LEFT_ROOM":
		var origin: Array=g.world.map_data.get("platinum_origin",[0,0])
		var at: Vector2i=g.world.player_pos+Vector2i(int(origin[0]),int(origin[1]))
		if at.x==35 and at.y in [2,3] and f.get("s_hm_4",false) and not f.get("s_riley_joined",false):
			return special(g,"IronIslandB2FLeftRoom_Riley",{})
		if at.x==21 and at.y in [40,41] and not f.get("s_iron_won",false):return special(g,"IronIslandB2FLeftRoom_CoordEvent_Grunts",{})
	if place=="STARK_MOUNTAIN_ROOM_1" and not f.get("s_stark_jupiter",false) and f.get("s_national_dex",false):
		stark_battle(g)
		return true
	if place=="STARK_MOUNTAIN_ROOM_3" and f.get("s_buck_joined",false) and not f.get("s_charon_arrested",false):
		arrest(g)
		return true
	if int(f.get("s_radar_charge",50))<50:f.s_radar_charge=int(f.s_radar_charge)+1
	if radar_step(g):return true
	return try_roamer(g)
static func field_item(g,name: String) -> bool:
	if name=="神奥的蛋":
		var lines := []
		for egg in g.save_data.get("sinnoh_eggs",[]):lines.append("还要走约 %d 步。"%int(egg.steps))
		if not lines.is_empty():g._dialog(lines,"宝可梦蛋")
		return true
	var rods:=["神奥破旧钓竿","神奥好钓竿","神奥厉害钓竿"]
	if name in rods:
		if not g.world.is_water(g.world.player_pos+g.world._dir_vec()):FR.say(g,"面向水边再甩竿。",name)
		else:g._fish(str(rods[rods.find(name)]).trim_prefix("神奥"))
		return true
	if g.world.map_data.get("region","")!="sinnoh":return false
	if Services.settings(g,load("res://core/sinnoh_side.gd"),name):return true
	match name:
		"代币盒":FR.say(g,"帷幕代币余额 %d / 50000。"%int(g.save_data.get("s_coins",0)),"代币盒")
		"城镇地图":g._open_world_atlas(false)
		"探宝器":dowsing(g)
		"宝可追踪":radar(g)
		"冒险笔记","对战记录器":
			var count:=0
			for i in 8:
				if g._flags().get("s_badge_%d"%(i+1),false):count+=1
			var visits:=0
			for key in g.save_data.get("defeated",{}):
				if str(key).begins_with("sinnoh/"):visits+=g.save_data.defeated[key].size()
			g._dialog(["神奥徽章 %d／8   图鉴已见 %d／210"%[count,regional_seen(g)],"已击败的神奥训练家 %d 名。"%visits],name)
		"探险套装":
			if str(g.world.map_data.get("map_type","")) not in ["MAP_TYPE_OUTDOORS","MAP_TYPE_TOWN_CITY"]:FR.say(g,"到神奥室外，再从地面进入地下通道。",name)
			else:preload("res://core/sinnoh_mining.gd").enter(g)
		"可达鸭喷壶":
			var actor: Dictionary=g.world._npc_at(g.world.player_pos+g.world._dir_vec())
			if str(actor.get("local_id","")).begins_with("LOCALID_BERRY_SOIL"):berry_plot(g,actor,true)
			else:FR.say(g,"面向已经种下树果的松软土壤。",name)
		"葛拉西蒂亚花":
			var hour:=int(Time.get_time_dict_from_system().hour)
			if hour<4 or hour>=20:FR.say(g,"夜色中花瓣合起了，等天亮再来吧。",name)
			else:FR.pick_party(g,"让哪只谢米闻花香？",func(mon):return int(mon.get("species_id",0))==492 and mon.get("status","")!="freeze",func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				Party.evolve(mon,492,"SHAYMIN_SKY")
				Dex.record(g.save_data,mon,true)
				g._persist()
				FR.say(g,"谢米变成了天空形态。",name))
		"新月之羽":FR.say(g,"到水脉市码头旁的水手家，与床上的孩子交谈。",name)
		"大木的信":FR.say(g,"大木博士在 224 号道路的白色岩石旁等你。",name)
		"会员卡":FR.say(g,"卡片上印着水脉市港口旅馆的标志。",name)
		"秘密钥匙":FR.say(g,"把钥匙带到百代市银河队大楼一层的西北角。",name)
		"房间钥匙":FR.say(g,"钥匙牌上刻着立志湖畔的湖畔大酒店。",name)
		"楔石":FR.say(g,"209 号道路的御灵塔上有与楔石吻合的缺口。",name)
		_:
			if name==item_name("AZURE_FLUTE"):
				var place:=source(g)
				var origin: Array=g.world.map_data.get("platinum_origin",[0,0])
				var cell:=Vector2i(g.world.player_pos)+Vector2i(int(origin[0]),int(origin[1]))
				if place in ["SPEAR_PILLAR","SPEAR_PILLAR_DIALGA","SPEAR_PILLAR_PALKIA"] and cell==Vector2i(31,52):extra_activity(g,"Platinum_AzureFlute",{})
				else:FR.say(g,"枪之柱的石板与笛声呼应。",name)
			elif name==item_name("HONEY"):
				for obj in g.world.objects:
					if script_of(obj)=="Platinum_HoneyTree" and obj.at==[g.world.player_pos.x,g.world.player_pos.y-1]:
						honey_tree(g)
						return true
				FR.say(g,"站在金黄色蜂蜜树的南边，可以在树上涂蜜。",name)
			else:return false
	return true

static func dowsing(g) -> void:
	var distance:=999999
	var delta:=Vector2i.ZERO
	for obj in g.world.objects:
		var id:=script_of(obj)
		if not id.begins_with("FLAG_OBTAINED_HIDDEN_") or g._flags().get("s_pick_"+id,false):continue
		var d:=Vector2i(int(obj.at[0]),int(obj.at[1]))-Vector2i(g.world.player_pos)
		var n:=absi(d.x)+absi(d.y)
		if n<distance:
			distance=n
			delta=d
	var message:="附近没有探测到埋藏的物品。"
	if distance==0:message="就在脚下！退开一步，面向原来的位置调查。"
	elif distance<=14:message="信号在%s%s方向，约 %d 格。"%["北" if delta.y<0 else "南" if delta.y>0 else "","西" if delta.x<0 else "东" if delta.x>0 else "",distance]
	FR.say(g,message,"探宝器")

static func berry_plot(g,npc: Dictionary,water: bool) -> void:
	var key:=source(g)+"/"+str(npc.get("local_id",""))
	var start: Array=data().plots.get(key,[])
	if start.is_empty():return
	var beds: Dictionary=g.save_data.get_or_add("sinnoh_berries",{})
	var initial: Dictionary={"item":start[0],"yield":int(start[1]),"ready":0}
	var bed: Dictionary=beds.get(key,initial)
	var now:=int(Time.get_unix_time_from_system())
	if water:
		if bed.is_empty() or now>=int(bed.ready):FR.say(g,"这儿目前没有需要浇水的小苗。","可达鸭喷壶")
		else:
			var stage:=int((now-int(bed.planted))/maxi(1,int((int(bed.ready)-int(bed.planted))/4)))
			if int(bed.get("watered",-1))!=stage:
				bed.watered=stage
				bed["yield"]=mini(int(bed["yield"])+1,5)
				beds[key]=bed
				g._persist()
			FR.say(g,"土壤湿润了。","可达鸭喷壶")
		return
	if bed.is_empty():
		var choices := []
		var keys := []
		for it in g.bag_items:
			if it.get("category")=="berry" and int(it.get("count",0))>0:
				var code:=str(it.get("berry","")).to_upper()+"_BERRY"
				if data().items.has(code):
					keys.append(code)
					choices.append(it.name)
		if choices.is_empty():
			FR.say(g,"这块松软的土里可以种树果。","树果田")
			return
		choices.append("暂时不种")
		g._pick("在这里种什么树果？",choices,func(i):
			if i<keys.size():
				g._consume_item(item_name(keys[i]))
				g.save_data.s_berries_planted=int(g.save_data.get("s_berries_planted",0))+1
				beds[key]={"item":keys[i],"yield":2,"planted":now,"ready":now+int(data().get("berry_hours",{}).get(keys[i],3))*4*3600}
				g._persist()
				FR.say(g,"种下了%s。"%item_name(keys[i]),"树果田"))
	elif now>=int(bed.ready):
		g._pick("摘下 %s ×%d？"%[item_name(bed.item),int(bed["yield"])],["采摘","保留"],func(i):
			if i==0:
				give(g,bed.item,int(bed["yield"]))
				beds[key]={}
				g._persist()
				FR.say(g,"树果收进了背包。","树果田"))
	else:FR.say(g,"树果苗正在生长。距离成熟还有约 %d 小时。"%ceili(float(int(bed.ready)-now)/3600.0),"树果田")

static func honey_shop(g) -> void:
	g._pick("花田的甜甜蜜",["买 1 罐    ₽100","买 10 罐    ₽1000","离开"],func(i):
		if i>1:return
		var n:=1 if i==0 else 10
		if int(g.save_data.get("money",0))<100*n:FR.say(g,"你的钱还不够。","花田大叔")
		else:
			g.save_data.money-=100*n
			give(g,"HONEY",n)
			g._persist()
			FR.say(g,"得到甜甜蜜 ×%d。"%n,"花田大叔"))

static func honey_tree(g) -> void:
	var key:=source(g)
	var woods: Dictionary=g.save_data.get_or_add("sinnoh_honey",{})
	var now:=int(Time.get_unix_time_from_system())
	var old: Dictionary=woods.get(key,{})
	if not old.is_empty():
		var hours:float=(now-int(old.time))/3600.0
		if hours>=6 and hours<24 and int(old.species)>0:
			woods.erase(key)
			g._persist()
			g._start_wild_battle(int(old.species),int(old.level))
			return
		if hours<6:
			FR.say(g,"树干还散发着甜味，宝可梦尚未出现。","蜂蜜树")
			return
	if not has(g,item_name("HONEY")):
		FR.say(g,"树干上有甜甜的香气。可以在这里涂上花田的甜甜蜜。","蜂蜜树")
		return
	g._pick("在树干上涂甜甜蜜？",["涂蜜","离开"],func(i):
		if i!=0:return
		g._consume_item(item_name("HONEY"))
		var trees: Array=data().honey_maps
		if not g.save_data.has("s_munchlax_trees"):
			var positions: Array=range(trees.size())
			var lucky: Array=[]
			for j in 4:
				var pick: int=g.rng.randi_range(0,positions.size()-1)
				lucky.append(positions.pop_at(pick))
			g.save_data.s_munchlax_trees=lucky
		var lucky: bool=g.save_data.s_munchlax_trees.has(trees.find(key))
		var group: int=g.rng.randi_range(0,99)
		var id:=0
		if lucky and group==0:id=446
		elif group>=10:
			var table: Array=data().honey.uncommon if (group>=30 if lucky else group<30) else data().honey.common
			var slot: int=g.rng.randi_range(0,99)
			id=int(table[5 if slot<5 else 4 if slot<10 else 3 if slot<20 else 2 if slot<40 else 1 if slot<60 else 0])
		woods[key]={"time":now,"species":id,"level":g.rng.randi_range(5,15)}
		g._persist()
		FR.say(g,"涂好了。六小时后回来调查，蜜香能维持一天。","蜂蜜树"))

static func radar(g) -> void:
	var area: Array=data().radar.get(source(g),[])
	if area.is_empty() or g.world.tile_at(g.world.player_pos)!=11 or g.world.surfing:
		FR.say(g,"在可以遇到野生宝可梦的普通草丛里使用。","宝可追踪")
		return
	var f: Dictionary=g._flags()
	if int(f.get("s_radar_charge",50))<50:
		FR.say(g,"电力还差 %d 步。"%(50-int(f.s_radar_charge)),"宝可追踪")
		return
	var cells: Array=[]
	for y in range(-4,5):
		for x in range(-4,5):
			if x==0 and y==0:continue
			var p:=Vector2i(g.world.player_pos)+Vector2i(x,y)
			if not g.world.is_blocked(p) and g.world.tile_at(p)==11:cells.append([p.x,p.y])
	if cells.is_empty():
		FR.say(g,"周围没有其他草丛作出反应。","宝可追踪")
		return
	var at: Array=cells[g.rng.randi_range(0,cells.size()-1)]
	var id:=int(area[g.rng.randi_range(0,area.size()-1)])
	var land: Array=preload("res://core/sinnoh_field.gd").field(g.world.map_data.id).get("land",[])
	if land.is_empty():return
	var slot: Dictionary=land[g.rng.randi_range(0,land.size()-1)]
	if id==0:id=int(slot.species)
	f.s_radar_charge=0
	g.save_data.s_radar={"map":g.world.map_data.id,"at":at,"species":id,"level":slot.min}
	g._persist()
	FR.say(g,"有草丛晃动！从这里走%s%s。"%[str(absi(int(at[0])-g.world.player_pos.x))+" 格向"+("东" if int(at[0])>g.world.player_pos.x else "西") if int(at[0])!=g.world.player_pos.x else "",str(absi(int(at[1])-g.world.player_pos.y))+" 格向"+("南" if int(at[1])>g.world.player_pos.y else "北") if int(at[1])!=g.world.player_pos.y else ""],"宝可追踪")

static func radar_step(g) -> bool:
	var row: Dictionary=g.save_data.get("s_radar",{})
	if row.is_empty():return false
	if row.map!=g.world.map_data.id:
		g.save_data.erase("s_radar")
		return false
	if Vector2i(int(row.at[0]),int(row.at[1]))!=g.world.player_pos:return false
	g.save_data.erase("s_radar")
	g._persist()
	g._start_wild_battle(int(row.species),int(row.level))
	return true

static func admit_marsh(g) -> void:
	if g.save_data.has("s_marsh"):
		FR.say(g,"剩余 %d 个原野球、%d 步。"%[int(g.save_data.s_marsh.balls),int(g.save_data.s_marsh.steps)],"大湿地")
		return
	g._pick("大湿地游猎 · ₽500／30 个原野球",["开始游猎","离开"],func(i):
		if i!=0:return
		if int(g.save_data.get("money",0))<500:
			FR.say(g,"入园费需要 ₽500。","大湿地")
			return
		g.save_data.money-=500
		g.save_data.s_marsh={"balls":30,"steps":500}
		g._persist()
		go(g,"GREAT_MARSH_6",[68,116]))

static func finish_marsh(g,message: String) -> void:
	g.save_data.erase("s_marsh")
	go(g,"PASTORIA_CITY_OBSERVATORY_GATE_1F",[5,4])
	g._persist()
	FR.say(g,message,"大湿地")

static func marsh_encounter(g,id: int,level: int,form_key: String) -> bool:
	if not g.save_data.has("s_marsh") or not source(g).begins_with("GREAT_MARSH_"):return false
	var visit: Dictionary=g.save_data.s_marsh
	if g.rng.randi_range(0,9)==0:id=daily_marsh(g,int(source(g).get_slice("_",2)))
	var mon:=Party.make(id,level,moves_for(id,level,form_key),form_key)
	Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
	Dex.record(g.save_data,mon,false)
	var ui=preload("res://scenes/frlg_safari_ui.gd").new()
	ui.name="SinnohSafariEncounter"
	g.panel_open+=1
	g.menu_layer.add_child(ui)
	g._set_hud_visible(false)
	var actions:=[["ball","扔原野球"],["bait","投饵"],["mud","扔泥巴"],["run","离开"]]
	ui.setup(mon,"原野球 %d    剩余 %d 步"%[visit.balls,visit.steps],actions)
	var state:={"catch":maxi(1,int(Data.species_of(id).catch_rate)*100/1275),"escape":maxi(2,int(data().safari.get(str(id),30))*100/1275)}
	ui.action_chosen.connect(func(key):
		if ui.is_queued_for_deletion():return
		var message:=""
		var done:=false
		match key:
			"ball":
				visit.balls=int(visit.balls)-1
				if g.rng.randf()<float(state.catch)*12.75*1.5/3.0/255.0:
					mon.capture_ball="原野球"
					var dest: String=g._store_mon(mon)
					done=true
					message="%s已%s。"%[mon.name,"加入队伍" if dest=="party" else "送入电脑"]
				else:message="它挣脱了原野球。"
			"mud","bait":
				var easier: bool=key=="mud"
				if g.rng.randi_range(0,9)==0:easier=not easier
				state["catch"]=clampi(int(state["catch"])*(2 if easier else 1)/(1 if easier else 2),3,20)
				state.escape=clampi(int(state.escape)*(2 if easier else 1)/(1 if easier else 2),2,20)
				message="它的警惕性提高了。" if easier else "它专心吃起了诱饵。"
			_:
				done=true
				message="你静静地离开了。"
		if not done and g.rng.randi_range(0,99)<int(state.escape)*5:
			done=true
			message="野生的%s跑掉了。"%mon.name
		if done or int(visit.balls)<=0:
			ui.queue_free()
			g.panel_open=maxi(0,g.panel_open-1)
			g._set_hud_visible(true)
			if int(visit.balls)<=0:finish_marsh(g,message+" 原野球用完了。")
			else:g._show_toast(message)
		else:
			ui.info.text="%s    原野球 %d"%[message,visit.balls]
		g._persist())
	return true

static func move_tutor(g,location: String) -> void:
	var reminder:=location=="REMINDER"
	var forget:=location=="FORGET"
	var shards:=["RED_SHARD","BLUE_SHARD","YELLOW_SHARD","GREEN_SHARD"]
	FR.pick_party(g,"选择宝可梦",func(mon):return not forget or mon.get("moves",[]).size()>1,func(slot):
		var mon: Dictionary=g.save_data.party[slot]
		var options: Array=[]
		var moves: Array=[]
		if forget:moves=mon.moves.duplicate()
		elif reminder:
			if not has(g,item_name("HEART_SCALE")):
				FR.say(g,"带一枚心之鳞片来，我可以帮伙伴回忆招式。","招式狂")
				return
			for entry in data().level_moves.get(str(int(mon.species_id)),[]):
				var move:=int(entry[1])
				if int(entry[0])<=int(mon.level) and not moves.has(move) and not mon.moves.has(move):moves.append(move)
		else:
			for id in data().tutors:
				var tutor: Dictionary=data().tutors[id]
				if tutor.location==location and tutor.species.has(float(mon.species_id)) and not mon.moves.has(int(id)):moves.append(int(id))
		if moves.is_empty():
			FR.say(g,"现在没有可以传授给这位伙伴的招式。","招式教学")
			return
		for move in moves:
			var title:=str(Data.move_of(int(move)).name)
			if not reminder and not forget:
				var costs: Array=data().tutors[str(int(move))].shards
				var labels: Array=[]
				for i in 4:
					if int(costs[i])>0:labels.append("%s×%d"%[item_name(shards[i]),int(costs[i])])
				title+="    "+"、".join(labels)
			options.append(title)
		options.append("取消")
		g._pick("选择招式",options,func(i):
			if i>=moves.size():return
			var mv:=int(moves[i])
			if forget:
				mon.moves.remove_at(i)
				mon.pp.remove_at(i)
				g._persist()
				FR.say(g,"伙伴忘记了%s。"%Data.move_of(mv).name,"遗忘爷爷")
				return
			var cost:Array=[0,0,0,0] if reminder else data().tutors[str(mv)].shards
			for n in 4:
				if int(cost[n])>g._bag_count(item_name(shards[n])):
					FR.say(g,"所需的碎片还没有集齐。","招式教学")
					return
			g._tm_teach_one(mv,slot,Data.move_of(mv).name,true,func():
				if reminder:g._consume_item(item_name("HEART_SCALE"))
				else:
					for color in 4:
						for amount in int(cost[color]):g._consume_item(item_name(shards[color])))))

const REGI_ROOMS:={"ROCK_PEAK_RUINS":["ROUTE_228_ROCK_PEAK_RUINS",377],"ICEBERG_RUINS":["MT_CORONET_ICEBERG_RUINS",378],"IRON_RUINS":["IRON_ISLAND_IRON_RUINS",379]}

static func fateful_giant(g) -> bool:
	for mon in g.save_data.get("party",[]):
		if mon is Dictionary and int(mon.get("species_id",0))==486 and mon.get("fateful_encounter",false):return true
	return false

static func destination(g,target: Dictionary) -> Dictionary:
	if target.get("region","")!="sinnoh":return target
	maps()
	var dest:=str(source_by_map.get(target.get("map",""),"")).trim_prefix("MAP_HEADER_")
	if dest in ["RUIN_MANIAC_CAVE_SHORT","RUIN_MANIAC_CAVE_LONG","MANIAC_TUNNEL"] and source(g)=="ROUTE_214":
		var n:=Services.unown_seen(g.save_data).size()
		var updated:=target.duplicate()
		updated.map=maps()["MAP_HEADER_"+("MANIAC_TUNNEL" if n>=26 else "RUIN_MANIAC_CAVE_LONG" if n>=10 else "RUIN_MANIAC_CAVE_SHORT")]
		return updated
	for room in REGI_ROOMS:
		var plain: String=REGI_ROOMS[room][0]
		if dest in [plain,room]:
			var changed:=target.duplicate()
			var active: bool=g._flags().get("s_champion",false) and fateful_giant(g)
			changed.map=maps()["MAP_HEADER_"+str(room if active else plain)]
			return changed
	return target

static func extra_activity(g,script: String,row: Dictionary) -> bool:
	var f: Dictionary=g._flags()
	var place:=source(g)
	if script=="Platinum_AzureFlute":
		if not f.get("s_national_dex",false) or not has(g,item_name("AZURE_FLUTE")):
			FR.say(g,"风吹过石上的凹痕，听起来像是笛声。","枪之柱")
		else:g._pick("吹响天界之笛？",["吹奏","离开"],func(i):
			if i==0:
				change(g,"s_flute_played")
				go(g,"HALL_OF_ORIGIN",[31,52]))
		return true
	if place=="HALL_OF_ORIGIN" and str(row.get("local_id",""))=="LOCALID_ARCEUS":
		if f.get("s_flute_played",false):wild(g,493,80)
		return true
	if REGI_ROOMS.has(place) and script.ends_with("_Statue"):
		var activated: Dictionary=g.save_data.get("s_regi_floor",{})
		if not f.get("s_champion",false) or not fateful_giant(g):FR.say(g,"石像静悄悄地伫立在这里。","遗迹")
		elif activated.get("room","")!=place or activated.get("dots",[]).size()!=7:FR.say(g,"地面上的七个圆点还没有全部点亮。","遗迹")
		else:wild(g,int(REGI_ROOMS[place][1]),30)
		return true
	match script:
		"TurnbackCaveGiratinaRoom_Giratina":
			if f.get("s_champion",false) and not f.get("s_caught_487",false):wild(g,487,47)
		"TurnbackCaveGiratinaRoom_Portal":
			if f.get("s_champion",false) and f.get("s_caught_487",false):
				g._pick("进入通往毁坏的世界的裂缝？",["进入","留在这里"],func(i):
					if i==0:go(g,"DISTORTION_WORLD_TURNBACK_CAVE_ROOM",[116,75]))
		"DistortionWorldTurnbackCaveRoom_Portal":
			g._pick("通过裂缝回到归途洞窟？",["返回","留在这里"],func(i):
				if i==0:go(g,"TURNBACK_CAVE_GIRATINA_ROOM",[11,15]))
		"Route210GrandmaWilmaHouse_Wilma":
			FR.pick_party(g,"让哪只龙属性伙伴学习流星群？",func(mon):return mon.get("types",[]).has("dragon") and not mon.moves.has(434) and int(mon.get("friendship",70))>=255,func(slot):g._tm_teach_one(434,slot,Data.move_of(434).name,true))
		"Route228NorthHouse_ExpertM":
			var ultimate:={3:338,6:307,9:308,154:338,157:307,160:308,254:338,257:307,260:308,389:338,392:307,395:308}
			FR.pick_party(g,"让哪只伙伴学习最终招式？",func(mon):
				return int(mon.get("friendship",70))>=255 and ultimate.has(int(mon.species_id)) and not mon.moves.has(ultimate.get(int(mon.species_id),0)),func(slot):
				var move:=int(ultimate[int(g.save_data.party[slot].species_id)])
				g._tm_teach_one(move,slot,Data.move_of(move).name,true))
		"Route221House_ExpertM":
			var today:=Time.get_date_string_from_system()
			var date_state: Dictionary=g.save_data.get_or_add("s_level_challenge",{})
			if date_state.get("day","")!=today:
				date_state.day=today
				date_state.level=g.rng.randi_range(1,100)
				date_state.done=false
				g._persist()
			if date_state.get("done",false):FR.say(g,"今天已经见过想见的伙伴了，明天再来吧。","等级大叔")
			else:
				var target:=int(date_state.level)
				var match_level: bool=g.save_data.party.any(func(mon):return int(mon.get("level",0))==target)
				if not match_level:FR.say(g,"我想见一只恰好 %d 级的宝可梦。"%target,"等级大叔")
				else:
					var n:=int(date_state.get("wins",0))
					var item:=str(["BLACK_BELT","EXPERT_BELT","FOCUS_SASH"][n%3])
					give(g,item)
					date_state.wins=n+1
					date_state.done=true
					g._persist()
					FR.say(g,"这正是我想见的等级！请收下%s。"%item_name(item),"等级大叔")
		"WaywardCave1F_Mira","FollowerPartners_Marley":
			var mira:=script.begins_with("Wayward")
			if not mira and not f.get("s_national_dex",false):return false
			var key:="s_mira" if mira else "s_marley"
			if f.get(key+"_done",false):return true
			change(g,key+"_joined")
			FR.say(g,"我在洞里迷路了，一起走到洞口吧。" if mira else "我想去看 224 号道路的白色岩石。请陪我走过这段洞穴。","迷露" if mira else "米依")
		"PastoriaCityObservatoryGate2F_Binocular":
			g._pick("投入 ₽100 使用望远镜？",["观察","不用"],func(i):
				if i!=0:return
				if int(g.save_data.get("money",0))<100:
					FR.say(g,"使用一次需要 ₽100。","望远镜")
					return
				g.save_data.money-=100
				var sector: int=g.rng.randi_range(1,6)
				var id:=daily_marsh(g,sector)
				g._persist()
				FR.say(g,"透过望远镜，你看见第 %d 区的草丛里有一只%s。"%[sector,Data.species_of(id).name],"望远镜"))
		_:
			if str(row.get("local_id",""))=="LOCALID_PROF_OAK" and place=="PAL_PARK_LOBBY":return false
			return false
	return true

static func daily_marsh(g,sector: int) -> int:
	var table: Array=data().marsh_daily["after_national_dex" if g._flags().get("s_national_dex",false) else "before_national_dex"]
	var day:=Time.get_date_string_from_system()
	var daily: Dictionary=g.save_data.get_or_add("s_marsh_daily",{})
	if daily.get("day","")!=day:
		daily.clear()
		daily.day=day
	if not daily.has(str(sector)):daily[str(sector)]=int(table[g.rng.randi_range(0,table.size()-1)])
	return int(daily[str(sector)])

static func extra_step(g,place: String,f: Dictionary) -> bool:
	if place=="HALL_OF_ORIGIN" and f.get("s_flute_played",false) and not f.get("s_caught_493",false):
		var origin: Array=g.world.map_data.get("platinum_origin",[0,0])
		var at:=Vector2i(g.world.player_pos)+Vector2i(int(origin[0]),int(origin[1]))
		if at.y==35 and at.x in [30,31,32]:
			wild(g,493,80)
			return true
	if REGI_ROOMS.has(place):
		var mat: Dictionary=g.save_data.get_or_add("s_regi_floor",{})
		if mat.get("room","")!=place:
			mat.clear()
			mat.room=place
			mat.dots=[]
		for e in g.world.map_data.get("coord_events",[]):
			var key:=str(e.get("source_script",""))
			if key.contains("_Dot") and Vector2i(int(e.at[0]),int(e.at[1]))==g.world.player_pos and not mat.dots.has(key):
				mat.dots.append(key)
				g._persist()
				g._show_toast("圆点亮了    %d／7"%mat.dots.size())
				break
	elif g.save_data.has("s_regi_floor"):g.save_data.erase("s_regi_floor")
	if place in ["WAYWARD_CAVE_1F","VICTORY_ROAD_1F_ROOM_2"]:
		var mira:=place=="WAYWARD_CAVE_1F"
		var key:="s_mira" if mira else "s_marley"
		if f.get(key+"_done",false):return false
		for e in g.world.map_data.get("coord_events",[]):
			var sc:=str(e.get("source_script",""))
			var r:=Rect2i(int(e.at[0]),int(e.at[1]),int(e.get("width",1)),int(e.get("length",1)))
			if not r.has_point(g.world.player_pos):continue
			if sc.contains("MarleyStartFollowing") and not f.get(key+"_joined",false):return extra_activity(g,"FollowerPartners_Marley",{})
			if f.get(key+"_joined",false) and (sc=="WaywardCave1F_CoordEvent_Exit" or sc.contains("MiraLeavePlayer") or sc.contains("MarleyLeavePlayer")):
				change(g,key+"_done")
				FR.say(g,"多亏你，我顺利找到了出口。下次再见！","迷露" if mira else "米依")
				return true
	return false


static func wild_form(g,id: int,original: String) -> String:
	if id!=201 or g.world.map_data.get("region")!="sinnoh":return original
	var group:=int(data().unown.get(source(g),0))
	if group<1 or group>8:return original
	var allowed: Array=["ABCGHJKLMOPQSTUVWXYZ","F","R","I","N","E","D","!?"]
	var letters:=str(allowed[group-1])
	var letter:=letters.substr(g.rng.randi_range(0,letters.length()-1),1)
	return "UNOWN_"+("QUESTION" if letter=="?" else "EXCLAMATION" if letter=="!" else letter)

static func capsule_effect(ui: Control,mine: Array) -> void:
	if mine.is_empty() or not mine[0] is Dictionary:return
	var seals: Array=mine[0].get("s_capsule",[])
	if seals.is_empty():return
	var symbols:={"HEART":"♥","STAR":"★","FLOWER":"✿","SONG":"♪","ELE":"ϟ","FIRE":"✦","SMOKE":"●","LINE":"◆","PARTY":"✧","FOAMY":"○","BUBBLE":"○"}
	var tones:={"HEART":"ff6d99","STAR":"ffe168","FIRE":"ff8854","ELE":"ffd248","SONG":"b8a1ff","FLOWER":"ff96da","FOAMY":"86e3ff"}
	var size:=ui.get_viewport_rect().size
	var center:=Vector2(size.x*0.28,size.y*0.52)
	for i in seals.size():
		var key:=str(seals[i]).get_slice("_",0)
		for j in 5:
			var label:=Label.new()
			label.mouse_filter=Control.MOUSE_FILTER_IGNORE
			label.text=str(seals[i]).trim_prefix("LETTER_").left(1) if key=="LETTER" else str(symbols.get(key,"✦"))
			label.modulate=Color(str(tones.get(key,"91d9ff")))
			label.position=center
			ui.add_child(label)
			var ray:=Vector2.RIGHT.rotated(TAU*(float(i)/seals.size()+float(j)/5.0))
			var tween:=label.create_tween()
			tween.set_parallel(true)
			tween.tween_property(label,"position",center+ray*(20.0+j*5.0),0.65)
			tween.tween_property(label,"modulate:a",0.0,0.65)
			tween.chain().tween_callback(label.queue_free)

static func clear_fog(g) -> void:
	var place:=source(g)
	if not field_unlocked(g,"DEFOG"):
		FR.say(g,"取得本地的遗迹徽章，并让队伍中的伙伴学会这个招式。","清除浓雾")
		return
	if place not in ["ROUTE_210_NORTH","ROUTE_209_LOST_TOWER_3F","ROUTE_209_LOST_TOWER_4F","ROUTE_209_LOST_TOWER_5F","TURNBACK_CAVE_ENTRANCE","VICTORY_ROAD_1F_ROOM_2"] and not place.begins_with("TURNBACK_CAVE_"):
		FR.say(g,"这里没有需要清除的浓雾。","清除浓雾")
		return
	if place=="ROUTE_209_LOST_TOWER_5F":g._flags().s_defog_lost_tower=true
	g.world.weather=""
	g.world.apply_light()
	g._persist()
	FR.say(g,"伙伴扇动翅膀，眼前的雾气消散了。","清除浓雾")

const PARTNER_ROUTE:={"ETERNA_FOREST":["cheryl","s_cheryl","s_forest_exit"],"IRON_ISLAND_B2F_LEFT_ROOM":["riley","s_riley_joined","s_iron_won"],"WAYWARD_CAVE_1F":["mira","s_mira_joined","s_mira_done"],"VICTORY_ROAD_1F_ROOM_2":["marley","s_marley_joined","s_marley_done"],"STARK_MOUNTAIN_ROOM_2":["buck","s_buck_joined","s_charon_arrested"]}
const CLUB_TRAINERS:=["roark","gardenia","fantina","maylene","wake","byron","candice","volkner","cheryl","mira","riley","marley","buck"]
const CLUB_NAMES:=["瓢太","菜种","梅丽莎","阿李","吉宪","东瓜","小菘","电次","芽米","迷露","亚玄","米依","麦可"]
const CLUB_PARTNER_FLAGS:=["s_forest_exit","s_mira_done","s_iron_won","s_marley_done","s_stark_finished"]

static func active_partner(header: String,flags: Dictionary) -> String:
	var link: Array=PARTNER_ROUTE.get(header,[])
	return str(link[0]) if not link.is_empty() and flags.get(link[1],false) and not flags.get(link[2],false) else ""

static func update_partner(g) -> void:
	var visual=g.world.get_node_or_null("SinnohWalkingPartner")
	var who:=active_partner(source(g),g._flags())
	if who=="":
		if is_instance_valid(visual) and not visual.is_queued_for_deletion():visual.queue_free()
		return
	if not is_instance_valid(visual) or visual.is_queued_for_deletion():
		visual=preload("res://core/sinnoh_companion.gd").new()
		visual.name="SinnohWalkingPartner"
		g.world.add_child(visual)
	var p:=Vector2i(g.world.player_pos)-Vector2i(g.world.last_dir)
	visual.follow(g.world,who,str(g.world.map_data.id),p,str(g.world.facing))

static func heal_companions(g) -> void:
	if g.world.map_data.get("region")=="sinnoh" and active_partner(source(g),g._flags())!="":
		g._heal_party()

static func lineup(f: Dictionary) -> Array:
	var rng:=RandomNumberGenerator.new()
	rng.seed=Time.get_date_string_from_system().hash()
	var leaders: Array=range(8)
	var team: Array=[leaders.pop_at(rng.randi_range(0,leaders.size()-1))]
	for n in 2:
		var choice:=rng.randi_range(0,leaders.size())
		team.append(-1 if choice==leaders.size() else leaders.pop_at(choice))
	var choice:=rng.randi_range(0,5)
	team.append(8+choice if choice<5 and f.get(CLUB_PARTNER_FLAGS[choice],false) else -1)
	return team

static func roster(map: Dictionary,flags: Dictionary,rows: Array) -> Array:
	var set: Array=[]
	var place:=str(map.get("source_id","")).trim_prefix("MAP_HEADER_")
	var who:=active_partner(place,flags)
	var club:=lineup(flags) if place=="BATTLEGROUND" else []
	for row in rows:
		if visibility(row,flags)==0:continue
		var actor:=str(row.get("local_id","")).trim_prefix("LOCALID_").to_lower()
		if place=="SOLACEON_TOWN" and actor=="day_care_man" and flags.get("s_daycare_egg_waiting",false):
			row=row.duplicate()
			row.facing="right"
		if who!="" and actor==who:continue
		if place=="IRON_ISLAND_B2F_LEFT_ROOM" and actor=="riley" and flags.get("s_iron_won",false):
			var off: Array=map.get("platinum_origin",[0,0])
			row=row.duplicate()
			row.at=[19-int(off[0]),41-int(off[1])]
		elif place=="BATTLEGROUND" and actor.begins_with("trainer_"):
			var slot:=actor.get_slice("_",1).to_int()-1
			if slot<0 or slot>=4 or int(club[slot])<0:continue
			var member:=int(club[slot])
			row=row.duplicate()
			row.name=CLUB_NAMES[member]
			row.platinum_gfx="OBJ_EVENT_GFX_"+str(CLUB_TRAINERS[member]).to_upper()
			row.s_club=member
		set.append(row)
	return set

static func clubhouse(g,npc: Dictionary) -> void:
	if not npc.has("s_club"):return
	var member:=int(npc.s_club)
	var key: String=CLUB_TRAINERS[member]
	var today:=Time.get_date_string_from_system()
	var flag:="s_club_"+key
	if g._flags().get(flag,"")==today:
		FR.say(g,"今天和你交手很尽兴。明天再约吧。",CLUB_NAMES[member])
		return
	g._pick("与%s再战？"%CLUB_NAMES[member],["对战","稍后"],func(i):
		if i!=0:return
		g.save_data.s_battleground_battles=int(g.save_data.get("s_battleground_battles",0))+1
		g._persist()
		var team: String="leader_"+key+"_rematch" if member<8 else key+"_battleground"
		battle(g,[team],"",CLUB_NAMES[member],func():
			change(g,flag,today)
			FR.say(g,"打得漂亮。下次我会准备新的战术。",CLUB_NAMES[member])))
