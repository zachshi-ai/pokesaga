extends SceneTree
## Open START through controller/keyboard, follow the field pages and return to the map.
const Save := preload("res://core/save_game.gd")
var game
var failed := false

func _initialize() -> void:
	call_deferred("run")

func expect(ok: bool, message: String) -> bool:
	if not ok:
		push_error("START: " + message)
		failed = true
	return ok

func frames() -> void:
	await process_frame
	await process_frame

func key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		root.push_input(event, true)

func pad(code: JoyButton) -> void:
	for down in [true, false]:
		var event := InputEventJoypadButton.new()
		event.button_index = code
		event.pressed = down
		root.push_input(event, true)

func tap(point: Vector2) -> void:
	for down in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = event.position
		event.pressed = down
		root.push_input(event, true)

func choose(label: String) -> bool:
	for button in game.start_menu.rows:
		if button.text == label:
			button.pressed.emit()
			return true
	return expect(false,"missing row " + label)

func choose_option(prefix: String) -> bool:
	var page := game.menu_layer.get_child(-1) as Control
	for button in page.find_children("*","Button",true,false):
		if button.text.begins_with(prefix):
			button.pressed.emit()
			return true
	return expect(false, "missing field option " + prefix)

func check_field_moves() -> void:
	game._give_item("秘传学习器 02",1,"tm")
	game._give_item("秘传学习器 05",1,"tm")
	game.save_data.badges = ["橙色徽章","灰色徽章"]
	game.save_data.party = [{"species_id":149,"name":"快龙","moves":[19,148]}]
	game.world.dark = true
	for move_name in ["闪光","飞翔"]:
		pad(JOY_BUTTON_START)
		choose("工具")
		choose("秘传")
		if not choose_option(move_name + "（快龙 已会）"): return
		if not choose_option("使用" + move_name): return
		await frames()
		if move_name == "闪光":
			expect(not game.world.dark and game.panel_open == 0, "Flash lights the map and closes START")
			game._flags()["fly_尼比市"] = true
		else:
			if not choose_option("尼比市"): return
			await frames()
			expect(game.world.player_pos == Vector2i(65,86) and game.world.area_name() == "尼比市",
				"Fly lands at Pewter's original Pokémon Center")
			expect(game.panel_open == 0, "Fly closes destination picker and START")

func finish() -> void:
	Save.clear_test_slot()
	print("START MENU ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)

func run() -> void:
	Save.use_test_slot()
	game = load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await frames()
	pad(JOY_BUTTON_START)
	expect(not is_instance_valid(game.start_menu), "opened over title")
	game.title_screen.new_button.pressed.emit()
	await frames()
	var position: Vector2i = game.world.player_pos
	key(KEY_ENTER)
	if not expect(is_instance_valid(game.start_menu), "Enter opens menu"):
		finish()
		return
	var menu = game.start_menu
	expect(menu.visible and game.panel_open == 1 and not game.touch_layer.visible, "field modal")
	expect(menu.rows.size() == 7 and menu.rows[0].text == "图鉴", "first page")
	game._move("down")
	expect(game.world.player_pos == position, "moving under menu")
	for label in ["图鉴","队伍","背包","电脑"]:
		if not choose(label): break
		expect(game.panel_open == 2 and not menu.visible and not game.touch_layer.visible, "open " + label)
		game._on_back()
		await frames()
		expect(menu.visible and game.panel_open == 1 and menu.rows[menu.selected].text == label, "return " + label)
	choose("工具")
	expect(menu.rows.map(func(b): return b.text) == ["骑行","秘传","修改器","返回"], "outside tools")
	choose("修改器")
	game._on_back()
	await frames()
	expect(menu.tools_open and menu.visible and menu.rows[menu.selected].text == "修改器", "editor return")
	pad(JOY_BUTTON_B)
	expect(not menu.tools_open and menu.rows[menu.selected].text == "工具", "tools back on controller")
	choose("存档")
	await frames()
	expect(not is_instance_valid(game.start_menu) and game.touch_layer.visible and game.panel_open == 0, "save closes menu")
	var saved := Save.existing()
	expect(Vector2i(int(saved.pos[0]), int(saved.pos[1])) == position, "saved from menu")
	game.world.load_map(root.get_node("Data").load_map("kanto","viridiancity_pokemoncenter_1f"))
	pad(JOY_BUTTON_START)
	choose("工具")
	expect(game.start_menu.rows.size() == 5 and game.start_menu.rows[3].text == "融合", "centre fusion")
	choose("融合")
	game._on_back()
	await frames()
	expect(game.start_menu.visible and game.panel_open == 1, "fusion return")
	pad(JOY_BUTTON_START)
	await frames()
	expect(not is_instance_valid(game.start_menu) and game.panel_open == 0 and game.touch_layer.visible, "toggle shut")
	game._dialog(["测试"], "")
	pad(JOY_BUTTON_START)
	expect(not is_instance_valid(game.start_menu), "opened during dialogue")
	game._on_back()
	await frames()
	tap(Vector2(435,22))
	await frames()
	if not expect(is_instance_valid(game.start_menu), "touch START"):
		finish()
		return
	tap(Vector2(393,140))
	await frames()
	expect(game.panel_open == 2 and not game.start_menu.visible, "touch bag")
	game._on_back()
	await frames()
	pad(JOY_BUTTON_DPAD_DOWN)
	expect(game.start_menu.rows[game.start_menu.selected].text == "电脑", "controller row selection")
	key(KEY_ENTER)
	await frames()
	expect(game.panel_open == 2, "Enter on selected row")
	game._on_back()
	await frames()
	tap(Vector2(435,22))
	await frames()
	expect(game.panel_open == 0 and game.touch_layer.visible, "touch START again")
	tap(Vector2(435,22))
	await frames()
	var start_pos: Vector2i = game.world.player_pos
	tap(Vector2(82,177))
	await frames()
	expect(game.panel_open == 0 and game.touch_layer.visible and game.world.player_pos == start_pos,
		"map tap over direction key dismisses without movement")
	await check_field_moves()
	finish()
