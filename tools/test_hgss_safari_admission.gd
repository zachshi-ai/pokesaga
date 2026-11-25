extends SceneTree
var g
var errors:=0
func _initialize():run.call_deferred()
func check(ok,label):
	if not ok:
		push_error(label);errors+=1
func press(label):
	for button in g.menu_layer.find_children("*","Button",true,false):
		if button.text==label and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit();return
	check(false,"no "+label)
func position(p):
	g.world.warp_to(p);g.world.finish_walk()
func up():
	check(g.world.step(Vector2i.UP),"step to cashier")
	g.world.tick_walk(1.0)
func action_at(spot):
	position(spot)
	g.world.facing="up"
	g._on_action()

func catch_in_park(id):
	var safari=load("res://core/frlg_safari.gd")
	for attempt in 16:
		check(safari.encounter(g,id,16,""),"Safari encounter "+str(id))
		var ui=g.menu_layer.get_node("SafariEncounter")
		while is_instance_valid(ui) and not ui.is_queued_for_deletion():
			ui.action_chosen.emit("ball")
		await process_frame
		for mon in g.save_data.party:
			if int(mon.species_id)==id and mon.get("johto_safari_caught",false):return
		if not g.save_data.has("j_safari"):break
	check(false,"catch locally owned "+str(id))

func travel(mid,at):
	g._do_warp({"region":"johto","map":mid,"at":at,"hgss":true})
	g.world.finish_walk()
	g._close_all_dialogs()

func run():
	var save=load("res://core/save_game.gd")
	var args=OS.get_cmdline_user_args()
	if args.size()!=1 or not args[0].is_absolute_path() or FileAccess.file_exists(args[0]):
		push_error("Pass a new absolute temporary save filename after --");quit(1);return
	save.slot=args[0]
	check(save.new_game(),"temporary fresh save")
	var d=save.existing()
	d.region="johto";d.map="hgss_safari_zone_entrance_interior";d.pos=[5,6];d.money=750;d.johto_field_revision=1;d.chapters={"johto":"carried"};d.flags={"j2_started":true}
	check(save.save(d),"open gate fixture")
	g=load("res://scenes/boot.tscn").instantiate();root.add_child(g);await process_frame
	g.title_screen.continue_button.pressed.emit();await process_frame
	position(Vector2i(5,6))
	up()
	check(g.world.map_data.id=="hgss_safari_zone_entrance_interior" and g.save_data.money==750,"lighthouse story blocks early arrival")
	g._close_all_dialogs()
	travel("johto_route_39",[23,12]);position(Vector2i(23,12))
	check(g.world.step(Vector2i.LEFT),"step into Baoba's original Route 39 scene")
	g.world.tick_walk(1.0);g._after_step();g._close_all_dialogs()
	check(g._flags().get("j_baoba_contact",false),"Baoba registered on Route 39")
	g._flags().j_lighthouse_cured=true
	travel("hgss_safari_zone_entrance_interior",[5,6])
	action_at(Vector2i(7,13));press("接受考验");g._close_all_dialogs()
	check(g._flags().get("j_safari_test1",false),"Baoba first test")
	action_at(Vector2i(9,7));check(g.menu_layer.find_children("*","Button",true,false).all(func(b):return b.text!="西北　草原"),"console locked");g._close_all_dialogs()
	position(Vector2i(5,6))
	up();press("取消")
	check(g.save_data.money==750 and g.world.map_data.id=="hgss_safari_zone_entrance_interior","cancel does not spend")
	up();press("入园");await process_frame
	check(g.save_data.money==250 and g.save_data.get("j_safari",{}).get("balls")==30 and g.world.map_data.id=="hgss_safari_zone_entrance_exterior","receive 30 balls and arrive across counter")
	check(save.existing().get("j_safari",{}).get("balls")==30,"paid visit persisted")
	check(g.world.step(Vector2i.DOWN),"return through real doorway");g.world.tick_walk(1.0);await process_frame
	check(not g.save_data.has("j_safari") and g.world.player_pos==Vector2i(5,6) and g.world.map_data.id=="hgss_safari_zone_entrance_interior","return to public counter")
	for i in range(1,13):
		var m=root.get_node("Data").load_map("johto","hgss_safari_zone_%02d"%i)
		check(m.get("hgss_encounters",{}).size()==3 and m.get("encounter_rate",0)>0,"area encounter bank "+str(i))
	g.save_data.money=1000
	up();press("入园");await process_frame
	travel("hgss_safari_zone_04",[15,29])
	g.rng.seed=1947
	await catch_in_park(74)
	travel("hgss_safari_zone_entrance_interior",[7,13])
	action_at(Vector2i(7,13));g._close_all_dialogs()
	check(g._flags().get("j_safari_wait",0)>10798,"show own Safari Geodude")
	var safari=load("res://core/johto_safari.gd")
	safari.clock(g,10798)
	check(not g._flags().get("j_safari_customizer",false),"three-hour call still pending")
	safari.clock(g,3)
	check(g._flags().get("j_safari_customizer",false),"Baoba calls after three in-game hours")
	action_at(Vector2i(9,7));press("正南 · 入园处　山峰");press("沙漠");await process_frame
	check(safari.layout(g._flags())==[1,8,2,6,12,7],"replace Peak with Desert")
	action_at(Vector2i(9,7));press("西北　草原");press("森林　· 东南");await process_frame
	check(safari.layout(g._flags())==[7,8,2,6,12,1],"swap two occupied slots")
	check(safari.layout(save.existing().flags)==[7,8,2,6,12,1],"six slots persisted")
	travel("hgss_safari_zone_entrance_exterior",[15,0]);g.world.step(Vector2i.UP);g.world.tick_walk(1.0);await process_frame
	check(g.world.map_data.id=="hgss_safari_zone_12","custom entrance leads directly into the desert")
	g.save_data.j_safari={"balls":30}
	await catch_in_park(27)
	travel("hgss_safari_zone_entrance_interior",[7,13]);action_at(Vector2i(7,13));g._close_all_dialogs()
	check(g._flags().get("j_safari_tests_done",false),"show Safari Sandshrew to finish the second test")
	var desired:=[3,5,9,10,11,12]
	for slot in 6:
		var current: Array=safari.layout(g._flags())
		if current[slot]==desired[slot]:continue
		var next_id: int=desired[slot]
		action_at(Vector2i(9,7));press("%s　%s"%[safari.SLOTS[slot],safari.NAMES[int(current[slot])]])
		var other:=current.find(next_id)
		press(safari.NAMES[next_id]+("　· "+str(safari.SLOTS[other]) if other>=0 else ""));await process_frame
	check(safari.layout(save.existing().flags)==desired,"all six alternate areas selected in the real console and saved")
	print("HGSS SAFARI admission, capture, clock, six-slot save, all-area console and two Baoba tests; errors=",errors)
	quit(1 if errors else 0)
