extends Control
## All pages edit the same draft. Only 保存 updates the party, bag and species database.
const UI := preload("res://core/field_ui.gd")
const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")
const DexArt := preload("res://core/dex_art.gd")
const INK := Color("#183e3c")
const GREEN := Color("#216c60")
const PAPER := Color("#f4f2e7")
const LINE := Color("#bfd0bd")
const WHITE := Color("#fffef5")
const STATS := {"hp":"体力", "atk":"攻击", "def":"防御", "spa":"特攻", "spd":"特防", "spe":"速度", "catch_rate":"捕获率"}
const PAGE_SIZE := 18

signal closed
signal changed

var party: Array
var bag: Array
var overrides: Dictionary
var original_party: Array
var original_bag: Array
var original_overrides: Dictionary
var edited_species := {}
var dirty := false
var tab := "party"
var slot := -1
var section := "属性"
var base_id := 1
var picker := ""
var move_slot := 0
var query := ""
var entered_query := ""
var page := 0
var species_ids: Array
var move_ids: Array
var goods := {}
var body: VBoxContainer
var toolbar: VBoxContainer
var scroller: ScrollContainer
var tabs: HBoxContainer
var save_button: Button
var status: Label
var member_info: Label
var member_hp: Label
var member_stats: Label
var hp_control: SpinBox

func setup(p_party: Array, p_bag: Array, p_overrides: Dictionary) -> void:
	original_party = p_party
	original_bag = p_bag
	original_overrides = p_overrides
	party = Party.compact(p_party.duplicate(true))
	bag = p_bag.duplicate(true)
	overrides = p_overrides.duplicate(true)
	species_ids = Data.species.keys()
	species_ids.sort()
	move_ids = Data.moves.keys()
	move_ids.sort()
	for entry in Data.load_shop():
		goods[str(entry.name)] = entry.duplicate(true)
		goods[str(entry.name)].erase("price")
	for name_text in ["力量强化","速度强化"]:
		goods[name_text] = {"name":name_text, "category":"battle"}
	for key in Data.held_items:
		var entry: Dictionary = Data.held_items[key]
		goods[str(entry.name)] = {"name":entry.name, "category":"held", "held":key}
	for entry in bag:
		goods[str(entry.name)] = entry.duplicate(true)
	_shell()
	_switch("party")

func _shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var background := ColorRect.new()
	background.color = PAPER
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 9
	layout.offset_right = -9
	layout.offset_top = 5
	layout.offset_bottom = -5
	layout.add_theme_constant_override("separation", 3)
	var head := _row(layout)
	var title := UI.label("修改器", 20, INK)
	head.add_child(title)
	status = UI.label("", 12, GREEN)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(status)
	_button(head, "取消", discard_changes)
	save_button = _button(head, "保存", save_changes, true)
	save_button.disabled = true
	tabs = _row(layout)
	toolbar = VBoxContainer.new()
	layout.add_child(toolbar)
	scroller = UI.FingerScroll.new()
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.scroll_deadzone = 8
	layout.add_child(scroller)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroller.add_child(body)

func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	return row

func _button(parent: Control, caption: String, action: Callable, active := false) -> Button:
	var b := UI.button(caption, action, active)
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 36)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(b)
	return b

func _wide(parent: Control, caption: String, action: Callable, active := false) -> Button:
	var b := _button(parent, caption, action, active)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return b

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _mark_dirty() -> void:
	dirty = true
	status.text = "待保存"
	save_button.disabled = false

func save_changes(close_panel := true) -> void:
	if get_viewport():
		get_viewport().gui_release_focus()
	if dirty:
		if not edited_species.is_empty():
			Data.apply_species_overrides(overrides)
			for m in party:
				if edited_species.has(int(m.get("species_id", 0))):
					Party.recalc(m, true)
		party = Party.compact(party)
		original_party.assign(party.duplicate(true))
		original_bag.assign(bag.duplicate(true))
		original_overrides.clear()
		original_overrides.merge(overrides.duplicate(true))
		dirty = false
		edited_species.clear()
		status.text = ""
		save_button.disabled = true
		changed.emit()
	if close_panel:
		_close()

func discard_changes() -> void:
	_close()

func _close() -> void:
	closed.emit()
	queue_free()

func handle_back() -> void:
	if picker != "":
		_close_picker()
	elif tab == "party" and slot >= 0:
		_switch("party")
	else:
		discard_changes()

func _switch(next_tab: String) -> void:
	tab = next_tab
	slot = -1
	picker = ""
	_render()

func _render() -> void:
	_clear(tabs)
	_clear(toolbar)
	_clear(body)
	scroller.scroll_vertical = 0
	for item in [["party","队伍"],["bag","背包"],["base","种族值"]]:
		_wide(tabs, item[1], _switch.bind(item[0]), tab == item[0])
	if picker != "":
		_build_picker()
	elif tab == "party":
		if slot < 0:
			_list_party()
		else:
			_member()
	elif tab == "bag":
		_bag_page()
	else:
		_base_page()

func _list_party() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	for i in party.size():
		var m: Dictionary = party[i]
		if m.is_empty():
			if i == 0 or not party[i-1].is_empty():
				_wide(grid, "＋  添加成员", _select_member.bind(i))
			break
		var b := _wide(grid, "", _select_member.bind(i))
		b.custom_minimum_size.y = 64
		b.accessibility_name = "%s，等级 %d" % [m.get("name",""), int(m.get("level",1))]
		var portrait := _portrait(m)
		UI.place(b, portrait, 3, 2, 58, 59)
		UI.place(b, UI.label("No.%04d   ·   Lv.%d" % [int(m.species_id), int(m.level)], 10, GREEN), 65, 3, 140, 16)
		UI.place(b, UI.label(str(m.name), 16, INK), 65, 18, 150, 24)
		UI.place(b, UI.label("HP %d / %d" % [int(m.hp),int(m.max_hp)], 10, GREEN), 66, 41, 136, 16)
		UI.meter(b, 66, 57, 100, float(m.hp)/maxi(1,int(m.max_hp)))


func _portrait(m: Dictionary) -> TextureRect:
	var image := UI.art("")
	image.texture = DexArt.texture(int(m.species_id), str(m.get("form", "")), Party.shiny_kind(m) != "none")
	return image

func _set_shiny(m: Dictionary, kind: String) -> void:
	if kind != Party.shiny_kind(m):
		Party.set_shiny_kind(m, kind)
		_mark_dirty()
		_render()

func _select_member(i: int) -> void:
	slot = i
	section = "属性"
	if party[i].is_empty():
		_open_picker("member")
	else:
		_render()

func _member() -> void:
	var m: Dictionary = party[slot]
	if m.is_empty():
		slot = -1
		_list_party()
		return
	var nav := _row(toolbar)
	_button(nav, "‹ 队伍", _switch.bind("party"))
	for s in ["属性","招式","物种"]:
		_wide(nav, s, _set_section.bind(s), section == s)
	var summary := _row(body)
	var portrait := _portrait(m)
	portrait.custom_minimum_size = Vector2(44,44)
	summary.add_child(portrait)
	member_info = UI.label("%s   Lv.%d" % [m.name, int(m.level)], 16, INK)
	member_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_child(member_info)
	member_hp = UI.label("HP %d / %d" % [int(m.hp),int(m.max_hp)],13,GREEN)
	summary.add_child(member_hp)
	match section:
		"属性":
			_number(body, "等级", int(m.level), 1, 100, _set_level.bind(m))
			hp_control = _number(body, "当前体力", int(m.hp), 0, int(m.max_hp), _set_hp.bind(m))
			var row := _row(body)
			_wide(row, "体力回满", func(): _set_hp(int(m.max_hp), m); _render())
			_wide(row, "恢复全部 PP", func(): _restore_pp(m); _render())
			member_stats = UI.label(_stat_text(m), 12, GREEN)
			body.add_child(member_stats)
		"招式":
			var moves: Array = m.get("moves",[])
			var pp: Array = m.get("pp",[])
			for i in mini(moves.size()+1,4):
				var text := "＋  学习招式"
				if i < moves.size():
					var mv: Dictionary = Data.move_of(int(moves[i]))
					text = "%d   %s     %s     PP %d/%d" % [i+1,mv.get("name","空"),Data.type_name(str(mv.get("type",""))),int(pp[i]) if i<pp.size() else 0,_max_pp(m,int(moves[i]))]
				_wide(body, text, _move_picker.bind(i))
		"物种":
			_wide(body, "更换物种   No.%04d   %s" % [int(m.species_id), Data.species_of(int(m.species_id)).get("name","")], _open_picker.bind("member"))
			var forms := _row(body)
			var form: String = str(m.get("form",""))
			_wide(forms, "形态   "+str(Data.form_of(int(m.species_id),form).get("label","默认")), _open_picker.bind("form"))
			_wide(forms, "编辑该物种种族值", _edit_member_base)
			var rarity := _row(body)
			for style in [["none", "普通"], ["star", "星星闪"], ["square", "方块闪"]]:
				_wide(rarity, style[1], _set_shiny.bind(m, style[0]), Party.shiny_kind(m) == style[0])
			_button(body, "移除此成员", _remove_member)

func _set_section(s: String) -> void:
	section = s
	_render()

func _number(parent: Control, caption: String, value: int, low: int, high: int, update: Callable) -> SpinBox:
	var row := _row(parent)
	var l := UI.label(caption, 14, INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.value = value
	input.custom_minimum_size = Vector2(80, 36)
	input.update_on_text_changed = true
	input.add_theme_constant_override("buttons_width", 0)
	input.add_theme_constant_override("set_min_buttons_width_from_icons", 0)
	for arrow in ["up","down"]:
		for state in ["", "_disabled", "_hover", "_pressed"]:
			input.add_theme_color_override(arrow+state+"_icon_modulate", Color.TRANSPARENT)
	input.get_line_edit().virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	input.get_line_edit().select_all_on_focus = true
	input.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.get_line_edit().add_theme_color_override("font_color", INK)
	input.get_line_edit().add_theme_stylebox_override("normal",UI.box(WHITE,LINE))
	_button(row, "−", func(): input.value -= 1).custom_minimum_size.x = 40
	row.add_child(input)
	_button(row, "＋", func(): input.value += 1).custom_minimum_size.x = 40
	input.value_changed.connect(func(v): update.call(int(v)))
	return input

func _stat_text(m: Dictionary) -> String:
	var stats: Dictionary = m.get("stats",{})
	return "攻 %d   防 %d   特攻 %d   特防 %d   速 %d" % [int(stats.get("atk",0)),int(stats.get("def",0)),int(stats.get("spa",0)),int(stats.get("spd",0)),int(stats.get("spe",0))]

func _set_level(v: int, m: Dictionary) -> void:
	if v == int(m.level):
		return
	m.level = v
	m.exp = Growth.exp_for_level(v,str(Data.species_of(int(m.species_id)).get("growth","medium_fast")))
	Party.recalc(m, true)
	_mark_dirty()
	# Updating the numeric widgets in place keeps touch and keyboard focus.
	member_info.text = "%s   Lv.%d" % [m.name,v]
	member_hp.text = "HP %d / %d" % [int(m.hp),int(m.max_hp)]
	member_stats.text = _stat_text(m)
	hp_control.set_block_signals(true)
	hp_control.max_value = int(m.max_hp)
	hp_control.set_value_no_signal(int(m.hp))
	hp_control.set_block_signals(false)

func _set_hp(v: int, m: Dictionary) -> void:
	m.hp = clampi(v, 0, int(m.max_hp))
	m.hp_text = "%d/%d" % [int(m.hp),int(m.max_hp)]
	_mark_dirty()
	if section == "属性" and tab == "party" and body.get_child_count() > 0:
		member_hp.text = "HP %d / %d" % [int(m.hp),int(m.max_hp)]

func _max_pp(m: Dictionary, mid: int) -> int:
	var base := int(Data.move_of(mid).get("pp",0))
	var bonus := int(m.get("pp_bonus",{}).get(str(mid),0))
	return base + bonus

func _restore_pp(m: Dictionary) -> void:
	var pp := []
	for mid in m.get("moves",[]):
		pp.append(_max_pp(m,int(mid)))
	m.pp = pp
	_mark_dirty()

func _remove_member() -> void:
	party[slot] = {}
	party = Party.compact(party)
	_mark_dirty()
	_switch("party")

func _edit_member_base() -> void:
	base_id = int(party[slot].species_id)
	_switch("base")

func _bag_page() -> void:
	_button(toolbar, "＋  添加道具", _open_picker.bind("item"))
	for i in bag.size():
		var it: Dictionary = bag[i]
		var row := _row(body)
		_number(row, str(it.get("name","道具")), int(it.get("count",0)), 0, maxi(9999,int(it.get("count",0))), func(v): it.count = v; _mark_dirty())
		row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(row, "移除", _remove_item.bind(i))

func _remove_item(i: int) -> void:
	bag.remove_at(i)
	_mark_dirty()
	_render()

func _base_page() -> void:
	var sp: Dictionary = Data.species_of(base_id)
	_wide(toolbar,"No.%04d   %s   ·   选择物种" % [base_id,sp.get("name","")], _open_picker.bind("base"))
	body.add_child(UI.label("变更影响此物种的所有个体",12,GREEN))
	var source: Dictionary = Data.base_species.get(base_id,sp)
	var patch: Dictionary = overrides.get(str(base_id),{})
	for key in STATS:
		var value := int(source.get("catch_rate",45)) if key=="catch_rate" else int(source.get("base",{}).get(key,1))
		_number(body, STATS[key], int(patch.get(key,value)), 1, 255, _base_change.bind(key))
	_button(body, "恢复此物种默认值", _reset_base)

func _base_change(v: int, key: String) -> void:
	_set_override(base_id, key, v)

func _set_override(sid: int, key: String, value: int) -> void:
	var patch: Dictionary = overrides.get(str(sid),{})
	patch[key] = clampi(value,1,255)
	overrides[str(sid)] = patch
	edited_species[sid] = true
	_mark_dirty()

func _reset_base() -> void:
	overrides.erase(str(base_id))
	edited_species[base_id] = true
	_mark_dirty()
	_render()

func _move_picker(i: int) -> void:
	move_slot = i
	_open_picker("move")

func _open_picker(kind: String) -> void:
	picker = kind
	query = ""
	entered_query = ""
	page = 0
	_render()

func _close_picker() -> void:
	if picker == "member" and slot >= 0 and party[slot].is_empty():
		slot = -1
	picker = ""
	_render()

func _build_picker() -> void:
	var row := _row(toolbar)
	_button(row, "‹ 返回", _close_picker)
	var search := LineEdit.new()
	search.placeholder_text = {"base":"查找物种名或编号","member":"查找物种名或编号","move":"查找招式名或编号","item":"查找或输入道具名","form":"查找形态"}[picker]
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = 36
	search.add_theme_color_override("font_color", INK)
	search.add_theme_color_override("font_placeholder_color", GREEN)
	search.add_theme_stylebox_override("normal",UI.box(WHITE,LINE))
	row.add_child(search)
	search.text = entered_query
	search.text_changed.connect(func(value):
		entered_query = value.strip_edges()
		query = entered_query.to_lower()
		page = 0
		_picker_rows())
	_picker_rows()

func _picker_rows() -> void:
	_clear(body)
	scroller.scroll_vertical = 0
	var choices := []
	if picker == "item":
		for name_text in goods:
			if query == "" or str(name_text).to_lower().contains(query):
				choices.append([name_text,name_text])
		if entered_query != "" and not goods.has(entered_query):
			choices.push_front([entered_query, "新道具   "+entered_query])
	elif picker == "form":
		if query.is_empty() or "默认形态".contains(query):
			choices.append(["", "默认形态"])
		for f in Data.forms_of(int(party[slot].species_id)):
			if f.get("kind", "") in ["mega", "gmax"] or f.get("battle", false):
				continue
			var label := str(f.get("label", ""))
			var form_key := str(f.get("key", ""))
			if query.is_empty() or label.to_lower().contains(query) or form_key.to_lower().contains(query.replace("-", "_")):
				choices.append([form_key, label])
	else:
		var is_move := picker == "move"
		if is_move and query == "" and move_slot < party[slot].get("moves",[]).size():
			choices.append([0,"移除此招式"])
		var ids := move_ids if is_move else species_ids
		for id in ids:
			var entry: Dictionary = Data.move_of(id) if is_move else Data.species_of(id)
			var title := str(entry.get("name",""))
			var num := "%04d" % int(id)
			if query != "" and not (num.contains(query) or title.to_lower().contains(query) or str(entry.get("key","")).to_lower().contains(query)):
				continue
			var desc := Data.type_name(str(entry.get("type",""))) if is_move else ""
			choices.append([id, "%s   %s  %s" % [num,title,desc]])
	if choices.is_empty():
		body.add_child(UI.label("没有匹配项",14,GREEN))
		return
	var pages := ceili(choices.size() / float(PAGE_SIZE))
	page = clampi(page,0,pages-1)
	if pages > 1:
		var pager := _row(body)
		_wide(pager, "上一页", _page_change.bind(-1)).disabled = page == 0
		pager.add_child(UI.label("%d / %d" % [page+1,pages],12,GREEN))
		_wide(pager, "下一页", _page_change.bind(1)).disabled = page+1 == pages
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	for item in choices.slice(page * PAGE_SIZE,(page+1)*PAGE_SIZE):
		var b := _wide(grid, str(item[1]), _choose.bind(item[0]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _page_change(delta: int) -> void:
	page += delta
	_picker_rows()

func _choose(key: Variant) -> void:
	if picker == "item":
		var label_text := str(key)
		var found := false
		for it in bag:
			if str(it.name) == label_text:
				it.count = int(it.get("count",0)) + 1
				found = true
				break
		if not found:
			var it: Dictionary = goods.get(key,{"name":label_text,"category":"other"}).duplicate(true)
			it.count = 1
			bag.append(it)
		_mark_dirty()
	elif picker == "base":
		base_id = int(key)
	elif picker == "form":
		Party.set_form(party[slot], str(key))
		_mark_dirty()
	elif picker == "move":
		_assign_move(int(key))
	else:
		var sid := int(key)
		if party[slot].is_empty():
			var moves := Growth.moves_learned({"species_id":sid}, -1, 5)
			if moves.is_empty():
				moves = [33]
			party[slot] = Party.make(sid,5,moves.slice(maxi(0,moves.size()-4)))
		else:
			Party.evolve(party[slot],sid)
		_mark_dirty()
	_close_picker()

func _assign_move(mid: int) -> void:
	var m: Dictionary = party[slot]
	var moves: Array = m.get("moves",[])
	var pp: Array = m.get("pp",[])
	while pp.size() < moves.size():
		pp.append(_max_pp(m,int(moves[pp.size()])))
	if mid == 0 and move_slot < moves.size():
		moves.remove_at(move_slot)
		pp.remove_at(move_slot)
	elif mid > 0:
		var existing := moves.find(mid)
		if existing < 0 and move_slot >= moves.size():
			moves.append(mid)
			pp.append(_max_pp(m,mid))
		elif existing < 0:
			moves[move_slot] = mid
			pp[move_slot] = _max_pp(m,mid)
		elif move_slot < moves.size() and existing != move_slot:
			var old_move: int = int(moves[move_slot])
			var old_pp: int = int(pp[move_slot])
			moves[move_slot] = mid
			pp[move_slot] = pp[existing]
			moves[existing] = old_move
			pp[existing] = old_pp
	m.moves = moves
	m.pp = pp
	_mark_dirty()
