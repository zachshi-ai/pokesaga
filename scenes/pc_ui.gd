extends Control
## 电脑：200 个箱子，每箱 30 格。素材用游戏里那套宝可梦图。
## 队伍里的宝可梦可以存进去，箱子里的可以取出来。

signal closed

const INK := Color(0.05, 0.08, 0.12, 0.97)
const CREAM := Color(0.95, 0.96, 0.93)
const MINT := Color(0.42, 0.80, 0.72)
const DIM := Color(0.55, 0.62, 0.64)
const BOXES := 200
const PER_BOX := 30
const COLS := 6
const CELL := Vector2(52, 46)

var boxes: Array = []      # [{name, mons:[{...}|{}]}]
var party: Array = []
var box_index := 0
var sel := -1
var info: Label
var grid: Control
var title: Label
var on_change := Callable()

var _tex_cache: Dictionary = {}


func setup(p_boxes: Array, p_party: Array) -> void:
	boxes = p_boxes
	party = p_party
	if boxes.is_empty():
		boxes = _empty_boxes()
	_build()


func _empty_boxes() -> Array:
	var out: Array = []
	for i in BOXES:
		out.append({"name": "箱子 %d" % (i + 1), "mons": []})
	return out


func _mon_tex(sid: int) -> Texture2D:
	if _tex_cache.has(sid):
		return _tex_cache[sid]
	var p := "res://assets/mon/%d.png" % sid
	var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
	_tex_cache[sid] = t
	return t


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

	title = Label.new()
	title.position = Vector2(20, 12)
	title.size = Vector2(vp.x - 40, 24)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", CREAM)
	add_child(title)

	var prev := _btn("◀", Vector2(vp.x - 96, 10))
	prev.pressed.connect(func() -> void: _turn(-1))
	var nxt := _btn("▶", Vector2(vp.x - 56, 10))
	nxt.pressed.connect(func() -> void: _turn(1))
	var cls := _btn("关闭", Vector2(20, vp.y - 40))
	cls.pressed.connect(func() -> void:
		if on_change.is_valid():
			on_change.call(boxes, party)
		closed.emit()
		queue_free())

	grid = Control.new()
	grid.position = Vector2(20, 44)
	grid.size = Vector2(COLS * CELL.x, 5 * CELL.y)
	add_child(grid)

	info = Label.new()
	info.position = Vector2(20 + COLS * CELL.x + 16, 44)
	info.size = Vector2(vp.x - (COLS * CELL.x) - 56, vp.y - 100)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", CREAM)
	add_child(info)

	_refresh()


func _btn(text: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = Vector2(34, 24) if text.length() < 3 else Vector2(56, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.add_theme_color_override("font_color", CREAM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.15, 0.20, 0.95)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.42, 0.78, 0.72, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	add_child(b)
	return b


func _turn(d: int) -> void:
	box_index = (box_index + d + BOXES) % BOXES
	sel = -1
	_refresh()


func _refresh() -> void:
	var box: Dictionary = boxes[box_index]
	var mons: Array = box.get("mons", [])
	title.text = "%s   （第 %d / %d 箱，共 %d 只）" % [String(box.get("name", "箱子")),
		box_index + 1, BOXES, mons.size()]
	for c in grid.get_children():
		c.queue_free()
	for i in PER_BOX:
		var x := (i % COLS) * CELL.x
		var y := (i / COLS) * CELL.y
		var b := Button.new()
		b.position = Vector2(x, y)
		b.size = Vector2(CELL.x - 4, CELL.y - 4)
		b.add_theme_stylebox_override("normal", _cell_style(sel == i))
		b.add_theme_stylebox_override("hover", _cell_style(true))
		b.add_theme_stylebox_override("pressed", _cell_style(true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if i < mons.size() and not (mons[i] as Dictionary).is_empty():
			var m: Dictionary = mons[i]
			var tex := _mon_tex(int(m.get("species_id", 0)))
			if tex:
				var icon := TextureRect.new()
				icon.texture = tex
				icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.position = Vector2(4, 4)
				icon.size = Vector2(CELL.x - 12, CELL.y - 18)
				b.add_child(icon)
			var lb := Label.new()
			lb.text = "%s L%d" % [String(m.get("name", "")), int(m.get("level", 1))]
			lb.position = Vector2(2, CELL.y - 18)
			lb.add_theme_font_size_override("font_size", 9)
			lb.add_theme_color_override("font_color", CREAM)
			b.add_child(lb)
			var idx := i
			b.pressed.connect(func() -> void: _click_box(idx))
		else:
			b.disabled = true
		grid.add_child(b)
	_refresh_info()


func _cell_style(active: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.22, 0.28, 0.9) if active else Color(0.09, 0.13, 0.18, 0.85)
	sb.set_corner_radius_all(5)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = MINT if active else Color(0.30, 0.45, 0.45, 0.5)
	return sb


func _click_box(i: int) -> void:
	sel = i
	var mons: Array = boxes[box_index]["mons"]
	if i < mons.size() and not (mons[i] as Dictionary).is_empty():
		# 取出：队伍没满就进队伍
		if party.size() < 6:
			party.append(mons[i])
			mons.remove_at(i)
			sel = -1
			_commit()
			_refresh()
			return
		info.text = "队伍已经满了（6 只），先把队伍里的存进箱子。"
		return
	# 空格子：把队伍里的存进去
	if not party.is_empty():
		var last: Dictionary = party[party.size() - 1]
		mons.append(last)
		party.remove_at(party.size() - 1)
		_commit()
		_refresh()


func _commit() -> void:
	if on_change.is_valid():
		on_change.call(boxes, party)


func _refresh_info() -> void:
	var mons: Array = boxes[box_index]["mons"]
	var lines: Array = ["队伍：%d / 6" % party.size()]
	for m in party:
		if m is Dictionary and not m.is_empty():
			lines.append("  %s Lv.%d" % [String(m.get("name", "")), int(m.get("level", 1))])
	lines.append("")
	lines.append("点箱子里的宝可梦取回队伍；点空格把队伍最后一只存进箱子。")
	lines.append("◀ ▶ 换箱子，一共 200 箱。")
	info.text = "\n".join(lines)
