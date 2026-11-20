extends Control

const TouchScroll := preload("res://core/touch_scroll.gd")
## 宝可梦中心的道具台：领改变形态用的道具（家电、石板、卡带、花、武器）。
## 拿到后到队伍里给对应宝可梦带上，形态当场就变。

signal closed
signal give(item_name: String, item_key: String)

const FusionScript := preload("res://core/fusion.gd")

const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)

var rows: Control
var scroller: ScrollContainer
var tip: Label
var y := 0

func setup(_npc: Dictionary = {}) -> void:
	_build()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport_rect().size
	if vp.x < 10:
		vp = Vector2(480, 320)
	size = vp

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.07, 0.94)
	add_child(veil)

	var head := Label.new()
	head.position = Vector2(16, 10)
	head.text = "形态道具台"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	var sub := Label.new()
	sub.position = Vector2(16, 30)
	sub.text = "领了给宝可梦带上，形态当场就变"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", DIM)
	add_child(sub)

	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(size.x - 66, 10)
	close.size = Vector2(54, 22)
	_style(close, 11)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

	scroller = ScrollContainer.new()
	TouchScroll.attach(scroller)
	scroller.position = Vector2(14, 50)
	scroller.size = Vector2(size.x - 28, size.y - 86)
	add_child(scroller)
	rows = Control.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(rows)

	tip = Label.new()
	tip.position = Vector2(16, size.y - 30)
	tip.text = "道具不占钱，随便领"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", DIM)
	add_child(tip)

	_refresh()

func _refresh() -> void:
	for c in rows.get_children():
		c.queue_free()
	y = 0
	for row in FusionScript.ITEM_FORMS:
		var key := String((row as Array)[0])
		var sid := int((row as Array)[1])
		var item_name := Data.item_name(key)
		var form_key := FusionScript.form_for_item(sid, key)
		var form_label := String((Data.form_of(sid, form_key) as Dictionary).get("label", ""))
		var who := String(Data.species_of(sid).get("name", "?"))
		var b := Button.new()
		b.position = Vector2(2, y)
		b.size = Vector2(size.x - 44, 28)
		b.text = "%s   →  %s（%s）" % [item_name, who, form_label]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_style(b, 12)
		b.add_theme_color_override("font_color", CREAM)
		var nm := item_name
		var kk := key
		b.pressed.connect(func() -> void:
			give.emit(nm, kk)
			tip.text = "拿到了 %s" % nm)
		rows.add_child(b)
		y += 32

func _style(b: Button, fs: int) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.13, 0.18, 0.90)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.42, 0.78, 0.72, 0.40)
	var sbh: StyleBoxFlat = sb.duplicate()
	sbh.bg_color = Color(0.14, 0.20, 0.26, 0.94)
	var sbp: StyleBoxFlat = sb.duplicate()
	sbp.bg_color = Color(0.42, 0.80, 0.72, 0.92)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sbh)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_size_override("font_size", fs)
