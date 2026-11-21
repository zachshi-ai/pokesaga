extends SceneTree
## godot --headless --fixed-fps 60 --path . --script tools/test_collection.gd

const Save := preload("res://core/save_game.gd")
var game
var party
var dex
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error("COLLECTION FAIL " + message)
		failed = true

# Replay an ordinary RNG draw of the requested type. The game still rolls through
# its normal encounter/egg paths at the shipped odds.
func next_shiny(kind: String) -> void:
	for i in 1000000:
		var original: int = game.appearance_rng.state
		if party.roll_shiny(game.appearance_rng) == kind:
			game.appearance_rng.state = original
			return
	check(false, "unreachable rarity " + kind)

func status(sid: int, form := "", shiny := "none", tera := "") -> int:
	return dex.status(game.save_data.dex_variants, sid, form, shiny, tera)

func run() -> void:
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	party = load("res://core/party.gd")
	dex = load("res://core/dex_variants.gd")
	game._close_all_dialogs()
	game.appearance_rng.seed = 731
	var old := {"party":[{"species_id":25, "shiny":true}], "boxes":[{"mons":[
		{"species_id":19,"form":"RATTATA_ALOLA","shiny":true,"shiny_kind":"square"}]}],
		"dex":{"seen":[74.0],"caught":[]}}
	dex.restore(old)
	check(old.party[0].shiny_kind == "star" and old.boxes[0].mons[0].shiny_kind == "square", "old shiny migration")
	check(dex.status(old.dex_variants, 19, "RATTATA_ALOLA", "square") == 2, "boxed form migration")
	check(dex.status(old.dex_variants, 74) == 0 and 74 in old.dex.seen, "old species-only data invented a variant")

	game._add_to_team(6, 50)
	game.bag_items.append({"name":"大师球","category":"ball","count":1})
	next_shiny("square")
	game._start_wild_battle(19, 4, "RATTATA_ALOLA")
	var ui = game.active_battle
	check(ui.battle.cur_b().shiny_kind == "square" and status(19, "RATTATA_ALOLA", "square") == 1, "wild encounter")
	check(ui.enemy_sprite.texture is AtlasTexture and ui.enemy_sprite.get_node("Appearance").shine == "square", "shiny battle art and effect")
	check(status(19) == 0 and status(19, "RATTATA_ALOLA", "star") == 0, "unseen combinations")
	ui._process(2.0)
	ui._on_command_kind("bag")
	for b in ui.get_node("BallPanel").find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and not b.disabled and b.text.begins_with("大师球"):
			b.pressed.emit()
			break
	for i in 30:
		if game.active_battle == null:
			break
		ui._process(2.0)
	check(game.active_battle == null and status(19, "RATTATA_ALOLA", "square") == 2, "capture via ball panel")
	if game.save_data.party.size() < 2:
		Save.clear_test_slot()
		quit(1)
		return
	check(game.save_data.party[1].shiny_kind == "square" and game.save_data.party[1].form == "RATTATA_ALOLA", "capture kept identity")
	await process_frame
	next_shiny("star")
	game.save_data.egg = {"species":25,"steps":1}
	game._tick_egg()
	game._close_all_dialogs()
	check(status(25, "", "star") == 2 and game.save_data.party[2].shiny_kind == "star", "hatched star")
	game._start_wild_battle(19, 4)
	ui = game.active_battle
	ui._process(2.0)
	ui._do_transform("CHARIZARD_MEGA_X")
	check(status(6, "CHARIZARD_MEGA_X") == 2 and status(6, "CHARIZARD_MEGA_Y") == 0, "Mega collection")
	for i in 30:
		if ui.state == "menu": break
		ui._process(2.0)
	ui._try_flee()
	for i in 30:
		if game.active_battle == null: break
		ui._process(2.0)
	await process_frame
	game._start_wild_battle(19, 4)
	ui = game.active_battle
	ui._process(2.0)
	ui._do_tera()
	check(status(6,"","none","fire") == 2 and status(6,"","none","water") == 0, "actual tera attribute")
	for i in 30:
		if ui.state == "menu": break
		ui._process(2.0)
	ui._try_flee()
	for i in 30:
		if game.active_battle == null: break
		ui._process(2.0)
	await process_frame
	var db = root.get_node("Data")
	game.world.load_map(db.load_map("johto", "johto_route_30"))
	var potion_tile := Vector2i(11,31) # Native Route 30 hidden potion event.
	game.world.warp_to(potion_tile)
	game._refresh_scene()
	var before: int = game._bag_count("伤药")
	game._on_action()
	game._close_all_dialogs()
	check(game._bag_count("伤药") == before + 1, "natural hidden-item interaction")
	var variants: Dictionary = game.save_data.dex_variants.duplicate(true)
	game._restore_from_save()
	check(game.save_data.dex_variants == variants, "saved collection changed")
	check(game.world.object_at(potion_tile).is_empty(), "hidden item respawned after reloading")
	game._on_action()
	check(game._bag_count("伤药") == before + 1, "duplicate hidden pickup")
	Save.clear_test_slot()
	print("COLLECTION ", "FAIL" if failed else "PASS", "  variants=", variants.size())
	quit(1 if failed else 0)
