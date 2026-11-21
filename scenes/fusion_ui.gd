extends Control

const TouchScroll := preload("res://core/touch_scroll.gd")

const FusionScript := preload("res://core/fusion.gd")
## 宝可梦中心的融合工坊：合体 / 分离 / 洛托姆家电切换。
## 只负责界面与点击，数据改动都交给 FusionScript，本层改完重新刷一遍列表。

signal closed
signal changed(msg: String)

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)
const GOLD := Color(0.95, 0.82, 0.45)

var party: Array = []
var rows: Control
var scroller: ScrollContainer
var tip: Label
var y := 0

func setup(p_party: Array) -> void:
	party = p_party
	_build()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.07, 0.94)
	add_child(veil)

	var head := Label.new()
	head.position = Vector2(16, 10)
	head.text = "融合工坊"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	var sub := Label.new()
	sub.position = Vector2(16, 30)
	sub.text = "宝可梦中心 · 合体 / 分离 / 洛托姆家电"
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
	tip.text = "合体后可用分离还原，原宝可梦不会丢失"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", DIM)
	add_child(tip)

	_refresh()

func _refresh() -> void:
	for c in rows.get_children():
		c.queue_free()
	y = 0
	var opts: Array = FusionScript.options(party)
	var unf: Array = FusionScript.unfusable(party)

	_section("合体", opts.is_empty() and unf.is_empty())
	if opts.is_empty():
		_note("队伍里没有可以合体的组合（酋雷姆 + 莱希拉姆 / 捷克罗姆，奈克洛兹玛 + 索尔迦雷欧 / 露奈雅拉）")
	for o in opts:
		var ob: Dictionary = o
		var b := _row(String(ob["text"]), MINT)
		var bi := int(ob["base"])
		var pi := int(ob["part"])
		var fk := String(ob["form"])
		b.pressed.connect(func() -> void:
			var nm := FusionScript.fuse(party, bi, pi, fk)
			if nm == "":
				_notify("合体失败")
			else:
				changed.emit("%s 合体完成！" % nm)
			_refresh())
		y += 34

	if not unf.is_empty():
		_section("分离", false)
		for u in unf:
			var ub: Dictionary = u
			var ub2 := _row(String(ub["text"]), GOLD)
			var ui := int(ub["base"])
			ub2.pressed.connect(func() -> void:
				var nm := FusionScript.unfuse(party, ui)
				_notify(nm if nm != "" else "分离失败")
				if nm != "" and not nm.contains("满"):
					changed.emit(nm)
				_refresh())
			y += 34

	_section("形态道具", false)
	_note("洛托姆家电、阿尔宙斯石板、盖诺赛克特卡带、葛拉西蒂亚花、腐朽之剑盾：找中心里的研究员领，给对应宝可梦带上就会变形。")

func _section(title: String, dim: bool) -> void:
	var l := Label.new()
	l.position = Vector2(2, y)
	l.text = title
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM if dim else MINT)
	rows.add_child(l)
	y += 24

func _note(text: String) -> void:
	var l := Label.new()
	l.position = Vector2(8, y)
	l.size = Vector2(size.x - 44, 20)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", DIM)
	rows.add_child(l)
	y += 24

func _row(text: String, color: Color) -> Button:
	var b := Button.new()
	b.position = Vector2(2, y)
	b.size = Vector2(size.x - 44, 28)
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style(b, 12)
	b.add_theme_color_override("font_color", color)
	rows.add_child(b)
	return b

func _notify(msg: String) -> void:
	tip.text = msg

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
