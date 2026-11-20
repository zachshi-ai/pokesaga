extends Control

const PartyScript := preload("res://core/party.gd")
const TouchScroll := preload("res://core/touch_scroll.gd")
## 修改器：队伍 / 道具 / 种族值三页，改完直接写存档。
## 这里只动 save_data，不碰渲染与战斗逻辑；退出菜单后世界读到的就是改后的数据。

signal closed
signal changed   # 有改动，外面负责存档

const INK := Color(0.06, 0.09, 0.13, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.60, 0.66, 0.68)
const WARN := Color(0.90, 0.45, 0.40)
const TAB_W := 76

var party: Array = []
var bag: Array = []
var overrides: Dictionary = {}

var tab := "party"
var slot := 0
var body: Control
var scroller: ScrollContainer
var tab_buttons: Array = []
var species_ids: Array = []
var move_ids: Array = []

var team_list: Control
var editor: Control
var base_page := 0

func setup(p_party: Array, p_bag: Array, p_overrides: Dictionary) -> void:
	party = p_party
	bag = p_bag
	overrides = p_overrides
	species_ids = Data.species.keys()
	species_ids.sort()
	move_ids = Data.moves.keys()
	move_ids.sort()
	_build()

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var vp := get_viewport_rect().size
	if vp.x < 10:
		vp = Vector2(480, 320)
	size = vp

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.07, 0.96)
	add_child(veil)

	var head := Label.new()
	head.position = Vector2(16, 12)
	head.text = "修改器"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", MINT)
	add_child(head)

	var tabs := ["队伍", "道具", "种族值"]
	for i in tabs.size():
		var b := Button.new()
		b.text = tabs[i]
		b.position = Vector2(80 + i * (TAB_W + 6), 10)
		b.size = Vector2(TAB_W, 24)
		_style(b, 12)
		b.pressed.connect(_switch.bind(String(tabs[i])))
		add_child(b)
		tab_buttons.append(b)

	# 内容放进滚动容器：手指从菜单上方往下拖不会再把通知栏拉下来
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 42)
	scroll.size = Vector2(size.x, maxf(80.0, size.y - 42 - 40))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	TouchScroll.attach(scroll)
	add_child(scroll)
	scroller = scroll
	# 手机上再给一对上下翻页按钮：拖动偶尔会被系统手势抢走，按钮不会
	TouchScroll.attach_arrows(self, scroll)

	body = Control.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	var close := Button.new()
	close.text = "完成"
	close.position = Vector2(size.x - 76, size.y - 32)
	close.size = Vector2(62, 26)
	_style(close, 12)
	close.pressed.connect(func() -> void:
		closed.emit()
		queue_free())
	add_child(close)

	_switch("party")

## 内容有多高就让 body 有多高，ScrollContainer 才知道能滚多少
func _fit_body() -> void:
	if body == null:
		return
	var bottom := 0.0
	for c in body.get_children():
		if c is Control:
			var ctl := c as Control
			bottom = maxf(bottom, ctl.position.y + ctl.size.y + 12.0)
	body.custom_minimum_size = Vector2(size.x, maxf(bottom, 10.0))
	# 列表里的按钮别把手指拖动吃掉，不然压着按钮往下拖就没反应
	TouchScroll.relax(body)


func _switch(name: String) -> void:
	tab = name
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	match name:
		"party":
			_build_party()
		"bag":
			_build_bag()
		"base":
			_build_base()
	_fit_body()
	for i in tab_buttons.size():
		var b: Button = tab_buttons[i]
		if i == ["party", "bag", "base"].find(name):
			b.add_theme_color_override("font_color", MINT)
		else:
			b.add_theme_color_override("font_color", DIM)

# ---------------- 队伍 ----------------

func _build_party() -> void:
	team_list = Control.new()
	team_list.position = Vector2(10, 0)
	body.add_child(team_list)
	for i in 12:
		var b := Button.new()
		b.position = Vector2(0, i * 23)
		b.size = Vector2(186, 21)
		_style(b, 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var m: Variant = party[i] if i < party.size() else {}
		if m is Dictionary and not (m as Dictionary).is_empty():
			b.text = "%2d. %s Lv%d" % [i + 1, String(m.get("name", "?")), int(m.get("level", 1))]
		else:
			b.text = "%2d. 空" % (i + 1)
			b.add_theme_color_override("font_color", DIM)
		if i == slot:
			b.add_theme_color_override("font_color", MINT)
		b.pressed.connect(func() -> void:
			slot = i
			_refresh_party())
		team_list.add_child(b)

	editor = Control.new()
	editor.position = Vector2(202, 0)
	body.add_child(editor)
	_render_editor()

func _refresh_party() -> void:
	_build_party_into()

func _build_party_into() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_build_party()

func _render_editor() -> void:
	for c in editor.get_children():
		editor.remove_child(c)
		c.queue_free()
	var m: Variant = party[slot] if slot < party.size() else {}
	var filled: bool = m is Dictionary and not (m as Dictionary).is_empty()

	var sp_pick := OptionButton.new()
	sp_pick.position = Vector2(0, 0)
	sp_pick.size = Vector2(258, 26)
	_style(sp_pick, 11)
	for sid in species_ids:
		var sp: Dictionary = Data.species_of(int(sid))
		sp_pick.add_item("No.%03d %s" % [int(sid), String(sp.get("name", "?"))], int(sid))
	if filled:
		var idx: int = species_ids.find(int(m.get("species_id", 1)))
		sp_pick.selected = max(0, idx)
	sp_pick.item_selected.connect(func(i: int) -> void:
		var sid: int = int(species_ids[i])
		if not filled:
			party[slot] = PartyScript.make(sid, 5, _default_moves(sid))
		else:
			m["species_id"] = sid
			m["form"] = ""
			var sp: Dictionary = Data.stats_of(sid, "")
			m["name"] = String(sp.get("name", "?"))
			m["types"] = sp.get("types", [])
			if (m.get("moves", []) as Array).is_empty():
				m["moves"] = _default_moves(sid)
				m["pp"] = _pps_of(m["moves"])
			PartyScript.recalc(m)
		_touch()
		_build_party_into())
	editor.add_child(sp_pick)

	if filled:
		# Mega / 极巨化是战斗里的变化，不能当常规形态存进队伍；这里只放地区形态与外观形态
		var forms: Array = []
		for f in Data.forms_of(int(m.get("species_id", 0))):
			if f is Dictionary and String((f as Dictionary).get("kind", "")) not in ["mega", "gmax"] and not bool((f as Dictionary).get("battle", false)):
				forms.append(f)
		var fp := OptionButton.new()
		fp.position = Vector2(0, 30)
		fp.size = Vector2(258, 26)
		_style(fp, 11)
		fp.add_item("— 默认形态 —", 0)
		for f in forms:
			if f is Dictionary:
				fp.add_item("形态：%s" % String((f as Dictionary).get("label", "?")), fp.item_count)
		var cur := String(m.get("form", ""))
		for i in fp.item_count:
			if i > 0 and String((forms[i - 1] as Dictionary).get("key", "")) == cur:
				fp.selected = i
		if forms.is_empty():
			fp.selected = 0
		fp.item_selected.connect(func(sel: int) -> void:
			var key := "" if sel == 0 else String((forms[sel - 1] as Dictionary).get("key", ""))
			PartyScript.set_form(m, key)
			_touch()
			_build_party_into())
		editor.add_child(fp)

	if not filled:
		var tip := Label.new()
		tip.position = Vector2(0, 34)
		tip.text = "选一个物种就会创建一个新成员。"
		tip.add_theme_font_size_override("font_size", 11)
		tip.add_theme_color_override("font_color", DIM)
		editor.add_child(tip)
		return

	var lv := SpinBox.new()
	lv.position = Vector2(0, 58)
	lv.size = Vector2(92, 26)
	lv.min_value = 1
	lv.max_value = 100
	lv.value = int(m.get("level", 5))
	lv.value_changed.connect(func(v: float) -> void:
		m["level"] = int(v)
		PartyScript.recalc(m, true)
		_touch()
		_build_party_into())
	editor.add_child(lv)

	var lbl := Label.new()
	lbl.position = Vector2(98, 62)
	lbl.text = "等级"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", CREAM)
	editor.add_child(lbl)

	var heal := Button.new()
	heal.text = "满血"
	heal.position = Vector2(136, 58)
	heal.size = Vector2(54, 26)
	_style(heal, 11)
	heal.pressed.connect(func() -> void:
		m["hp"] = int(m["max_hp"])
		m["hp_text"] = "%d/%d" % [int(m["max_hp"]), int(m["max_hp"])]
		_touch()
		_build_party_into())
	editor.add_child(heal)

	var del := Button.new()
	del.text = "删除"
	del.position = Vector2(196, 58)
	del.size = Vector2(54, 26)
	_style(del, 11)
	del.add_theme_color_override("font_color", WARN)
	del.pressed.connect(func() -> void:
		party[slot] = {}
		save_data_hook()
		_touch()
		_build_party_into())
	editor.add_child(del)

	# 六维（只读，改种族值去第三页）
	var st: Dictionary = m.get("stats", {})
	var stat := Label.new()
	stat.position = Vector2(0, 88)
	stat.text = "HP %d/%d   攻 %d  防 %d  特攻 %d  特防 %d  速 %d" % [
		int(m.get("hp", 0)), int(m.get("max_hp", 0)),
		int(st.get("atk", 0)), int(st.get("def", 0)), int(st.get("spa", 0)),
		int(st.get("spd", 0)), int(st.get("spe", 0))]
	stat.add_theme_font_size_override("font_size", 11)
	stat.add_theme_color_override("font_color", CREAM)
	editor.add_child(stat)

	# 技能四格
	var moves: Array = m.get("moves", [])
	var pp: Array = m.get("pp", [])
	for i in 4:
		var pick := OptionButton.new()
		pick.position = Vector2((i % 2) * 132, 112 + (i / 2) * 30)
		pick.size = Vector2(126, 26)
		_style(pick, 11)
		pick.add_item("— 空 —", 0)
		for mid in move_ids:
			var mv: Dictionary = Data.move_of(int(mid))
			pick.add_item(String(mv.get("name", "?")) + " " + String(mv.get("type", "")), int(mid))
		if i < moves.size():
			var idx2: int = move_ids.find(int(moves[i]))
			pick.selected = idx2 + 1 if idx2 >= 0 else 0
		else:
			pick.selected = 0
		pick.item_selected.connect(func(sel: int) -> void:
			var arr: Array = m.get("moves", [])
			var pps: Array = m.get("pp", [])
			while arr.size() <= i:
				arr.append(0)
				pps.append(0)
			if sel == 0:
				arr[i] = 0
				pps[i] = 0
			else:
				var mid: int = int(move_ids[sel - 1])
				arr[i] = mid
				pps[i] = int((Data.move_of(mid) as Dictionary).get("pp", 10))
			m["moves"] = arr
			m["pp"] = pps
			_touch()
			_build_party_into())
		editor.add_child(pick)

	var ppfix := Button.new()
	ppfix.text = "PP 全恢复"
	ppfix.position = Vector2(0, 174)
	ppfix.size = Vector2(126, 24)
	_style(ppfix, 11)
	ppfix.pressed.connect(func() -> void:
		var pps: Array = []
		for mid in m.get("moves", []):
			pps.append(int((Data.move_of(int(mid)) as Dictionary).get("pp", 10)) if int(mid) > 0 else 0)
		m["pp"] = pps
		_touch()
		_build_party_into())
	editor.add_child(ppfix)

func _default_moves(sid: int) -> Array:
	var sp: Dictionary = Data.species_of(sid)
	var arr: Array = []
	for mid in sp.get("moves", [33]):
		if Data.moves.has(int(mid)):
			arr.append(int(mid))
	if arr.is_empty():
		arr.append(33)
	return arr.slice(0, 4)

func _pps_of(moves: Array) -> Array:
	var out: Array = []
	for mid in moves:
		var mv: Dictionary = Data.move_of(int(mid))
		out.append(int(mv.get("pp", 10)))
	return out

# ---------------- 道具 ----------------

func _build_bag() -> void:
	var rows := Control.new()
	rows.position = Vector2(10, 0)
	body.add_child(rows)
	for i in bag.size():
		var it: Dictionary = bag[i]
		var y := i * 26
		var l := Label.new()
		l.position = Vector2(0, y + 4)
		l.size = Vector2(150, 20)
		l.text = "%s ×%d" % [String(it.get("name", "?")), int(it.get("count", 0))]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", CREAM)
		rows.add_child(l)

		var minus := Button.new()
		minus.text = "−"
		minus.position = Vector2(152, y)
		minus.size = Vector2(26, 24)
		_style(minus, 12)
		minus.pressed.connect(func() -> void:
			it["count"] = maxi(0, int(it.get("count", 0)) - 1)
			_touch()
			_reload("bag"))
		rows.add_child(minus)

		var plus := Button.new()
		plus.text = "+"
		plus.position = Vector2(180, y)
		plus.size = Vector2(26, 24)
		_style(plus, 12)
		plus.pressed.connect(func() -> void:
			it["count"] = int(it.get("count", 0)) + 1
			_touch()
			_reload("bag"))
		rows.add_child(plus)

		var kill := Button.new()
		kill.text = "删"
		kill.position = Vector2(208, y)
		kill.size = Vector2(26, 24)
		_style(kill, 11)
		kill.add_theme_color_override("font_color", WARN)
		kill.pressed.connect(func() -> void:
			bag.remove_at(i)
			_touch()
			_reload("bag"))
		rows.add_child(kill)

	# 新增
	var add_y: int = maxi(120, bag.size() * 26 + 8)
	var input := LineEdit.new()
	input.position = Vector2(10, add_y)
	input.size = Vector2(120, 26)
	input.placeholder_text = "道具名"
	_style(input, 11)
	rows.add_child(input)

	var preset := OptionButton.new()
	preset.position = Vector2(10, add_y + 30)
	preset.size = Vector2(120, 26)
	_style(preset, 11)
	var presets := [["精灵球", "ball"], ["超级球", "ball"], ["高级球", "ball"], ["伤药", "heal"],
		["好伤药", "heal"], ["全复药", "heal"], ["力量强化", "battle"], ["速度强化", "battle"]]
	for p in presets:
		preset.add_item(String(p[0]))
	preset.item_selected.connect(func(i: int) -> void:
		input.text = String(presets[i][0]))
	rows.add_child(preset)

	var cnt := SpinBox.new()
	cnt.position = Vector2(136, add_y)
	cnt.size = Vector2(68, 26)
	cnt.min_value = 1
	cnt.max_value = 999
	cnt.value = 1
	rows.add_child(cnt)

	var add := Button.new()
	add.text = "添加"
	add.position = Vector2(136, add_y + 30)
	add.size = Vector2(68, 26)
	_style(add, 11)
	add.pressed.connect(func() -> void:
		var nm := input.text.strip_edges()
		if nm == "":
			nm = String(presets[preset.selected][0])
		var cat := "other"
		for p in presets:
			if String(p[0]) == nm:
				cat = String(p[1])
		# 同名道具合并数量，不制造重复条目
		var found := false
		for it in bag:
			if String(it.get("name", "")) == nm:
				it["count"] = int(it.get("count", 0)) + int(cnt.value)
				found = true
		if not found:
			bag.append({"id": 0, "name": nm, "category": cat, "count": int(cnt.value)})
		_touch()
		_reload("bag"))
	rows.add_child(add)

	var tip := Label.new()
	tip.position = Vector2(214, add_y)
	tip.text = "同名会合并数量"
	tip.add_theme_font_size_override("font_size", 10)
	tip.add_theme_color_override("font_color", DIM)
	rows.add_child(tip)

func _reload(t: String) -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_switch(t)

# ---------------- 种族值 ----------------

func _build_base() -> void:
	var sid := int(species_ids[base_page])
	var sp: Dictionary = Data.species_of(sid)
	var base: Dictionary = sp.get("base", {})

	var head := Label.new()
	head.position = Vector2(10, 2)
	head.text = "No.%03d  %s   （第 %d / %d 只）" % [sid, String(sp.get("name", "?")), base_page + 1, species_ids.size()]
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", MINT)
	body.add_child(head)

	var prev := Button.new()
	prev.text = "‹"
	prev.position = Vector2(300, 0)
	prev.size = Vector2(28, 24)
	_style(prev, 12)
	prev.pressed.connect(func() -> void:
		base_page = maxi(0, base_page - 1)
		_reload("base"))
	body.add_child(prev)

	var next := Button.new()
	next.text = "›"
	next.position = Vector2(332, 0)
	next.size = Vector2(28, 24)
	_style(next, 12)
	next.pressed.connect(func() -> void:
		base_page = mini(species_ids.size() - 1, base_page + 1)
		_reload("base"))
	body.add_child(next)

	var keys := ["hp", "atk", "def", "spa", "spd", "spe"]
	var names := ["HP", "攻击", "防御", "特攻", "特防", "速度"]
	for i in keys.size():
		var k := String(keys[i])
		var l := Label.new()
		l.position = Vector2(10, 32 + i * 34)
		l.size = Vector2(44, 22)
		l.text = names[i]
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", CREAM)
		body.add_child(l)

		var box := SpinBox.new()
		box.position = Vector2(58, 32 + i * 34)
		box.size = Vector2(96, 26)
		box.min_value = 1
		box.max_value = 255
		box.value = int(base.get(k, 1))
		box.value_changed.connect(func(v: float) -> void:
			_set_override(sid, k, int(v))
			_touch()
			_reload("base"))
		body.add_child(box)

	var rate := SpinBox.new()
	rate.position = Vector2(178, 32)
	rate.size = Vector2(96, 26)
	rate.min_value = 1
	rate.max_value = 255
	rate.value = int(sp.get("catch_rate", 45))
	rate.value_changed.connect(func(v: float) -> void:
		_set_override(sid, "catch_rate", int(v))
		_touch()
		_reload("base"))
	body.add_child(rate)

	var rate_l := Label.new()
	rate_l.position = Vector2(178, 12)
	rate_l.text = "捕获率"
	rate_l.add_theme_font_size_override("font_size", 11)
	rate_l.add_theme_color_override("font_color", DIM)
	body.add_child(rate_l)

	var reset := Button.new()
	reset.text = "恢复默认"
	reset.position = Vector2(178, 100)
	reset.size = Vector2(96, 26)
	_style(reset, 11)
	reset.pressed.connect(func() -> void:
		overrides.erase(str(sid))
		Data.apply_species_overrides(overrides)
		_recalc_all()
		_touch()
		_reload("base"))
	body.add_child(reset)

	var note := Label.new()
	note.position = Vector2(178, 134)
	note.size = Vector2(180, 120)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "改完会写进存档，所有读取这只宝可梦的地方都跟着变。队伍里已有的个体按新种族值重算六维。"
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", DIM)
	body.add_child(note)

func _set_override(sid: int, key: String, val: int) -> void:
	var key_s := str(sid)
	var row: Dictionary = overrides.get(key_s, {})
	row[key] = val
	overrides[key_s] = row
	Data.apply_species_overrides(overrides)
	_recalc_all()

func _recalc_all() -> void:
	for m in party:
		if m is Dictionary and not (m as Dictionary).is_empty():
			PartyScript.recalc(m, true)

func save_data_hook() -> void:
	pass

func _touch() -> void:
	changed.emit()

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
		(c as Button).add_theme_color_override("font_color", CREAM)
	elif c is LineEdit:
		(c as LineEdit).add_theme_stylebox_override("normal", sb)
		(c as LineEdit).add_theme_color_override("font_color", CREAM)
	elif c is OptionButton:
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			(c as OptionButton).add_theme_stylebox_override(st, sb)
		(c as OptionButton).add_theme_color_override("font_color", CREAM)
