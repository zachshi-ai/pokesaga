extends "test_hoenn_items.gd"
## Exercise the shared field, menu and battle callbacks in one new save.

func count_of(key: String) -> int:
	return int(game.save_data.get("h_fan_club",{}).get("stats",{}).get(key,0))

func start_command(command: String) -> void:
	game._toggle_start_menu()
	for button in game.start_menu.find_children("*","Button",true,false):
		if button.text==command:
			button.pressed.emit()
			return
	game._start_selected(command)

func try_fishing() -> void:
	var w=game.world
	for y in w.tile_size.y:
		for x in w.tile_size.x:
			var water:=Vector2i(x,y)
			if not w.is_water(water):continue
			for dir in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
				var from: Vector2i=water-dir
				if not w.can_enter(from,dir) or w.is_water(from):continue
				w.warp_to(from);w.finish_walk()
				w.facing={Vector2i.UP:"up",Vector2i.DOWN:"down",Vector2i.LEFT:"left",Vector2i.RIGHT:"right"}[dir]
				game._use_rod("破旧钓竿")
				return
	check(false,"fishing spot")

func extra_counts():
	var db=root.get_node("Data")
	game._flags().fr_egg_count=3
	game.save_data.egg={"species":133,"steps":1}
	game._tick_egg()
	check(count_of("HATCHED_EGGS")==4 and game._flags().fr_egg_count==4,"hatched egg preserves earlier count")
	dismiss()
	game.save_data.party=[game.PartyScript.make(25,20,[33])]
	var stone: String=db.evo_item_name("THUNDER_STONE")
	game._give_bag_item(stone,"evo")
	game._evolve_with_item(0,stone,null)
	check(game.save_data.party[0].species_id==26 and count_of("EVOLVED_POKEMON")==1,"stone evolution counted after success")
	game._open_shop()
	var shop=game.menu_layer.get_child(-1)
	shop.money=0
	shop._buy(0)
	check(count_of("SHOPPED")==0,"rejected purchase excluded")
	shop.money=10000;game.save_data.money=10000
	shop._buy(0)
	check(count_of("SHOPPED")==1,"paid shop purchase")
	shop.closed.emit()
	shop.queue_free()
	game.save_data.party=[game.PartyScript.make(6,50,[15,249])]
	for item in [["kanto_main","cut","USED_CUT","蓝色徽章"],["rocktunnel_b1f","rock","USED_ROCK_SMASH","金色徽章"]]:
		var field: Dictionary=db.load_map("kanto",item[0])
		game.world.load_map(field);game.world.arrive({"at":field.spawn});game.world.finish_walk()
		var obstacle: Dictionary=field.objects.filter(func(o):return o.get("kind")==item[1])[0]
		game._handle_object(obstacle)
		check(count_of(item[2])==0,"field move badge restriction "+item[1])
		dismiss()
		game.Journey.grant(game.save_data,"kanto",item[3])
		game._handle_object(obstacle)
		check(count_of(item[2])==1,"cleared obstacle "+item[1])
		dismiss()

func run() -> void:
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	dismiss()
	game.save_data.party=[game.PartyScript.make(150,80,[94])]
	game._flags().got_dex=true
	game._persist()
	check(count_of("SAVED_GAME")==0,"autosaves excluded")
	start_command("存档")
	check(count_of("SAVED_GAME")==1 and int(Save.existing().h_fan_club.stats.SAVED_GAME)==1,"manual save atomically recorded")
	var slot: String=Save.slot
	Save.slot="user://absent-story-count-test-dir/missing.json"
	check(not game._manual_save() and count_of("SAVED_GAME")==1,"failed manual save excluded")
	Save.slot=slot
	start_command("图鉴")
	check(count_of("CHECKED_POKEDEX")==1,"START opens the Pokedex")
	dismiss()
	await process_frame
	game._close_start_menu()
	visit("littleroot_birch_lab")
	game._use_rod("破旧钓竿")
	check(count_of("FISHING_ENCOUNTERS")==0,"dry land excludes fishing")
	visit("hoenn_110")
	try_fishing()
	check(is_instance_valid(game.active_battle) and count_of("FISHING_ENCOUNTERS")==1 and count_of("TRAINER_BATTLES")==0,"fish encounter counts once")
	if is_instance_valid(game.active_battle):
		var ui=game.active_battle
		game._give_item("大师球",1,"ball")
		ui._process(2.0)
		ui.menu.get_node("bag").pressed.emit()
		for button in ui.find_children("*","Button",true,false):
			if button.text.contains("大师球"):
				button.pressed.emit()
				break
		for i in 45:
			if game.active_battle!=ui:break
			ui._process(2.0)
		check(count_of("POKEMON_CAPTURES")==1 and game.active_battle==null,"thrown ball and successful capture increment once")
		await process_frame
	dismiss()
	game._add_to_team(133,5)
	check(count_of("POKEMON_CAPTURES")==1,"gift excluded")
	var foe:={"name":"训练家","battle":{"team":[{"species":129,"level":3,"moves":[150]}]}}
	game._start_battle(foe)
	var trainer=game.active_battle
	check(is_instance_valid(trainer) and count_of("TRAINER_BATTLES")==1,"trainer fight entry")
	for i in 100:
		if game.active_battle!=trainer:break
		if trainer.state=="menu":
			trainer.menu.get_node("fight").pressed.emit()
			trainer.move_menu.get_node("Move0").pressed.emit()
		trainer._process(2.0)
	check(game.active_battle==null and count_of("TRAINER_BATTLES")==1 and count_of("POKEMON_CAPTURES")==1,"finish trainer fight exactly once")
	dismiss()
	await process_frame
	var clinic: Dictionary=root.get_node("Data").load_map("kanto","viridiancity_pokemoncenter_1f")
	game.world.load_map(clinic);game.world.arrive({"at":clinic.spawn});game.world.finish_walk()
	var nurse: Dictionary=game.world.npcs.filter(func(n):return n.get("heal",false))[0]
	game._dialog_heal(nurse);game._dialogs.back()._pick(false);dismiss()
	check(count_of("USED_POKECENTER")==0,"declined nurse excluded")
	game.save_data.party[0].hp=1
	game._dialog_heal(nurse);game._dialogs.back()._pick(true);dismiss()
	check(count_of("USED_POKECENTER")==1 and game.save_data.party[0].hp==game.save_data.party[0].max_hp,"accepted nurse heals and records")
	game._heal_party()
	check(count_of("USED_POKECENTER")==1,"other heals excluded")
	await extra_counts()
	game._persist()
	check(int(Save.existing().h_fan_club.stats.get("POKEMON_CAPTURES",0))==1,"counts survive reload")
	Save.clear_test_slot()
	print("EMERALD STORY COUNTS ","FAIL" if failed else "PASS"," checks=",checks)
	quit(int(failed))
