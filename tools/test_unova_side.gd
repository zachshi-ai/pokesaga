extends "res://tools/test_emerald_frontier.gd"
## Isolated new save. Later-story fixtures exercise optional interactions without modifying a campaign replay.
var side
var q
var party
var field
var db
var fac

func clear() -> void:
	g._close_all_dialogs()
	for layer in g.menu_layer.get_children():
		if layer.has_method("choose") or layer is Control:
			if layer.is_queued_for_deletion():continue
			if layer.get_class()=="PanelContainer":layer.hide();layer.queue_free()

func map_for(row: Dictionary) -> Dictionary:
	var period: String=row.era
	g._flags().u2_started=period=="b2"
	g._flags().erase("u1_memory")
	db.set_unova_era(period)
	var m: Dictionary=db.load_map("unova",row.map)
	g.world.load_map(m)
	g.world.refresh_story_actors(g._flags())
	return m

func actor(key: String) -> Dictionary:
	var row=side.book().filter(func(r):return r.id==key)[0]
	for flag in row.requires:
		if not g._flags().get(flag,false):g._flags()[flag]=true
	map_for(row)
	for n in g.world.npcs:
		if n.get("unova_side","")==key:return n
	check(false,"missing actor on field "+key)
	return {}

func speak(key: String) -> void:
	clear()
	var n:=actor(key)
	if n.is_empty():return
	var at:=Vector2i(int(n.at[0]),int(n.at[1]))
	for v in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP]:
		var p: Vector2i=at+v
		if g.world.is_blocked(p):continue
		g.world.warp_to(p)
		g.world.finish_walk()
		g.world.facing={Vector2i.DOWN:"up",Vector2i.UP:"down",Vector2i.RIGHT:"left",Vector2i.LEFT:"right"}[v]
		g._on_action()
		return
	check(false,"no adjacent tile "+key)

func run() -> void:
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"unova")
	g._close_all_dialogs()
	db=root.get_node("Data")
	side=load("res://core/unova_side.gd")
	q=load("res://core/unova_side_quests.gd")
	party=load("res://core/party.gd")
	field=load("res://core/unova_field.gd")
	fac=load("res://core/unova_side_facilities.gd")
	g.save_data.party=[party.make(445,90,[89,242]),party.make(9,90,[57,58]),party.make(25,90,[85,98])]
	var total:=0
	for era in ["bw","b2"]:
		for rows in side.data().pickups[era].values():total+=rows.size()
	check(total==1068,"both native versions' visible and hidden pickups")
	for row in side.book():
		var flags: Dictionary={}
		for need in row.requires:flags[need]=true
		var m: Dictionary=db.load_unova_map(row.map,row.era)
		if m.is_empty():check(false,"unloaded zone "+row.id);continue
		var resolved: Array=side.decorate(m,flags,[])
		check(resolved.any(func(n):return n.get("unova_side","")==row.id),"appears "+row.id)
		if not row.requires.is_empty():check(not side.active(row,{}),"story gate "+row.id)
	speak("bw_look")
	check(g._flags().get("u1_super_rod",false) and g._bag_count("厉害钓竿")==1,"Looker initiates hunt and gives rod")
	speak("bw_sage_gorm")
	check(g._flags().get("us_bw_sage_gorm",false) and g._bag_count(field.machine_name(g,75,false))==1,"sage machine collected")
	check(not g.world.npcs.any(func(n):return n.get("unova_side","")=="bw_sage_gorm"),"Looker removes arrested sage from actual map")
	speak("bw_museum_fossil")
	if button(side.item_name("COVER_FOSSIL")):
		check(g._bag_count(side.item_name("COVER_FOSSIL"))==1,"choose Cover Fossil")
		speak("bw_fossil")
		if button(side.item_name("COVER_FOSSIL")):check(g._bag_count(side.item_name("COVER_FOSSIL"))==0 and side.has_mon(g,564),"museum revives Tirtouga")
	speak("bw_liberty_pass")
	check(g._bag_count("自由船票")==1,"offline Liberty Pass available")
	speak("b2_rood")
	check(side.has_mon(g,570),"Rood's Zorua")
	speak("b2_rod")
	check(g._flags().get("u2_super_rod",false) and g._bag_count("厉害钓竿")==1,"two licenses share one rod")
	g.save_data.party.append(party.make(587,30,[98]))
	speak("b2_trade_26")
	if button("电飞鼠") and button("交换"):
		check(not side.has_mon(g,587) and side.has_mon(g,526) and g._flags().get("us_b2_trade_26",false),"route 7 actually exchanges Emolga")
	speak("b2_splicers")
	check(g._bag_count("基因之楔")==1,"Kyurem encounter unlocks splicers")
	g.save_data.party.append(party.make(646,70,[58]))
	var stored: Dictionary=party.make(644,70,[85])
	stored.test_uuid="original Zekrom"
	g.save_data.party.append(stored)
	clear()
	g._use_bag_item("基因之楔")
	if button("合体"):
		check(not side.has_mon(g,644) and g.save_data.party.any(func(m):return m.get("form","")=="KYUREM_BLACK"),"DNA Splicers fuse original duo")
		clear()
		g._use_bag_item("基因之楔")
		if button("分离"):check(g.save_data.party.any(func(m):return m.get("test_uuid","")=="original Zekrom"),"DNA Splicers restore original partner")
	speak("b2_subway")
	if button("单打列车"):
		for i in 3:button("",true)
		if button("开始对战"):
			check(is_instance_valid(g.active_battle),"Subway reception starts battle")
			if is_instance_valid(g.active_battle):
				var original: Array=g.save_data.party.duplicate(true)
				play_battle()
				check(g.save_data.party==original,"rental-size team isolated")
				if g.save_data.has("unova_facility_b2_subway"):button("暂时休息")
	speak("b2_studios")
	if button("哈奇库侠") and button("使用租借队开拍"):
		check(is_instance_valid(g.active_battle),"film rental battle opened")
		if is_instance_valid(g.active_battle):
			var ui=g.active_battle
			ui.fast=true
			for i in 250:
				if not is_instance_valid(g.active_battle):break
				if ui.state=="menu":
					ui._on_move(0 if ui.battle.active_b==0 else 1)
				else:ui._process(2)
			check(g.save_data.get("unova_films",{}).get("0",{}).get("hit",false),"Riolu Kid hits both scripted cues")
	field_actions()
	speak("b2_tutor_red")
	clear()
	var test_mon: Dictionary=party.make(151,50,[1])
	g.save_data.party.append(test_mon)
	side.give(g,"RED_SHARD",2)
	speak("b2_tutor_red")
	if button("渴望") and button("梦幻"):
		check(test_mon.moves.any(func(id):return int(id)==343) and g._bag_count(side.item_name("RED_SHARD"))==0,"tutor checks species, teaches Covet and consumes exactly two red shards")
	speak("bw_wingull_handler")
	speak("bw_gram1")
	speak("bw_wingull_handler")
	check(g._flags().get("us_bw_sent_gram1",false) and g._bag_count(side.item_name("GRAM_1"))==0 and not g._flags().get("us_bw_grams_sent",false),"partial Wingull delivery is consumed and remembered")
	speak("bw_gram2")
	speak("bw_gram3")
	speak("bw_wingull_handler")
	check(g._flags().get("us_bw_grams_sent",false) and g._bag_count(field.machine_name(g,89,false))==1 and not g.world.npcs.any(func(n):return n.get("unova_side","")=="bw_wingull"),"all three Grams returned, Wingull departs, TM89 usable")
	speak("b2_hanky")
	check(g._bag_count(side.item_name("GRUBBY_HANKY"))==1,"café inquiry gives missing hanky")
	speak("b2_hanky_guest")
	check(g._bag_count(side.item_name("GRUBBY_HANKY"))==0,"café patron claims hanky")
	speak("b2_hanky")
	check(g._bag_count(side.item_name("FLUFFY_TAIL"))==1,"return to café employer earns Fluffy Tail")
	daycare_actions()
	var stored_data: Dictionary=Save.load_game()
	check(stored_data.get("flags",{}).get("us_bw_sage_gorm",false) and stored_data.get("flags",{}).get("us_b2_trade_26",false),"both eras reload in same save")
	print("UNOVA SIDE ", "PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
	Save.clear_test_slot()
	quit(0 if failures.is_empty() else 1)

func face_object(o: Dictionary) -> bool:
	var at:=Vector2i(int(o.at[0]),int(o.at[1]))
	for v in [Vector2i.DOWN,Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP]:
		var p: Vector2i=at+v
		if g.world.is_blocked(p):continue
		g.world.warp_to(p)
		g.world.finish_walk()
		g.world.facing={Vector2i.DOWN:"up",Vector2i.UP:"down",Vector2i.RIGHT:"left",Vector2i.LEFT:"right"}[v]
		g._on_action()
		return true
	return false

func field_actions() -> void:
	clear()
	g._flags().u2_badge_4=true
	g._flags().u2_grotto=true
	g._flags().u2_plasma_park=true
	g._flags().u2_champion=true
	map_for({"map":"unova_5","era":"b2"})
	var route: Dictionary=g.world.map_data
	var visible: Array=route.objects.filter(func(o):return o.get("unova_item","")=="SUPER_REPEL")
	var hidden: Array=route.objects.filter(func(o):return o.get("kind","")=="unova_hidden")
	check(visible.size()==1 and hidden.size()==1,"route 5 places both pickup styles")
	if visible.is_empty() or hidden.is_empty():return
	var name: String=side.item_name("SUPER_REPEL")
	var before: int=g._bag_count(name)
	face_object(visible[0])
	check(g._bag_count(name)==before+1,"visible item ball collected through field A")
	clear()
	name=side.item_name("HYPER_POTION")
	before=g._bag_count(name)
	var detector: bool=q.use_item(g,"探宝器")
	check(detector and not g._dialogs.is_empty(),"dowsing points to actual hidden item before collection")
	clear()
	face_object(hidden[0])
	check(g._bag_count(name)==before+1,"hidden item collected at original coordinate")
	clear()
	face_object(hidden[0])
	check(g._bag_count(name)==before+1,"no duplicate pickup after search")
	clear()
	var entrances: Array=route.objects.filter(func(o):return o.has("unova_grotto"))
	check(entrances.size()==1,"native route 5 grotto entrance")
	if entrances.is_empty():return
	face_object(entrances[0])
	check(g.world.map_data.id=="unova_b2_zone_518","walked through actual grotto entrance")
	if g.world.map_data.id!="unova_b2_zone_518":return
	var places: Dictionary=g.save_data.get("unova_grottos",{})
	check(places.has("1") and int(places["1"].mon.species_id)==572 and int(places["1"].mon.ability)==92,"first Minccino has Skill Link")
	var centre: Array=g.world.map_data.objects.filter(func(o):return o.get("kind","")=="unova_grotto_content")
	if not centre.is_empty():
		face_object(centre[0])
		button("靠近")
		if is_instance_valid(g.active_battle):
			check(int(g.active_battle.battle.cur_b().ability)==92 and not g.active_battle.battle.cur_b().get("fr_roaming",false),"grotto event opens a stationary hidden ability battle")
			play_battle()
			check(not places.has("1"),"resolved grotto occupant removed")
	clear()
	var exits: Array=g.world.map_data.objects.filter(func(o):return o.get("kind","")=="unova_grotto_exit")
	if not exits.is_empty():face_object(exits[0])
	check(g.world.map_data.id=="unova_5","grotto returns to its route")

func daycare_actions() -> void:
	var care=load("res://core/unova_side_breeding.gd")
	var mother: Dictionary=party.make(133,8,[33,39])
	mother.sex="female"
	mother.ot_id=5
	mother.held="EVERSTONE"
	mother.nature="大胆"
	mother.tag="mother"
	var father: Dictionary=party.make(133,8,[33,39,204])
	father.ot_id=27
	father.sex="male"
	father.tag="father"
	g.save_data.party=[party.make(445,65,[89]),mother,father]
	g.save_data.money=3000
	for i in 2:
		speak("b2_daycare")
		if button("寄放伙伴"):button("伊布")
	var s: Dictionary=care.state(g)
	check(s.parents.size()==2 and not side.has_mon(g,133),"both original partners safely boarded")
	if s.parents.size()!=2:return
	g.rng.seed=674
	for i in 4096:
		if s.has("egg"):break
		care.step(g)
	check(s.has("egg") and int(s.egg.mon.species_id)==133 and s.egg.mon.nature=="大胆","compatible pair actually produced a Gen V egg with Everstone nature")
	if not s.has("egg"):return
	speak("b2_daycare")
	if button("领取宝可梦蛋"):
		check(g._bag_count("合众的蛋")==1 and g.save_data.unova_nursery_eggs.size()==1,"collect actual daycare egg")
		while not g.save_data.unova_nursery_eggs.is_empty():care.step(g)
		check(g._bag_count("合众的蛋")==0 and side.has_mon(g,133),"walked the full hatch cycle")
	for i in 2:
		speak("b2_daycare")
		if button("领回伊布"):button("领回")
	check(g.save_data.party.any(func(m):return m.get("tag","")=="mother") and g.save_data.party.any(func(m):return m.get("tag","")=="father") and s.parents.is_empty(),"paid to retrieve both exact parents")
	clear()
	var official: Array=q.special().regional
	g.save_data.dex.caught=official.duplicate()
	speak("b2_charms")
	check(g._flags().get("us_b2_oval",false) and g._bag_count(side.item_name("OVAL_CHARM"))==1,"regional dex completion awards working Oval Charm")
	g.save_data.dex.caught=range(1,650)
	speak("b2_charms")
	check(g._flags().get("us_b2_shiny",false) and g._bag_count(side.item_name("SHINY_CHARM"))==1,"National dex completion awards shiny rolls")
