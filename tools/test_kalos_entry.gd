extends "res://tools/test_region_journey.gd"

func verify_arrival(old: Dictionary, mode: String, version: String) -> void:
	expect(Save.save(old.duplicate(true)),"save legacy party")
	await title()
	expect(await preload("regional_start.gd").enter(game,"kalos",mode,version),"choose Kalos party and version")
	var slot: Dictionary=Save.existing()
	expect(slot.chapters.kalos==mode and slot.flags.k_version==version and slot.flags.k_started,"store the chosen chapter")
	expect(slot.map=="kalos_home_2f" and game.world.player_pos==Vector2i(14,11),"wake up in the Vaniville bedroom")
	expect(slot.money==old.money and slot.hall_of_fame==old.hall_of_fame and slot.dex==old.dex,"keep previous adventures")
	if mode=="carried":expect(slot.party==old.party and slot.boxes==old.boxes,"carry twelve intact individual records")
	else:expect(slot.party.is_empty() and slot.boxes[0].mons.slice(1)==old.party,"deposit the same twelve Pokémon")
	game._close_all_dialogs()
	for mid in ["kalos_gym_cyllage","kalos_champion_room"]:
		game._do_warp({"region":"kalos","map":mid,"at":[2,3]})
		expect(game.world.map_data.id=="kalos_home_2f","early warp denied: "+mid)
		game._close_all_dialogs()
	expect(not game._party_can_move("SURF") and not game._party_can_move("FLY"),"Hoenn and Unova moves cannot skip access")
	game._do_warp(root.get_node("Data").travel_regions().ultra.hub)
	expect(game.world.map_data.region=="ultra","can depart before dressing")
	expect(preload("regional_start.gd").open_trip(game,"kalos"),"device can return to the unfinished opening")
	await process_frame
	expect(game.world.map_data.id=="kalos_home_2f" and not game._flags().get("k_dressed",false),"return before dressing preserves the mirror task")
	game._persist()
	await title()
	game.title_screen.continue_button.pressed.emit()
	await process_frame
	expect(game.world.map_data.id=="kalos_home_2f" and not game._offer_chapter("kalos"),"resume without repeating the initial choice")

func verify_battle() -> void:
	var b=load("res://core/battle.gd").new(42)
	var mon: Dictionary=b.make_combatant(448,32,[612])
	var other: Dictionary=b.make_combatant(6,36,[53])
	var rival: Dictionary=b.make_combatant(448,32,[612])
	mon.held="LUCARIONITE"
	other.held="CHARIZARDITE_X"
	rival.held="LUCARIONITE"
	b.kalos_rules=true
	b.start([mon,other],[rival])
	expect(b.available_forms("a").is_empty() and not b.transform("a","LUCARIO_MEGA").ok,"cross-region stone cannot replace the Key Stone")
	b.kalos_ring=true
	mon.held="CHARIZARDITE_X"
	expect(b.available_forms("a").is_empty(),"wrong species cannot use stone")
	mon.held="LUCARIONITE"
	expect(b.available_forms("a").size()==1 and not b.can_use_z("a") and not b.can_use_tera("a"),"only X/Y's matching form is offered")
	var pp:=int(mon.pp[0])
	var atk:=int(mon.stats.atk)
	mon.kalos_intent="LUCARIO_MEGA"
	b.run_turn("move:0","move:0")
	expect(mon.form=="LUCARIO_MEGA" and mon.stats.atk>atk and int(mon.ability)==91,"attack and Adaptability change on the field")
	expect(int(mon.pp[0])<pp and rival.form=="LUCARIO_MEGA","both sides can Mega Evolve and attack on one turn")
	b.active_a=1
	expect(b.available_forms("a").is_empty() and not b.transform("a","CHARIZARD_MEGA_X").ok,"a second teammate cannot Mega Evolve")
	var fresh: Dictionary=b.make_combatant(6,36,[53])
	fresh.held="CHARIZARDITE_Y"
	b.start([fresh],[b.make_combatant(10,4,[33])])
	expect(b.available_forms("a").size()==1 and b.available_forms("a")[0].key=="CHARIZARD_MEGA_Y","next battle resets permission and distinguishes X/Y stones")

func verify_forms_and_balls() -> void:
	var forms=load("res://core/kalos_forms.gd")
	var party=load("res://core/party.gd")
	var growth=load("res://core/growth.gd")
	for row in [[678,1,"MEOWSTIC_F"],[666,6,"SPEWPA_MEADOW"],[710,3,"PUMPKABOO_SUPER"],[550,1,"BASCULIN_BLUE_STRIPED"],[676,1,"FURFROU_HEART"]]:
		expect(forms.key(row[0],row[1])==row[2] and not root.get_node("Data").form_of(row[0],row[2]).is_empty(),"original regional form "+row[2])
	var flower: Dictionary=party.make(669,19,[33],forms.key(669,2))
	var next: Dictionary=forms.evolution(game,flower)
	expect(next.to==670 and next.form=="FLOETTE_ORANGE","flower color survives level evolution")
	party.evolve(flower,next.to,next.form)
	next=growth.evolution_for_item(flower,"SHINY_STONE","kalos")
	expect(next.to==671 and next.form=="FLORGES_ORANGE","Shiny Stone preserves orange flower")
	var mon: Dictionary=party.make(676,20,[33],"FURFROU_STAR")
	mon.kalos_trim_until=int(Time.get_unix_time_from_system())+10000
	var boxes: Array=[]
	expect(party.store_in_boxes(boxes,mon) and boxes[0].mons[0].form=="","salon trim grows out in PC")
	mon=party.make(676,20,[33],"FURFROU_STAR")
	mon.kalos_trim_until=10;party.restore_trim(mon)
	expect(mon.form=="","five-day trim expiry")
	var b=load("res://core/battle.gd").new(15)
	var opponent: Dictionary=b.make_combatant(7,10,[33])
	b.kalos_rules=true
	expect(b.catch_bonus("先机球",1,opponent)==5 and b.catch_bonus("捕网球",1,opponent)==3,"Quick Ball on first turn and Net Ball on Water")
	b.completed_turns=10;b.previously_caught=true;b.dark_encounter=true;b.fishing_encounter=true
	expect(b.catch_bonus("先机球",1,opponent)==1 and b.catch_bonus("重复球",1,opponent)==3 and b.catch_bonus("计时球",1,opponent)==4,"later turns and repeat catches")
	expect(b.catch_bonus("黑暗球",1,opponent)==3.5 and b.catch_bonus("潜水球",1,opponent)==3.5,"dark cave and hooked encounters")
	var night: Dictionary=party.make(698,39,[33])
	var day: Dictionary=party.make(696,39,[33])
	expect(forms.evolution(game,night).is_empty()!=forms.evolution(game,day).is_empty(),"day/night fossil evolution windows")

func run() -> void:
	Save.use_test_slot()
	await title()
	var old:=fixture()
	Chapters.migrate(old)
	old.regional_badges.erase("kalos")
	old.party[0].moves=[57,19]
	old.party[0].pp=[10,10]
	old=JSON.parse_string(JSON.stringify(old))
	for index in 2:
		await verify_arrival(old,["carried","boxed"][index],["x","y"][index])
	var field=load("res://core/kalos_field.gd")
	var x: Array=field.habitat({"kalos_zone":259},{"k_version":"x"},"grass")
	var y: Array=field.habitat({"kalos_zone":259},{"k_version":"y"},"grass")
	expect(x.any(func(row):return row.species==13) and not x.any(func(row):return row.species==10),"X Route 2 has Weedle")
	expect(y.any(func(row):return row.species==10) and not y.any(func(row):return row.species==13),"Y Route 2 has Caterpie")
	verify_forms_and_balls()
	verify_battle()
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("KALOS SHARED SAVE AND MEGA ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(1 if failed else 0)
