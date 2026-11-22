extends "res://tools/test_sinnoh_side.gd"
var Daily
var Enc
var Field

func run():
	Field=load("res://core/sinnoh_field.gd")
	Enc=load("res://core/encounter.gd")
	Daily=load("res://core/sinnoh_dailies.gd")
	Side=load("res://core/sinnoh_side.gd")
	Party=load("res://core/party.gd")
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"sinnoh")
	world=game.world
	game._close_all_dialogs()
	lottery_checks()
	garden_checks()
	Save.clear_test_slot()
	game.queue_free()
	await process_frame
	print("PLATINUM DAILY LOTTERY / TROPHY GARDEN ","PASS" if failed.is_empty() else "FAIL"," checks=",checks," ",failed)
	quit(0 if failed.is_empty() else 1)

func lottery_checks():
	switch("JUBILIFE_TV_1F")
	var actor:="JubilifeTV1F_AceTrainerSnowF"
	game.save_data.js_trainer_id=22220
	var mon: Dictionary=Party.make(25,15,[33])
	game.save_data.party=Party.compact([mon])
	var egg: Dictionary=mon.duplicate(true)
	egg.is_egg=true
	egg.ot_id=11111
	game.save_data.boxes=[{"name":"盒","mons":[egg,{}]}]
	interact(actor)
	var state: Dictionary=game.save_data.s_tv_lottery
	click("下次再来")
	check(state.has("number") and not state.has("paid"),"declining preserves the daily number and redraw eligibility")
	state.number=11111
	interact(actor)
	click("核对号码")
	game._close_all_dialogs()
	check(not state.get("paid",false) and state.number==11111,"no match leaves same ticket available; eggs excluded")
	for n in range(1,6):
		var id: int=[0,12341,12311,12111,21111,11111][n]
		state.erase("paid")
		state.number=11111
		var boxed: Dictionary=Party.make(133,20,[33])
		boxed.ot_id=65536+id
		game.save_data.boxes[0].mons[1]=boxed
		var item: String=Side.item_name(Daily.PRIZES[n])
		var before:=int(game._bag_count(item))
		interact(actor)
		click("核对号码")
		game._close_all_dialogs()
		check(state.get("paid",false) and int(game._bag_count(item))==before+1,"low 16-bit boxed OT prize bracket "+str(n))
		interact(actor)
		game._close_all_dialogs()
		check(int(game._bag_count(item))==before+1,"cannot claim daily award twice "+str(n))
	var old: Dictionary=Party.make(83,20,[33])
	old.original_trainer="ELYSSA"
	old.nickname="CH'DING"
	var legacy: Dictionary=Daily.best_match({"party":[old,mon],"boxes":[]},8810,22220)
	check(legacy.digits==5 and legacy.mon=="CH'DING","recognizes saved FireRed OT and leading zero in historic four-digit ID")
	var tied: Dictionary=Daily.best_match({"party":[mon],"boxes":[{"mons":[mon.duplicate(true)]}]},22220,22220)
	check(tied.digits==5 and tied.place=="队伍","old untagged player-owned individual resolves shared trainer ID; party wins ties")
	check(int(Save.load_game().s_tv_lottery.number)==11111 and Save.load_game().s_tv_lottery.paid,"lottery persists after reload")
	var prize: String=Side.item_name("PP_UP")
	game._use_bag_item(prize)
	click(mon.name)
	click("撞击")
	game._close_all_dialogs()
	check(game._bag_count(prize)==0 and int(mon.pp_bonus.get("33",0))>0,"won PP Up raises an actual move limit")
	state.date="2000-01-01"
	interact(actor)
	click("下次")
	check(state.date==Time.get_date_string_from_system() and not state.get("paid",false),"device date change resets draw and claim")

func garden_checks():
	switch("POKEMON_MANSION_OFFICE")
	var who:="PokemonMansionOffice_MrBacklot"
	interact(who)
	game._close_all_dialogs()
	check(game.save_data.get("s_trophy_garden",{}).is_empty(),"no new garden Pokemon without national dex")
	game._flags().s_national_dex=true
	interact(who)
	click("是")
	click("下次再说")
	check(game.save_data.s_trophy_garden.is_empty(),"declining second question adds no garden visitor")
	interact(who)
	click("是")
	click("想听")
	game._close_all_dialogs()
	var visit: Dictionary=game.save_data.s_trophy_garden
	var first:=int(visit.current)
	check(Side.data().garden_species.size()==16 and Side.data().garden_species.has(float(first)) and int(visit.previous)==0,"first announced species comes from the exact sixteen candidates")
	check(find_row("PokemonMansionOffice_OldMan").is_empty(),"butler leaves office after owner's boast")
	switch("TROPHY_GARDEN")
	switch("POKEMON_MANSION_OFFICE")
	check(not find_row("PokemonMansionOffice_OldMan").is_empty(),"returning later restores the original butler")
	interact(who)
	game._close_all_dialogs()
	check(int(visit.current)==first and visit.previous==0,"repeat visit cannot reroll today's addition")
	for n in 2:
		var old:=int(visit.current)
		var older:=int(visit.previous)
		visit.date="2000-01-01"
		interact(who)
		click("是")
		click("想听")
		game._close_all_dialogs()
		check(int(visit.previous)==old and int(visit.current) not in [old,older],"next announcement shifts exactly once, excluding both old species "+str(n))
		switch("TROPHY_GARDEN")
		if n==0:switch("POKEMON_MANSION_OFFICE")
	var area: Dictionary=Field.field(world.map_data.id)
	var base: Array=Field.land(area,12)
	var pool: Array=Daily.garden_pool(game.save_data,base)
	var changed: Array=[]
	for i in base.size():
		if int(base[i].species)!=int(pool[i].species):changed.append(i)
	check(changed==[6,7] and pool[6].weight==5 and pool[7].weight==5 and int(pool[6].min)==22 and int(pool[7].min)==22,"only native five-percent slots 6/7 change, preserving original levels and table")
	check(int(Save.load_game().s_trophy_garden.current)==int(visit.current),"both garden slots survive disk roundtrip")
	var tile_found:=false
	for y in int(world.map_data.size[1]):
		for x in int(world.map_data.size[0]):
			var at:=Vector2i(x,y)
			if world.tile_at(at)==11 and not world.is_blocked(at):
				world.warp_to(at)
				tile_found=true
				break
		if tile_found:break
	var candidate:=RandomNumberGenerator.new()
	for n in 10000:
		candidate.seed=n
		if Enc.should_encounter(candidate,float(area.land_rate),1):
			var wild: Dictionary=Enc.roll(pool,candidate)
			if int(wild.species)==int(visit.current):
				game.rng.seed=n
				game.grass_streak=0
				game._try_encounter()
				break
	var active=game.active_battle
	check(is_instance_valid(active) and int(active.battle.cur_b().species_id)==int(visit.current) and int(active.battle.cur_b().level)==22,"advertised rare Pokemon enters the actual wild battle from native garden grass")
