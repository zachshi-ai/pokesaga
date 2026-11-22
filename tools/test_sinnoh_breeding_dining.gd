extends SceneTree

const Save:=preload("res://core/save_game.gd")
var g
var care
var diner
var side
var party
var failures: Array=[]
var count:=0
var time:={"year":2026,"month":11,"day":23,"hour":9}
var walked:=0

func _initialize() -> void:run.call_deferred()

func check(test: bool,description: String) -> bool:
	count+=1
	if not test:
		failures.append(description)
		push_error(description)
	return test

func open_map(mid: String,at: Vector2i) -> void:
	var map: Dictionary=root.get_node("Data").load_map("sinnoh",mid)
	g.world.load_map(map)
	g.world.refresh_story_actors(g._flags())
	g.world.warp_to(at)
	g.world.tick_walk(1)

func npc(script: String) -> Dictionary:
	for actor in g.world.npcs:
		if actor.get("source_script","")==script:return actor
	return {}

func speak(actor: Dictionary,counter:=false) -> void:
	if not check(not actor.is_empty(),"actor on actual map "+str(actor.get("source_script",""))):return
	var at:=Vector2i(int(actor.at[0]),int(actor.at[1]))
	for v in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
		var pos: Vector2i=at+v*(2 if counter else 1)
		if g.world.is_blocked(pos) or not g.world._npc_at(pos).is_empty():continue
		g.world.warp_to(pos)
		g.world.tick_walk(1)
		g.world.facing={Vector2i.DOWN:"up",Vector2i.UP:"down",Vector2i.LEFT:"right",Vector2i.RIGHT:"left"}[v]
		g._on_action()
		return
	check(false,"no accessible approach to "+str(actor))

func clear() -> void:
	for i in 32:
		if g._dialogs.is_empty():return
		g._on_action()

func click(prefix: String) -> bool:
	for node in g.menu_layer.get_children():
		if node.is_queued_for_deletion() or not node.visible:continue
		for button in node.find_children("*","Button",true,false):
			if button.is_visible_in_tree() and str(button.text).begins_with(prefix):
				button.pressed.emit()
				return true
	return check(false,"missing enabled button "+prefix)

func steps(n: int) -> void:
	g.world.warp_to(Vector2i(8,8))
	for i in n:
		g.world.tick_walk(1)
		var start: Vector2i=g.world.player_pos
		g._move("right" if i%2==0 else "left")
		g.world.tick_walk(1)
		if not check(start!=g.world.player_pos,"walking trainer took step "+str(i)):return
		walked+=1
		clear()

func run() -> void:
	Save.use_test_slot()
	party=load("res://core/party.gd")
	care=load("res://core/sinnoh_day_care.gd")
	diner=load("res://core/sinnoh_restaurant.gd")
	side=load("res://core/sinnoh_side.gd")
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"sinnoh")
	g._close_all_dialogs()
	var a: Dictionary=party.make(129,7,[150])
	var b: Dictionary=party.make(130,7,[44])
	a.merge({"name":"溪溪","sex":"female","ot_id":12,"test_mark":"original A","held":"EVERSTONE"},true)
	b.merge({"name":"海海","sex":"male","ot_id":13,"test_mark":"original B"},true)
	g.save_data.party=party.compact([party.make(466,95,[85]),party.make(445,94,[337]),a,b])
	g.save_data.money=50000
	g._flags().s_dex_recovered=true
	g.save_data.js_trainer_id=12
	check(care.compatibility(a,b,12)==50,"different compatible species and trainers")
	var other: Dictionary=a.duplicate(true)
	other.sex="male"
	check(care.compatibility(a,other,12)==50,"same species and trainer")
	other.ot_id=13
	check(care.compatibility(a,other,12)==70,"same species, foreign trainer")
	other.sex="female"
	check(care.compatibility(a,other,12)==0,"same gender")
	other.species_id=132
	check(care.compatibility(a,other,12)==50 and care.compatibility(other,other,12)==0,"Ditto rules")
	other.species_id=490
	check(care.compatibility(b,other,12)==0,"genderless requires Ditto")
	var ditto: Dictionary=party.make(132,10,[144])
	var manaphy: Dictionary=party.make(490,10,[145])
	check(care.compatibility(manaphy,ditto,12)==20 and int(care.egg_mon(g,side,manaphy,ditto).species_id)==489,"Manaphy with Ditto produces Phione")
	var pika: Dictionary=party.make(25,10,[85,98])
	pika.held="LIGHT_BALL"
	pika.sex="male"
	check(care.egg_mon(g,side,pika,ditto).moves.has(344),"Light Ball transmits Volt Tackle")
	var marill: Dictionary=party.make(183,10,[145])
	check(int(care.egg_mon(g,side,marill,ditto).species_id)==183,"Marill without incense")
	marill.held="SEA_INCENSE"
	check(int(care.egg_mon(g,side,marill,ditto).species_id)==298,"Sea Incense produces Azurill")
	var ineligible: Dictionary=party.make(493,70,[449])
	check(care.compatibility(ineligible,ditto,12)==0,"unbreedable deity with Ditto")
	open_map("sinnoh_pokemon_day_care",Vector2i(9,6))
	for name in ["溪溪","海海"]:
		speak(npc("DayCareCommon_Lady"),true)
		click("寄放伙伴")
		click(name)
		clear()
	if not check(g.save_data.get("s_day_care",[]).size()==2,"both originals deposited across counter"):finish();return
	speak(npc("PokemonDayCare_GymGuide"));clear()
	check("培育屋查看器" in g.save_data.get("s_apps",[]),"checking app really installed after deposit")
	g.rng.seed=8472
	steps(254)
	check(not g.save_data.has("s_daycare_egg"),"no early egg before slot two's 255th step")
	var before:=walked
	for attempt in 20:
		if g.save_data.has("s_daycare_egg"):break
		steps(1 if attempt==0 else 256)
	if not check(g.save_data.has("s_daycare_egg"),"egg generated on regular walking"):finish();return
	print("DAYCARE FIRST EGG STEP ",walked," SECOND PARENT ",g.save_data.s_day_care[1].steps)
	var generated_at:=walked
	check((generated_at-before-1)%256==0 and int(g.save_data.s_daycare_egg.species_id)==129,"correct roll interval and family")
	g._persist();g._restore_from_save()
	check(g.save_data.s_day_care[0].mon.test_mark=="original A" and g.save_data.s_daycare_egg.species_id==129,"reload retains both parents and pending egg")
	open_map("sinnoh_solaceon",Vector2i(11,9))
	var grandpa:=npc("DayCareCommon_Man")
	check(grandpa.facing=="right","egg-ready grandpa turns toward traveler")
	var actual_party: Array=g.save_data.party
	var full_party: Array=[]
	for i in party.MAX_SIZE:full_party.append(party.make(129,5,[150]))
	g.save_data.party=full_party
	speak(grandpa);click("领取蛋");clear()
	check(g.save_data.has("s_daycare_egg") and g.save_data.get("sinnoh_eggs",[]).is_empty(),"full party leaves unclaimed egg safely with grandfather")
	g.save_data.party=actual_party
	speak(grandpa);click("领取蛋");clear()
	if not check(g.save_data.get("sinnoh_eggs",[]).size()==1 and not g.save_data.has("s_daycare_egg"),"receive once from exterior NPC"):finish();return
	open_map("sinnoh_pokemon_day_care",Vector2i(9,6))
	g.save_data.money=0
	speak(npc("DayCareCommon_Lady"),true);click("接回溪溪");click("支付并接回");clear()
	check(g.save_data.s_day_care.size()==2 and g.save_data.money==0,"unpaid parents remain in daycare")
	g.save_data.money=50000
	for name in ["溪溪","海海"]:
		speak(npc("DayCareCommon_Lady"),true);click("接回"+name);click("支付并接回");clear()
	check(g.save_data.s_day_care.is_empty() and int(g.save_data.money)<50000,"both parents returned after paying")
	var returned: Array=g.save_data.party.filter(func(m):return m.has("test_mark"))
	check(returned.size()==2 and returned[0].name=="溪溪" and returned[0].held=="EVERSTONE" and returned[1].ot_id==13,"original identity and held item returned")
	var exp:int=a.exp
	check(int(returned[0].exp)==exp+generated_at,"held parent gained exactly one EXP per walked tile")
	steps(256);g._persist();g._restore_from_save()
	check(int(g.save_data.sinnoh_eggs[0].cycles)<5,"hatch progress survives reload")
	for j in 15:
		if g.save_data.sinnoh_eggs.is_empty():break
		steps(120)
	check(g.save_data.sinnoh_eggs.is_empty() and g._bag_count("神奥的蛋")==0 and g.save_data.party.any(func(m):return m.get("origin","")=="随意镇培育屋" and int(m.level)==1 and int(m.species_id)==129),"walking hatched actual family member")
	print("DAYCARE WALKED ",walked," steps")
	diner.clock=func():return time
	time.hour=8
	check(not side.gate(g,{"map":"sinnoh_restaurant"}).is_empty(),"08:59 closed")
	time.hour=9
	check(side.gate(g,{"map":"sinnoh_restaurant"}).is_empty(),"09:00 open")
	open_map("sinnoh_restaurant",Vector2i(9,11))
	var guests: Array=g.world.npcs.filter(func(n):return str(n.get("source_flag","")).begins_with("FLAG_HIDE_RESTAURANT_"))
	if not check(guests.size()==10 and g._flags().s_restaurant.guests.size()==5,"only five pairs seated on real map"):finish();return
	var seats: Array=g._flags().s_restaurant.guests.keys()
	var table_key: String=guests[0].source_flag
	var second: Dictionary=guests.filter(func(n):return n.source_flag==table_key and n.local_id!=guests[0].local_id)[0]
	var saved: Array=g.save_data.party
	g.save_data.party=party.compact([saved[0]])
	speak(guests[0]);clear()
	check(not is_instance_valid(g.active_battle),"one healthy combatant denied")
	g.save_data.party=saved
	speak(guests[0]);clear();click("接受双打")
	var ui=g.active_battle
	if not check(is_instance_valid(ui) and ui.get_script().resource_path.ends_with("double_battle_ui.gd"),"real two-opponent double battle launched"):finish();return
	check(ui.battle.groups.b==["first","second"] and not ui.companion,"two trainers command separate teams, player commands both")
	for i in 1000:
		if ui.is_queued_for_deletion():break
		if ui.state=="menu":ui._on_command_kind("fight");ui._on_move(0)
		else:ui._process(2.0)
	clear()
	check(table_key in g._flags().s_restaurant.won,"real battle won and keeps the pair defeated")
	g._persist();g._restore_from_save()
	speak(npc(second.source_script))
	check(not g._dialogs.is_empty(),"other diner offers original post-battle lines")
	clear()
	check(seats.all(func(k):return g._flags().s_restaurant.guests.has(k)) and g._flags().s_restaurant.won.has(table_key),"same day seats and both defeated partners survive reload")
	time.hour=22;check(diner.open_at(time),"22:59 last hour")
	time.hour=23;check(not diner.open_at(time),"23:00 closed")
	speak(npc("Restaurant_Waiter"));clear()
	check(g.world.map_data.id=="sinnoh_valor_lakefront","inside restaurant at closing returned to lakeshore")
	time.hour=9;time.day=24
	open_map("sinnoh_restaurant",Vector2i(9,11))
	check(g._flags().s_restaurant.won.is_empty() and g._flags().s_restaurant.guests.size()==5,"next day resets all battle records")
	print("RESTAURANT TWO DATES ",seats," -> ",g._flags().s_restaurant.guests.keys())
	diner.clock=Callable()
	finish()

func finish() -> void:
	print("SINNOH BREEDING AND DINING ", "PASS" if failures.is_empty() else "FAIL"," ",count," checks ",failures)
	Save.clear_test_slot()
	quit(0 if failures.is_empty() else 1)
