extends "res://tools/test_region_journey.gd"
## Both public travel options, a mid-chapter reload, and the powers an older team carries.
const Destination := {"region":"sinnoh","map":"sinnoh_pokemon_league_champion_room","at":[8,12],"platinum_native":true}
const HOME := "sinnoh_twinleaf_town_player_house_2f"

func sinnoh_branch(old: Dictionary, mode: String) -> void:
	expect(Save.save(old.duplicate(true)),"write isolated slot")
	await title()
	expect(await preload("regional_start.gd").enter(game,"sinnoh",mode),"travel using the atlas and touch choice")
	expect(game.world.map_data.id==HOME and game.world.player_pos==Vector2i(4,6),"arrive in Twinleaf bedroom")
	game._close_all_dialogs()
	var loaded: Dictionary = Save.existing()
	expect(loaded.origin==old.origin and loaded.chapters.sinnoh==mode,"same campaign records first arrival")
	expect(loaded.flags.s_started and not loaded.flags.get("s_badge_1",false),"local story starts before Oreburgh")
	expect(loaded.money==old.money and loaded.badges==old.badges and loaded.hall_of_fame==old.hall_of_fame,"wallet, badges and champion records survive")
	expect(loaded.dex==old.dex,"Pokédex survives crossing")
	if mode=="boxed":
		expect(loaded.party.is_empty() and loaded.boxes[0].mons.slice(1)==old.party,"all 12 stored in order with their attributes")
	else:
		expect(loaded.party==old.party and loaded.boxes==old.boxes,"all 12 keep HP, PP, held items and variants")
	expect(not game._party_can_move("SURF") and not game._party_can_move("ROCK_CLIMB"),"old HMs and badges cannot open a pass")
	game._do_warp(Destination)
	expect(game.world.map_data.id==HOME,"direct champion-room entry is blocked")
	game._close_all_dialogs()
	game._persist()
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	expect(not game._offer_chapter("sinnoh") and game.save_data.chapters.sinnoh==mode,"continue never repeats the deposit")

func run() -> void:
	Save.use_test_slot()
	await title()
	var old:=fixture()
	Chapters.migrate(old)
	old.regional_badges.erase("sinnoh")
	old.party[0].moves=[57,431]
	old.party[0].pp=[10,10]
	old=JSON.parse_string(JSON.stringify(old))
	for mode in ["carried","boxed"]: await sinnoh_branch(old,mode)
	var full:=old.duplicate(true)
	var box: Array=[]
	for i in 30: box.append({"species_id":25})
	full.boxes=[]
	for i in 200: full.boxes.append({"mons":box.duplicate(true)})
	var before:=JSON.stringify(full)
	expect(Chapters.begin(full,"sinnoh","boxed").is_empty() and JSON.stringify(full)==before,"full PC leaves party and origin intact")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("PLATINUM SHARED SAVE ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(int(failed))
