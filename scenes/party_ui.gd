extends Control

const TouchScroll := preload("res://core/touch_scroll.gd")

const Growth := preload("res://core/growth.gd")
## 队伍界面：12 格一屏（4 行 × 3 列），点击看摘要。
## 数据来自 core/party.gd，跨地区通用，不做地区分支。

signal closed
signal evolve_with(slot: int, item_name: String)   # 用道具进化
signal tera_change(slot: int, tera_type: String)   # 用太晶碎块改太晶属性
signal held_change(slot: int, held_key: String, item_name: String)   # 换携带道具

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)
const SLOT := Vector2(214, 40)

var party: Array = []
var bag: Array = []
var detail: Control
var list: Control

func setup(p_party: Array, p_bag: Array = []) -> void:
	party = p_party
	bag = p_bag
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
	head.text = "队伍  %d / 12" % _filled()
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	list = Control.new()
	list.position = Vector2(14, 30)
	add_child(list)

	for i in 12:
		var b := Button.new()
		b.custom_minimum_size = SLOT
		b.size = SLOT
		b.position = Vector2((i % 2) * (SLOT.x + 10), (i / 2) * (SLOT.y + 4))
		_style(b)
		if i < party.size() and party[i] is Dictionary and not (party[i] as Dictionary).is_empty():
			var m: Dictionary = party[i]
			var tag := "★ " if bool(m.get("shiny", false)) else ""
			b.text = "%2d. %s%s   Lv%d   %s" % [i + 1, tag, String(m.get("name", "?")),
				int(m.get("level", 1)), String(m.get("hp_text", ""))]
			b.pressed.connect(_open_detail.bind(i))
		else:
			b.text = "%2d. —" % (i + 1)
			b.disabled = true
		list.add_child(b)

	var close := Button.new()
	close.text = "返回"
	close.position = Vector2(size.x - 78, size.y - 36)
	close.size = Vector2(64, 30)
	_style(close)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

	var hint := Label.new()
	hint.position = Vector2(16, size.y - 30)
	hint.text = "点击查看详细数值"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", DIM)
	add_child(hint)

func _filled() -> int:
	var n := 0
	for m in party:
		if m is Dictionary and not (m as Dictionary).is_empty():
			n += 1
	return n

func _style(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = INK if st == "normal" else Color(0.12, 0.19, 0.25, 0.98)
		if st == "disabled":
			sb.bg_color = Color(0.08, 0.10, 0.14, 0.7)
		sb.set_corner_radius_all(9)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.35)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_disabled_color", DIM)
	b.add_theme_font_size_override("font_size", 13)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT

## 道具进化：有石头就能当场进化，没有就告诉玩家还差什么
func _add_evolve_row(m: Dictionary, slot: int) -> void:
	var list2: Array = Growth.item_evolutions(m)
	if list2.is_empty():
		return
	for e in list2:
		var key := String((e as Dictionary).get("item", ""))
		var iname := Data.evo_item_name(key)
		var have := 0
		for it in bag:
			if it is Dictionary and String((it as Dictionary).get("name", "")) == iname:
				have = int(it.get("count", 0))
				break
		if have > 0:
			var b := Button.new()
			b.text = "用 %s 进化" % iname
			b.position = Vector2(12, 214)
			b.size = Vector2(150, 28)
			_style(b)
			b.pressed.connect(func() -> void:
				_confirm_evolve(m, slot, iname, String((e as Dictionary).get("to", 0)),
					String((e as Dictionary).get("form", ""))))
			detail.add_child(b)
			return
		else:
			var tip := Label.new()
			tip.text = "还差 %s 才能进化" % iname
			tip.position = Vector2(12, 220)
			tip.add_theme_font_size_override("font_size", 11)
			tip.add_theme_color_override("font_color", DIM)
			detail.add_child(tip)
			return

## 进化前先问一句：点错了不至于把形态走歪
func _confirm_evolve(m: Dictionary, slot: int, item_name: String, to_id: String, to_form: String) -> void:
	var box := Panel.new()
	box.position = Vector2(20, 96)
	box.size = Vector2(size.x - 40, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.99)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1.0, 0.85, 0.45, 0.8)
	box.add_theme_stylebox_override("panel", sb)
	add_child(box)

	var target := Data.stats_of(int(to_id), to_form)
	var q := Label.new()
	q.position = Vector2(14, 12)
	q.size = Vector2(box.size.x - 28, 48)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.text = "要让 %s 进化成 %s 吗？\n会消耗 1 个 %s。" % [String(m.get("name", "?")),
		String(target.get("name", "?")), item_name]
	q.add_theme_font_size_override("font_size", 13)
	q.add_theme_color_override("font_color", CREAM)
	box.add_child(q)

	var yes := Button.new()
	yes.text = "确认进化"
	yes.position = Vector2(14, 72)
	yes.size = Vector2(130, 30)
	_style(yes)
	yes.pressed.connect(func() -> void:
		box.queue_free()
		evolve_with.emit(slot, item_name)
		if detail:
			detail.queue_free()
			detail = null)
	box.add_child(yes)

	var no := Button.new()
	no.text = "再想想"
	no.position = Vector2(box.size.x - 144, 72)
	no.size = Vector2(130, 30)
	_style(no)
	no.pressed.connect(func() -> void: box.queue_free())
	box.add_child(no)

## 太晶属性：有碎块就能改
func _add_tera_row(m: Dictionary, slot: int) -> void:
	var cur := String(m.get("tera_type", ""))
	if cur == "":
		cur = String((m.get("types", ["normal"]) as Array)[0])
	var owned: Array = []
	for it in bag:
		if it is Dictionary:
			var nm := String((it as Dictionary).get("name", ""))
			if nm.begins_with("太晶碎块"):
				if int((it as Dictionary).get("count", 0)) > 0:
					owned.append(String((it as Dictionary).get("tera", "")))
	var b := Button.new()
	b.text = "改太晶属性  （%s）" % Data.type_name(cur)
	b.position = Vector2(12, 246)
	b.size = Vector2(200, 28)
	_style(b)
	if owned.is_empty():
		b.disabled = true
		b.tooltip_text = "没有太晶碎块"
	else:
		b.pressed.connect(func() -> void: _pick_tera(m, slot, owned))
	detail.add_child(b)

func _pick_tera(m: Dictionary, slot: int, owned: Array) -> void:
	var picker := Panel.new()
	picker.position = Vector2(10, 40)
	picker.size = Vector2(size.x - 20, 210)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.99)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.7)
	picker.add_theme_stylebox_override("panel", sb)
	add_child(picker)

	var head := Label.new()
	head.position = Vector2(12, 8)
	head.text = "选一个太晶属性（消耗 1 个碎块）"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", MINT)
	picker.add_child(head)

	var i := 0
	for ty in owned:
		var tb := Button.new()
		tb.text = Data.type_name(String(ty))
		tb.position = Vector2(12 + (i % 4) * 78, 32 + (i / 4) * 32)
		tb.size = Vector2(74, 28)
		_style(tb)
		tb.pressed.connect(func() -> void:
			picker.queue_free()
			tera_change.emit(slot, String(ty))
			if detail:
				detail.queue_free()
				detail = null)
		picker.add_child(tb)
		i += 1

	var no := Button.new()
	no.text = "取消"
	no.position = Vector2(picker.size.x - 80, 8)
	no.size = Vector2(66, 24)
	_style(no)
	no.pressed.connect(func() -> void: picker.queue_free())
	picker.add_child(no)

## 携带道具：从背包里挑一个给这只宝可梦带上（道具与树果共用这一格，身上只带一样）
func _add_held_row(m: Dictionary, slot: int) -> void:
	var owned: Array = []
	for it in bag:
		if it is Dictionary:
			var d: Dictionary = it
			var cat := String(d.get("category", ""))
			if int(d.get("count", 0)) <= 0:
				continue
			if cat == "held":
				owned.append({"key": String(d.get("held", "")), "name": String(d.get("name", ""))})
			elif cat == "berry":
				owned.append({"key": "berry:" + String(d.get("berry", "")),
					"name": String(d.get("name", "")), "berry": true})
	var cur := String(m.get("held", ""))
	var cur_berry := String(m.get("berry", ""))
	var cur_name := "无"
	if cur != "":
		cur_name = Data.item_name(cur)
	elif cur_berry != "":
		cur_name = "树果·" + Data.berry_name(cur_berry)
	var b := Button.new()
	b.text = "携带物品  （%s）" % cur_name
	b.position = Vector2(12, 278)
	b.size = Vector2(200, 26)
	_style(b)
	if owned.is_empty():
		b.disabled = true
		b.tooltip_text = "背包里没有可携带的道具或树果"
	else:
		b.pressed.connect(func() -> void: _pick_held(m, slot, owned))
	detail.add_child(b)

func _pick_held(m: Dictionary, slot: int, owned: Array) -> void:
	var picker := Panel.new()
	picker.position = Vector2(8, 34)
	picker.size = Vector2(size.x - 16, 260)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.08, 0.12, 0.99)
	sb.set_corner_radius_all(10)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.7)
	picker.add_theme_stylebox_override("panel", sb)
	add_child(picker)

	var head := Label.new()
	head.position = Vector2(10, 6)
	head.text = "选一个携带物品（道具与树果只能带一样）"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", MINT)
	picker.add_child(head)

	# 道具加树果几十种，一屏放不下，这里用滚动列表
	var sc := ScrollContainer.new()
	TouchScroll.attach(sc)
	sc.position = Vector2(8, 26)
	sc.size = Vector2(picker.size.x - 16, picker.size.y - 58)
	picker.add_child(sc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)

	for it in owned:
		var d: Dictionary = it
		var tb := Button.new()
		tb.text = String(d["name"])
		tb.custom_minimum_size = Vector2(sc.size.x - 24, 26)
		_style(tb)
		var key := String(d["key"])
		var nm := String(d["name"])
		tb.pressed.connect(func() -> void:
			picker.queue_free()
			held_change.emit(slot, key, nm))
		box.add_child(tb)

	var no := Button.new()
	no.text = "取下"
	no.position = Vector2(picker.size.x - 70, 6)
	no.size = Vector2(62, 22)
	_style(no)
	no.pressed.connect(func() -> void:
		picker.queue_free()
		held_change.emit(slot, "", ""))
	picker.add_child(no)

func _open_detail(i: int) -> void:
	if detail:
		detail.queue_free()
	var m: Dictionary = party[i]

	detail = Panel.new()
	detail.position = Vector2(size.x * 0.5 - 160, size.y * 0.5 - 146)
	detail.size = Vector2(320, 292)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.14, 0.99)
	sb.set_corner_radius_all(12)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.6)
	detail.add_theme_stylebox_override("panel", sb)
	add_child(detail)

	var icon := TextureRect.new()
	icon.texture = load(Data.party_hd_path(int(m.get("species_id", 143))))
	icon.position = Vector2(10, 10)
	icon.size = Vector2(96, 96)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail.add_child(icon)

	var t := Label.new()
	t.position = Vector2(86, 14)
	t.size = Vector2(222, 190)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", 12)
	t.add_theme_color_override("font_color", CREAM)
	var stats: Dictionary = m.get("stats", {})
	var grow := String(Data.species_of(int(m.get("species_id", 0))).get("growth", "medium_fast"))
	var lv := int(m.get("level", 1))
	var need := Growth.exp_for_level(lv + 1, grow)
	var cur := int(m.get("exp", 0))
	var exp_line := "经验 %d/%d" % [cur, need] if lv < Growth.MAX_LEVEL else "经验 已满级"
	var abil := String(m.get("ability_name", ""))
	var abil_desc := ""
	if abil != "":
		abil_desc = String(Data.ability_effect(abil).get("desc", ""))
	if abil == "":
		var ids2: Array = Data.species_of(int(m.get("species_id", 0))).get("abilities", [])
		if not ids2.is_empty():
			abil = String((Data.abilities.get(int(ids2[0]), {}) as Dictionary).get("name", ""))
	var move_names: Array = []
	for mid in m.get("moves", []):
		var mv: Dictionary = Data.move_of(int(mid))
		if not mv.is_empty():
			move_names.append(String(mv.get("name", "?")))
	var tera := String(m.get("tera_type", ""))
	if tera == "":
		tera = String((m.get("types", ["normal"]) as Array)[0])
	var berry := String(m.get("berry", ""))
	t.text = "%s  Lv%d\n属性 %s\n体力 %s\n攻击 %d  防御 %d\n特攻 %d  特防 %d\n速度 %d\n特性 %s\n性格 %s\n%s\n太晶 %s%s\n招式 %s" % [
		String(m.get("name", "?")), int(m.get("level", 1)),
		"/".join(PackedStringArray(m.get("types", []))),
		String(m.get("hp_text", "-")),
		int(stats.get("atk", 0)), int(stats.get("def", 0)),
		int(stats.get("spa", 0)), int(stats.get("spd", 0)),
		int(stats.get("spe", 0)),
		(abil + ("：" + abil_desc if abil_desc != "" else "")) if abil != "" else "—",
		String(m.get("nature", "坦率")), exp_line, Data.type_name(tera),
		("  树果 %s" % Data.berry_name(berry)) if berry != "" else "",
		"、".join(PackedStringArray(move_names)) if not move_names.is_empty() else "—"]
	detail.add_child(t)

	_add_evolve_row(m, i)
	_add_tera_row(m, i)
	_add_held_row(m, i)

	var close := Button.new()
	close.text = "关"
	close.position = Vector2(278, 12)
	close.size = Vector2(30, 26)
	_style(close)
	close.pressed.connect(func() -> void:
		detail.queue_free()
		detail = null)
	detail.add_child(close)
