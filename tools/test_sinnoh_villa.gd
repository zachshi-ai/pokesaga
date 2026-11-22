extends SceneTree
const Save := preload("res://core/save_game.gd")
var g
var failures: Array=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:push_error(label);failures.append(label)
func click(prefix: String) -> bool:
	for parent in g.menu_layer.get_children():
		if parent.is_queued_for_deletion() or not parent.visible:continue
		for b in parent.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.text.begins_with(prefix):
				b.pressed.emit();return true
	check(false,"missing "+prefix)
	return false
func next() -> void:
	for i in 32:
		if g._dialogs.is_empty():break
		g._on_action()
func order(item: String) -> void:
	g.world.tick_walk(1.0)
	if g.world.player_pos==Vector2i(10,6):
		g._move("down");g.world.tick_walk(1.0)
	check(g.world.player_pos==Vector2i(10,7),"unblocked aisle to order form")
	g.world.facing="right";g._on_action()
	click(item);click("确认订购");next()
func run() -> void:
	Save.use_test_slot();g=load("res://scenes/boot.tscn").instantiate();root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"sinnoh")
	g._close_all_dialogs()
	g._flags().s_national_dex=true;g._flags().s_champion=true
	var v=load("res://core/sinnoh_villa.gd")
	var map: Dictionary=root.get_node("Data").load_map("sinnoh","sinnoh_resort")
	g.world.load_map(map);g.world.refresh_story_actors(g._flags())
	var org: Array=map.platinum_origin
	g.world.warp_to(Vector2i(814-int(org[0]),473-int(org[1])))
	g.world.tick_walk(1);g._move("right");g.world.tick_walk(1)
	next();click("收下别墅");next()
	check(g._flags().get("s_villa_deed",false) and g.world.map_data.id=="sinnoh_villa","owner delivered keys at original coordinate")
	if g.world.map_data.id!="sinnoh_villa":quit(1);return
	click("桌子");click("确认订购");next()
	check(v.stock(g).has("table") and g.world.is_blocked(Vector2i(12,6)),"free table delivered and collidable")
	check(g.world.npcs.any(func(n):return n.local_id=="LOCALID_RIVAL"),"Barry visits after table")
	g.save_data.money=999999
	order("小沙发")
	check(v.stock(g).has("small_sofa") and int(g.save_data.money)==909999,"paid price once")
	check(g.world.npcs.any(func(n):return n.local_id=="LOCALID_COUNTERPART") and not g.world.npcs.any(func(n):return n.local_id=="LOCALID_RIVAL"),"Dawn replaced Barry")
	g.world.tick_walk(1.0)
	if g.world.player_pos==Vector2i(10,6):
		g._move("down");g.world.tick_walk(1.0)
	check(g.world.player_pos==Vector2i(10,7),"unblocked aisle to order form")
	g.world.facing="right";g._on_action();click("小沙发");next()
	check(int(g.save_data.money)==909999,"duplicate held out")
	check(not v.available(g,"music_box") and not v.available(g,"piano"),"locked music box and piano")
	order("陈列架");check(v.available(g,"music_box"),"rack unlocks music box")
	order("音乐盒")
	g.save_data.s_hall_entries=10
	order("钢琴")
	check(v.stock(g).has("piano") and g.world.npcs.any(func(n):return n.local_id=="LOCALID_CYNTHIA"),"ten halls unlock piano and invite Cynthia")
	if OS.get_environment("POKESAGA_VILLA_SCREENSHOT")!="":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("POKESAGA_VILLA_SCREENSHOT"))
	g._persist()
	var saved: Dictionary=Save.load_game()
	check(saved.flags.s_villa_furniture.size()==5 and saved.flags.s_villa_guest==12,"villa furnishing and visitor persist")
	# Exercise every conditional line of the order form with explicit record fixtures.
	check(not v.available(g,"guest_set") and not v.available(g,"masterpiece") and not v.available(g,"chandelier"),"activity limits guard special decorations")
	g.save_data.s_battleground_battles=50;g.save_data.s_berries_planted=50
	g.save_data.s_eggs_hatched=30;g.save_data.s_pedometer=300000
	g.save_data.s_frontier_records={"tower":1,"hall":1,"factory":1,"arcade":1,"castle":1}
	g.save_data.s_frontier_prints={"tower":1};g.save_data.money=9999999
	for key in v.data():
		if not v.stock(g).has(key):order(v.data()[key].name)
	check(v.stock(g).size()==20,"all twenty unique furniture deliveries fulfilled through order form")
	var expected:=0
	for row in v.data().values():expected+=row.placements.size()
	check(g.world.get_node("VillaFurniture").get_child_count()==expected+1,"each furniture model and order book rendered")
	g._persist();check(Save.load_game().flags.s_villa_furniture.size()==20,"all twenty retained")
	g._close_all_dialogs();g.queue_free();await process_frame;Save.clear_test_slot()
	print("SINNOH VILLA UI ", "PASS" if failures.is_empty() else "FAIL", " ",failures)
	quit(0 if failures.is_empty() else 1)
