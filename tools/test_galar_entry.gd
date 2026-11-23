extends "res://tools/test_region_journey.gd"

const Start = preload("regional_start.gd")
const GrassGym = preload("res://core/galar_gym.gd")
const Moves = preload("res://core/galar_moves.gd")

func run() -> void:
	Save.use_test_slot()
	await title()
	var old := fixture()
	Chapters.migrate(old)
	old.party[0].moves=[57,19]
	old.party[0].pp=[10,10]
	old=JSON.parse_string(JSON.stringify(old))
	for version in ["sword","shield"]:
		expect(Save.save(old.duplicate(true)),"write pre-Galar shared party")
		await title()
		expect(await Start.enter(game,"galar","carried",version),"enter from bag " + version)
		var slot:=Save.existing()
		expect(slot.party==old.party and slot.boxes==old.boxes,"all twelve carried individuals and boxes")
		expect(slot.flags.g_version==version and slot.regional_badges.galar.is_empty(),"local version and badge case")
		game._close_all_dialogs()
		var origin: Vector2i=game.world.player_pos
		for target in ["galar_weald","galar_motostoke_inn","galar_motostoke_stadium","galar_turffield",GrassGym.MISSION,GrassGym.PITCH,"galar_stadium"]:
			game._do_warp({"region":"galar","map":target,"at":[3,3]})
			expect(game.world.map_data.id=="galar_player_home" and game.world.player_pos==origin,"blocked direct warp "+target)
			game._close_all_dialogs()
		expect(not game._party_can_move("SURF") and not game._party_can_move("FLY"),"imported field moves")
		var progress:Dictionary=game._flags()
		progress.g_gym_ready=true
		game._do_warp({"region":"galar","map":GrassGym.PITCH,"at":[14,24]})
		expect(game.world.map_data.id=="galar_player_home","cannot skip sheep even with lookout complete")
		game._close_all_dialogs()
		progress.erase("g_gym_ready")
		game._do_warp(root.get_node("Data").travel_regions().ultra.hub)
		expect(game.world.map_data.region=="ultra","leave prologue")
		expect(Start.open_trip(game,"galar"),"return through transfer device")
		await process_frame
		expect(game.world.map_data.id=="galar_player_home","resume prologue at home")
		game._persist()
		await title()
		game.title_screen.continue_button.pressed.emit()
		await process_frame
		expect(game._flags().g_version==version and not game._offer_chapter("galar"),"cold resume")
	for species in [810,813,816,829,830]:
		expect(not Moves.learnset(species).is_empty(),"Galar level moves "+str(species))
		expect(not Moves.moves_for(species,20).is_empty(),"resolved project move IDs")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("GALAR SHARED SAVE AND WARP GATES ", "FAIL" if failed else "PASS", " checks=",checks)
	quit(1 if failed else 0)
