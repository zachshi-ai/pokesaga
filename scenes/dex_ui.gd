extends Control

const TouchScroll := preload("res://core/touch_scroll.gd")
## 图鉴界面：按编号排全部物种，没见过只显示编号与问号，见过显示名字，抓到加标记。
## 数据全部来自 content/species.json，加物种不用改这里。

signal closed

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)
const GOLD := Color(0.95, 0.82, 0.45)
const SLOT := Vector2(112, 66)
const COLS := 4

var seen: Array = []
var caught: Array = []
var ids: Array = []
var page := 0
var gen := 1            # 0 = 全国，1 = 关都，2..9 其他世代
const GEN_RANGE := [[1,151],[152,251],[252,386],[387,493],[494,649],[650,721],[722,809],[810,905],[906,1025]]
var grid: Control
var head: Label
var prev_btn: Button
var next_btn: Button

func setup(p_seen: Array, p_caught: Array) -> void:
	seen = p_seen
	caught = p_caught
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

	head = Label.new()
	head.position = Vector2(16, 10)
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	# 世代筛选：1025 只翻页太慢，先按世代缩小范围
	var tabs := Control.new()
	tabs.position = Vector2(14, 30)
	add_child(tabs)
	var labels := ["全国", "关都", "城都", "丰缘", "神奥", "合众", "卡洛斯", "阿罗拉", "伽勒尔", "帕底亚"]
	for i in labels.size():
		var b := Button.new()
		b.text = String(labels[i])
		b.position = Vector2(i * 30, 0)
		b.size = Vector2(28, 20)
		_style(b)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(func() -> void:
			gen = i
			page = 0
			_refresh())
		tabs.add_child(b)

	grid = Control.new()
	grid.position = Vector2(14, 54)
	add_child(grid)

	var close := Button.new()
	close.text = "返回"
	close.position = Vector2(size.x - 78, size.y - 36)
	close.size = Vector2(64, 30)
	_style(close)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

	prev_btn = Button.new()
	prev_btn.text = "‹"
	prev_btn.position = Vector2(size.x - 78, size.y - 70)
	prev_btn.size = Vector2(30, 28)
	_style(prev_btn)
	prev_btn.pressed.connect(func() -> void:
		if page > 0:
			page -= 1
			_refresh())
	add_child(prev_btn)

	next_btn = Button.new()
	next_btn.text = "›"
	next_btn.position = Vector2(size.x - 44, size.y - 70)
	next_btn.size = Vector2(30, 28)
	_style(next_btn)
	next_btn.pressed.connect(func() -> void:
		if (page + 1) * _per_page() < _pool_size():
			page += 1
			_refresh())
	add_child(next_btn)

	ids = Data.species.keys()
	ids.sort()
	_refresh()

func _pool_size() -> int:
	if gen <= 0:
		return ids.size()
	var lo: int = int(GEN_RANGE[gen - 1][0])
	var hi: int = int(GEN_RANGE[gen - 1][1])
	var n := 0
	for sid in ids:
		if int(sid) >= lo and int(sid) <= hi:
			n += 1
	return n

func _per_page() -> int:
	return COLS * 3

func _refresh() -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	var pool: Array = ids
	if gen > 0:
		var lo: int = int(GEN_RANGE[gen - 1][0])
		var hi: int = int(GEN_RANGE[gen - 1][1])
		pool = []
		for sid in ids:
			var n := int(sid)
			if n >= lo and n <= hi:
				pool.append(sid)
	var per := _per_page()
	var start := page * per
	var gen_name := "全部世代"
	if gen > 0:
		gen_name = ["关都", "城都", "丰缘", "神奥", "合众", "卡洛斯", "阿罗拉", "伽勒尔", "帕底亚"][gen - 1] + "地区"
	head.text = "图鉴·%s   见过 %d   抓到 %d / %d" % [gen_name, seen.size(), caught.size(), ids.size()]
	for k in per:
		var idx := start + k
		if idx >= pool.size():
			break
		var sid := int(pool[idx])
		var sp: Dictionary = Data.species_of(sid)
		var b := Button.new()
		b.custom_minimum_size = SLOT
		b.size = SLOT
		b.position = Vector2((k % COLS) * (SLOT.x + 6), (k / COLS) * (SLOT.y + 6))
		_style(b)
		b.clip_text = true
		var known := caught.has(sid)
		var met := seen.has(sid)
		b.text = "No.%03d\n%s%s" % [sid, "" if met else "？", String(sp.get("name", "?")) if met else "？？？"]
		if known:
			b.add_theme_color_override("font_color", GOLD)
		elif met:
			b.add_theme_color_override("font_color", CREAM)
		else:
			b.add_theme_color_override("font_color", DIM)
		b.pressed.connect(_show_detail.bind(sid))
		grid.add_child(b)
	prev_btn.disabled = page <= 0
	next_btn.disabled = (page + 1) * per >= pool.size()

## 详情正文：form_key 为空就是原始形态
func _detail_text(sid: int, form_key: String) -> String:
	var sp: Dictionary = Data.stats_of(sid, form_key)
	if sp.is_empty():
		return "No.%03d\n还没有数据。" % sid
	var base: Dictionary = sp.get("base", {})
	# 特性放在属性下面：面板高度有限，放最后会被裁掉
	var ab_ids: Array = sp.get("abilities", [])
	var ab_txt := ""
	for aid in ab_ids:
		var ad: Dictionary = Data.abilities.get(int(aid), {})
		var an := String(ad.get("name", ""))
		if an == "":
			continue
		var ae: Dictionary = Data.ability_effect(an)
		var d := String(ae.get("desc", ""))
		if d.length() > 12:
			d = d.substr(0, 12) + "…"
		ab_txt += ("／" if ab_txt != "" else "") + an + (("：" + d) if d != "" else "")
	var out := "No.%03d  %s\n属性 %s\n特性 %s\n捕获率 %d\nHP %d  攻击 %d  防御 %d\n特攻 %d  特防 %d  速度 %d" % [
		sid, String(sp.get("name", "?")), "/".join(sp.get("types", [])),
		ab_txt if ab_txt != "" else "—",
		int(sp.get("catch_rate", 0)),
		int(base.get("hp", 0)), int(base.get("atk", 0)), int(base.get("def", 0)),
		int(base.get("spa", 0)), int(base.get("spd", 0)), int(base.get("spe", 0))]
	if form_key != "":
		var f: Dictionary = Data.form_of(sid, form_key)
		if String(f.get("kind", "")) == "gmax":
			out += "\n注：极巨化形态，战斗中血量翻倍"
		elif String(f.get("kind", "")) == "mega":
			out += "\n注：Mega 形态，只能在战斗中进化"
		elif String(f.get("kind", "")) == "regional":
			out += "\n注：地区形态，野生可直接遇到"
	return out

func _show_detail(sid: int) -> void:
	var sp: Dictionary = Data.species_of(sid)
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.07, 0.10, 0.98)
	panel.position = Vector2(40, 60)
	panel.size = Vector2(size.x - 80, size.y - 120)
	add_child(panel)

	var met := seen.has(sid)
	var has_forms := met and not Data.forms_of(sid).is_empty()

	# 正文：给底部形态栏留出 76px，不然文字会被按钮压住
	var t := Label.new()
	t.position = Vector2(14, 12)
	t.size = Vector2(panel.size.x - 28, panel.size.y - (100 if has_forms else 70))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.clip_text = true
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", CREAM)
	if not met:
		t.text = "No.%03d\n还没见过这只。" % sid
	else:
		t.text = _detail_text(sid, "")
	panel.add_child(t)

	# 形态不另开图鉴号：Mega、极巨化、地区形态都从这一只里切
	if has_forms:
		var forms: Array = Data.forms_of(sid)
		var hint := Label.new()
		hint.position = Vector2(14, panel.size.y - 84)
		hint.text = "形态 %d 种（同一图鉴号）" % forms.size()
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", DIM)
		panel.add_child(hint)

		var scroll := ScrollContainer.new()
		TouchScroll.attach(scroll)
		scroll.position = Vector2(12, panel.size.y - 64)
		# 右侧给「关闭」按钮留出位置，别让按钮和滚动条压在一起
		scroll.size = Vector2(panel.size.x - 24 - 74, 32)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		panel.add_child(scroll)

		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 6)
		scroll.add_child(bar)

		var b0 := Button.new()
		b0.text = "原始"
		b0.custom_minimum_size = Vector2(52, 28)
		_style(b0)
		b0.pressed.connect(func() -> void: t.text = _detail_text(sid, ""))
		bar.add_child(b0)
		for f in forms:
			if not (f is Dictionary):
				continue
			var fk := String(f.get("key", ""))
			var label := String(f.get("label", ""))
			if label == "":
				continue
			var fb := Button.new()
			fb.text = label
			fb.custom_minimum_size = Vector2(maxf(52, 15 * label.length()), 28)
			_style(fb)
			fb.pressed.connect(func() -> void: t.text = _detail_text(sid, fk))
			bar.add_child(fb)

	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(panel.size.x - 72, panel.size.y - 40)
	close.size = Vector2(60, 28)
	_style(close)
	close.pressed.connect(func() -> void: panel.queue_free())
	panel.add_child(close)

func _style(b: Button) -> void:
	b.add_theme_font_size_override("font_size", 11)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.13, 0.18, 0.94)
	sb.set_corner_radius_all(6)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.42, 0.78, 0.72, 0.40)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
