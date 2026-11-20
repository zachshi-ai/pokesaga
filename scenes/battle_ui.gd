extends Control
## 战斗界面。逻辑在 core/battle.gd，这里只负责画和收输入。

signal finished(result: String)
signal item_used(item_name: String)

const Party := preload("res://core/party.gd")
const DexArt := preload("res://core/dex_art.gd")
const DexEffect := preload("res://core/dex_effect.gd")

const INK := Color(0.06, 0.09, 0.13, 0.94)
const INK_SOFT := Color(0.10, 0.14, 0.20, 0.96)
const MINT := Color(0.42, 0.80, 0.72)
const CREAM := Color(0.95, 0.96, 0.93)
const DIM := Color(0.62, 0.68, 0.70)
const HP_HI := Color(0.42, 0.82, 0.52)
const HP_MID := Color(0.94, 0.78, 0.34)

const HP_LO := Color(0.90, 0.40, 0.36)

var battle
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
var flash_t := 0.0
var trainer_name := ""
var fast := false   # 自检时压缩等待
var shake_t := 0.0
var bag: Array = []          # 只读引用，投球时弹窗列出来
var field_label: Label      # 顶部的天气 / 场地提示

func setup(p_team: Array, e_team: Array, seed_value: int = 0, p_bag: Array = [], trainer := "") -> void:
	trainer_name = trainer
	player_team = p_team
	enemy_team = e_team
	bag = p_bag
	battle = preload("res://core/battle.gd").new(seed_value)
	if observe_variant.is_valid():
		battle.variant_seen.connect(observe_variant)
	battle.start(player_team, enemy_team)
	_build()
	var opponent := _display_name(battle.cur_b())
	_say("野生的 %s 出现了！" % opponent if trainer_name == "" else "%s 派出了 %s！" % [trainer_name, opponent])
	state = "intro"
	wait = _dur(0.9)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	position = Vector2.ZERO

	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.draw.connect(_draw_bg)
	add_child(bg)

	# 站位：敌右上方、我左下方，都留出与血条框、底栏的空隙
	enemy_sprite = _make_sprite(battle.cur_b(), Vector2(318, 44), 2.0)
	player_sprite = _make_sprite(battle.cur_a(), Vector2(70, 92), 2.0)

	enemy_hp = _make_hpbox(Vector2(12, 12), battle.cur_b())
	player_hp = _make_hpbox(Vector2(274, 158), battle.cur_a())
	enemy_hp.name = "EnemyHP"
	player_hp.name = "PlayerHP"

	# 天气与场地：放在底部文字框上方那一行，右侧留给指令，不压血条也不压文字
	field_label = Label.new()
	field_label.position = Vector2(22, 233)
	field_label.size = Vector2(276, 13)
	field_label.clip_text = true
	field_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	field_label.add_theme_font_size_override("font_size", 10)
	field_label.add_theme_color_override("font_color", MINT)
	add_child(field_label)

	# 底部整条底板：左文右令，避免文字直接压在地图上
	var bottom := _panel(Vector2(6, 232), Vector2(300, 82), 14)
	add_child(bottom)

	msg = Label.new()
	msg.position = Vector2(24, 246)
	msg.size = Vector2(258, 56)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	msg.add_theme_font_size_override("font_size", 15)
	msg.add_theme_color_override("font_color", CREAM)
	add_child(msg)

	menu = _make_menu()
	move_menu = _make_move_menu()
	move_menu.visible = false

func _panel(pos: Vector2, size: Vector2, radius := 8) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = INK
	sb.set_corner_radius_all(radius)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.35)
	p.add_theme_stylebox_override("panel", sb)
	return p

func _make_sprite(c: Dictionary, pos: Vector2, scale_f: float) -> TextureRect:
	var t := TextureRect.new()
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var effect := DexEffect.new()
	effect.name = "Appearance"
	t.add_child(effect)
	effect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_appearance(t, c)
	t.position = pos
	t.custom_minimum_size = Vector2(64, 64)
	t.size = Vector2(64, 64)
	t.scale = Vector2(scale_f, scale_f)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(t)
	return t

func _make_hpbox(pos: Vector2, c: Dictionary) -> Control:
	var box := _panel(pos, Vector2(194, 62), 10)
	add_child(box)

	var name_l := Label.new()
	name_l.name = "Name"
	name_l.position = Vector2(12, 5)
	name_l.clip_text = true
	name_l.size = Vector2(126, 20)
	name_l.text = _display_name(c)
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", CREAM)
	box.add_child(name_l)

	var lv := Label.new()
	lv.name = "Lv"
	lv.position = Vector2(146, 8)
	lv.text = "Lv %d" % int(c.get("level", 1))
	lv.add_theme_font_size_override("font_size", 12)
	lv.add_theme_color_override("font_color", DIM)
	box.add_child(lv)

	var track := ColorRect.new()
	track.name = "Track"
	track.position = Vector2(12, 34)
	track.size = Vector2(168, 8)
	track.color = Color(1, 1, 1, 0.14)
	box.add_child(track)

	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(12, 34)
	fill.size = Vector2(168, 8)
	fill.color = HP_HI
	box.add_child(fill)

	var hp_l := Label.new()
	hp_l.name = "HP"
	hp_l.position = Vector2(12, 44)
	hp_l.text = "%d/%d" % [int(c.get("hp", 0)), int(c.get("max_hp", 1))]
	hp_l.add_theme_font_size_override("font_size", 11)
	hp_l.add_theme_color_override("font_color", DIM)
	box.add_child(hp_l)
	return box

func _make_menu() -> Control:
	# 底板收窄后右侧整列归指令：上排三个变化类指令，下面 2×2 常规四格
	var extra: Array = []
	if not battle.available_forms("a").is_empty():
		extra.append([transform_label(), "form"])
	if battle.can_use_z("a"):
		extra.append(["Z招式", "z"])
	if battle.can_use_tera("a"):
		extra.append(["太晶化", "tera"])

	var h := 2 * 32 + 2
	if not extra.is_empty():
		h += 30
	var wrap := Control.new()
	wrap.size = Vector2(156, h)
	wrap.position = Vector2(312, 318 - h)
	add_child(wrap)

	var base_y := 0
	if not extra.is_empty():
		var w := 50.0
		for i in extra.size():
			wrap.add_child(_cmd_button(String(extra[i][0]), String(extra[i][1]),
				Vector2(i * (w + 3), 0), Vector2(w, 26)))
		base_y = 30

	var items: Array = [["战斗", "fight"], ["背包", "bag"], ["宝可梦", "switch"], ["逃跑", "flee"]]
	for i in items.size():
		wrap.add_child(_cmd_button(String(items[i][0]), String(items[i][1]),
			Vector2((i % 2) * 76, base_y + (i / 2) * 32)))
	return wrap

func _cmd_button(text: String, kind: String, pos: Vector2, sz := Vector2(72, 28)) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.add_theme_font_size_override("font_size", 14)
	_style_button(b)
	b.pressed.connect(_on_command_kind.bind(kind))
	return b

func _style_button(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = INK_SOFT if st == "normal" else Color(0.16, 0.24, 0.30, 0.98)
		sb.set_corner_radius_all(7)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(MINT.r, MINT.g, MINT.b, 0.5)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))

func _make_move_menu() -> Control:
	var wrap := Control.new()
	wrap.position = Vector2(312, 242)
	wrap.size = Vector2(156, 72)
	add_child(wrap)

	var c: Dictionary = battle.cur_a()
	var moves: Array = c.get("moves", [])
	for i in 4:
		var b := Button.new()
		b.position = Vector2((i % 2) * 76, (i / 2) * 32)
		b.size = Vector2(74, 28)
		b.add_theme_font_size_override("font_size", 12)
		_style_button(b)
		if i < moves.size():
			var mv: Dictionary = Data.move_of(int(moves[i]))
			b.text = "%s" % String(mv.get("name", "?"))
			b.tooltip_text = "威力 %d  PP %d" % [int(mv.get("power", 0)), int(c["pp"][i])]
			b.pressed.connect(_on_move.bind(i))
		else:
			b.disabled = true
			b.text = "—"
		wrap.add_child(b)
	return wrap

func _draw_bg() -> void:
	var W := size.x
	var H := size.y
	# 天空
	for i in 40:
		var t := float(i) / 40.0
		var col := Color(0.62, 0.82, 0.90).lerp(Color(0.86, 0.94, 0.92), t)
		bg.draw_rect(Rect2(0, H * 0.5 * t, W, H * 0.5 / 40.0 + 1), col)
	# 草地
	bg.draw_rect(Rect2(0, H * 0.5, W, H * 0.5), Color(0.45, 0.66, 0.42))
	bg.draw_rect(Rect2(0, H * 0.5, W, 6), Color(0.55, 0.75, 0.50))
	# 平台
	bg.draw_set_transform(Vector2(120, 214), 0, Vector2(1, 0.32))
	bg.draw_circle(Vector2.ZERO, 86, Color(0.40, 0.60, 0.38))
	bg.draw_set_transform(Vector2(352, 118), 0, Vector2(1, 0.30))
	bg.draw_circle(Vector2.ZERO, 74, Color(0.42, 0.62, 0.40))
	bg.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _dur(x: float) -> float:
	return 0.02 if fast else x

func _say(text: String) -> void:
	msg.text = text
	pending.append(text)

func _process(delta: float) -> void:
	# 走动式呼吸动画
	var t := Time.get_ticks_msec() / 1000.0
	if player_sprite:
		player_sprite.position.y = 92 + sin(t * 2.4) * 2.0
	if enemy_sprite:
		enemy_sprite.position.y = 44 + sin(t * 2.0 + 1.2) * 2.0
	if flash_t > 0:
		flash_t -= delta
		var f: float = 0.55 + 0.45 * abs(sin(flash_t * 40))
		enemy_sprite.modulate = Color(f, f, f)

	match state:
		"intro":
			wait -= delta
			if wait <= 0:
				state = "menu"
				menu.visible = true
				move_menu.visible = false
		"resolve":
			if pending.size() > 0:
				wait -= delta
				if wait <= 0:
					msg.text = pending.pop_front()
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

func _on_command(i: int) -> void:
	match i:
		0:
			menu.visible = false
			move_menu.visible = true
		1:
			menu.visible = false
			_open_balls()
		2:
			menu.visible = false
			_open_switch()
		3:
			_try_flee()
		4:
			menu.visible = false
			_open_transform()

func _on_command_kind(kind: String) -> void:
	match kind:
		"fight":
			menu.visible = false
			move_menu.visible = true
		"bag":
			menu.visible = false
			_open_balls()
		"switch":
			menu.visible = false
			_open_switch()
		"flee":
			_try_flee()
		"form":
			menu.visible = false
			_open_transform()
		"z":
			menu.visible = false
			_open_z_moves()
		"tera":
			_do_tera()

## 按钮上写「Mega 进化」还是「极巨化」，看这只本来能变什么
func transform_label() -> String:
	return battle.form_action_label("a")

## 形态面板：一只可能有 Mega X / Mega Y 两种，让玩家自己选
func _open_transform() -> void:
	if state != "menu":
		return
	var forms: Array = battle.available_forms("a")
	if forms.is_empty():
		menu.visible = true
		return
	var panel := Control.new()
	panel.name = "FormPanel"
	panel.position = Vector2(140, 60)
	panel.size = Vector2(200, 120)
	add_child(panel)
	var bg := _panel(Vector2.ZERO, Vector2(200, 40 + forms.size() * 34), 10)
	panel.add_child(bg)
	var title := Label.new()
	title.text = "选择变化"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MINT)
	panel.add_child(title)
	for i in forms.size():
		var f: Dictionary = forms[i]
		var b := Button.new()
		b.text = String(f.get("label", "形态"))
		b.position = Vector2(12, 32 + i * 34)
		b.size = Vector2(176, 28)
		_style_button(b)
		b.pressed.connect(func() -> void:
			panel.queue_free()
			_do_transform(String(f.get("key", ""))))
		panel.add_child(b)
	var back := Button.new()
	back.text = "返回"
	back.position = Vector2(12, 32 + forms.size() * 34)
	back.size = Vector2(176, 26)
	_style_button(back)
	back.pressed.connect(func() -> void:
		panel.queue_free()
		menu.visible = true)
	panel.add_child(back)

## Z 招式面板：把这一招换成它的 Z 版本打出去
func _open_z_moves() -> void:
	if state != "menu":
		return
	var c: Dictionary = battle.cur_a()
	var moves: Array = c.get("moves", [])
	var panel := Control.new()
	panel.name = "ZPanel"
	panel.position = Vector2(120, 60)
	add_child(panel)
	var h := 44 + moves.size() * 30 + 30
	panel.add_child(_panel(Vector2.ZERO, Vector2(240, h), 10))
	var title := Label.new()
	title.text = "用哪一招发动 Z 力量"
	title.position = Vector2(12, 8)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MINT)
	panel.add_child(title)
	for i in moves.size():
		var mid := int(moves[i])
		if mid <= 0:
			continue
		var base: Dictionary = Data.move_of(mid)
		var zid: int = battle.z_move_of(c, mid)
		var zname := String((Data.move_of(zid) as Dictionary).get("name", ""))
		var b := Button.new()
		b.text = "%s  →  %s" % [String(base.get("name", "?")), zname]
		b.position = Vector2(12, 30 + i * 30)
		b.size = Vector2(216, 26)
		b.add_theme_font_size_override("font_size", 11)
		_style_button(b)
		b.pressed.connect(func() -> void:
			panel.queue_free()
			_do_z(i))
		panel.add_child(b)
	var back := Button.new()
	back.text = "返回"
	back.position = Vector2(12, 34 + moves.size() * 30)
	back.size = Vector2(216, 24)
	_style_button(back)
	back.pressed.connect(func() -> void:
		panel.queue_free()
		menu.visible = true)
	panel.add_child(back)

func _do_z(idx: int) -> void:
	var r: Dictionary = battle.use_z("a", idx)
	state = "resolve"
	pending.clear()
	pending.append(String(r.get("text", "")))
	battle.run_turn("z:%d" % idx, "move:0")
	for line in battle.log:
		pending.append(String(line))
	battle.log.clear()
	_sync_sprites()
	_refresh_hp()
	msg.text = ""
	wait = _dur(0.1)
	flash_t = 0.3

func _do_tera() -> void:
	var r: Dictionary = battle.use_tera("a")
	state = "resolve"
	pending.clear()
	pending.append(String(r.get("text", "")))
	battle.run_turn("item", "move:0")
	for line in battle.log:
		pending.append(String(line))
	battle.log.clear()
	_sync_sprites()
	_refresh_hp()
	msg.text = ""
	wait = _dur(0.1)

func _do_transform(form_key: String) -> void:
	var r: Dictionary = battle.transform("a", form_key)
	state = "resolve"
	pending.clear()
	pending.append(String(r.get("text", "")))
	# 变形算这一回合的行动，对手照样出手
	battle.run_turn("item", "move:0")
	for line in battle.log:
		pending.append(String(line))
	battle.log.clear()
	_sync_sprites()
	_refresh_hp()
	msg.text = ""
	wait = _dur(0.1)

const BALL_BONUS := {"精灵球": 1.0, "超级球": 1.5, "高级球": 2.0, "大师球": 255.0}

## 投球面板：只列背包里数量>0 的球，别的道具战斗中不给用
func _open_balls() -> void:
	if state != "menu":
		return
	if trainer_name != "":
		menu.visible = true
		msg.text = "训练家对战不能投球。"
		return
	var ball_rows: Array = []
	for it in bag:
		if not (it is Dictionary):
			continue
		if String((it as Dictionary).get("category", "")) != "ball":
			continue
		if int((it as Dictionary).get("count", 0)) <= 0:
			continue
		ball_rows.append(it)

	var panel := Control.new()
	panel.name = "BallPanel"
	panel.position = Vector2(140, 40)
	add_child(panel)
	var h := 96 + ball_rows.size() * 30
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.10, 1.0)
	bg.size = Vector2(320, h)
	panel.add_child(bg)
	var frame := ReferenceRect.new()
	frame.size = Vector2(320, h)
	frame.border_color = Color(0.55, 0.86, 0.78, 0.9)
	frame.border_width = 1.0
	panel.add_child(frame)

	var title := Label.new()
	title.position = Vector2(12, 8)
	title.text = "用哪个球？"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MINT)
	panel.add_child(title)

	if ball_rows.is_empty():
		var t := Label.new()
		t.position = Vector2(12, 40)
		t.text = "背包里没有精灵球。"
		t.add_theme_font_size_override("font_size", 12)
		t.add_theme_color_override("font_color", CREAM)
		panel.add_child(t)

	for i in ball_rows.size():
		var it: Dictionary = ball_rows[i]
		var b := Button.new()
		b.position = Vector2(12, 34 + i * 30)
		b.size = Vector2(296, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.text = "%s  ×%d" % [String(it.get("name", "?")), int(it.get("count", 0))]
		_style_button(b)
		b.pressed.connect(_throw.bind(String(it.get("name", "精灵球")), panel))
		panel.add_child(b)

	var back := Button.new()
	back.text = "返回"
	back.position = Vector2(12, h - 34)
	back.size = Vector2(296, 26)
	_style_button(back)
	back.pressed.connect(func() -> void:
		panel.queue_free()
		menu.visible = true)
	panel.add_child(back)

func _throw(ball_name: String, panel: Control) -> void:
	panel.queue_free()
	state = "resolve"
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
	if not bool(res.get("ok", false)):
		# 没抓到就轮对手出招，接在一句话后面播
		battle.run_turn("item", "move:0")
		for line in battle.log:
			pending.append(String(line))
		battle.log.clear()

## 换人面板：只列没倒下的、且不是当前上场的那只，避免出现两个自己
func _open_switch() -> void:
	if state != "menu":
		return
	var panel := Control.new()
	panel.name = "SwitchPanel"
	panel.position = Vector2(20, 30)
	add_child(panel)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.08, 0.11, 0.97)
	bg.size = Vector2(440, 90 + ceili(player_team.size() / 2.0) * 28)
	panel.add_child(bg)

	var title := Label.new()
	title.position = Vector2(12, 8)
	title.text = "换哪一只上场？"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", MINT)
	panel.add_child(title)

	var alive_other := 0
	for i in player_team.size():
		var c: Dictionary = player_team[i]
		var b := Button.new()
		b.position = Vector2(12 + (i % 2) * 211, 32 + floori(i / 2.0) * 28)
		b.size = Vector2(207, 26)
		b.add_theme_font_size_override("font_size", 12)
		_style_button(b)
		var is_active: bool = i == int(battle.active_a)
		if bool(c.get("fainted", false)) or is_active:
			b.disabled = true
			b.text = "%s  Lv%d  %s%s" % [String(c.get("name", "?")), int(c.get("level", 1)),
				String(c.get("hp_text", "")), "  （已倒下）" if bool(c.get("fainted", false)) else "  （场上）"]
		else:
			alive_other += 1
			b.text = "%s  Lv%d  %d/%d" % [String(c.get("name", "?")), int(c.get("level", 1)),
				int(c.get("hp", 0)), int(c.get("max_hp", 1))]
			b.pressed.connect(_do_switch.bind(i, panel))
		panel.add_child(b)

	if alive_other == 0:
		var t := Label.new()
		t.position = Vector2(12, bg.size.y - 55)
		t.text = "没有可以换上场的宝可梦。"
		t.add_theme_font_size_override("font_size", 12)
		t.add_theme_color_override("font_color", CREAM)
		panel.add_child(t)

	var back := Button.new()
	back.text = "返回"
	back.position = Vector2(12, bg.size.y - 34)
	back.size = Vector2(416, 26)
	_style_button(back)
	back.pressed.connect(func() -> void:
		panel.queue_free()
		menu.visible = true)
	panel.add_child(back)

func _try_flee() -> void:
	if state != "menu":
		return
	if trainer_name != "":
		msg.text = "训练家对战不能逃跑。"
		return
	state = "resolve"
	pending.clear()
	var res: Dictionary = battle.try_flee()
	pending.append(String(res.get("text", "")))
	if not bool(res.get("ok", false)):
		battle.run_turn("item", "move:0")
		for line in battle.log:
			pending.append(String(line))
		battle.log.clear()
	msg.text = ""
	wait = _dur(0.1)

func _do_switch(index: int, panel: Control) -> void:
	panel.queue_free()
	state = "resolve"
	pending.clear()
	battle.run_turn("switch:%d" % index, "move:0")
	pending = battle.log.duplicate()
	battle.log.clear()
	msg.text = ""
	wait = _dur(0.1)

func _on_move(i: int) -> void:
	if state != "menu":
		return
	move_menu.visible = false
	state = "resolve"
	pending.clear()
	battle.run_turn("move:%d" % i, "move:0")
	pending = battle.log.duplicate()
	battle.log.clear()
	msg.text = ""
	wait = _dur(0.1)
	# 受击闪烁
	flash_t = 0.35

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
		menu.visible = true
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
	return marker + str(mon.get("name", "?"))

func _apply_appearance(sprite: TextureRect, mon: Dictionary) -> void:
	var sid := int(mon.get("species_id", 0))
	var form := str(mon.get("form", ""))
	var shine := Party.shiny_kind(mon)
	var tera := str(mon.get("tera_type", "")) if mon.get("tera_active", false) else ""
	var identity := "%d|%s|%s|%s" % [sid, form, shine, tera]
	if sprite.get_meta("identity", "") == identity:
		return
	sprite.set_meta("identity", identity)
	var texture := DexArt.texture(sid, form, true) if shine != "none" else null
	sprite.texture = texture if texture != null else load(Data.sprite_path(sid, form))
	var effect = sprite.get_node("Appearance")
	effect.shine = shine
	effect.tera = tera
	effect.giant = bool(mon.get("gmax_active", false))
	effect.visible = shine != "none" or tera != "" or effect.giant
	effect.set_process(effect.visible)
	effect.queue_redraw()

func _update_hpbox(box: Control, c: Dictionary) -> void:
	var track: ColorRect = box.get_node("Track")
	var fill: ColorRect = box.get_node("Fill")
	var hp_l: Label = box.get_node("HP")
	var ratio := clampf(float(c["hp"]) / float(max(1, c["max_hp"])), 0.0, 1.0)
	fill.size = Vector2(track.size.x * ratio, track.size.y)
	fill.color = HP_HI if ratio > 0.5 else (HP_MID if ratio > 0.2 else HP_LO)
	hp_l.text = "%d/%d" % [int(c["hp"]), int(c["max_hp"])]
	var nm: Label = box.get_node_or_null("Name")
	if nm:
		nm.text = _display_name(c)
	var lv2: Label = box.get_node_or_null("Lv")
	if lv2:
		lv2.text = "Lv %d" % int(c.get("level", 1))
