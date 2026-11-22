extends SceneTree
## Run against an imported project or an exported pack. Uses a temporary save slot.

const Save := preload("res://core/save_game.gd")
const DIRS := {Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}
var game
var world
var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> bool:
	if not value:
		push_error("ATLAS: "+message)
		failed = true
	return value

func tile(coords: Array) -> Vector2i:
	return Vector2i(int(coords[0]),int(coords[1]))

func click(panel: Control, label: String) -> bool:
	for node in panel.find_children("*","Button",true,false):
		if node.text == label and not node.disabled:
			node.pressed.emit()
			return true
	return expect(false,"missing button "+label)

func walk_room(to: Vector2i) -> bool:
	var cells: Array[Vector2i] = [world.player_pos]
	var parent := {world.player_pos:world.player_pos}
	var stairs := {}
	for w in world.map_data.get("warps",[]):
		stairs[tile(w.at)] = true
	for current in cells:
		if current == to:
			break
		for d in DIRS:
			var next: Vector2i = current+d
			if not stairs.has(next) and not parent.has(next) and world.can_enter(next,d):
				parent[next] = current
				cells.append(next)
	if not expect(parent.has(to),"bed to wall"):
		return false
	var path: Array[Vector2i] = []
	while to != world.player_pos:
		path.push_front(to)
		to = parent[to]
	for step in path:
		var direction: Vector2i = step - world.player_pos
		if not expect(world.step(direction),"bedroom step"): return false
		world.tick_walk(1.0)
	return true

func use_navigator(hub: Dictionary) -> bool:
	for i in 32:
		if game._dialogs.is_empty(): break
		game._on_action()
	var delta: Vector2i = tile(hub.npc_at)-world.player_pos
	if not expect(DIRS.has(delta),"navigator must stand beside arrival "+str(hub)):
		return false
	world.facing = DIRS[delta]
	game._on_action()
	if game.panel_open!=1 or not game.menu_layer.get_child(-1).has_signal("trip_requested"):
		print("navigator diagnostic ",world.last_event," dialogues=",game._dialogs.size()," panels=",game.panel_open," facing=",world.facing," npc=",world._npc_at(world.player_pos+delta))
	return expect(game.panel_open==1 and game.menu_layer.get_child(-1).has_signal("trip_requested"),"navigator opens atlas "+str(hub))

func run() -> void:
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	world = game.world
	game.title_screen.new_button.pressed.emit()
	await process_frame
	var catalog: Dictionary = root.get_node("Data").travel_regions()
	if not expect(catalog.size()==21,"region count"):
		finish()
		return
	if not walk_room(Vector2i(11,2)):
		finish()
		return
	world.facing = "up"
	game._on_action()
	if not expect(game.panel_open==1,"wall map opens"):
		finish()
		return
	var atlas = game.menu_layer.get_child(-1)
	expect(atlas.travel == false,"wall map mode")
	expect(atlas.chart.art != null,"world chart")
	for id in catalog:
		if not click(atlas,catalog[id].name): break
		expect(atlas.chart.art != null,"regional chart "+id)
		expect(atlas.chart.points.size()==catalog[id].locations.size(),"places "+id)
		atlas.chart.magnify(.5)
		expect(atlas.chart.zoom==1.5,"zoom")
		if id=="hoenn":
			click(atlas,"丰缘地图")
			expect(atlas.viewing_art and atlas.chart.art!=null and atlas.chart.art.resource_path=="res://assets/emerald/ui/hoenn_map.png","Emerald PokéNav map")
			atlas.handle_back()
		atlas.handle_back()
	atlas.handle_back()
	await process_frame
	expect(world.map_data.id=="pallet_town_players_house_2f","reading moved player")
	var origin: Dictionary = catalog.kanto.hub
	game._do_warp(origin)
	var hubs := 0
	var here: Dictionary = origin
	for id in catalog:
		if not use_navigator(here): break
		atlas = game.menu_layer.get_child(-1)
		if not click(atlas,catalog[id].name) or not click(atlas,"出发前往"+str(catalog[id].name)):
			break
		await process_frame
		if id=="hoenn": click(game.menu_layer.get_child(-1),"直接抵达")
		if id=="sinnoh" and not game.save_data.chapters.has(id): click(game.menu_layer.get_child(-1),"带现有队伍出发")
		await process_frame
		game._close_all_dialogs()
		await process_frame
		if id in ["hoenn","johto","sinnoh"] and (world.map_data.id!=catalog[id].hub.map or world.player_pos!=tile(catalog[id].hub.at)):
			expect(game.save_data.chapters.has(id),"first visit began local story")
			game._use_bag_item("地区转移器")
			atlas = game.menu_layer.get_child(-1)
			click(atlas,catalog[id].name)
			click(atlas,"出发前往"+str(catalog[id].name))
			await process_frame
			if id=="hoenn": click(game.menu_layer.get_child(-1),"直接抵达")
			await process_frame
		here = catalog[id].hub
		var stored := Save.existing()
		expect(world.map_data.region==here.region and world.map_data.id==here.map and world.player_pos==tile(here.at),"arrival "+id)
		expect(tile(stored.pos)==world.player_pos and stored.region==here.region and stored.map==here.map,"save "+id)
		hubs += 1
	expect(hubs==catalog.size(),"all hubs visited")
	print("ATLAS regional charts=",catalog.size()," navigator destinations=",hubs)
	finish()

func finish() -> void:
	Save.clear_test_slot()
	print("ATLAS ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
