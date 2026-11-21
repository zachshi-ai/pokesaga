extends SceneTree
## Exercise the same field input as a player against native map blocks.
const World := preload("res://core/world.gd")
var world
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, why: String) -> void:
	if not value:
		push_error("FIELD MAPPING " + why)
		failed = failed or not value

func walk(dir: Vector2i) -> void:
	var want: Vector2i = world.player_pos + dir
	check(world.step(dir) and world.player_pos == want, "step to %s in %s" % [want, world.map_data.id])
	world.finish_walk()

func run() -> void:
	world = World.new()
	root.add_child(world)
	await process_frame
	var db := root.get_node("Data")
	world.load_map(db.load_map("kanto", "kanto_main"))
	world.warp_to(Vector2i(72,261))
	for i in 4:
		walk(Vector2i.UP)
	check(world.area_name() == "1 号道路", "northbound Pallet / Route 1 border")
	world.warp_to(Vector2i(84,200))
	check(not world.is_water(world.player_pos) and world.elevation_at(world.player_pos) == 3, "dry Viridian Mart doorstep")
	check(world.blocked_by_terrain(Vector2i(84,199)), "solid Mart door has an upward-only warp")
	check(world.step(Vector2i.UP) and world.pending_warp.get("map") == "viridiancity_mart", "enter Viridian Mart")
	world.finish_walk()
	for p in [Vector2i(325,135),Vector2i(288,166),Vector2i(319,140),Vector2i(336,189)]:
		check(not world.blocked_by_terrain(p) and not world.is_water(p), "Route 6 / Route 8 / Saffron heal location %s" % p)
	world.warp_to(Vector2i(325,136))
	walk(Vector2i.UP)
	world.warp_to(Vector2i(288,167))
	walk(Vector2i.UP)
	world.warp_to(Vector2i(320,140))
	walk(Vector2i.LEFT)
	check(world.step(Vector2i.LEFT) and world.pending_warp.get("map") == "route8_west_entrance", "Route 8 gate reached from the east")
	world.finish_walk()

	world.load_map(db.load_map("kanto","ceruleancity_gym"))
	var cast := {
		Vector2i(10,12):"fr_swimmer_m_water_left", Vector2i(4,7):"fr_picnicker_right",
		Vector2i(8,6):"fr_misty_down", Vector2i(7,16):"fr_gym_guy_down"
	}
	for cell in cast:
		var actor: Dictionary = world._npc_at(cell)
		var slot: int = world.npcs.find(actor)
		check(slot>=0,"missing Cerulean actor at %s" % cell)
		if slot<0: continue
		var sprite: Sprite2D = world._npc_nodes[slot*2+1]
		check(sprite.texture.resource_path.ends_with(cast[cell]+".png"), "incorrect Cerulean sprite at %s" % cell)
		check(sprite.position == Vector2(cell*16) + Vector2(8,0),"native foot anchor for 16×32 actor")
		check(world._npc_nodes[slot*2].visible == (cell!=Vector2i(10,12)), "swimmer has no land shadow")
	var wet := 0
	var dry := 0
	var index: Dictionary = preload("res://core/frlg_actors.gd").data()
	for actors: Dictionary in index.maps.values():
		for actor: Dictionary in actors.values():
			var pose: String = actor.get("field_art","")
			if "swimmer" in pose or "tuber" in pose:
				check(ResourceLoader.exists("res://assets/npc/"+pose+".png"), "missing "+pose)
				if actor.get("in_water_pose",false): wet+=1
				else: dry+=1
	check(wet==35 and dry==6, "all FRLG swimmer and tuber object events")
	world.night = 1.0
	world.apply_light()
	check(world._night_tint.color == Color.WHITE, "native indoor palette at night")
	world.warp_to(Vector2i(9,16))
	world.surfing = false
	walk(Vector2i.UP)
	check(not world.is_water(world.player_pos) and world.elevation_at(world.player_pos) == 3, "dry gym boardwalk")
	check(world.is_water(Vector2i(8,15)) and world.elevation_at(Vector2i(8,15)) == 1, "gym pool surface")
	check(not world.step(Vector2i.LEFT) and world.player_pos == Vector2i(9,15), "cannot walk from boards onto water")
	check(world.toggle_surf() == "用冲浪下水了。" and world.surfing and world.player_pos == Vector2i(8,15), "Surf boards exactly one tile")
	world.finish_walk()
	world.facing = "left"
	world.toggle_surf()
	check(world.surfing and world.player_pos == Vector2i(8,15), "cannot dismount in the pool")
	walk(Vector2i.LEFT)
	walk(Vector2i.RIGHT)
	world.facing = "right"
	check(world.toggle_surf() == "回到岸上。" and not world.surfing and world.player_pos == Vector2i(9,15), "dismount on the boardwalk")
	world.finish_walk()
	world.load_map(db.load_map("kanto","pokemon_mansion_1f"))
	world.warp_to(Vector2i(5,6))
	world.facing = "up"
	world.step_interact()
	check(world.last_event == "obj:mansion_switch", "interact with the original 1F statue")
	var door := Vector2i(33,25)
	check(world.blocked_by_terrain(door), "mansion east gates are initially closed")
	world.set_mansion_switch(true)
	check(not world.blocked_by_terrain(door), "press statue to open the east corridor")
	world.load_map(db.load_map("kanto","pokemon_mansion_2f"))
	check(not world.mansion_switches.is_empty() and world.taken.get(world.MANSION_FLAG,false), "upper floors share the mansion switch")
	world.load_map(db.load_map("kanto","pokemon_mansion_1f"))
	check(not world.blocked_by_terrain(door), "return downstairs with the gates still open")
	world.warp_to(Vector2i(34,32))
	walk(Vector2i.DOWN)
	check(world.step(Vector2i.DOWN) and world.pending_warp.get("map") == "kanto_main", "use mansion southeast exit")
	world.finish_walk()
	world.set_mansion_switch(false)
	check(world.blocked_by_terrain(door), "reset statue closes the east corridor again")

	world.taken = {}
	world.load_map(db.load_map("sevii","mt_ember_exterior"))
	world.warp_to(Vector2i(42,40))
	check(world.blocked_by_terrain(Vector2i(42,39)) and not world.step(Vector2i.UP), "unopened Mt Ember cave wall")
	world.refresh_story_actors({"ember_ruby_requested": true})
	check(not world.blocked_by_terrain(Vector2i(42,39)), "quest opens Mt Ember cave tile")
	check(world.step(Vector2i.UP) and not world.pending_warp.is_empty(), "enter revealed cave")
	world.finish_walk()
	world.taken = {"got_ember_ruby":true}
	world.load_map(db.load_map("sevii","mt_ember_exterior"))
	check(world.quest_door_open and not world.blocked_by_terrain(Vector2i(42,39)), "collected ruby keeps Mt Ember cave open")
	world.taken = {}
	world.load_map(db.load_map("sevii","six_island_ruin_valley"))
	world.warp_to(Vector2i(24,25))
	check(world.blocked_by_terrain(Vector2i(24,24)) and not world.step(Vector2i.UP), "Dotted Hole stays closed before Cut")
	world.refresh_story_actors({"ruin_valley_cut_door":true})
	check(not world.blocked_by_terrain(Vector2i(24,24)) and world.step(Vector2i.UP), "Cut opens the Dotted Hole")
	world.finish_walk()
	if not failed: print("PASS native field: Pallet north border, Viridian Mart, Saffron gates, Cerulean Gym boardwalk, boarding and dismounting, mansion statue, Mt Ember quest cave.")
	quit(1 if failed else 0)
