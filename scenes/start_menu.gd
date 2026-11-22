extends Control
## The field menu keeps the map visible behind Emerald's original window frame.
signal chosen(command: String)
signal closed

const UI := preload("res://core/field_ui.gd")
const FRAME := preload("res://assets/emerald/ui/menu_frame.png")
const MAIN := ["图鉴", "队伍", "背包", "电脑", "工具", "存档", "退出菜单"]
const TOOLS := ["骑行", "秘传", "修改器"]
const INK := Color("#30483e")
const PAPER := Color("#fffee9")
const ROW_HEIGHT := 34
const WINDOW_X := 319
const WINDOW_Y := 47
const WINDOW_WIDTH := 153

var has_fusion := false
var unova_memory := false
var registered:=""
var tools_open := false
var selected := 0
var rows: Array[Button] = []
var frame: NinePatchRect
var cursor: Polygon2D

static func start_key(callback: Callable) -> Button:
	var key := UI.button("START", callback)
	key.name = "StartKey"
	key.focus_mode = Control.FOCUS_NONE
	key.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed"]:
		var fill := Color("#234943e8") if state == "normal" else Color("#366752")
		var style := UI.box(fill, Color("#bad9ae"), 5)
		style.set_border_width_all(2)
		key.add_theme_stylebox_override(state, style)
		key.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", PAPER)
	key.position = Vector2(400, 4)
	key.size = Vector2(70, 36)
	return key

func setup(in_center: bool) -> void:
	has_fusion = in_center
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var outside := Button.new()
	outside.name = "MapOutside"
	outside.flat = true
	outside.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed"]:
		outside.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	add_child(outside)
	outside.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outside.pressed.connect(func(): closed.emit())
	add_child(start_key(func(): closed.emit()))
	frame = NinePatchRect.new()
	frame.name = "MenuFrame"
	frame.texture = FRAME
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	frame.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	frame.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_patch_margin(side, 8)
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.position = Vector2(WINDOW_X, WINDOW_Y)
	add_child(frame)
	cursor = Polygon2D.new()
	cursor.color = INK
	cursor.polygon = PackedVector2Array([Vector2(0,0), Vector2(3,0), Vector2(3,2),
		Vector2(5,2), Vector2(5,4), Vector2(7,4), Vector2(7,6), Vector2(5,6),
		Vector2(5,8), Vector2(3,8), Vector2(3,10), Vector2(0,10)])
	cursor.z_index = 1
	frame.add_child(cursor)
	_populate(0)

func _populate(focus_row: int) -> void:
	for b in rows:
		frame.remove_child(b)
		b.queue_free()
	rows.clear()
	var labels: Array = TOOLS.duplicate() if tools_open else MAIN
	if tools_open:
		if unova_memory: labels.append("回忆链接")
		if registered!="":labels.append("快捷道具")
		if has_fusion:
			labels.append("融合")
		labels.append("返回")
	frame.size = Vector2(WINDOW_WIDTH, 16 + labels.size() * ROW_HEIGHT)
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 17)
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color.TRANSPARENT if state in ["normal", "focus"] else Color("#dfefdc")
			style.content_margin_left = 23
			b.add_theme_stylebox_override(state, style)
		for color in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(color, INK)
		b.focus_entered.connect(_show_cursor.bind(i))
		b.pressed.connect(_activate.bind(i))
		rows.append(b)
		UI.place(frame, b, 8, 8 + i * ROW_HEIGHT, WINDOW_WIDTH - 16, ROW_HEIGHT)
	_focus(focus_row)

func _show_cursor(index: int) -> void:
	selected = index
	cursor.position = Vector2(17, 8 + index * ROW_HEIGHT + (ROW_HEIGHT - 10) / 2)

func _focus(index: int) -> void:
	_show_cursor(wrapi(index, 0, rows.size()))
	rows[selected].grab_focus()

func resume() -> void:
	show()
	_focus(selected)

func _activate(index: int) -> void:
	_show_cursor(index)
	var command := rows[index].text
	match command:
		"工具":
			tools_open = true
			_populate(0)
		"返回", "退出菜单":
			handle_back()
		_:
			chosen.emit(command)

func handle_back() -> void:
	if tools_open:
		tools_open = false
		_populate(MAIN.find("工具"))
	else:
		closed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed():
		return
	var key: int = event.keycode if event is InputEventKey else KEY_NONE
	var pad: int = event.button_index if event is InputEventJoypadButton else JOY_BUTTON_INVALID
	if event.is_action_pressed("ui_up", true) or key == KEY_W or pad == JOY_BUTTON_DPAD_UP:
		_focus(selected - 1)
	elif event.is_action_pressed("ui_down", true) or key == KEY_S or pad == JOY_BUTTON_DPAD_DOWN:
		_focus(selected + 1)
	elif event.is_echo():
		return
	elif event.is_action_pressed("ui_cancel") or key == KEY_X or pad == JOY_BUTTON_B:
		handle_back()
	elif pad == JOY_BUTTON_START:
		closed.emit()
	elif event.is_action_pressed("ui_accept") or key == KEY_Z or pad == JOY_BUTTON_A:
		_activate(selected)
	else:
		return
	get_viewport().set_input_as_handled()
