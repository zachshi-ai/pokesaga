extends ScrollContainer
## Scroll even when the finger starts on an interactive child. Keep short taps native.

var finger := -1
var origin := Vector2.ZERO
var offset := 0
var scrolling := false

func _on_top(point: Vector2) -> bool:
	if not get_global_rect().has_point(point):
		return false
	# A forms picker or detail sheet can cover a list without removing it.
	var branch: Node = self
	while branch.get_parent() is Control:
		for sibling in branch.get_parent().get_children().slice(branch.get_index() + 1):
			if sibling is Control and sibling.is_visible_in_tree() and sibling.mouse_filter != Control.MOUSE_FILTER_IGNORE and sibling.get_global_rect().has_point(point):
				return false
		branch = branch.get_parent()
	return true

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or get_v_scroll_bar().max_value <= get_v_scroll_bar().page:
		return
	if event is InputEventScreenTouch:
		if event.pressed and finger == -1 and _on_top(event.position):
			finger = event.index
			origin = event.position
			offset = scroll_vertical
			scrolling = false
		elif not event.pressed and event.index == finger:
			finger = -1
			if scrolling:
				get_viewport().set_input_as_handled()
				propagate_notification(Control.NOTIFICATION_SCROLL_END)
			scrolling = false
	elif event is InputEventScreenDrag and event.index == finger:
		var distance: float = origin.y - event.position.y
		if not scrolling and absf(distance) >= scroll_deadzone:
			scrolling = true
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		if scrolling:
			scroll_vertical = offset + roundi(distance)
			get_viewport().set_input_as_handled()
