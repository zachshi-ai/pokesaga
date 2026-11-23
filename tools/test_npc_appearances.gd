extends SceneTree
## Run in the exported pack with --headless --main-pack build.pck --script tools/test_npc_appearances.gd.
const Art := preload("res://core/npc_appearance.gd")

func _initialize() -> void:
	call_deferred("audit")

func audit() -> void:
	var counts := {}
	var total := 0
	var navigators := 0
	var failures := 0
	for region in DirAccess.get_directories_at("res://content/regions"):
		var folder := "res://content/regions/%s/maps" % region
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".json"):
				continue
			var room: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join(file)))
			for person in room.get("npcs", []):
				var texture := Art.texture_for(person)
				total += 1
				if texture == null:
					push_error("Unresolved map character %s/%s %s" % [region,file,person])
					failures += 1
					continue
				if texture.get_width() != 16 or texture.get_height() not in [16, 32]:
					push_error("Unexpected overworld pixel size %s for %s" % [texture.get_size(), person.name])
					failures += 1
				var key := texture.resource_path.get_file().get_basename()
				counts[key] = counts.get(key, 0) + 1
				var expected := ""
				if person.get("transit", false):
					expected = "navigator"
					navigators += 1
				elif region == "galar" and file == "galar_player_home.json" and person.name == "妈妈":
					expected = "mom"
				elif person.get("heal", false):
					expected = "nurse"
				elif person.get("shop", false):
					expected = "clerk"
				elif person.get("gives_mon", false) and person.name == "精灵球":
					expected = "ball"
				if expected != "" and key != expected:
					push_error("Wrong appearance for %s: %s, expected %s" % [person.name,key,expected])
					failures += 1
	if navigators == 0 or not counts.has("sailor") or not counts.has("mom"):
		failures += 1
	if Art.texture_for({"name":"研究员", "gfx":"expert_m", "form_items":true}).resource_path != Art.DIRECTORY + "scientist.png":
		failures += 1
	print("Emerald NPC sprites ", "PASS" if failures == 0 else "FAIL", ": ",total," map NPCs, ",counts.size()," distinct pictures, ",navigators," navigators, failures=",failures)
	print("NPC sprite counts ",counts)
	quit(0 if failures == 0 else 1)
