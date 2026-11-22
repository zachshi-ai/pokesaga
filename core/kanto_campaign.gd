extends RefCounted

const BADGES := ["灰色徽章","蓝色徽章","橙色徽章","彩虹徽章","粉红徽章","金色徽章","深红徽章","绿色徽章"]
const FIELD_BADGES := {"FLASH":"灰色徽章","CUT":"蓝色徽章","FLY":"橙色徽章","STRENGTH":"彩虹徽章",
	"SURF":"粉红徽章","ROCK_SMASH":"金色徽章","WATERFALL":"深红徽章"}

static func caught_species_count(save: Dictionary) -> int:
	var caught := {}
	for species in save.get("dex",{}).get("caught",[]) + save.get("dex_caught",[]):
		var id := int(species)
		if id >= 1 and id <= 151: caught[id]=true
	return caught.size()

static var rules: Dictionary

static func data() -> Dictionary:
	if rules.is_empty():
		rules = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/kanto/campaign.json"))
	return rules

static func migrate(save: Dictionary) -> void:
	var flags: Dictionary = save.get("flags",{})
	var badges: Array = preload("res://core/region_journey.gd").badges(save,"kanto")
	if "橙色徽章" in badges: flags.surge_open=true
	if "深红徽章" in badges:
		for i in range(1,7): flags["cinnabar_quiz_"+str(i)]=true
	flags.kanto_eight_badges = BADGES.all(func(b): return b in badges)
	var legacy_items: Array = save.get("bag",[]) if save.get("import_kanto_items",not save.has("chapters")) else []
	for row in legacy_items:
		if row.get("name","")=="自行车" and int(row.get("count",0))>0: flags.received_kanto_bike=true
	# Keys were collectible before their item labels and story flags were connected.
	for key in [["silph_co_5f:22,21","ITEM_CARD_KEY","钥匙卡","card_key"],
			["pokemon_mansion_b1f:4,7","ITEM_SECRET_KEY","秘密钥匙","secret_key"],
			["safarizone_west:28,14","ITEM_GOLD_TEETH","金假牙","gold_teeth"]]:
		if flags.get(key[0],false): flags[key[3]] = true
		for row in legacy_items:
			if row.get("name","") in [key[1],key[2]] and int(row.get("count",0))>0:
				row.name=key[2]
				row.category="key"
				flags[key[3]]=true
	save.erase("import_kanto_items")
	save.flags=flags

static func passage_message(source: Dictionary, target: Dictionary, save: Dictionary) -> String:
	if target.get("region","") != "kanto" or source.get("region","")!="kanto": return ""
	var here: String = source.get("id","")
	var dest: String = target.get("map","")
	var fl: Dictionary = save.get("flags",{})
	var badges: Array = preload("res://core/region_journey.gd").badges(save,"kanto")
	if here=="kanto_main":
		match dest:
			"s_s_anne_exterior":
				if fl.get("anne_departed",false): return "圣安奴号已经起航。枯叶的联络船仍在码头另一侧候客。"
				if not fl.get("ss_ticket",false): return "船员伸手拦住了你。登上圣安奴号需要船票。"
			"cinnabarisland_gym":
				if not fl.get("secret_key",false) and "深红徽章" not in badges: return "门锁着。岛上的宝可梦屋里也许留着道馆的秘密钥匙。"
			"saffroncity_gym":
				if not fl.get("freed_silph",false) and "金色徽章" not in badges: return "道馆被火箭队占领了。西尔佛公司里还有人被困着。"
			"ceruleancave_1f":
				if not fl.get("sevii_network_online",false): return "洞穴里住着极为强大的宝可梦。先成为冠军，并帮助七岛的锦辉修好网络机器。"
	if here=="mt_moon_b2f" and dest=="mt_moon_b1f" and same_cell(target.get("at",[]),39,4) and not fl.get("moon_fossil_chosen",false):
		return "研究员还在看守那两块化石。去和他谈谈吧。"
	if here=="celadon_city_game_corner" and dest=="rocket_hideout_b1f" and not fl.get("hideout_stairs",false): return "楼梯藏在墙后。看看那张被火箭队看守的海报。"
	if dest=="rocket_hideout_elevator" and not fl.get("lift_key",false): return "电梯需要钥匙。有个手下在地下四层的楼梯那一侧看守着它。"
	if here=="pokemontower_6f" and dest=="pokemontower_7f" and not fl.get("tower_mother",false): return "幽灵挡住了楼梯。玉虹市火箭队手里的检视镜可以看破它的身形。"
	if here=="silph_co_7f" and dest=="silph_co_11f" and not fl.get("rival_silph",false): return "小茂从背后叫住了你。先跟他比一场吧。"
	if here in ["route5_south_entrance","route6_north_entrance","route7_east_entrance","route8_west_entrance"] and dest=="kanto_main":
		var at: Array = target.get("at",[])
		if at.size()==2 and int(at[0])>=312 and int(at[0])<372 and int(at[1])>=150 and int(at[1])<200 and not fl.get("saffron_gates_open",false):
			return "警卫挡住去路：现在不能进入金黄市。玉虹公寓的婆婆泡了一壶好茶。"
	var rounds: Array = data().league
	for i in rounds.size():
		if dest != rounds[i].room: continue
		if i>0 and here!=rounds[i-1].room: return ""
		if i==0 and here!="indigo_plateau_pokemon_center_1f": return ""
		for badge in BADGES:
			if badge not in badges: return "挑战关都联盟还缺少%s。" % badge
		if i>0 and not fl.get(attempt_flag(fl,rounds[i-1].flag),false): return "先战胜%s，才能继续向前。" % rounds[i-1].name
	if dest=="pokemon_league_hall_of_fame" and not fl.get(attempt_flag(fl,"kanto_champions_win"),false): return "只有赢得冠军战的队伍才能登记。"
	return ""

static var puzzles: Dictionary
static func field_rules(mid: String) -> Array:
	if puzzles.is_empty():
		puzzles=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/kanto/puzzles.json"))
	return puzzles.get(mid,[])

static func tiles(mid: String, flags: Dictionary) -> Array:
	var result := []
	for rule: Dictionary in field_rules(mid):
		var changes: Array = rule.base.duplicate()
		for variant: Dictionary in rule.variants:
			if variant.flags.all(func(f): return flags.get(attempt_flag(flags,f) if str(f).begins_with("kanto_") else f,false)):
				changes.append_array(variant.cells)
		for row: Array in changes:
			result.append([row[0],row[1],32768+int(row[2]),32768+int(row[3]) if int(row[3]) else 0,row[4]])
	return result

static func control(mid: String, xy: Vector2i) -> Dictionary:
	var point := [xy.x,xy.y]
	for rule: Dictionary in field_rules(mid):
		var idx: int = rule.controls.find_custom(func(cell): return Vector2i(int(cell[0]),int(cell[1])) == xy)
		if idx>=0: return {"kind":"kanto_puzzle","at":point,"switch":idx,"flag":rule.variants.back().flags[0]}
	return {}

static func set_switch(game: Node, flag: String) -> void:
	game._flags()[flag]=true
	game.world.refresh_story_actors(game._flags())
	game._persist()

static func use_control(game: Node, obj: Dictionary) -> void:
	var flags: Dictionary = game._flags()
	var mid: String = game.world.map_data.id
	var f: String = obj.flag
	if flags.get(f,false):
		game._dialog(["这道门已经打开了。"])
		return
	if mid=="vermilioncity_gym":
		var count := 15
		if not flags.has("surge_bin"):
			flags.surge_bin=game.rng.randi_range(0,count-1)
		var index: int = obj["switch"]
		if flags.get("surge_first",false):
			if index == int(flags.get("surge_second_bin",-1)):
				set_switch(game,"surge_open")
				game._dialog(["第二把电锁解除了，通往马志士的路已经打开。"])
			else:
				flags.surge_first=false
				flags.surge_bin=game.rng.randi_range(0,count-1)
				game.world.refresh_story_actors(flags)
				game._persist()
				game._dialog(["电锁重新扣上了。得从第一个开关再找起。"])
		elif index==int(flags.surge_bin):
			var adjacent := []
			for i in count:
				if abs(i%5-index%5)+abs(floori(i/5.0)-floori(index/5.0))==1: adjacent.append(i)
			flags.surge_second_bin=adjacent[game.rng.randi_range(0,adjacent.size()-1)]
			set_switch(game,"surge_first")
			game._dialog(["第一把电锁解除了！第二个开关就在相邻的垃圾桶里。"])
		else:
			game._dialog(["这里只有垃圾。"])
		return
	if mid=="cinnabarisland_gym":
		var quiz: Dictionary = data().quizzes[int(f.get_slice("_",2))-1]
		game._pick(quiz.question,["是","否"],func(index: int):
			if index<0: return
			if (index==0)==bool(quiz.answer):
				set_switch(game,f)
				game._dialog(["答对了！前往下一间的门打开了。"])
			else:
				var ev: Dictionary = game.story.take("talk",{"map":mid,"actor":quiz.role},flags,game._has_party())
				if not ev.is_empty(): game._play_story(ev))
		return
	if flags.get("card_key",false):
		set_switch(game,f)
		game._dialog(["钥匙卡在感应器上轻响了一声。隔离门打开了。"])
	else:
		game._dialog(["隔离门锁着。需要西尔佛公司的钥匙卡。"])

static func attempt_flag(flags: Dictionary, round_flag: String) -> String:
	return "repeat_"+round_flag if flags.get("kanto_rematch_running",false) else round_flag

static func begin_rematch(source: Dictionary, destination: Dictionary, flags: Dictionary) -> void:
	if source.get("id","")!="indigo_plateau_pokemon_center_1f" or destination.get("map","")!="pokemon_league_loreleis_room": return
	if not (flags.get("kanto_champion",false) and flags.get("sevii_network_online",false)): return
	flags.kanto_rematch_running=true
	flags.erase("kanto_rematch_complete")
	for round_info in data().league: flags.erase("repeat_"+str(round_info.flag))

static func lost_league(game: Node) -> void:
	var flags: Dictionary=game._flags()
	for round_info in data().league:
		var current:=attempt_flag(flags,round_info.flag)
		flags.erase(current)
		flags.erase("story_"+current)
	flags.erase("kanto_rematch_running")
	game._do_warp({"region":"kanto","map":"indigo_plateau_pokemon_center_1f","at":[5,5],"facing":"down"})
	game._heal_party()
	game._persist()

static func checkpoint(here: Dictionary, point: Vector2i, direction: Vector2i, badges: Array) -> String:
	if here.get("region","")!="kanto" or direction==Vector2i.DOWN: return ""
	var rules_by_cell: Dictionary = data().badge_gates.get(here.get("id",""),{})
	var i: int=rules_by_cell.get("%d,%d"%[point.x,point.y],-1)
	if i>=0 and BADGES[i] not in badges: return "前面是关都联盟的检查站。请先取得%s再通过。" % BADGES[i]
	return ""

static func same_cell(xy: Array, x: int, y: int) -> bool:
	return xy.size()==2 and int(xy[0])==x and int(xy[1])==y

static func victory_rocks(mid: String, objects: Array, flags: Dictionary) -> Array:
	if not mid.begins_with("victoryroad_"): return objects
	var result := []
	for o in objects:
		if o.get("kind","")=="boulder":
			var start: Array=o.at
			o["rock_id"]="%s:%d,%d"%[mid,int(start[0]),int(start[1])]
			if mid=="victoryroad_2f" and same_cell(start,33,19) and not flags.get("victory_rock_dropped",false): continue
			if mid=="victoryroad_3f" and same_cell(start,33,18) and flags.get("victory_rock_dropped",false): continue
			var placed: Variant=flags.get("placed:"+str(o.rock_id))
			if placed is Array: o.at=placed.duplicate()
		result.append(o)
	return result

# The original coordinate events summon Blue only for this scene. His final tile
# depends on which lane triggered him. A loss or reload restores the field roster.
static func stage_rival(world: Node, event_id: String) -> bool:
	var p: Vector2i=world.player_pos
	var spot: Vector2i
	var sprite := "fr_blue"
	match event_id:
		"rival_bridge":
			spot=p+Vector2i.UP
			world.facing="up"
		"rival_route22_early","rival_route22_final":
			if p.y==196:
				spot=p+Vector2i.UP
				world.facing="up"
			else:
				spot=p+Vector2i.LEFT
				sprite="fr_blue_right"
				world.facing="left"
		_: return false
	world.npcs.append({"at":[spot.x,spot.y],"role":"visiting_rival","name":"小茂","gfx":sprite})
	world._draw_npcs()
	return true
