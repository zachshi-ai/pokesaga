extends "res://tools/test_sinnoh_side.gd"

func run():
	Side=load("res://core/sinnoh_side.gd")
	Party=load("res://core/party.gd")
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"sinnoh")
	world=game.world
	game._close_all_dialogs()
	game.rng.seed=45801
	arcade()
	prize_effects()
	await park()
	villa_stats()
	Save.clear_test_slot()
	game.queue_free()
	await process_frame
	print("PLATINUM GAME CORNER / PAL PARK ", "PASS" if failed.is_empty() else "FAIL"," checks=",checks," ",failed)
	quit(0 if failed.is_empty() else 1)

func arcade() -> void:
	switch("VEILSTONE_CITY_SOUTHEAST_HOUSE")
	for attempt in 20:
		if game._bag_count("代币盒")>0:break
		interact("VeilstoneCitySoutheastHouse_Clown")
		click("左手")
		game._close_all_dialogs()
	check(game._flags().get("s_coin_case",false) and game._bag_count("代币盒")==1,"clown hand game supplies a single coin case")
	switch("GAME_CORNER")
	for key in ["GameCorner_OldMan20Coins","GameCorner_Farmer","GameCorner_Farmer"]:
		interact(key)
		game._close_all_dialogs()
	check(game.save_data.get("s_coins",0)==70,"farmer and old man have distinct once-only currency gifts")
	game.save_data.money=2000
	interact("GameCorner_CoinsClerk")
	click("50 枚")
	game._close_all_dialogs()
	check(game.save_data.get("s_coins",0)==120 and game.save_data.money==1000,"counter sells 50 coins for exactly 1000")
	var machines: Array=world.objects.filter(func(o):return str(o.get("source_script","")).begins_with("GameCorner_SlotMachine_"))
	check(machines.size()==12,"twelve individual native machine tiles")
	interact("GameCorner_SlotMachine_0")
	var ui=game.menu_layer.get_child(-1)
	if not check_machine(ui):return
	var cost:=int(game.save_data.s_coins)
	# Stop as the visible red seven crosses the payline. Advance animation in fixed ticks.
	click("开始")
	for lane in 3:
		for t in 20:
			if ui.STRIPS[lane][ui.tops[lane]]==0:break
			ui._process(0.0951)
		ui.lane_buttons[lane].pressed.emit()
	check(ui.in_bonus and game.save_data.s_coins==cost-3,"touch reel stops line up a real jackpot and unlock Clefairy")
	for spin in 150:
		ui.action.pressed.emit()
		for lane in ui.order:ui.lane_buttons[lane].pressed.emit()
	check(int(game.save_data.get("s_slots_record",0))==10 and int(game.save_data.s_coins)==cost-3+14*150,"150 guided one-coin rounds pay correctly and complete ten full bonuses")
	ui.handle_back()
	interact("GameCorner_CoinsClerk")
	game._close_all_dialogs()
	check(game._flags().get("s_slots_tm64",false) and game._bag_count("神奥招式学习器 64")==1,"ten-round record redeems TM64 at original counter")
	switch("VEILSTONE_CITY_PRIZE_EXCHANGE")
	var coins:=int(game.save_data.s_coins)
	interact("VeilstoneCityPrizeExchange_Receptionist")
	check(Side.data().game_prizes.size()==19,"original prize list with all 19 keys")
	click("广角镜")
	click("兑换")
	game._close_all_dialogs()
	check(int(game.save_data.s_coins)==coins-1000 and game._bag_count("广角镜")==1,"exchange pays 1000 for an equippable Wide Lens")

func check_machine(ui) -> bool:
	var ok: bool=ui.get_script()!=null and ui.get_script().resource_path=="res://scenes/sinnoh_slots.gd"
	check(ok,"touching original slot BG opens real three-reel screen")
	return ok

func park() -> void:
	var ids:=[1,4,7,25,54,129]
	var names: Array=[]
	var mons: Array=[]
	for id in ids:
		var mon: Dictionary=Party.make(id,23,[33])
		mon.name="伙伴%d"%id
		mon.friendship=218
		names.append(mon.name)
		mons.append(mon)
	game.save_data.boxes=[{"name":"旅行","mons":mons}]
	game._flags().s_national_dex=true
	switch("PAL_PARK_LOBBY")
	interact("PalParkLobby_Worker")
	click("从电脑选择")
	for m in names:click(str(m)+"　")
	click("开始捕捉秀")
	check(Side.source(game)=="PAL_PARK" and game.save_data.get("s_park_show",{}).get("mons",[]).size()==6 and Party.occupied(game.save_data.boxes[0].mons)==0,"all six removed from PC together and carried by the park")
	if not game.save_data.has("s_park_show"):return
	var read: Dictionary=Save.load_game()
	check(read.s_park_show.mons.size()==6 and Party.occupied(read.boxes[0].mons)==0,"save restart cannot duplicate escrowed Pokemon")
	var reserve:=load("res://core/sinnoh_pal_park.gd")
	for i in 6:
		await process_frame
		var next:=0
		while next<6 and game.save_data.s_park_show.order.has(next):next+=1
		var desired:=int(Side.data().pal_park[str(ids[next])][0])
		var found:=false
		for y in 64:
			for x in 64:
				var pos:=Vector2i(x,y)
				var zone:=int(x>=32)+int(y>=32)*2
				if (desired==5+zone and world.is_water(pos)) or (desired==1+zone and world.tile_at(pos)==11):
					world.warp_to(pos)
					found=true
					break
			if found:break
		for step in 2000:
			reserve.step(game,Side)
			if game.menu_layer.get_child_count()>0 and game.menu_layer.get_child(-1).name=="PalParkEncounter" and not game.menu_layer.get_child(-1).is_queued_for_deletion():break
		var ui=game.menu_layer.get_child(-1)
		if ui.name!="PalParkEncounter" or ui.is_queued_for_deletion():
			check(false,"encounter in canonical park habitat %d"%desired)
			return
		click("投公园球")
	check(Side.source(game)=="PAL_PARK_LOBBY" and game.save_data.s_park_show.order.size()==6,"catch all six in correct native habitats before evaluation")
	click("将六只送回电脑")
	game._close_all_dialogs()
	check(not game.save_data.has("s_park_show") and Party.occupied(game.save_data.boxes[0].mons)==6 and int(game.save_data.s_park_record)>2000,"complete scoring and restore six once")
	for i in 6:
		var mon: Dictionary=game.save_data.boxes[0].mons[i]
		check(mon.name==names[i] and int(mon.friendship)==218 and int(mon.species_id)==ids[i],"same individual restored to original slot "+str(i))
	interact("PalParkLobby_Worker")
	click("从电脑选择")
	for m in names:click(str(m)+"　")
	click("开始捕捉秀")
	interact("PalPark_Worker")
	click("返回大厅")
	interact("PalParkLobby_Worker")
	click("取回六只")
	game._close_all_dialogs()
	check(not game.save_data.has("s_park_show") and Party.occupied(game.save_data.boxes[0].mons)==6,"early withdrawal also restores individuals without extra rewards")

func villa_stats() -> void:
	switch("ETERNA_FOREST_OUTSIDE")
	var soil: Dictionary={}
	for row in world.npcs:
		if str(row.get("local_id","")).begins_with("LOCALID_BERRY_SOIL"):
			soil=row
			break
	check(not soil.is_empty(),"source berry plot for villa record")
	if not soil.is_empty():
		var before:=int(game.save_data.get("s_berries_planted",0))
		Side.berry_plot(game,soil,false)
		click("采摘")
		game._close_all_dialogs()
		Side.berry_plot(game,soil,false)
		var planted: String=Side.item_name(Side.data().plots["ETERNA_FOREST_OUTSIDE/"+str(soil.local_id)][0])
		click(planted)
		game._close_all_dialogs()
		check(int(game.save_data.get("s_berries_planted",0))==before+1,"planting one berry advances villa threshold once")

func prize_effects() -> void:
	var battle=load("res://core/battle.gd").new()
	var attacker: Dictionary=Party.make(54,75,[56,33])
	var defender: Dictionary=Party.make(143,95,[33])
	attacker.ability=0
	defender.ability=0
	battle.start([attacker],[defender])
	var hits: Array=[]
	for item in ["","WIDE_LENS","ZOOM_LENS","ZOOM_LENS"]:
		var successes:=0
		attacker.held=item
		defender.acted_this_turn=hits.size()==3
		for seed_no in 180:
			defender.hp=defender.max_hp
			attacker.pp[0]=10
			battle.rng.seed=seed_no+100
			battle._take_action("a","move:0")
			if int(defender.hp)<int(defender.max_hp):successes+=1
		hits.append(successes)
	check(hits[1]>hits[0] and hits[2]==hits[0] and hits[3]>hits[1],"wide lens and zoom lens change actual move hit rates only in the proper order")
	attacker.held="METRONOME"
	var loss: Array=[]
	for hit in 3:
		attacker.pp[1]=10
		defender.hp=defender.max_hp
		battle.rng.seed=209
		battle._take_action("a","move:1")
		loss.append(int(defender.max_hp)-int(defender.hp))
	check(loss[2]>loss[0] and int(attacker.get("metronome_chain",0))==3,"Metronome increases actual successive damage %s / %s"%[loss,attacker.get("metronome_chain",0)])
	battle._take_action("a","move:0")
	check(int(attacker.get("metronome_chain",0))<=1,"changing moves resets repeated-hit bonus")
