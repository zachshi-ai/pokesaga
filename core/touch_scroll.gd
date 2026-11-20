extends RefCounted
## 给 ScrollContainer 补上「手指拖动」。
## Godot 默认只把鼠标滚轮当滚动，触摸拖动要靠 emulate_mouse_from_touch，
## 在手机上经常被系统手势抢走（从屏幕顶部往下拖会把通知栏拉下来）。
## 这里直接监听 InputEventScreenDrag，自己改 scroll_vertical，并吃掉这个事件，
## 免得继续传给上层。

static func attach(sc: ScrollContainer) -> void:
	if sc == null:
		return
	sc.mouse_filter = Control.MOUSE_FILTER_STOP
	var dragging := [false, 0.0]
	sc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventScreenDrag:
			sc.scroll_vertical -= int(ev.relative.y)
			sc.scroll_horizontal -= int(ev.relative.x)
			sc.accept_event()
		elif ev is InputEventScreenTouch:
			dragging[0] = ev.pressed
			sc.accept_event()
	)

## 把里面的按钮设成 PASS：按钮照常能被点，但没被它接住的手势会往上冒，
## 这样手指压在按钮上往下拖也能滚列表（STOP 会把拖动吃掉，表现就是"拖不动"）
static func relax(node: Node) -> void:
	for c in node.get_children():
		if c is Control:
			var ctl := c as Control
			if ctl is Button or ctl is Label or ctl is Panel:
				ctl.mouse_filter = Control.MOUSE_FILTER_PASS
		relax(c)

## 面板右侧的上下翻页按钮：手机上比拖动更稳，也不会碰到系统手势区
static func attach_arrows(host: Control, sc: ScrollContainer) -> void:
	if host == null or sc == null:
		return
	var mk := func(txt: String, dy: int, y: float) -> Button:
		var b := Button.new()
		b.text = txt
		b.position = Vector2(host.size.x - 34, y)
		b.size = Vector2(30, 34)
		b.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.13, 0.18, 0.92)
		sb.set_corner_radius_all(7)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.42, 0.80, 0.72, 0.35)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(0.95, 0.96, 0.93))
		b.pressed.connect(func() -> void:
			sc.scroll_vertical = clampi(sc.scroll_vertical + dy, 0, 1 << 20))
		host.add_child(b)
		return b
	mk.call("▲", -110, 56.0)
	mk.call("▼", 110, 96.0)
