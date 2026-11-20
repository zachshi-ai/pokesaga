extends Control
## 对话框：原版 GBA 那种贴在屏幕下方的窗口。
## 一次可以排队几句，按 A / 点窗口往下翻；带「是 / 否」时可以就地选。
## 只负责显示与选值，治疗、购买这些后果都回给调用方。

signal closed
signal answered(yes: bool)

const INK := Color(0.05, 0.08, 0.13, 0.97)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.96, 0.97, 0.94)
const DIM := Color(0.62, 0.68, 0.70)

var lines: Array = []
var index := 0
var speaker := ""
var ask_mode := false
var ask_yes := "是"
var ask_no := "否"
var body: Label
var hint: Label
var box: Panel
var btn_yes: Button
var btn_no: Button
var _speaker_label: Label = null
var _chars := 0
var _full := ""
var _typing := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()

func _build() -> void:

	box = Panel.new()
	box.position = Vector2(8, size.y - 130)
	box.size = Vector2(size.x - 16, 92)
	# 用原版的窗口九宫格：绿宝石那种深蓝底 + 白边 + 圆角，
	# 自己画矩形永远不像，直接贴原图
	box.add_theme_stylebox_override("panel", _window_style(3))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.gui_input.connect(_on_input)
	add_child(box)

	# 名牌：压在对话框上沿的一小块，比单纯一行字更像原版
	var plate_panel := Panel.new()
	plate_panel.position = Vector2(14, -14)
	plate_panel.size = Vector2(84, 26)
	plate_panel.add_theme_stylebox_override("panel", _window_style(1))
	plate_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(plate_panel)

	var name_plate := Label.new()
	_speaker_label = name_plate
	name_plate.position = Vector2(0, 3)
	name_plate.size = Vector2(84, 20)
	name_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_plate.add_theme_font_size_override("font_size", 12)
	name_plate.add_theme_color_override("font_color", Color(0.18, 0.24, 0.45))
	name_plate.text = speaker
	name_plate.name = "Speaker"
	name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate_panel.add_child(name_plate)

	body = Label.new()
	body.position = Vector2(18, 20)
	body.size = Vector2(box.size.x - 40, 60)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_constant_override("line_spacing", 4)
	body.add_theme_color_override("font_color", Color(0.10, 0.13, 0.22))
	box.add_child(body)

	hint = Label.new()
	hint.position = Vector2(box.size.x - 34, box.size.y - 26)
	hint.size = Vector2(24, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.text = "▼"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.25, 0.30, 0.45))
	box.add_child(hint)

	btn_yes = _mk_button(ask_yes, Vector2(box.size.x - 138, 12))
	btn_yes.pressed.connect(func() -> void: _pick(true))
	btn_no = _mk_button(ask_no, Vector2(box.size.x - 138, 50))
	btn_no.pressed.connect(func() -> void: _pick(false))
	btn_yes.visible = false
	btn_no.visible = false

## 原版窗口贴图做成九宫格；8 像素切边和游戏里一致
func _window_style(variant := 2) -> StyleBox:
	var path := "res://assets/ui/window_%d.png" % variant
	if not ResourceLoader.exists(path):
		var f := StyleBoxFlat.new()
		f.bg_color = INK
		f.set_corner_radius_all(8)
		return f
	var st := StyleBoxTexture.new()
	st.texture = load(path)
	st.texture_margin_left = 8
	st.texture_margin_top = 8
	st.texture_margin_right = 8
	st.texture_margin_bottom = 8
	st.content_margin_left = 12
	st.content_margin_top = 10
	st.content_margin_right = 12
	st.content_margin_bottom = 10
	# 像素风不许插值，否则边角会糊
	st.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return st

func _mk_button(txt: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = txt
	b.position = pos
	b.size = Vector2(62, 30)
	b.add_theme_font_size_override("font_size", 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.16, 0.21, 0.96)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.42, 0.78, 0.72, 0.55)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.42, 0.80, 0.72, 0.85)
	sbp.content_margin_top = 3
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_pressed_color", Color(0.04, 0.10, 0.10, 1))
	box.add_child(b)
	return b

## lines 里的每一项要么是字符串，要么是 {"who": "护士", "text": "……"}
func setup(p_lines: Array, p_speaker := "") -> void:
	modulate = Color(1, 1, 1, 0)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1, 1), 0.12)
	lines = p_lines
	speaker = p_speaker
	index = 0
	if _speaker_label:
		_speaker_label.text = speaker
	_show_line()

## 末尾追加一个「是 / 否」，选完发 answered
func ask(yes_text := "是", no_text := "否") -> void:
	ask_mode = true
	ask_yes = yes_text
	ask_no = no_text
	if btn_yes:
		btn_yes.text = ask_yes
		btn_no.text = ask_no
		btn_yes.visible = true
		btn_no.visible = true
	if body:
		body.size = Vector2(box.size.x - 160, 60)
	if hint:
		hint.text = ""

func _show_line() -> void:
	if index >= lines.size():
		_close()
		return
	var raw = lines[index]
	var txt := ""
	if raw is Dictionary:
		var d: Dictionary = raw
		txt = String(d.get("text", ""))
		if d.has("who"):
			speaker = String(d["who"])
			if _speaker_label:
				_speaker_label.text = speaker
	else:
		txt = String(raw)
	_full = txt
	_chars = 0
	_typing = true
	body.text = ""
	index += 1

## A 键 / 点窗口：先把这句显示完，再翻下一句
func advance() -> void:
	# 正在逐字显示时，按 A 先把这句放完（哪怕是最后一句、正在等选择）
	if _typing:
		_typing = false
		_chars = _full.length()
		body.text = _full
		return
	if ask_mode and index >= lines.size():
		return
	if index < lines.size():
		_show_line()
	else:
		_close()

func is_waiting_answer() -> bool:
	return ask_mode and index >= lines.size() and not _typing

func _pick(yes: bool) -> void:
	if not ask_mode:
		return
	ask_mode = false
	answered.emit(yes)
	_close()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		advance()

var _blink := 0.0

func _process(delta: float) -> void:
	# 右下角的小三角闪一下，提示可以继续
	_blink += delta
	if hint and hint.visible:
		hint.modulate = Color(1, 1, 1, 0.45 + 0.55 * absf(sin(_blink * 3.2)))
	if _typing:
		_chars = mini(_chars + int(delta * 90.0) + 1, _full.length())
		body.text = _full.substr(0, _chars)
		if _chars >= _full.length():
			_typing = false
			if ask_mode and btn_yes:
				btn_yes.visible = true
				btn_no.visible = true
				hint.text = ""

func _close() -> void:
	closed.emit()
	queue_free()
