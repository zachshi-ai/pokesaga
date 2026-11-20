extends Control
## 背包：分类列表 + 数量。道具数据来自 content/items.json，界面不写死任何道具。

signal closed

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)

## 分类顺序固定，新增分类只加一行；树果、携带道具、进化石、太晶碎块都是能用的东西，不能再藏起来
const CATEGORIES := [
	["ball", "精灵球"], ["heal", "伤药"], ["battle", "战斗"],
	["berry", "树果"], ["held", "携带"], ["evo", "进化石"], ["tera", "太晶"], ["other", "其他"],
]

var items: Array = []
var row_box: Control
var scroller: ScrollContainer
var tab_buttons: Array = []
var cur_cat := "heal"
## 点某一行时回调（TM/HM 用来学招式，药水用来回复），不接就只是看
var on_use: Callable = Callable()

func setup(p_items: Array) -> void:
	items = p_items
	_build()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport_rect().size
	if vp.x < 10:
		vp = Vector2(480, 320)
	size = vp

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.07, 0.92)
	add_child(veil)

	var head := Label.new()
	head.position = Vector2(16, 10)
	head.text = "背包"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	var x := 52
	var i := 0
	for pair in CATEGORIES:
		var key := String(pair[0])
		var b := Button.new()
		b.text = String(pair[1])
		b.position = Vector2(x + i * 52, 8)
		b.size = Vector2(50, 26)
		b.set_meta("cat", key)
		_style(b, key == cur_cat)
		b.pressed.connect(_switch.bind(key))
		add_child(b)
		tab_buttons.append(b)
		i += 1

	# 树果二十多种，一屏放不下，列表要能滚
	scroller = ScrollContainer.new()
	scroller.position = Vector2(14, 44)
	scroller.size = Vector2(size.x - 28, size.y - 84)
	add_child(scroller)
	row_box = Control.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(row_box)

	close_btn()
	_refresh()

func close_btn() -> void:
	var close := Button.new()
	close.text = "返回"
	close.position = Vector2(size.x - 76, size.y - 40)
	close.size = Vector2(64, 30)
	_style(close)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

	var hint := Label.new()
	hint.position = Vector2(16, size.y - 34)
	hint.text = "数量为 0 的道具不显示"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", DIM)
	add_child(hint)

func _style(b: Button, active := false) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.24, 0.28, 0.98) if active else INK
		if st == "hover":
			sb.bg_color = Color(0.12, 0.19, 0.25, 0.98)
		sb.set_corner_radius_all(7)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.5 if active else 0.28)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_font_size_override("font_size", 10)

func _switch(cat: String) -> void:
	cur_cat = cat
	for b in tab_buttons:
		_style(b, String(b.get_meta("cat")) == cat)
	_refresh()

## 外面用掉一件东西后调一下，数量立刻变
func refresh() -> void:
	_refresh()

func _refresh() -> void:
	for c in row_box.get_children():
		row_box.remove_child(c)
		c.queue_free()
	var y := 0
	for it in items:
		if String(it.get("category", "other")) != cur_cat:
			continue
		var count := int(it.get("count", 0))
		if count <= 0:
			continue
		var row := Panel.new()
		row.position = Vector2(0, y)
		row.size = Vector2(size.x - 44, 30)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.13, 0.18, 0.92)
		sb.set_corner_radius_all(6)
		row.add_theme_stylebox_override("panel", sb)
		row_box.add_child(row)

		var nm := Label.new()
		nm.position = Vector2(10, 6)
		nm.text = String(it.get("name", "?"))
		nm.add_theme_font_size_override("font_size", 13)
		nm.add_theme_color_override("font_color", CREAM)
		row.add_child(nm)

		var ct := Label.new()
		ct.position = Vector2(size.x - 92, 6)
		ct.text = "×%d" % count
		ct.add_theme_font_size_override("font_size", 13)
		ct.add_theme_color_override("font_color", MINT)
		row.add_child(ct)
		# 整行做成可点的透明按钮：手机上点一下就能用，不用去找小按钮
		var hit := Button.new()
		hit.flat = true
		hit.position = Vector2.ZERO
		hit.size = row.size
		hit.focus_mode = Control.FOCUS_NONE
		hit.pressed.connect(func() -> void:
			if on_use.is_valid():
				on_use.call(String(it.get("name", ""))))
		row.add_child(hit)
		y += 34
	row_box.custom_minimum_size = Vector2(0, y)
