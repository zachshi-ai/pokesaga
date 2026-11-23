extends SceneTree
## Use the live chapter UI, real PC and bag, and time-stamped saves in an isolated slot.
var game
var resort
var errors:Array=[]
var presses:=0
var save_tool
func _initialize() -> void:
	run.call_deferred()

func check(ok:bool,reason:String) -> void:
	if not ok:
		errors.append(reason)
		push_error(reason)

func frames() -> void:
	await process_frame
	await process_frame

func press(label:String) -> bool:
	for obj in game.menu_layer.find_children("*","Button",true,false):
		if obj.is_visible_in_tree() and not obj.disabled and str(obj.text).begins_with(label):
			obj.pressed.emit()
			presses+=1
			await frames()
			return true
	check(false,"No button "+label+" visible="+str(game.menu_layer.find_children("*","Button",true,false).filter(func(b):return b.is_visible_in_tree()).map(func(b):return b.text)))
	return false

func close_text() -> void:
	game._close_all_dialogs()
	await frames()

func office(isle:String) -> void:
	resort.office(game,isle)
	await frames()

func visit_service(isle:String) -> void:
	resort.open(game);await frames();await press(resort.NAMES[isle])
	var world=game.world
	var desk:=Vector2i(14,10)
	var dirs:={"u":Vector2i.UP,"r":Vector2i.RIGHT,"d":Vector2i.DOWN,"l":Vector2i.LEFT}
	var names:={"u":"up","r":"right","d":"down","l":"left"}
	var start:Vector2i=world.player_pos
	var todo:Array=[start];var parent:Dictionary={start:null}
	var goal:=Vector2i(-1,-1);var forward:=""
	while not todo.is_empty() and goal.x<0:
		var p:Vector2i=todo.pop_front()
		for letter in dirs:
			var step:Vector2i=dirs[letter];var xy:=p+step
			if xy==desk:goal=p;forward=letter;break
			if parent.has(xy) or not world.warp_at(xy).is_empty() or not world.can_enter(xy,step):continue
			parent[xy]=[p,step];todo.append(xy)
	if goal.x<0:check(false,"cannot approach "+isle);return
	var walk:Array=[]
	while goal!=start:
		var row:Array=parent[goal]
		walk.push_front(row[1]);goal=row[0]
	for step in walk:
		check(world.step(step),"blocked en route to "+isle)
		world.tick_walk(1)
	world.facing=names[forward]
	game._on_action();await frames()

func run() -> void:
	save_tool=load("res://core/save_game.gd")
	save_tool.use_test_slot()
	var src:=OS.get_cmdline_user_args()
	var seed:Dictionary=save_tool.empty() if src.is_empty() else JSON.parse_string(FileAccess.get_file_as_string(src[0]))
	if src.is_empty():
		seed.flags={"a_started":true,"a_version":"ultra_sun","a_ride_charizard":true}
		seed.chapters={"alola":"carried"};seed.region="alola";seed.map="alola_home";seed.pos=[8,7]
	seed.erase("alola_pelago")
	save_tool.save(seed)
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game);await frames()
	game.title_screen.continue_button.pressed.emit();await frames();await close_text()
	resort=load("res://core/alola_pelago.gd")
	var party=load("res://core/party.gd")
	game.save_data.boxes=[]
	for i in 90:
		var mon:Dictionary=party.make(25,12,[84])
		mon.name="度假伙伴"+str(i);mon.friendship=40
		party.store_in_boxes(game.save_data.boxes,mon)
	game._give_bag_item("橙橙果","berry","","oran")
	var before:String=game.world.map_data.id
	game._toggle_start_menu();await frames()
	if not await press("工具") or not await press("宝可度假地") or not await press("悠悠度假地"):finish();return
	check(game.world.map_data.id=="alola_pelago_abeens","START flight")
	var s:Dictionary=resort.current(game)
	for i in 3:
		s.shaken=int(s.last)-24*3600
		await office("abeens");await press("摇豆树");await close_text()
	check(int(s.beans[0])>=216,"harvest and elapsed replenishment")
	for isle in ["aplenny","aphun","evelup","avue"]:
		await visit_service(isle);await press("开发")
		check(int(s.ranks.get(isle,0))==1,"development "+isle)
	await office("aplenny");await press("种树果");await press("橙橙果")
	check(s.jobs.aplenny.size()==1,"berry planted from bag")
	await office("aphun");await press("派伙伴寻宝");await press("寻找碎片")
	await office("evelup");await press("安排训练");await press("攻击");await press("4 次");await press("箱子 1 · 度假伙伴0")
	await office("avue");await press("去泡温泉");await press("箱子 1 · 度假伙伴1")
	check(game.save_data.boxes[0].mons[0].is_empty() and game.save_data.boxes[0].mons[1].is_empty(),"training and spa participants stay in save")
	await office("evelup");await press("给豆箱投豆");await press("普通豆")
	check(int(s.boost.evelup)>0 and s.crates.evelup.size()==1,"beans in crate")
	var last:int=s.last
	var before_xp:int=s.jobs.evelup[0].work
	# --fixed-fps advances simulated frames independently of the OS clock.
	var real_start:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-real_start<2100:
		OS.delay_msec(50)
		await process_frame
	resort.current(game)
	check(int(s.last)>last and int(s.jobs.evelup[0].work)-before_xp>=4,"system-clock doubled training")
	# Simulate leaving the powered-down console for a day. Reopen the same saved slot.
	s.last=int(Time.get_unix_time_from_system())-24*3600
	game._persist()
	game.queue_free();await frames()
	game=load("res://scenes/boot.tscn").instantiate();root.add_child(game);await frames()
	game.title_screen.continue_button.pressed.emit();await frames();await close_text()
	s=resort.current(game)
	var berry_count:int=game._bag_count("橙橙果")
	for isle in ["aplenny","aphun","evelup","avue"]:
		var job:Dictionary=s.jobs[isle][0]
		await office(isle);await press(job.name+" · ");await close_text()
		check(s.jobs[isle].is_empty(),"job removed once "+isle)
	check(game._bag_count("橙橙果")>berry_count,"harvest returned to bag")
	check(int(game.save_data.boxes[0].mons[0].effort.atk)==4,"four EV training sessions")
	check(int(game.save_data.boxes[0].mons[1].friendship)>40,"hot spring raised friendship")
	check(int(s.boost.evelup)==0 and s.crates.evelup.is_empty(),"bean duration expired while closed")
	# The received Paniola egg moves from walking incubation to the hot spring and back.
	game._flags().as_egg_steps=35*256-20
	await visit_service("avue");await press("去泡温泉");await press("寄放屋的伊布蛋")
	check(not game._flags().has("as_egg_steps") and s.jobs.avue[0].egg,"egg was deposited once")
	s.last=int(Time.get_unix_time_from_system())-120;resort.current(game)
	await office("avue");await press("伊布的蛋 · ");await close_text()
	check(s.jobs.avue.is_empty() and 133 in game.save_data.dex.caught,"timed hatching recorded Eevee")
	await visit_service("abeens");await press("来访的宝可梦");await close_text()
	check(s.has("visitor") and int(s.visitor.mon.species_id) in game.save_data.dex.seen,"only the visiting species recorded")
	game._toggle_start_menu();await frames();await press("工具");await press("宝可度假地");await press("返回出发地点")
	check(game.world.map_data.id==before,"returned to original map")
	finish()

func finish() -> void:
	save_tool.clear_test_slot()
	print("ALOLA PELAGO ", "PASS" if errors.is_empty() else "FAIL"," UI presses=",presses," ",errors)
	quit(0 if errors.is_empty() else 1)
