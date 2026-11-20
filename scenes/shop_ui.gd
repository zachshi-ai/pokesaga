extends Control

const TouchScroll := preload("res://core/touch_scroll.gd")
## 商店：读 content/shop.json 的货架，买完直接改背包与金钱。
## 界面只做展示和取值，扣钱/入包都回给外层，避免两处各算一遍。

signal closed
signal bought(item_name: String, price: int, category: String)

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)
const WARN := Color(0.90, 0.45, 0.40)
const GOLD := Color(0.95, 0.82, 0.45)

var goods: Array = []
var money := 0
var rows: Control
var scroller: ScrollContainer
var money_label: Label
var tip: Label

func setup(p_goods: Array, p_money: int) -> void:
	goods = p_goods
	money = p_money
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
	head.text = "商店"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	money_label = Label.new()
	money_label.position = Vector2(size.x - 150, 12)
	money_label.size = Vector2(134, 20)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.add_theme_font_size_override("font_size", 13)
	money_label.add_theme_color_override("font_color", GOLD)
	add_child(money_label)

	# 货架有六七十件，必须能滚，否则下面的树果根本看不到
	scroller = ScrollContainer.new()
	TouchScroll.attach(scroller)
	scroller.position = Vector2(14, 36)
	scroller.size = Vector2(size.x - 28, size.y - 76)
	add_child(scroller)
	rows = Control.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(rows)
	_refresh()

	tip = Label.new()
	tip.position = Vector2(16, size.y - 30)
	tip.text = "点价格即可购买"
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", DIM)
	add_child(tip)

	var close := Button.new()
	close.text = "返回"
	close.position = Vector2(size.x - 78, size.y - 34)
	close.size = Vector2(64, 28)
	_style(close, 12)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

const CAT_ORDER := ["ball", "heal", "battle", "berry", "held", "evo", "tera"]
const CAT_NAME := {"ball": "精灵球", "heal": "伤药", "battle": "战斗道具",
	"berry": "树果", "held": "携带道具", "evo": "进化石", "tera": "太晶"}

func _refresh() -> void:
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	money_label.text = "持有 %d 元" % money

	# 按分类排好再画，一屏里能顺着看下来
	var sorted: Array = goods.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca := CAT_ORDER.find(String(a.get("category", "")))
		var cb := CAT_ORDER.find(String(b.get("category", "")))
		if ca < 0:
			ca = CAT_ORDER.size()
		if cb < 0:
			cb = CAT_ORDER.size()
		return ca < cb)

	var y := 0
	var last_cat := ""
	for i in sorted.size():
		var g: Dictionary = sorted[i]
		var g_idx := goods.find(g)
		var price := int(g.get("price", 0))
		var cat := String(g.get("category", "other"))
		if cat != last_cat:
			last_cat = cat
			var sec := Label.new()
			sec.position = Vector2(0, y + 8)
			sec.size = Vector2(200, 18)
			sec.text = String(CAT_NAME.get(cat, "其他"))
			sec.add_theme_font_size_override("font_size", 11)
			sec.add_theme_color_override("font_color", MINT)
			rows.add_child(sec)
			y += 24

		var name_l := Label.new()
		name_l.position = Vector2(8, y + 6)
		name_l.size = Vector2(170, 20)
		name_l.text = String(g.get("name", "?"))
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.add_theme_color_override("font_color", CREAM)
		rows.add_child(name_l)

		var buy := Button.new()
		buy.position = Vector2(216, y)
		buy.size = Vector2(96, 28)
		buy.text = "%d 元" % price
		_style(buy, 12)
		buy.disabled = money < price
		buy.add_theme_color_override("font_color", GOLD if money >= price else WARN)
		buy.pressed.connect(_buy.bind(g_idx))
		rows.add_child(buy)
		y += 34

	rows.custom_minimum_size = Vector2(0, y)

func _buy(i: int) -> void:
	var g: Dictionary = goods[i]
	var price := int(g.get("price", 0))
	if money < price:
		tip.text = "钱不够。"
		tip.add_theme_color_override("font_color", WARN)
		return
	money -= price
	tip.text = "买了 %s。" % String(g.get("name", "?"))
	tip.add_theme_color_override("font_color", MINT)
	bought.emit(String(g.get("name", "?")), price, String(g.get("category", "other")))
	_refresh()

func _style(c: Control, fs: int) -> void:
	c.add_theme_font_size_override("font_size", fs)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.13, 0.18, 0.96)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.42, 0.78, 0.72, 0.40)
	if c is Button:
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			(c as Button).add_theme_stylebox_override(st, sb)
