extends Control
## 战斗界面。逻辑在 core/battle.gd，这里只负责画和收输入。

signal finished(result: String)
signal item_used(item_name: String)

const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")
const DexArt := preload("res://core/dex_art.gd")
const DexCatalog := preload("res://core/dex_catalog.gd")
const DexEffect := preload("res://core/dex_effect.gd")

const UI := preload("res://core/field_ui.gd")
const HUD_INK := Color("#374a45")
const HP_HI := Color(0.42, 0.82, 0.52)
const HP_MID := Color(0.94, 0.78, 0.34)

const HP_LO := Color(0.90, 0.40, 0.36)

var battle
var alola_rules := false
var alola_ring := false
var alola_ultra := false
var kalos_rules := false
var kalos_ring := false
var observe_variant: Callable
var enemy_team: Array = []
var player_team: Array = []

var state := "intro"
var pending: Array = []
var wait := 0.0

var bg: Control
var enemy_sprite: TextureRect
var player_sprite: TextureRect
var enemy_hp: Control
var player_hp: Control
var msg: Label
var menu: Control
var move_menu: Control
var sheet: Control
var health_cues := {}
var health_motion := {}
var line_offset := 0
var spoken_lines := 0
var frontier_rules
var frontier_kit := Callable()
var trainer_name := ""
var backdrop := "grass"
var backdrop_texture: Texture2D
var dialogue_texture: Texture2D
var fast := false   # 自检时压缩等待
var shake_t := 0.0
var bag: Array = []          # 只读引用，投球时弹窗列出来
var field_label: Label      # 顶部的天气 / 场地提示

func setup(p_team: Array, e_team: Array, seed_value: int = 0, p_bag: Array = [], trainer := "") -> void:
	trainer_name = trainer
	player_team = p_team
	enemy_team = e_team
	bag = p_bag
	battle = _battle_engine(seed_value)
	battle.alola_rules=alola_rules
	battle.alola_ring=alola_ring
	battle.alola_ultra=alola_ultra
	battle.kalos_rules=kalos_rules
	battle.kalos_ring=kalos_ring
	if observe_variant.is_valid():
		battle.variant_seen.connect(observe_variant)
	battle.start(player_team, enemy_team)
	if battle.over:
		# The field connects the normal loss and recovery handler after setup returns.
		state = "end"
		wait = 0.0
		return
	battle.health_changed.connect(_queue_health)
	_build()
	var opponent := _display_name(battle.cur_b())
	_say("野生的 %s 出现了！" % opponent if trainer_name == "" else "%s 派出了 %s！" % [trainer_name, opponent])
	state = "intro"
	wait = _dur(0.9)

func _battle_engine(seed_value: int):
	return preload("res://core/battle.gd").new(seed_value)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO

	backdrop_texture = load("res://assets/emerald/battle/%s.png" % backdrop)
	dialogue_texture = load("res://assets/emerald/battle/dialogue.png")
	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.draw.connect(_draw_bg)
	add_child(bg)

	# 站位：敌右上方、我左下方，都留出与血条框、底栏的空隙
	enemy_sprite = _make_sprite(battle.cur_b(), Vector2(288, 0), 2.0)
	player_sprite = _make_sprite(battle.cur_a(), Vector2(40, 0), 2.0, true)

	enemy_hp = _make_hpbox(Vector2(8, 8), battle.cur_b(), false)
	player_hp = _make_hpbox(Vector2(267, 146), battle.cur_a(), true)
	enemy_hp.set_meta("slot", battle.active_b)
	player_hp.set_meta("slot", battle.active_a)
	enemy_hp.name = "EnemyHP"
	player_hp.name = "PlayerHP"

	# 天气与场地：放在底部文字框上方那一行，右侧留给指令，不压血条也不压文字
	field_label = Label.new()
	field_label.position = Vector2(16, 233)
	field_label.size = Vector2(212, 14)
	field_label.clip_text = true
	field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	field_label.add_theme_font_size_override("font_size", 10)
	field_label.add_theme_color_override("font_color", Color.WHITE)
	field_label.add_theme_color_override("font_shadow_color", HUD_INK)
	field_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(field_label)

	msg = Label.new()
	msg.position = Vector2(16, 242)
	msg.size = Vector2(437, 64)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", Color.WHITE)
	msg.add_theme_color_override("font_shadow_color", HUD_INK)
	msg.add_theme_constant_override("shadow_offset_x", 1)
	msg.add_theme_constant_override("shadow_offset_y", 1)
	add_child(msg)

	menu = _make_menu()
	move_menu = _frame(self,Rect2(0,224,480,96))
	move_menu.name = "Moves"
	move_menu.visible = false

func _make_sprite(c: Dictionary, pos: Vector2, scale_f: float, rear := false) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.set_meta("rear",rear)
	t.set_meta("normal_scale",scale_f)
	t.set_meta("home_x",pos.x)
	var effect := DexEffect.new()
	effect.name = "Appearance"
	t.add_child(effect)
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.position = pos
	_apply_appearance(t, c)
	t.custom_minimum_size = Vector2(64, 64)
	t.size = Vector2(64, 64)
	t.scale = Vector2(scale_f, scale_f)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(t)
	return t

func _make_hpbox(pos: Vector2, c: Dictionary, player: bool) -> Control:
	var box := TextureRect.new()
	box.position = pos
	box.texture = load("res://assets/emerald/battle/hp_%s.png" % ("player" if player else "opponent"))
	box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	box.size = box.texture.get_size() * 2.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := 24 if player else 12
	add_child(box)

	var name_l := Label.new()
	name_l.name = "Name"
	name_l.position = Vector2(left, 1)
	name_l.clip_text = true
	name_l.size = Vector2(126, 20)
	name_l.add_theme_color_override("font_color", HUD_INK)
	box.add_child(name_l)
	_set_hpbox_name(name_l, c)

	var lv := Label.new()
	lv.name = "Lv"
	lv.position = Vector2(left+126, 5)
	lv.text = "Lv %d" % int(c.get("level", 1))
	lv.add_theme_font_size_override("font_size", 12)
	lv.add_theme_color_override("font_color", HUD_INK)
	box.add_child(lv)

	var track := ColorRect.new()
	track.name = "Track"
	track.position = Vector2(left, 24)
	track.size = Vector2(160, 6)
	track.color = Color("#53665c")
	box.add_child(track)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(left, 24)
	fill.size = Vector2(160, 6)
	fill.color = HP_HI
	box.add_child(fill)

	var hp_l := Label.new()
	hp_l.name = "HP"
	hp_l.position = Vector2(left, 30)
	hp_l.text = "%d/%d" % [int(c.get("hp", 0)), int(c.get("max_hp", 1))]
	hp_l.add_theme_font_size_override("font_size", 11)
	hp_l.add_theme_color_override("font_color", HUD_INK)
	box.add_child(hp_l)
	if player:
		var exp_fill := ColorRect.new()
		exp_fill.name = "ExpFill"
		exp_fill.position = Vector2(62, 66)
		exp_fill.color = Color("#48acce")
		box.add_child(exp_fill)
	_update_hpbox(box, c)
	return box

func _frame(parent: Control, rect: Rect2) -> NinePatchRect:
	var frame := NinePatchRect.new()
	frame.texture = preload("res://assets/emerald/ui/menu_frame.png")
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		frame.set_patch_margin(side, 8)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(parent,frame,rect.position.x,rect.position.y,rect.size.x,rect.size.y)
	return frame

func _rule(parent: Control, rect: Rect2) -> void:
	var line := ColorRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = Color("#d8dfd8")
	UI.place(parent,line,rect.position.x,rect.position.y,rect.size.x,rect.size.y)

func _choice(caption: String, action: Callable, font_size := 16) -> Button:
	var b := Button.new()
	b.text = caption
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size",font_size)
	for style in ["normal","focus","hover","pressed","disabled","hover_pressed"]:
		var bg_style := StyleBoxFlat.new()
		bg_style.bg_color = Color.TRANSPARENT
		if style == "pressed" or style == "hover_pressed":
			bg_style.bg_color = Color("#d0e4d1")
		elif style == "hover":
			bg_style.bg_color = Color("#eaf2e4")
		bg_style.content_margin_left = 18
		bg_style.content_margin_right = 3
		bg_style.content_margin_top = 0
		bg_style.content_margin_bottom = 0
		b.add_theme_stylebox_override(style,bg_style)
	for key in ["font_color","font_hover_color","font_focus_color","font_pressed_color","font_hover_pressed_color"]:
		b.add_theme_color_override(key,HUD_INK)
	b.add_theme_color_override("font_disabled_color", Color("#7b887f"))
	var arrow := Polygon2D.new()
	arrow.polygon = PackedVector2Array([Vector2(0,0),Vector2(2,0),Vector2(2,2),Vector2(4,2),
		Vector2(4,4),Vector2(6,4),Vector2(6,6),Vector2(4,6),Vector2(4,8),Vector2(2,8),
		Vector2(2,10),Vector2(0,10)])
	arrow.color = HUD_INK
	arrow.visible = false
	b.add_child(arrow)
	b.resized.connect(func(): arrow.position = Vector2(6, floorf((b.size.y-10)*0.5)))
	b.focus_entered.connect(func(): arrow.show())
	b.focus_exited.connect(func(): arrow.hide())
	if action.is_valid():
		b.pressed.connect(action)
	return b

func _make_menu() -> Control:
	var panel := _frame(self, Rect2(244,224,236,96))
	panel.name = "Commands"
	panel.hide()
	_rule(panel,Rect2(118,13,1,70))
	_rule(panel,Rect2(15,47,207,1))
	var options := [["战斗","fight"],["背包","bag"],["宝可梦","switch"],["逃跑","flee"]]
	for i in options.size():
		var entry: Array = options[i]
		var button := _choice(entry[0],_on_command_kind.bind(entry[1]),17)
		button.name = entry[1]
		UI.place(panel,button,8 + (i%2)*111,6 + floori(i/2.0)*42,111,41)
	return panel

func _open_commands(focus_key := "fight", prompt := "") -> void:
	if battle.galar_rules:battle.cur_a().erase("galar_intent")
	_close_sheet()
	move_menu.hide()
	menu.show()
	field_label.show()
	msg.show()
	msg.size.x = 208
	msg.text = "%s\n要怎么做？" % _display_name(battle.cur_a()) if prompt.is_empty() else prompt
	menu.get_node(focus_key).grab_focus()
	bg.queue_redraw()

func _open_moves() -> void:
	_close_sheet()
	menu.hide()
	msg.hide()
	field_label.hide()
	UI.clear(move_menu)
	move_menu.show()
	_rule(move_menu, Rect2(331,10,1,76))
	var c: Dictionary = battle.cur_a()
	var moves: Array = c.moves
	var first: Button
	var exhausted := not (c.pp as Array).slice(0, moves.size()).any(func(v): return int(v)>0)
	if exhausted:
		first = _choice("挣扎",_on_move.bind(0))
		first.name = "Struggle"
		UI.place(move_menu,first,8,26,311,42)
	for i in (0 if exhausted else mini(moves.size(),4)):
		var mv: Dictionary = Data.move_of(int(moves[i]))
		var base_pp := int(mv.get("pp",0))
		if battle.galar_rules and (c.get("galar_intent",false) or c.has("galar_base_hp")):mv=battle.galar_move(c,mv)
		var b := _choice("",_on_move.bind(i))
		b.name = "Move%d" % i
		b.accessibility_name = str(mv.get("name","招式"))
		UI.place(move_menu,b,8 + (i%2)*160,6 + floori(i/2.0)*42,159,42)
		var name_text := UI.label(str(mv.get("name","?")),15,HUD_INK)
		name_text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UI.place(b,name_text,18,1,138,23)
		var uses := int(c.pp[i])
		b.disabled = uses <= 0
		var power := int(mv.get("power",0))
		var effect := "变化" if str(mv.get("category","")) == "status" else ("威力%d" % power if power > 0 else "威力—")
		var max_pp := base_pp + int(c.get("pp_bonus",{}).get(str(moves[i]),0))
		var details := UI.label("%s · %s · PP %d/%d" % [Data.type_name(str(mv.get("type","normal"))),effect,uses,max_pp],
			10,Color("#5c7369") if uses > 0 else Color("#a05340"))
		UI.place(b,details,18,23,138,15)
		if first == null and not b.disabled:
			first = b
	if not exhausted and moves.size() > 2:
		_rule(move_menu,Rect2(20,47,295,1))
	var special: bool = not battle.available_forms("a").is_empty() or _has_z_move() or battle.can_use_tera("a")
	if special:
		var more := _choice("特殊行动",_open_special,14)
		more.name = "Special"
		UI.place(move_menu,more,338,6,133,41)
		_rule(move_menu,Rect2(349,47,113,1))
	var back := _choice("返回",_open_commands,14)
	UI.place(move_menu,back,338,48 if special else 27,133,42)
	if first: first.grab_focus()
	bg.queue_redraw()

func _close_sheet() -> void:
	if is_instance_valid(sheet):
		remove_child(sheet)
		sheet.queue_free()
		sheet = null
		menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
		move_menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED

func _list_sheet(id: String, title: String, count: int, columns := 1) -> GridContainer:
	_close_sheet()
	var overlay := ColorRect.new()
	overlay.name = id
	overlay.color = Color("#14242a99")
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet = overlay
	menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	move_menu.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	var width := 436 if columns == 2 else 328
	var height := mini(276, 67 + maxi(1,ceili(float(count)/columns))*41)
	var panel := _frame(overlay,Rect2((480-width)/2.0,(320-height)/2.0,width,height))
	UI.place(panel,UI.label(title,18,HUD_INK),20,9,width-112,34)
	var back := _choice("返回",handle_back,14)
	back.name = "Return"
	UI.place(panel,back,width-82,7,72,38)
	back.grab_focus()
	_rule(panel,Rect2(16,46,width-32,1))
	var sc := UI.scroll(panel,Vector2(12,49),Vector2(width-24,height-59))
	sc.follow_focus = true
	var list := GridContainer.new()
	list.columns = columns
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation",4)
	list.add_theme_constant_override("v_separation",1)
	sc.add_child(list)
	return list

func _row(list: GridContainer, caption: String, action: Callable, disabled := false) -> Button:
	var b := _choice(caption,action,14)
	b.disabled = disabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 40
	list.add_child(b)
	if not disabled and not list.has_meta("initial_focus"):
		list.set_meta("initial_focus",true)
		b.grab_focus()
	return b

func _empty(list: GridContainer, caption: String) -> void:
	var info := UI.label(caption,14,HUD_INK)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.custom_minimum_size = Vector2(0,40)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(info)

func handle_back() -> void:
	if state != "menu":
		return
	if is_instance_valid(sheet):
		match str(sheet.name):
			"ZPanel":
				_open_special()
			"SpecialPanel", "FormPanel":
				_open_moves()
				if move_menu.has_node("Special"): move_menu.get_node("Special").grab_focus()
			"BallPanel":
				_open_commands("bag")
			"SwitchPanel":
				_open_commands("switch")
	elif move_menu.visible:
		_open_commands()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and state == "menu":
		get_viewport().set_input_as_handled()
		handle_back()

func _draw_bg() -> void:
	bg.draw_texture_rect(backdrop_texture,Rect2(0,0,size.x,224),false)
	var width := 250.0 if is_instance_valid(menu) and menu.visible else size.x
	bg.draw_texture_rect(dialogue_texture,Rect2(0,224,width,size.y-224),false)

func _dur(x: float) -> float:
	return 0.02 if fast else x

func _say(text: String) -> void:
	msg.text = text
	pending.append(text)

func _process(delta: float) -> void:
	# 走动式呼吸动画
	var t := Time.get_ticks_msec() / 1000.0
	if player_sprite:
		player_sprite.position.y = float(player_sprite.get_meta("ground_y")) + roundf(sin(t * 2.4)) * 2
	if enemy_sprite:
		enemy_sprite.position.y = float(enemy_sprite.get_meta("ground_y")) + roundf(sin(t * 2.0 + 1.2)) * 2
	_advance_health(delta)

	match state:
		"intro":
			wait -= delta
			if wait <= 0:
				state = "menu"
				_open_commands()
		"resolve":
			if pending.size() > 0:
				wait -= delta
				if wait <= 0:
					msg.text = pending.pop_front()
					_play_health(spoken_lines)
					spoken_lines += 1
					wait = _dur(0.85)
			else:
				wait -= delta
				if wait <= 0:
					_after_resolve()
		"end":
			wait -= delta
			if wait <= 0:
				state = "finished"
				finished.emit(battle.winner)
				queue_free()

func _on_command_kind(kind: String) -> void:
	if frontier_rules!=null and state=="menu":
		if kind=="bag" and frontier_kit.is_valid():
			frontier_kit.call()
			return
		if kind=="bag" or kind=="switch" and frontier_rules.kind=="arena":
			_open_commands("fight","本场禁止使用背包。" if kind=="bag" else "裁判赛按报名顺序出场。")
			return
		if kind=="fight" and frontier_rules.kind=="palace":
			_on_move(0)
			return
	if state != "menu":
		return
	match kind:
		"fight": _open_moves()
		"bag": _open_balls()
		"switch": _open_switch()
		"flee": _try_flee()
		"form": _open_transform()
		"z": _open_z_moves()
		"tera": _do_tera()

func transform_label() -> String:
	return battle.form_action_label("a")

func _has_z_move() -> bool:
	if not battle.can_use_z("a"):
		return false
	var c: Dictionary = battle.cur_a()
	for i in c.moves.size():
		if int(c.pp[i]) > 0 and battle.z_move_of(c,int(c.moves[i])) > 0:
			return true
	return false

func _open_special() -> void:
	var forms: Array = battle.available_forms("a")
	var z := _has_z_move()
	var tera: bool = battle.can_use_tera("a")
	var list := _list_sheet("SpecialPanel","特殊行动",forms.size()+int(z)+int(tera))
	for f in forms:
		_row(list,str(f.label),_do_transform.bind(str(f.key)))
	if z:
		_row(list,"Z 招式",_open_z_moves)
	if tera:
		_row(list,"太晶化  ·  " + Data.type_name(str(battle.cur_a().tera_type)),_do_tera)

func _open_transform() -> void:
	var forms: Array = battle.available_forms("a")
	if forms.is_empty(): return
	var list := _list_sheet("FormPanel","选择变化",forms.size())
	for f in forms:
		_row(list,str(f.label),_do_transform.bind(str(f.key)))

func _open_z_moves() -> void:
	var c: Dictionary = battle.cur_a()
	var list := _list_sheet("ZPanel","选择 Z 招式",c.moves.size())
	for i in c.moves.size():
		var mid := int(c.moves[i])
		var base: Dictionary = Data.move_of(mid)
		var zid: int = battle.z_move_of(c,mid)
		var zname := str(Data.move_of(zid).get("name","暂无 Z 形态"))
		_row(list,"%s → %s" % [base.get("name","?"), zname],_do_z.bind(i),zid<=0 or int(c.pp[i])<=0)

func _begin_resolve() -> void:
	health_cues.clear()
	spoken_lines = 0
	line_offset = 0
	_close_sheet()
	menu.hide()
	move_menu.hide()
	state = "resolve"
	field_label.show()
	msg.show()
	msg.size.x = 437
	bg.queue_redraw()


func _do_z(idx: int) -> void:
	var r: Dictionary = battle.use_z("a", idx)
	if not r.ok:return
	_begin_resolve()
	pending.clear()
	pending.append(String(r.get("text", "")))
	_queue_turn("z:%d" % idx, "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _do_tera() -> void:
	_begin_resolve()
	var r: Dictionary = battle.use_tera("a")
	_apply_appearance(player_sprite, battle.cur_a())
	_queue_health(0, "a", battle.active_a, battle.cur_a())
	pending.clear()
	pending.append(String(r.get("text", "")))
	_queue_turn("item", "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _do_transform(form_key: String) -> void:
	if battle.galar_rules:
		if form_key!="DYNAMAX" or battle.available_forms("a").is_empty():return
		battle.cur_a().galar_intent=true
		_open_moves()
		return
	if kalos_rules or alola_rules:
		var active: Dictionary=battle.cur_a()
		if not battle.available_forms("a").any(func(form):return form.key==form_key):return
		active.kalos_intent=form_key
		_open_moves()
		return
	_begin_resolve()
	var r: Dictionary = battle.transform("a", form_key)
	_apply_appearance(player_sprite, battle.cur_a())
	_queue_health(0, "a", battle.active_a, battle.cur_a())
	pending.clear()
	pending.append(String(r.get("text", "")))
	# 变形算这一回合的行动，对手照样出手
	_queue_turn("item", "move:0")
	msg.text = ""
	wait = _dur(0.1)

const BALL_BONUS := {"究极球":1.0,"重复球":1.0,"巢穴球":1.0,"捕网球":1.0,"潜水球":1.0,"先机球":1.0,"黑暗球":1.0,"治愈球":1.0,"豪华球":1.0, "纪念球":1.0, "计时球":1.0, "竞赛球":1.5, "精灵球": 1.0, "超级球": 1.5, "高级球": 2.0, "大师球": 255.0, "等级球":1.0, "诱饵球":1.0, "月亮球":1.0, "友友球":1.0, "速度球":1.0, "沉重球":1.0, "甜蜜球":1.0}

## Share the field bag with battle. Trainer battles only allow battle supplies.
func _open_balls() -> void:
	if state != "menu": return
	var choices: Array = bag.filter(func(it):
		return it is Dictionary and int(it.get("count", 0)) > 0 and (
			(trainer_name.is_empty() and (BALL_BONUS.has(str(it.get("name", ""))) or it.get("name","")=="向尾喵的尾巴")) or
			str(it.get("name", "")) in Data.FIELD_BATTLE_ITEMS.values() or str(it.get("name","")) in ["蓝色玻璃哨","黄色玻璃哨","红色玻璃哨"]))
	if not trainer_name.is_empty() and choices.is_empty():
		_open_commands("bag", "训练家对战不能投球。")
		return
	var list := _list_sheet("BallPanel", "战斗背包", choices.size())
	if choices.is_empty():
		_empty(list, "训练家对战不能投球。" if not trainer_name.is_empty() else "没有可用的战斗道具。")
	for item in choices:
		var item_name := str(item.name)
		var action := _throw.bind(item_name) if BALL_BONUS.has(item_name) else _use_booster.bind(item_name)
		_row(list, "%s    ×%d" % [item_name, item.count], action)

func _use_booster(item_name: String) -> void:
	if not bag.any(func(it): return it is Dictionary and it.get("name", "") == item_name and int(it.get("count", 0)) > 0):
		return
	if item_name=="向尾喵的尾巴" and trainer_name.is_empty():
		battle.over=true
		battle.fled=true
		battle.winner="fled"
		item_used.emit(item_name)
		_begin_resolve()
		pending=["利用向尾喵的尾巴分散了野生宝可梦的注意，成功逃走了！"]
		return
	var reusable := item_name in ["蓝色玻璃哨","黄色玻璃哨","红色玻璃哨"]
	var key := str(Data.FIELD_BATTLE_ITEMS.find_key(item_name))
	var effect: bool = preload("res://core/hoenn_items.gd").flute_effect(battle.cur_a(),item_name) if reusable else battle.use_battle_item("a", key)
	if not effect:
		_open_commands("bag", "现在使用没有效果。")
		return
	_begin_resolve()
	pending.clear()
	pending.append("使用了%s！" % item_name)
	pending.append_array(battle.log)
	battle.log.clear()
	if not reusable: item_used.emit(item_name)
	_queue_turn("item", "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _throw(ball_name: String) -> void:
	_begin_resolve()
	pending.clear()
	item_used.emit(ball_name)
	var res: Dictionary = battle.throw_ball(float(BALL_BONUS.get(ball_name, 1.0)), ball_name)
	pending.append("投出了 " + ball_name + "！")
	var shakes := int(res.get("shakes", 0))
	if shakes >= 3:
		pending.append("……咔哒！")
	elif shakes > 0:
		pending.append("晃了 %d 下…" % shakes)
	pending.append(String(res.get("text", "")))
	msg.text = ""
	wait = _dur(0.1)
	if not bool(res.get("ok", false)) and ball_name=="竞赛球" and bag.all(func(it):return int(it.get("count",0))<=0):
		pending.append("竞赛球已经用完。回到会场参加评选！")
		battle.over=true
		battle.winner="fled"
	elif not bool(res.get("ok", false)):
		# 没抓到就轮对手出招，接在一句话后面播
		_queue_turn("item", "move:0")

## 换人面板：只列没倒下的、且不是当前上场的那只，避免出现两个自己
func _open_switch() -> void:
	if state != "menu": return
	var list := _list_sheet("SwitchPanel","选择上场的宝可梦",player_team.size(),2)
	for i in player_team.size():
		var mon: Dictionary = player_team[i]
		var active := i == int(battle.active_a)
		var fainted := bool(mon.get("fainted",false))
		var b := _row(list,"",_do_switch.bind(i),active or fainted)
		b.accessibility_name = "%s  Lv.%d  %d/%d" % [mon.name,mon.level,mon.hp,mon.max_hp]
		var image := UI.member_portrait(mon)
		UI.place(b,image,14,0,40,40)
		var title := UI.label(str(mon.name),14,HUD_INK)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UI.place(b,title,56,0,140,22)
		var stats := "Lv.%d   %d/%d" % [mon.level,mon.hp,mon.max_hp]
		if active: stats += "   场上"
		elif fainted: stats += "   已倒下"
		UI.place(b,UI.label(stats,10,Color("#5c7369")),56,21,140,17)

func _try_flee() -> void:
	if state != "menu":
		return
	if trainer_name != "":
		_open_commands("flee","训练家对战不能逃跑。")
		return
	_begin_resolve()
	pending.clear()
	var res: Dictionary = battle.try_flee()
	pending.append(String(res.get("text", "")))
	if not bool(res.get("ok", false)):
		_queue_turn("item", "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _do_switch(index: int) -> void:
	_begin_resolve()
	pending.clear()
	_queue_turn("switch:%d" % index, "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _on_move(i: int) -> void:
	if state != "menu":
		return
	move_menu.visible = false
	_begin_resolve()
	pending.clear()
	_queue_turn("move:%d" % i, "move:0")
	msg.text = ""
	wait = _dur(0.1)

func _queue_turn(player: String, opponent: String) -> void:
	line_offset = pending.size()
	if frontier_rules!=null:frontier_rules.turn(battle,player)
	else:battle.run_turn(player, opponent)
	pending.append_array(battle.log)
	battle.log.clear()
	# Some passive effects change HP without adding a line of their own.
	if health_cues.has(pending.size()):
		pending.append("")

func _queue_health(line: int, side: String, slot: int, mon: Dictionary) -> void:
	if state != "resolve": return
	var index := line_offset + line
	if not health_cues.has(index): health_cues[index] = {}
	var sample := mon.duplicate()
	sample["slot"] = slot
	health_cues[index][side] = sample

func _play_health(index: int) -> void:
	for side in health_cues.get(index, {}):
		var sample: Dictionary = health_cues[index][side]
		var box := player_hp if side == "a" else enemy_hp
		var sprite := player_sprite if side == "a" else enemy_sprite
		var before := int(box.get_meta("shown_hp", sample.hp))
		var same := int(box.get_meta("slot")) == int(sample.slot) and int(box.get_meta("max_hp")) == int(sample.max_hp)
		box.set_meta("slot", sample.slot)
		_apply_appearance(sprite, sample)
		_update_hpbox(box, sample)
		if same and before != int(sample.hp):
			_draw_hp(box, before, int(sample.max_hp))
			var fraction := absf(float(before - int(sample.hp)) / maxi(1, int(sample.max_hp)))
			health_motion[side] = {"from":before, "to":int(sample.hp), "max":int(sample.max_hp),
				"time":0.0, "duration":_dur(clampf(0.20 + fraction * 0.48, 0.20, 0.68))}
		else:
			health_motion.erase(side)
			sprite.modulate = Color.WHITE

func _advance_health(delta: float) -> void:
	for side in health_motion.keys():
		var anim: Dictionary = health_motion[side]
		anim.time = minf(float(anim.duration), float(anim.time) + delta)
		var t := float(anim.time) / float(anim.duration)
		var box := player_hp if side == "a" else enemy_hp
		var sprite := player_sprite if side == "a" else enemy_sprite
		_draw_hp(box, roundi(lerpf(float(anim.from), float(anim.to), t)), int(anim.max))
		if int(anim.to) < int(anim.from):
			sprite.modulate = Color.WHITE.darkened(0.38 if t < 0.65 and int(t * 9) % 2 == 0 else 0.0)
		if t >= 1.0:
			sprite.modulate = Color.WHITE
			health_motion.erase(side)

func _after_resolve() -> void:
	_refresh_hp()
	if battle.over:
		state = "end"
		wait = _dur(1.0)
		match battle.winner:
			"caught":
				msg.text = "抓到了！"
			"fled":
				msg.text = "成功逃走了！"
			"a":
				msg.text = "打赢了！"
			"b":
				msg.text = "眼前一黑…"
			_:
				msg.text = "平局。"
	else:
		state = "menu"
		_open_commands()
	_refresh_field_label()

func _refresh_hp() -> void:
	_update_hpbox(player_hp, battle.cur_a())
	_update_hpbox(enemy_hp, battle.cur_b())
	_sync_sprites()
	_refresh_field_label()

## 天气 / 场地 / 屏障 / 撒菱：拼成一行小字，没有就清空
func _refresh_field_label() -> void:
	if field_label == null or not is_instance_valid(field_label):
		return
	var parts: Array = []
	if battle == null:
		field_label.text = ""
		return
	var f = battle.field
	if f == null:
		field_label.text = ""
		return
	if battle.galar_rules:
		for pair in [[battle.cur_a(),"我方"],[battle.cur_b(),"对手"]]:
			if pair[0].has("galar_turns"): parts.append("%s极巨 %d"%[pair[1],int(pair[0].galar_turns)])
	if String(f.weather) != "":
		var wn: String = {"sun": "晴", "rain": "雨", "sandstorm": "沙暴",
			"snow": "雪", "fog": "雾"}.get(String(f.weather), String(f.weather))
		parts.append("%s%d" % [wn, int(f.weather_turns)])
	if String(f.terrain) != "":
		var tn: String = {"electric": "电气", "grassy": "青草",
			"misty": "薄雾", "psychic": "精神"}.get(String(f.terrain), String(f.terrain))
		parts.append("%s%d" % [tn, int(f.terrain_turns)])
	if int(f.gravity_turns) > 0:
		parts.append("重力%d" % int(f.gravity_turns))
	if not (f.screens["b"] as Dictionary).is_empty():
		parts.append("敌屏障")
	if not (f.screens["a"] as Dictionary).is_empty():
		parts.append("我屏障")
	var hb: Dictionary = f.hazards["b"]
	if int(hb.get("spikes", 0)) > 0 or bool(hb.get("stealth_rock", false)) \
			or int(hb.get("toxic_spikes", 0)) > 0 or bool(hb.get("sticky_web", false)) \
			or bool(hb.get("steel_rocks", false)):
		parts.append("敌钉子")
	field_label.text = " ".join(PackedStringArray(parts))

## 换人后精灵与名字都要跟着换，否则两只叠在一起
func _sync_sprites() -> void:
	_apply_appearance(player_sprite, battle.cur_a())
	_apply_appearance(enemy_sprite, battle.cur_b())

func _display_name(mon: Dictionary) -> String:
	var marker: String = {"star":"★ ", "square":"◇ "}.get(Party.shiny_kind(mon), "")
	var display := str(mon.get("name", "?"))
	var form := str(mon.get("form", ""))
	if not form.is_empty():
		var sid := int(mon.get("species_id", 0))
		var base := str(Data.species_of(sid).get("name", ""))
		if display.begins_with(base + "（"):
			for variant in DexCatalog.variants(sid):
				if int(variant.species_id) == sid and variant.get("form", "") == form:
					var label := str(variant.label).trim_suffix("的样子")
					display = label if label.contains(base) else base + "·" + label
					break
	return marker + display

func _set_hpbox_name(label: Label, mon: Dictionary) -> void:
	label.text = _display_name(mon)
	var font := label.get_theme_font("font")
	var points := 15
	while points > 9 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > label.size.x:
		points -= 1
	label.add_theme_font_size_override("font_size", points)

func _apply_appearance(sprite: TextureRect, mon: Dictionary) -> void:
	var sid := int(mon.get("species_id", 0))
	var form := str(mon.get("form", ""))
	var shine := Party.shiny_kind(mon)
	var tera := str(mon.get("tera_type", "")) if mon.get("tera_active", false) else ""
	var giant := bool(mon.get("gmax_active", false))
	var identity := "%d|%s|%s|%s|%s" % [sid, form, shine, tera, giant]
	if sprite.get_meta("identity", "") == identity:
		return
	sprite.set_meta("identity", identity)
	var rear := bool(sprite.get_meta("rear", false))
	var texture := DexArt.battle_texture(sid, form, shine != "none", rear)
	sprite.texture = texture if texture != null else load(Data.sprite_path(sid, form))
	var feet := float(sprite.texture.get_meta("feet", 56))
	var size_factor:=float(sprite.get_meta("normal_scale",2.0))*(1.28 if mon.has("galar_base_hp") else 1.0)
	sprite.scale=Vector2.ONE*size_factor
	sprite.position.x=float(sprite.get_meta("home_x",sprite.position.x))-32.0*(size_factor-2.0)
	var ground_y := (222.0 if rear else 134.0) - feet * size_factor
	sprite.set_meta("ground_y", ground_y)
	sprite.position.y = ground_y
	var effect = sprite.get_node("Appearance")
	effect.shine = shine
	effect.tera = tera
	effect.giant = giant
	effect.visible = shine != "none" or tera != "" or effect.giant
	effect.set_process(effect.visible)
	effect.queue_redraw()
	if bg: bg.queue_redraw()

func _draw_hp(box: Control, hp: int, maximum: int) -> void:
	var track: ColorRect = box.get_node("Track")
	var fill: ColorRect = box.get_node("Fill")
	var hp_l: Label = box.get_node("HP")
	var ratio := clampf(float(hp) / maxi(1, maximum), 0.0, 1.0)
	fill.size = Vector2(roundf(track.size.x * ratio), track.size.y)
	fill.color = HP_HI if ratio > 0.5 else (HP_MID if ratio > 0.2 else HP_LO)
	hp_l.text = "%d/%d" % [hp, maximum]
	box.set_meta("shown_hp", hp)
	box.set_meta("max_hp", maximum)

func _update_hpbox(box: Control, c: Dictionary) -> void:
	_draw_hp(box, int(c.hp), int(c.max_hp))
	var exp_fill := box.get_node_or_null("ExpFill") as ColorRect
	if exp_fill:
		var species := Data.species_of(int(c.species_id))
		var ratio_exp := Growth.progress(int(c.get("exp", 0)), int(c.level), str(species.get("growth", "medium_fast")))
		exp_fill.size = Vector2(roundf(ratio_exp * 64) * 2, 4)
	var nm: Label = box.get_node_or_null("Name")
	if nm:
		_set_hpbox_name(nm, c)
	var lv2: Label = box.get_node_or_null("Lv")
	if lv2:
		lv2.text = "Lv %d" % int(c.get("level", 1))
