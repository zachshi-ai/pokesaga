extends SceneTree

const Save := preload("res://core/save_game.gd")
var game
var failed := false

func _initialize():
	call_deferred("run")

func expect(ok: bool, message: String):
	if not ok:
		failed = true
		push_error("KANTO SERVICES " + message)

func check_fishing():
	var rods := [["破旧钓竿","vermilion_city_house1",4,5],["好钓竿","fuchsia_city_house2",6,5],["厉害钓竿","route12_fishing_house",4,4]]
	for gift in rods:
		game._do_warp({"region":"kanto","map":gift[1],"at":[gift[2], gift[3]+1]})
		game.world.facing = "up"
		game._on_action()
		var menu = game.menu_layer.get_child(-1)
		var accepted := false
		for b in menu.find_children("*","Button",true,false):
			if b.text == "好":
				b.pressed.emit()
				accepted = true
				break
		expect(accepted and game._bag_count(gift[0]) == 1, "fish rod from " + str(gift[1]))
		game._close_all_dialogs()
		game._on_action()
		game._close_all_dialogs()
		expect(game._bag_count(gift[0]) == 1, "fish rod repeat")
		game._do_warp({"region":"kanto","map":"kanto_main","at":[67,276]})
		game.world.facing = "down"
		game._use_bag_item(gift[0])
		expect(is_instance_valid(game.active_battle), "rod encounters a Pokémon in Pallet")
		if game.active_battle != null:
			var enemy: Dictionary = game.active_battle.battle.cur_b()
			var index: int = game.RODS.find(gift[0])
			var pool: Array = game.world.area_at(Vector2i(67,277)).fishing[index]
			expect(pool.any(func(r): return r.species == enemy.species_id and r.min <= enemy.level and enemy.level <= r.max), "species and level from selected rod")
			game.active_battle.finished.emit("fled")
			game._close_all_dialogs()

func run():
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	game._add_to_team(117,38)
	game._do_warp({"region":"kanto","map":"vermilioncity_pokemoncenter_1f","at":[6,5]})
	game.world.facing = "up"
	game._on_action()
	game._close_all_dialogs()
	game._on_action()
	game._close_all_dialogs()
	expect(game._bag_count("对战搜寻器")==1,"Vermilion trainer gives one reusable VS Seeker")
	var mon: Dictionary = game.save_data.party[0]
	mon.hp = 0
	game._give_item("活力碎片",1,"heal")
	game._apply_heal("活力碎片",0,game.HEAL_TABLE["活力碎片"])
	expect(int(mon.hp)==int(mon.max_hp/2) and game._bag_count("活力碎片")==0,"Revive restores half HP")
	game._give_item("全复药",1,"heal")
	mon.status = "psn"
	game._apply_heal("全复药",0,game.HEAL_TABLE["全复药"])
	expect(mon.hp == mon.max_hp and not mon.has("status") and game._bag_count("全复药")==0,"Full Restore heals HP and status")
	game._do_warp({"region":"kanto","map":"kanto_main","at":[330,218]})
	game._close_all_dialogs()
	var trainer: Dictionary = game.world._npc_at(Vector2i(331,218))
	expect(trainer.has("battle"),"missing Route 11 trainer")
	game._mark_defeated(trainer.name)
	game._apply_defeated()
	game._use_bag_item("对战搜寻器")
	game._close_all_dialogs()
	expect(not trainer.defeated and game.save_data.vs_charge==0,"eligible opponent accepts")
	game._mark_defeated(trainer.name)
	game._apply_defeated()
	game._use_bag_item("对战搜寻器")
	game._close_all_dialogs()
	expect(trainer.defeated and Save.load_game().vs_charge==0,"charge survives saving and blocks reuse")
	game._do_warp({"region":"kanto","map":"vermilioncity_pokemoncenter_1f","at":[7,6]})
	game._close_all_dialogs()
	var start: Vector2i = game.world.player_pos
	var horizontal := "left" if game.world.can_step(Vector2i.LEFT) else "right"
	var reverse := "right" if horizontal=="left" else "left"
	for i in 50:
		for direction in [horizontal,reverse]:
			game._move(direction)
			game.world.tick_walk(1)
			game._close_all_dialogs()
	expect(game.world.player_pos==start and game.save_data.vs_charge==100,"100 field steps recharge the device")
	game._do_warp({"region":"kanto","map":"kanto_main","at":[330,218]})
	mon.hp = 0
	game._blackout()
	game._close_all_dialogs()
	expect(game.world.map_data.id=="vermilioncity_pokemoncenter_1f" and mon.hp==mon.max_hp,"blackout restores the party at the last center")
	check_fishing()
	Save.clear_test_slot()
	print("KANTO SERVICES ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
