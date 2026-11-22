extends SceneTree
const Save:=preload("res://core/save_game.gd")
const Side:=preload("res://core/crystal_sidequests.gd")
const Ruins:=preload("res://core/crystal_ruins.gd")
const Radio:=preload("res://core/crystal_radio.gd")
const Calls:=preload("res://core/crystal_calls.gd")
const Home:=preload("res://core/crystal_home.gd")
const Phone:=preload("res://core/crystal_phone.gd")
const Tower:=preload("res://core/crystal_tower.gd")
const Contest:=preload("res://core/crystal_bug_contest.gd")
var g
var failures:=0
var checks:=0
func _initialize():run.call_deferred()
func check(ok:bool,why:String):
	checks+=1
	if not ok:
		failures+=1
		push_error("Crystal side story: "+why)
func clear():g._close_all_dialogs()
func travel(mid:String):
	clear()
	var m: Dictionary=root.get_node("Data").load_map("johto","johto_"+mid)
	g._do_warp({"region":"johto","map":"johto_"+mid,"at":m.spawn,"hgss":true})
	clear()
func who(key:String) -> Dictionary:
	for n in g.world.npcs:
		if n.get("crystal_quest","")==key:return n
	check(false,"missing "+key+" in "+str(g.world.map_data.id))
	return {}
func act(key:String):
	clear()
	var n:=who(key)
	if n.is_empty():return
	var at:=Vector2i(n.at[0],n.at[1])
	for v in [[Vector2i.DOWN,"up"],[Vector2i.UP,"down"],[Vector2i.RIGHT,"left"],[Vector2i.LEFT,"right"]]:
		var p: Vector2i=at+v[0]
		if not g.world.warp_at(p).is_empty() or g.world.is_blocked(p) or g.world.is_water(p) or not g.world._npc_at(p).is_empty():continue
		g.world.warp_to(p)
		if g.world.player_pos!=p:continue
		g.world.facing=v[1]
		g._on_action()
		return
	check(false,"no accessible adjacent tile at "+str(n.at)+" "+key)
func click(prefix:String):
	var panels: Array=g.menu_layer.get_children()
	panels.reverse()
	for p in panels:
		if p.is_queued_for_deletion():continue
		for b in p.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.text.begins_with(prefix):
				b.pressed.emit()
				return
	check(false,"button "+prefix)
func fresh_mon(sid:int,lv:=20) -> Dictionary:
	return g.PartyScript.make(sid,lv,g.EncounterScript.moves_for(sid,lv))
func fixture_day(weekday:int) -> Dictionary:
	return {"year":2026,"month":11,"day":15+weekday,"weekday":weekday,"hour":15}
func scripted(key:String,day:Dictionary):
	clear()
	Side.talk(g,{"name":"测试角色","crystal_quest":key,"at":[0,0]},day)
func run():
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"johto")
	g.save_data.party=[fresh_mon(158)]
	travel("ecruteak_pokecenter_1f")
	check(g._flags().get("js_bill_met",false),"Bill visits the healing center as it is entered")
	travel("bills_familys_house")
	act("bill_home");click("接受");clear()
	check(g.save_data.party.any(func(m):return m.get("species_id")==133 and int(m.level)==20),"Bill gives level 20 Eevee")
	act("bill_home");clear()
	check(g.save_data.party.filter(func(m):return m.get("species_id")==133).size()==1,"Eevee only once")
	travel("route_35_goldenrod_gate")
	act("kenya");click("接受");clear()
	check(g.save_data.party.any(func(m):return m.get("name")=="KENYA" and m.held=="FLOWER_MAIL"),"Kenya carries unique mail")
	travel("route_31");act("letter");click("3　KENYA");clear()
	check(g._bag_count("城都招式学习器 50")==1 and not g.save_data.party.any(func(m):return m.get("name")=="KENYA"),"letter and actual mailed party member delivered")
	travel("route_35_goldenrod_gate");act("kenya");clear()
	check(g._bag_count("HP 增强剂")==1,"return to guard for HP Up")
	travel("manias_house");act("shuckie");click("照看");clear()
	check(g.save_data.party.any(func(m):return m.get("crystal_gift")=="shuckie"),"Mania's actual gift")
	var sun:=fixture_day(0)
	for i in 7:
		var day:=fixture_day(i)
		var key:="sibling_"+str(i)
		check(Side.visible(key,g._flags(),day) and not Side.visible(key,g._flags(),fixture_day((i+1)%7)),"weekday "+str(i))
		scripted(key,day)
		var item: String=Side.data().siblings[i]
		check(g._bag_count(item)==1 and root.get_node("Data").held_keys_by_name.has(item),"weekday usable held item "+item)
		scripted(key,day)
		check(g._bag_count(item)==1,"weekday reward is one-time")
	for key in Side.data().trades:
		var t: Array=Side.data().trades[key]
		var wanted:=fresh_mon(t[0],37)
		if t[6]:wanted.sex="female"
		g.save_data.party=[wanted]
		scripted(key,sun);click("1　");clear()
		check(g.save_data.party[0].species_id==t[1] and g.save_data.party[0].level==37 and g.save_data.party[0].ot==t[5],"native exchange "+key)
	travel("bills_house")
	for entry in Side.STONES:
		g.save_data.party=[fresh_mon(entry[0])]
		var before:int=g._bag_count(entry[1])
		act("grandpa");click("1　");clear()
		check(g._bag_count(entry[1])==before+1,"show species for "+entry[1])
	travel("route_39_barn");g._give_bag_item("橙橙果","berry","","oran")
	for i in 6:g._give_bag_item("橙橙果","berry","","oran")
	for i in 7:
		act("moomoo");click("喂树果");clear()
	check(g._flags().get("js_milk_berries")==7,"feed seven real berries")
	travel("route_39_farmhouse");act("snore");clear()
	check(g._bag_count("城都招式学习器 13")==1,"farm family reward")
	act("dairy");click("买一瓶");clear()
	check(g._bag_count("哞哞鲜奶")==1 and g.HEAL_TABLE["哞哞鲜奶"].hp==100,"buy usable Moomoo Milk")
	g.save_data.party=[fresh_mon(158)]
	for key in Ruins.TYPES:
		travel("ruins_of_alph_"+key+"_chamber")
		g.world.warp_to(Vector2i(6,7));g.world.facing="up";g._on_action()
		var board=g.menu_layer.get_child(-1)
		check(board.has_method("press"),"original stone tablet opens "+key)
		if not board.has_method("press"):continue
		for i in 16:
			if board.order[i]!=i:
				var index:int=board.order.find(i)
				board.tiles[i].pressed.emit();board.tiles[index].pressed.emit()
		clear()
		check(g._flags().get("js_puzzle_"+key,false) and g.world.map_data.id==Ruins.HALL,"solve and fall into hall "+key)
	check(Ruins.letters(g._flags())=="ABCDEFGHIJKLMNOPQRSTUVWXYZ","four original Unown groups")
	for letter in ["A","D","Z"]:g.DexVariants.record(g.save_data,{"species_id":201,"form":"UNOWN_"+letter},true)
	g.DexVariants.record(g.save_data,{"species_id":201,"form":"UNOWN_B"},false)
	check(Ruins.caught_letters(g).size()==3,"research counts only caught forms")
	travel("ruins_of_alph_research_center");act("ruins_scientist");clear()
	check(g._flags().get("js_unown_dex",false),"scientist opens alphabet record")
	travel("route_35_national_park_gate")
	scripted("bug_officer",fixture_day(2));click("报名");clear()
	check(Contest.active(g) and g.world.map_data.id==Contest.PARK and g.save_data.js_contest.balls==20,"real gate enters park with 20 balls")
	if Contest.active(g):
		Contest.encounter(g)
		check(is_instance_valid(g.active_battle) and g.active_battle.bag.size()==1 and g.active_battle.bag[0].name=="竞赛球","actual field encounter only shows contest supplies")
		if is_instance_valid(g.active_battle):
			g.active_battle.finished.emit("fled");await process_frame
		var caught:=fresh_mon(123,14)
		Contest.caught(g,caught);clear()
		Contest.finish(g);clear()
		check(not Contest.active(g) and g.save_data.party.any(func(m):return m.get("species_id")==123),"judging stores the retained capture and gives prize")
		scripted("bug_officer",fixture_day(2))
		check(not Contest.active(g),"one attempt per day")
	travel("mount_mortar_b1_f")
	act("kiyo")
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().species_id==106,"Karate King starts with Hitmonlee")
	if is_instance_valid(g.active_battle):g.active_battle.finished.emit("a");await process_frame
	clear();check(g.save_data.party.any(func(p):return p.get("species_id",0)==236 and int(p.get("level",0))==10),"Karate King gives Tyrogue on victory")
	scripted("lapras",fixture_day(5))
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().species_id==131 and g.active_battle.battle.cur_b().level==20,"Friday Lapras enters wild battle")
	if is_instance_valid(g.active_battle):g.active_battle.finished.emit("fled");await process_frame
	check(not Side.visible("lapras",g._flags(),fixture_day(5)),"Lapras leaves for this Friday")
	travel("ruins_of_alph_kabuto_chamber");g._give_item("离洞绳",1,"other")
	check(Ruins.use_rope(g,"离洞绳") and g._flags().get("js_wall_kabuto",false),"escape rope opens Kabuto secret room");clear()
	travel("ruins_of_alph_aerodactyl_chamber")
	check(Ruins.flash(g) and g._flags().get("js_wall_aerodactyl",false),"Flash opens stone room");clear()
	travel("ruins_of_alph_omanyte_chamber");g._give_item("水之石",1,"other");Ruins.automatic_walls(g)
	check(g._flags().get("js_wall_omanyte",false),"Water Stone opens Omanyte secret room");clear()
	g.save_data.party=[fresh_mon(250)];travel("ruins_of_alph_ho_oh_chamber");Ruins.automatic_walls(g)
	check(g._flags().get("js_wall_ho_oh",false),"Ho-oh in first slot opens fourth stone room");clear()
	travel("goldenrod_game_corner");g._give_item("代币盒",1,"key");g.save_data.j_coins=2000
	act("game_mon");click("凯西");clear()
	check(g.save_data.j_coins==1900 and g.save_data.party.any(func(p):return p.get("species_id",0)==63),"100 coins exchanged for original level 5 Abra")
	var machines:Array=g.world.objects.filter(func(o):return "MachineScript" in str(o.get("source_script","")))
	var slots:Array=machines.filter(func(o):return "SlotsMachine" in str(o.source_script))
	var cards:Array=machines.filter(func(o):return "CardFlip" in str(o.source_script))
	check(not slots.is_empty() and not cards.is_empty(),"both real room machine objects survive art remap")
	if not slots.is_empty():
		g._handle_object(slots[0]);click("1 枚")
		var reels=g.menu_layer.get_child(-1)
		check(reels.has_method("stop"),"slot opens touch reel screen")
		if reels.has_method("stop"):
			reels.stops=[0,0,0];reels.stop_button.pressed.emit();reels.stop_button.pressed.emit();reels.stop_button.pressed.emit();clear()
			check(g.save_data.j_coins==2199,"three sevens pay 300 with a one-coin stake")
	if not cards.is_empty():
		g._handle_object(cards[0]);click("猜一个数字");click("1");click("收起")
		check(int(g.save_data.j_coins) in [2196,2214],"flip deducts three and pays at the correct odds")
	# Use the actual trainer and phonebook after an initial defeat.
	travel("route_30")
	var joey:Dictionary=g._find_npc("短裤小子 Joey")
	check(not joey.is_empty() and not Phone.talk(g,joey,sun),"normal first trainer battle is preserved")
	g._flags().j_gear=true
	g._mark_defeated(joey.name);g._apply_defeated()
	g._talk_to_npc(joey);click("登录号码");clear()
	check("joey" in Phone.state(g).book,"trainer saves number after initial battle")
	travel("route_31")
	var monday:=fixture_day(1);monday.hour=15
	check(Phone.call_contact(g,"joey",monday).contains("再比") and Phone.state(g).pending.joey=="fight","correct weekly appointment")
	travel("route_30");joey=g._find_npc("短裤小子 Joey")
	g._talk_to_npc(joey)
	check(is_instance_valid(g.active_battle) and g.active_battle.battle.cur_b().species_id==19,"actual Joey rematch launches original team")
	if is_instance_valid(g.active_battle):g.active_battle.finished.emit("a");await process_frame
	check(Phone.state(g).wins.get("joey",0)==1 and not Phone.state(g).pending.has("joey"),"only completed battle advances phone tier")
	check(Phone.tier({},Phone.data().joey,4)==0 and Phone.tier({"johto_champion":true},Phone.data().joey,4)==4,"rematch levels respect story gate")
	var stamp:=Phone.current_day(Time.get_datetime_dict_from_system())
	Phone.state(g).swarm.arnie=stamp
	travel("route_35")
	check(Phone.swarm_pool(g,[],"nite").any(func(r):return r.species==193),"active swarm changes real map encounter pool")
	travel("radio_tower_1f");act("lottery");clear()
	g.save_data.js_trainer_id=12345;g._flags().js_lottery_number=12345
	var balls:int=g._bag_count("大师球");act("lottery");clear();act("lottery");clear()
	check(g._bag_count("大师球")==balls+1,"matching OT id draws a Master Ball once per week")
	travel("battle_tower_1f")
	g.save_data.party=[fresh_mon(25,10),fresh_mon(39,10),fresh_mon(52,10)]
	var before_team:Array=g.save_data.party.duplicate(true)
	act("tower");click("Lv.10 组");click("皮卡丘");click("胖丁");click("喵喵")
	for n in 7:
		check(is_instance_valid(g.active_battle) and g.active_battle.bag.is_empty() and g.active_battle.player_team.size()==3,"tower round %d uses three and seals the bag"%n)
		if not is_instance_valid(g.active_battle):break
		check(g.save_data.js_tower.opponent.size()==3 and g.active_battle.battle.cur_b().max_hp==g.save_data.js_tower.opponent[0].stats[0],"fixed source team stats for round %d"%n)
		g.active_battle.finished.emit("a");await process_frame
		if n<6:click("下一场")
	clear()
	check(g.world.map_data.id==Tower.LOBBY and g._flags().get("js_tower_best",0)==7,"seven-win prize returns to lobby")
	check(g.save_data.party==before_team,"tower preserves real party, held items and damage")
	travel("players_house_1f")
	var mother:Dictionary=g._find_npc("妈妈")
	g._talk_to_npc(mother);click("请妈妈代存");clear()
	check(Home.bank(g).saving,"mother opts into saving prize money")
	travel("route_30");g.save_data.money=100000
	g._start_battle({"name":"对战存款验证","battle":{"species":19,"level":4,"prize":400}})
	if is_instance_valid(g.active_battle):g.active_battle.finished.emit("a");await process_frame
	check(Home.bank(g).balance==100 and g.save_data.money==100300,"trainer prize splits into wallet and Mom's account")
	travel("players_house_1f");Home.transfer(g,true,90000);clear()
	travel("route_30")
	for n in 9:Home.shopping(g)
	check(g._flags().get("js_dolls_owned",{}).has("doll_pikachu") and Home.bank(g).parcels.has("月之石"),"thresholded parcels and three dolls are paid from bank")
	g._open_pc();click("妈妈买来");click("好伤药");clear()
	check(g._bag_count("好伤药")>0,"PC delivers bought item")
	travel("players_house_2f");g.world.warp_to(Vector2i(6,5));g.world.facing="up";g._on_action()
	click("装饰房间");click("左侧");click("皮卡丘玩偶");clear()
	check(g.world.npcs.any(func(x):return x.get("field_art","")=="crystal_doll_pikachu"),"bedroom PC places a visible physical Pikachu doll")
	travel("mount_moon_square")
	var night:=fixture_day(1);night.hour=21
	check(Home.square_open(night,g._flags()) and not Home.square_open(fixture_day(1),g._flags()),"Monday night only on real local calendar")
	g.world.warp_to(Vector2i(9,13));await Home.field_step(g,night)
	await create_timer(2.2).timeout;clear()
	check(g._flags().get("js_moon_rock",false) and g.world.npcs.any(func(x):return x.get("crystal_quest","")=="moon_rock"),"two fairies dance and leave a smashable rock")
	g.save_data.party[0].moves=[249];g.world.facing="up";g._on_action();click("使用碎岩");clear()
	var stones:int=g._bag_count("月之石");g._on_action();clear()
	check(g._bag_count("月之石")==stones+1 and not Home.square_open(night,g._flags()),"smash then inspect the spot to receive one Moon Stone")
	travel("route_30");g._give_item("收音机卡",1,"key")
	var morning:=fixture_day(0);morning.hour=6
	check("dex" in Radio.stations(g,morning) and "talk" in Radio.stations(g,sun),"radio 4.5 changes between morning and daytime in Johto")
	Radio.tune(g,"music",morning);clear()
	check(g.snd.cur_key=="crystal_pokemonmarch" and Radio.track(g,"music",morning)=="pokemonmarch" and Radio.track(g,"music",monday)=="pokemonlullaby","real March/Lullaby audio and weekday selection")
	Radio.tune(g,"lucky",morning);clear()
	check(g._flags().has("js_lottery_number") and g.snd.cur_key=="crystal_gamecorner","lucky radio reads the same saved lottery ticket")
	travel("ruins_of_alph_inner_chamber")
	check("alph" in Radio.stations(g,sun),"13.5 only inside Alph landmark")
	g._give_item("收音机扩充卡",1,"key");travel("vermilion_city")
	check(Radio.stations(g,morning)==["places","sing","flute"],"three Kanto radio stations require expansion card")
	Radio.tune(g,"flute",morning);clear();check(g._flags().get("j2_flute",false) and g.snd.cur_key=="crystal_pokeflutechannel","actual station activates the Snorlax flute")
	travel("bills_familys_house");act("bill_sister");click("登录号码");clear()
	check("bill" in Phone.state(g).book and Phone.call_contact(g,"bill",sun).contains("电脑"),"younger sister registers Bill's actual PC status call")
	for key in Phone.data():
		var st={"swarm":{},"pending":{},"gift_done":{},"weekdays":{}}
		var contact:Dictionary=Phone.data()[key]
		var appt:=fixture_day(maxi(0,int(contact.weekday)))
		appt.hour=6 if contact.period=="MORN" else (21 if contact.period=="NITE" else 12)
		var conversation:=Calls.run(g,st,key,false,appt)
		check(not conversation.is_empty() and (contact.rematches.is_empty() or st.pending.get(key,"")=="fight"),"original phone script outgoing appointment "+key)
		for n in 6:check(not Calls.run(g,st,key,true,appt).is_empty(),"incoming original contact "+key)
	travel("lake_of_rage_magikarp_house")
	g._flags().j_plant_clear=true
	g.save_data.party=[fresh_mon(129)];g.save_data.party[0].js_dvs=65535;g.save_data.party[0].ot_id=0
	act("karp");clear();act("karp");click("1　");clear()
	check(g._flags().get("js_karp_inches",0)>42 and g._bag_count("PP 多项小补剂")>=1,"record Magikarp measured by stable DVs and OT, with actual elixir")
	var prize:int=g._bag_count("PP 多项小补剂");act("karp");click("1　");clear();check(g._bag_count("PP 多项小补剂")==prize,"same Magikarp cannot repeatedly break its own record")
	travel("ilex_forest")
	g.save_data.party[0].moves=[29];var found:=false
	for y in g.world.tile_size.y:
		if found:break
		for x in g.world.tile_size.x:
			var p:=Vector2i(x,y)
			if g.world.is_blocked(p) or g.world.is_water(p) or not g.world.warp_at(p).is_empty():continue
			var tree:Vector2i=p+Vector2i.UP
			if (preload("res://core/hgss_field.gd").word(g.world.map_data.hgss,tree)&255)==6:
				g.world.warp_to(p);g.world.facing="up";g.save_data.js_trainer_id=(tree.x*tree.y+tree.x+tree.y)/5
				found=true;break
	check(found,"reachable native forest tree is marked as headbuttable")
	if found:
		for attempt in 20:
			g._on_action();click("使用头锤")
			if is_instance_valid(g.active_battle):break
			clear()
		check(is_instance_valid(g.active_battle) and int(g.active_battle.battle.cur_b().level)==10,"field Headbutt uses Ilex Forest encounter table")
		if is_instance_valid(g.active_battle):g.active_battle.finished.emit("fled");await process_frame
	g._flags().erase("j_plant_clear");travel("lake_of_rage")
	var trainers:=["FisherAndre","FisherRaymond","CooltrainerMAaron","CooltrainerFLois"]
	check(not g.world.npcs.any(func(n):return n.get("trainer","") in trainers),"Rocket radio keeps all four civilian trainers away from lake")
	g._flags().j_plant_clear=true;g.world.refresh_story_actors(g._flags())
	check(g.world.npcs.filter(func(n):return n.get("trainer","") in trainers and n.has("battle")).size()==4,"all four actual battle trainers return after basement transmitters are cleared")
	var original_map:Dictionary=root.get_node("Data").load_map("johto","johto_lake_of_rage")
	var wed:=Side.roster(original_map.id,original_map.npcs,g._flags(),fixture_day(3))
	var thu:=Side.roster(original_map.id,original_map.npcs,g._flags(),fixture_day(4))
	check(wed.any(func(n):return n.get("crystal_quest","")=="sibling_3") and not thu.any(func(n):return n.get("crystal_quest","")=="sibling_3"),"Wesley is present Wednesday only while the Crystal lake map stays the same")
	await test_daily_events()
	clear();g._persist()
	var saved:=Save.existing()
	check(saved.flags.get("js_puzzle_ho_oh",false) and saved.flags.get("js_letter",false),"story flags survive disk save")
	Save.clear_test_slot()
	g.queue_free();await process_frame
	print("CRYSTAL SIDEQUESTS ", "PASS" if failures==0 else "FAIL", " checks=",checks)
	quit(int(failures!=0))

func vendor_at_counter(key:String,day:Dictionary,y:int):
	var map:Dictionary=g.world.map_data
	var rows:=Side.roster(map.id,map.npcs,g._flags(),day)
	g.world.npcs=preload("res://core/hgss_field.gd").roster(map,rows)
	g.world._draw_npcs()
	g.world.warp_to(Vector2i(8,y))
	g.world.facing="right"
	g.world.step_interact()
	check(g.world.player_pos==Vector2i(8,y) and g.world.last_npc.get("crystal_quest","")==key,"A across the physical shop counter reaches "+key)
	Side.talk(g,g.world.last_npc,day)

func test_daily_events():
	const Daily=preload("res://core/crystal_daily.gd")
	travel("trainer_house_b1_f")
	check(preload("res://core/johto_gba_cast.gd").character(who("cal"))=="cal","Cal uses the Emerald-style Johto player sprite in both the lobby and the escort")
	g.save_data.party=[fresh_mon(160,60)]
	g.world.warp_to(Vector2i(8,4))
	g._move("left");g.world.tick_walk(1.0)
	check(g.world.player_pos==Daily.GATE,"training hall gate is walkable from the stairs")
	click("改天再来")
	check(g.world.player_pos==Daily.EXIT and not g._flags().has("js_cal_day"),"declining steps back without spending today's entry")
	g._move("left");g.world.tick_walk(1.0)
	click("接受挑战")
	await create_timer(1.2).timeout
	check(is_instance_valid(g.active_battle) and g.world.player_pos==Daily.ARENA,"gate attendant walks player to Cal and launches the match")
	if is_instance_valid(g.active_battle):
		var team:Array=g.active_battle.enemy_team
		check(team.map(func(m):return int(m.species_id))==[154,157,160] and team.all(func(m):return m.level==50),"native CAL3 has all three fully evolved Johto starters")
		check(team[0].moves==[77,235,34,113] and team[2].moves==[44,184,163,103],"native Crystal last-four moves")
		g.active_battle.finished.emit("b")
		await create_timer(1.4).timeout
	var lost_date:int=g._flags().get("js_cal_day",-1)
	check(lost_date==Phone.current_day(Side.today()) and Save.existing().flags.get("js_cal_day",-2)==lost_date,"declared attempt survives loss and disk reload")
	g.world.warp_to(Daily.GATE);Daily.cal(g,Side.today())
	check(g.world.player_pos==Daily.EXIT and not is_instance_valid(g.active_battle),"a second same-day challenge is turned away");clear()
	var future:Dictionary=Time.get_datetime_dict_from_unix_time((1+lost_date)*86400)
	Daily.cal(g,future);click("接受挑战")
	check(is_instance_valid(g.active_battle),"next day unlocks another real battle")
	if is_instance_valid(g.active_battle):
		g.active_battle.finished.emit("a")
		await create_timer(1.4).timeout
	check(g.world.player_pos==Daily.EXIT,"victory returns player to the staircase corridor")
	travel("goldenrod_underground")
	var day:=fixture_day(1)
	day.hour=4
	var m:Dictionary=root.get_node("Data").load_map("johto","johto_goldenrod_underground")
	var monday:Array=Side.roster(m.id,m.npcs,g._flags(),day)
	check(monday.any(func(n):return n.get("crystal_quest")=="bargain" and n.native_anchor.at==[10,17]) and not monday.any(func(n):return n.get("crystal_quest")=="herbal"),"Monday morning physical bargain counter")
	var late:=day.duplicate();late.hour=10
	var before:=day.duplicate();before.hour=3
	check(not Side.visible("bargain",{},late) and not Side.visible("bargain",{},before) and Side.visible("herbal",{},fixture_day(6)) and Side.visible("herbal",{},fixture_day(0)),"clock boundaries and weekend herb seller")
	g.save_data.money=500;var nuggets:int=g._bag_count("金珠")
	scripted("bargain",day);click("金珠")
	check(g._bag_count("金珠")==nuggets and not g._flags().has("js_bargain_day"),"insufficient funds leaves all bargain stock");click("返回")
	g.save_data.money=10000;var pearls:int=g._bag_count("珍珠")
	vendor_at_counter("bargain",day,17);click("金珠");click("珍珠");click("返回")
	check(g._bag_count("金珠")==nuggets+1 and g._bag_count("珍珠")==pearls+1 and g.save_data.money==4850,"two genuine items bought during one appointment")
	scripted("bargain",day)
	check(not g._dialogs.is_empty() and g.save_data.money==4850 and Save.existing().flags.get("js_bargain_day",-1)==Phone.current_day(day),"leaving after a purchase closes the vendor, even across reloading");clear()
	var next:=day.duplicate();next.day+=7
	scripted("bargain",next);click("大珍珠");click("返回")
	check(g._bag_count("大珍珠")>=1 and g.save_data.money==1350,"new Monday restocks and applies native price")
	travel("goldenrod_dept_store_2f");act("resale");click("卖贵重物品");click("金珠");clear()
	check(g.save_data.money==6350 and g._bag_count("金珠")==nuggets,"regular department mart pays native resale price")
	travel("goldenrod_underground")
	var weekend:=fixture_day(6);var powder:int=g._bag_count("元气粉")
	vendor_at_counter("herbal",weekend,28);click("元气粉");click("元气粉");click("元气根");click("万能粉");click("复活草");click("返回")
	check(g._bag_count("元气粉")==powder+2 and g.save_data.money==1300,"repeat herb purchases and four authentic prices")
	g.save_data.party[0].hp=1;g.save_data.party[0].friendship=70
	g._apply_heal("元气粉",0,g.HEAL_TABLE["元气粉"])
	check(g.save_data.party[0].hp==51 and g.save_data.party[0].friendship==65 and g._bag_count("元气粉")==powder+1,"herbal medicine really heals and lowers friendship")
	g.save_data.party[0].status="psn"
	g._apply_heal("万能粉",0,g.HEAL_TABLE["万能粉"])
	check(not g.save_data.party[0].has("status"),"weekend heal powder cures status")
	g.save_data.party[0].hp=0
	g._apply_heal("复活草",0,g.HEAL_TABLE["复活草"])
	check(g.save_data.party[0].hp==g.save_data.party[0].max_hp,"weekend revival herb revives fully")
