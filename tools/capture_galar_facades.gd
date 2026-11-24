extends "res://tools/test_world_walks.gd"
## Run in a graphical viewport with -- /absolute/output to also save one game frame per design.

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := "" if args.is_empty() else str(args[0])
	if not folder.is_empty() and (not folder.is_absolute_path() or DirAccess.make_dir_recursive_absolute(folder) != OK):
		push_error("Provide an absolute output directory.")
		quit(1)
		return
	db = root.get_node("Data")
	world = load("res://core/world.gd").new()
	root.add_child(world)
	await process_frame
	var designs := {}
	var lots := 0
	for id in db.load_region("galar").map_ids:
		var map: Dictionary = db.load_map("galar", id)
		for prop in map.get("hoenn_art", {}).get("p", []):
			var uri := str(prop[0])
			if not uri.begins_with("res://assets/galar/architecture/"):
				continue
			current = "galar/" + str(id)
			world.load_map(map)
			world.warp_to(vec(map.spawn))
			world.finish_walk()
			var door := Vector2i(int(prop[1]), int(prop[2]))
			var art := load(uri) as Texture2D
			var front := door + Vector2i.DOWN
			if art == null or vec(prop[3]) != Vector2i(art.get_width() / 2, art.get_height()) or world.warp_at(door).is_empty():
				fail("misaligned entrance " + current + " " + str(door))
				break
			if not walk(front) or world.player_pos != front:
				fail("blocked doorstep " + current + " " + str(front))
				break
			lots += 1
			if not designs.has(uri):
				designs[uri] = true
				if not folder.is_empty():
					world.facing = "up"
					world._sync_player()
					await process_frame
					await RenderingServer.frame_post_draw
					if root.get_texture().get_image().save_png(folder.path_join(uri.get_file())) != OK:
						fail("could not capture " + uri)
						break
		if failed: break
	if designs.is_empty(): fail("no Galar buildings visited")
	print("GALAR FACADES ", "FAIL" if failed else "PASS", " lots=", lots, " designs=", designs.size(), " steps=", steps)
	quit(1 if failed else 0)
