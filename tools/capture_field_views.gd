extends SceneTree
## Run with a displayed Godot viewport. Compare the same landmarks across packs.
## Godot --path . --resolution 720x480 --script tools/capture_field_views.gd -- /absolute/folder
## Append a region ID to survey the spawn view of every map in that region's registry.
const VIEWS := [
	["hoenn", "littleroot_town", 8, 10], ["hoenn", "hoenn_119", 8, 34],
	["johto", "johto_new_bark_town", 18, 12],
	["sinnoh", "sinnoh_twinleaf", 19, 22], ["sinnoh", "sinnoh_sandgem", 15, 13],
	["sinnoh", "sinnoh_201", 27, 21], ["sinnoh", "sinnoh_hearthome", 31, 20],
	["unova", "unova_nuvema", 14, 14, "bw"], ["unova", "unova_aspertia", 15, 58, "b2"],
	["unova", "unova_1", 40, 28, "bw"], ["unova", "unova_nimbasa", 27, 18, "bw"],
	["kalos", "kalos_vaniville", 30, 14], ["kalos", "kalos_aquacorde", 63, 53],
	["alola", "alola_iki", 12, 14], ["alola", "alola_hauoli", 33, 27],
	["galar", "galar_postwick", -1, -1], ["galar", "galar_1", -1, -1],
	["hisui", "hisui_jubilife", -1, -1],
	["paldea", "paldea_cabo", -1, -1]
]
const REVISED_KALOS := {"kalos_vaniville": Vector2i(18,12), "kalos_aquacorde": Vector2i(15,18)}

func _initialize() -> void:
	capture.call_deferred()

func standing_spot(world, origin: Vector2i, size: Array) -> Vector2i:
	# A renderer probe must not place the player on a roof, under water or on a transition.
	var pending := [origin]
	var visited := {origin: true}
	var bounds := Rect2i(0, 0, int(size[0]), int(size[1]))
	var index := 0
	while index < pending.size():
		var cell: Vector2i = pending[index]
		index += 1
		if bounds.has_point(cell) and not world.is_blocked(cell) and not world.is_water(cell) and world.warp_at(cell).is_empty():
			return cell
		for dir in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var next: Vector2i = cell + dir
			if bounds.has_point(next) and not visited.has(next):
				visited[next] = true
				pending.append(next)
	return Vector2i(-1, -1)

func capture() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() not in [1,2] or not args[0].is_absolute_path():
		push_error("Provide an absolute output directory and optional region after --")
		quit(1)
		return
	var folder := args[0]
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		quit(1)
		return
	var db := root.get_node("Data")
	var views := VIEWS.duplicate()
	if args.size() == 2:
		views.clear()
		var entry: Dictionary = db.load_region(args[1])
		for key in entry.get("map_ids", []):
			views.append([args[1], key, -1, -1])
		if views.is_empty():
			push_error("Empty registry: " + args[1])
			quit(1)
			return
	var world = load("res://core/world.gd").new()
	root.add_child(world)
	await process_frame
	for view in views:
		if view.size() == 5:
			db.set_unova_era(view[4])
		var map: Dictionary = db.load_map(view[0], view[1])
		if map.is_empty():
			push_error("Unregistered map " + str(view[1]))
			quit(1)
			return
		world.load_map(map)
		var focus := Vector2i(view[2], view[3])
		if map.has("kalos_opening_revision"):
			focus = REVISED_KALOS.get(view[1], focus)
		if focus.x < 0:
			focus = Vector2i(map.spawn[0], map.spawn[1])
		focus = standing_spot(world, focus, map.size)
		if focus.x < 0:
			push_error("No dry standable tile in " + str(view[1]))
			quit(1)
			return
		world.warp_to(focus)
		world.finish_walk()
		await process_frame
		await RenderingServer.frame_post_draw
		var file := folder.path_join(str(view[1]) + ".png")
		if root.get_texture().get_image().save_png(file) != OK:
			push_error("Failed to write " + file)
			quit(1)
			return
	print("Captured ", views.size(), " game views in ", folder)
	quit()
