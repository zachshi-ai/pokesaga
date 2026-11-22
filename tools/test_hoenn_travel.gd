extends SceneTree
## Verify first arrival, optional replay, the truck exit after reloading and direct return.
const Save := preload("res://core/save_game.gd")
const Start := preload("regional_start.gd")
var g
var failed := false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("HOENN TRAVEL: "+message)

func launch() -> void:
	if is_instance_valid(g):
		g.queue_free()
		await process_frame
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame

func leave_truck() -> void:
	for n in 3:
		g._move("right")
		g.world.tick_walk(1.0)
		await process_frame
	check(g.world.map_data.id!="em_inside_of_truck","right-hand exit works")

func settle_dialogs() -> void:
	for n in 90:
		if g._dialogs.is_empty(): break
		g._on_action()
		await process_frame

func run() -> void:
	Save.use_test_slot()
	await launch()
	var buttons: Array=[]
	for b in g.title_screen.find_children("*","Button",true,false):
		if b.is_visible_in_tree(): buttons.append(b.text)
	check(buttons==["新的冒险"],"single fresh game on title")
	g.title_screen.new_button.pressed.emit()
	await process_frame
	await settle_dialogs()
	check(g.world.map_data.region=="kanto","initial chapter")
	Start.open_trip(g,"hoenn")
	await process_frame
	check(Start.press(g.menu_layer,"直接抵达"),"first entry can skip the ride")
	await process_frame
	await settle_dialogs()
	var snapshot := Save.existing()
	check(g.world.map_data.id=="littleroot_town" and g._flags().get("h_moved",false),"first direct arrival meets Mom")
	check(not snapshot.has("hoenn_truck") and snapshot.origin=="kanto","single career")
	var target: Dictionary=root.get_node("Data").travel_regions().hoenn.hub
	Start.open_trip(g,"hoenn")
	await process_frame
	Start.press(g.menu_layer,"乘坐搬家货车")
	await process_frame
	check(g.world.map_data.id=="em_inside_of_truck" and g._escort_active,"replay runs without depositing anybody")
	check(Save.existing().hoenn_truck.phase=="moving","interrupted ride is resumable")
	await launch()
	g.title_screen.continue_button.pressed.emit()
	await process_frame
	for n in 600:
		if not g._escort_active: break
		await process_frame
	check(g.world.map_data.id=="em_inside_of_truck" and Save.existing().hoenn_truck.phase=="parked","interrupted ride reaches the open door")
	await launch()
	g.title_screen.continue_button.pressed.emit()
	await process_frame
	check(not g._escort_active,"parked truck reloads without replay")
	await leave_truck()
	var stored:=Save.existing()
	check(g.world.map_data.id==target.map and g.world.player_pos==Vector2i(int(target.at[0]),int(target.at[1])),"replay unloads at selected destination")
	check(g._dialogs.is_empty() and not stored.has("hoenn_truck"),"no second introduction")
	for field in ["party","money","dex","regional_badges","chapters","flags"]:
		check(stored.get(field)==snapshot.get(field),"preserved "+field)
	Start.open_trip(g,"kanto")
	await process_frame
	await settle_dialogs()
	Start.open_trip(g,"hoenn")
	await process_frame
	Start.press(g.menu_layer,"直接抵达")
	await process_frame
	check(g.world.map_data.id==target.map and g._dialogs.is_empty() and not g.save_data.has("hoenn_truck"),"later direct travel skips van and intro (map=%s, dialogs=%d, truck=%s)" % [g.world.map_data.id,g._dialogs.size(),g.save_data.get("hoenn_truck",{})])
	g.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("HOENN REPEATABLE TRAVEL ","FAIL" if failed else "PASS")
	quit(int(failed))
