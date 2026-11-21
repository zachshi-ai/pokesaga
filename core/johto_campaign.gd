extends RefCounted
## Johto's story actors share their state with the corresponding events and map gates.

const PATH := "res://content/regions/johto/campaign.json"
const SWITCH_ROOM := "johto_goldenrod_underground_switch_room_entrances"
static var cache: Dictionary = {}
static var shutters: Dictionary = {}
const BIRD_STOPS := [[7,15],[7,12],[10,12],[14,11],[14,15],[12,17],[11,15],[7,14],[5,17],[3,13]]
# Facing the bird from a different side changes which clearing it flees into.
const BIRD_PATHS := [
	{"next":2},{"down":8,"next":3},{"left":2,"next":4},{"up":3,"next":5},
	{"up":4,"left":7,"right":4,"next":6},{"right":5,"next":7},
	{"down":5,"left":6,"next":8},{"up":2,"left":2,"right":7,"next":9},
	{"right":8,"down":8,"next":10}
]

static func data() -> Dictionary:
	if cache.is_empty():
		cache = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return cache

static func eligible(row: Dictionary, flags: Dictionary) -> bool:
	if row.get("civilian_during_takeover",false) and flags.get("j_radio_takeover",false) and not flags.get("j_radio_free",false): return false
	for key in row.get("requires",[]):
		if not flags.get(key,false): return false
	for key in row.get("until",[]):
		if flags.get(key,false): return false
	return true

static func roster(map: Dictionary, flags: Dictionary) -> Array:
	var rows: Array = []
	var defs: Dictionary = data().actors.get(map.get("id",""),{})
	for original in map.get("npcs",[]):
		var spec: Dictionary = defs.get("%d,%d" % original.at,{})
		if not eligible(spec,flags): continue
		if map.get("id","") == "johto_elms_lab" and flags.get("j_mystery_egg",false):
			var stolen: int = {152:155,155:158,158:152}.get(int(flags.get("j_starter_species",0)),0)
			if stolen and int(spec.get("gives_mon",{}).get("species",-1)) == stolen: continue
		var row: Dictionary = original.duplicate(true)
		row.merge(spec,true)
		if row.get("role","") == "j_farfetchd":
			var stop := bird_stop(flags)
			row.at = BIRD_STOPS[stop-1]
		if spec.get("story_only",false):
			for key in ["badge","battle","gives_mon","sight"]: row.erase(key)
		rows.append(row)
	for row in data().add.get(map.get("id",""),[]):
		if eligible(row,flags): rows.append(row.duplicate(true))
	return rows

static func sync(save: Dictionary) -> void:
	var flags: Dictionary = save.get("flags",{})
	var n := 0
	for badge in data().badges:
		if badge in save.get("badges",[]):
			flags["j_badge_" + str(data().badges.find(badge)+1)] = true
			n += 1
	if n >= 7 and flags.get("j_plant_clear",false): flags.j_radio_takeover = true

static func gate(from: Dictionary, to: Dictionary, flags: Dictionary) -> String:
	if to.get("region","") != "johto": return ""
	var dst: String = to.get("map","")
	var src: String = from.get("id","")
	var at: Array = to.get("at",[])
	if src == "johto_goldenrod_underground" and ((dst == src and at == [10,14]) or (dst == SWITCH_ROOM and at == [11,2])) and not flags.get("j_basement_open",false):
		return "地下通道的门锁上了。"
	if src == "johto_radio_tower_3f" and dst == "johto_radio_tower_4f" and at == [8,1] and not flags.get("j_radio_door",false): return "隔门还没打开。"
	for gate_row in data().gates.get(to.get("map",""),[]):
		if gate_row.has("from") and gate_row.from != from.get("id",""): continue
		if not eligible(gate_row,flags): return gate_row.message
	return ""

static func team(stage: int, flags: Dictionary) -> Array:
	# The rival steals the starter with a type advantage over the player's choice.
	var starter := str(int(flags.get("j_starter_species", 152)))
	return data().rivals[str(stage)].get(starter,data().rivals[str(stage)]["152"])

static func quiz(game, questions: Array, index: int) -> void:
	if index >= questions.size():
		game._story_step()
		return
	var question: Array = questions[index]
	game._pick(question[0], question[1], func(answer: int) -> void:
		if answer < 0:
			game.story_abort = true
			game.story_queue.clear()
			game._story_step()
		elif question[2].any(func(valid): return int(valid)==answer):
			quiz(game,questions,index+1)
		else:
			game._flags().j_quiz_mistake = true
			var prompt = game._dialog(["再好好想一想，再回答一次吧。"],"长老")
			prompt.closed.connect(func(): quiz(game,questions,index), CONNECT_ONE_SHOT))

static func interact_field(game) -> bool:
	var mid: String = game.world.map_data.id
	var tile: Vector2i = game.world.player_pos + game.world._dir_vec()
	var flags: Dictionary = game._flags()
	var actor := ""
	if mid == "johto_ilex_forest" and game.world._npc_at(tile).get("role","") == "j_farfetchd":
		var stop := bird_stop(flags)
		if stop < 10 and flags.get("j_bird_request",false):
			var path: Dictionary = BIRD_PATHS[stop-1]
			var next: int = path.get(game.world.facing,path.next)
			flags.j_bird_position = next
			if stop == 1: flags.j_bird_1 = true
			if next == 8: flags.j_bird_2 = true
			if next == 10: flags.j_bird_home = true
			game.world.refresh_story_actors(flags)
			game._persist()
			game._dialog(["嘎嘎！大葱鸭跑回了学徒身边。" if next==10 else "嘎！大葱鸭往林子里跑去了。"],"大葱鸭")
		else: game._dialog(["嘎嘎！"],"大葱鸭")
		return true
	if mid == "johto_lake_of_rage" and game.world._npc_at(tile).get("role","") == "j_red_gyarados": actor = "j_red_gyarados"
	if mid == "johto_goldenrod_underground" and tile == preload("res://core/hgss_field.gd").position(game.world.map_data,Vector2i(9,3)): actor = "j_basement_door"
	if mid == "johto_radio_tower_3f" and tile == preload("res://core/hgss_field.gd").position(game.world.map_data,Vector2i(7,1)): actor = "j_radio_door"
	if actor != "": return game._story_fire("talk",{"map":mid,"actor":actor})
	if mid != SWITCH_ROOM: return false
	var switches := [Vector2i(7,1),Vector2i(4,1),Vector2i(0,1),Vector2i(10,5)]
	for i in switches.size(): switches[i]=preload("res://core/hgss_field.gd").position(game.world.map_data,switches[i])
	var selected := switches.find(tile)
	if selected < 0 or not flags.get("j_rival4",false): return false
	var key := "j_switch_%d" % selected
	var on := bool(flags.get(key,false))
	var prompt = game._dialog(["这是%s。" % ("紧急开关" if selected==3 else "%d 号开关" % (selected+1))])
	prompt.ask("关闭" if on else "按下","离开")
	prompt.answered.connect(func(yes: bool):
		if not yes: return
		toggle_switch(flags,selected)
		game.world._rebuild(flags)
		game._show_toast("隔门改变了位置。")
		game._persist())
	return true

static func load_shutters() -> Dictionary:
	if shutters.is_empty(): shutters = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/shutters.json"))
	return shutters

static func toggle_switch(flags: Dictionary, selected: int) -> void:
	var key := "j_switch_%d" % selected
	flags[key] = not flags.get(key,false)
	if selected==3:
		for i in 3: flags["j_switch_%d"%i] = flags[key]
	var pos := 0
	for i in 3:
		if flags.get("j_switch_%d"%i,false): pos += i+1
	var states: Dictionary = flags.get("j_shutters",{})
	if selected==3 and flags[key]:
		for i in range(1,12): states[str(i)] = i>=3
	else:
		states.merge(load_shutters().updates[str(pos)],true)
	flags.j_shutters = states
	if pos == 6: flags.j_switches = true

static func draw_shutters(world, flags: Dictionary) -> void:
	var book := load_shutters()
	var states: Dictionary = flags.get("j_shutters",{})
	var sheet: Texture2D = load("res://assets/field/crystal_shutters.png")
	for i in book.doors.size():
		for cell in book.doors[i]:
			var tile: int = cell[3] if states.get(str(i+1),false) else cell[2]
			world.emerald_collision[int(cell[1])][int(cell[0])] = int(tile not in [0x2d,0x3d])
			var region := AtlasTexture.new()
			region.atlas = sheet
			region.region = Rect2(book.tiles.find(float(tile))*32,0,32,32)
			var image := Sprite2D.new()
			image.texture = region
			image.centered = false
			image.scale = Vector2(0.5,0.5)
			image.position = Vector2(cell[0],cell[1])*world.TILE
			image.z_index = 1
			world.add_child(image)
			world._tile_nodes.append(image)


static func bird_stop(flags: Dictionary) -> int:
	if flags.get("j_bird_home",false): return 10
	return clampi(int(flags.get("j_bird_position",9 if flags.get("j_bird_2",false) else 2 if flags.get("j_bird_1",false) else 1)),1,10)
