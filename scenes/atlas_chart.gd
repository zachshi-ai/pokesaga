extends Control
## Interactive paper chart. Positions share the coordinate system used to paint the relief.
signal picked(id: String)

var art: Texture2D
var points: Dictionary = {}
var edges: Array = []
var here := ""
var selected := ""
var overview := false
var zoom := 1.0
var pan := Vector2.ZERO
var anchor := Vector2.ZERO
var pan_start := Vector2.ZERO
var pressed := false
var moved := false

func setup(chart_id: String, markers: Dictionary, links: Array, current: String, focus: String) -> void:
	var path := "res://assets/atlas/%s.webp" % chart_id
	art = load(path) if ResourceLoader.exists(path) else null
	points = markers
	edges = links
	here = current
	selected = focus
	overview = chart_id == "world"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	clip_contents = true
	queue_redraw()

func _pos(id: String) -> Vector2:
	return (points[id].pos as Vector2) * size * zoom + pan

func magnify(step: float) -> void:
	var new_zoom := clampf(zoom + step, 1, 3)
	var center := size * .5
	pan = center + (pan-center) * (new_zoom/zoom)
	zoom = new_zoom
	_limit_pan()
	queue_redraw()

func _limit_pan() -> void:
	pan = pan.clamp(size*(1-zoom), Vector2.ZERO)

func _draw() -> void:
	var area := Rect2(pan, size*zoom)
	draw_rect(Rect2(Vector2.ZERO,size), Color("#196487"))
	if art:
		draw_texture_rect(art, area, false)
	for edge in edges:
		if edge.size() < 2 or not points.has(str(edge[0])) or not points.has(str(edge[1])):
			continue
		var a := _pos(str(edge[0]))
		var b := _pos(str(edge[1]))
		draw_line(a,b,Color("#264c66ad"),2.9 if overview else 2.0,true)
		draw_dashed_line(a,b,Color("#ffebbf"),1.25 if overview else 1.0,4,true,true)
	for key in points:
		var pos := _pos(key)
		var minor: bool = points[key].get("minor",false)
		var primary: bool = (overview and (not minor or zoom>=1.9)) or key == selected or key == here
		var town: bool = points[key].get("town",false)
		var r := 4.4 if primary else (2.9 if town or overview else 1.55)
		if key == here:
			draw_arc(pos,r+3,0,TAU,24,Color("#fff5d6"),1.5,true)
		draw_circle(pos,r+1.3,Color("#143851"),true,-1,true)
		var marker := Color("#c4bcea") if points[key].get("layer",false) else (Color("#a7e8de") if minor else Color("#e1f8e9"))
		draw_circle(pos,r,Color("#ffbc69") if key==here or key==selected else marker,true,-1,true)
		if primary or (town and zoom>=1.9):
			var title := str(points[key].name)
			var font := get_theme_default_font()
			var width := font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x
			var x := clampf(pos.x-width*.5,2,maxf(2,size.x-width-2))
			var baseline := Vector2(x, pos.y+17 if pos.y+20<size.y else pos.y-8)
			draw_string_outline(font,baseline,title,HORIZONTAL_ALIGNMENT_LEFT,-1,11,3,Color("#154157"))
			draw_string(font,baseline,title,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#fffae9"))
	if points.is_empty():
		return
	# Small north arrow in the map margin.
	draw_colored_polygon(PackedVector2Array([Vector2(12,8),Vector2(8,19),Vector2(12,16),Vector2(16,19)]),Color("#fff7d9"))
	draw_string(get_theme_default_font(),Vector2(9,29),"N",HORIZONTAL_ALIGNMENT_LEFT,-1,9,Color.WHITE)

func _gui_input(event: InputEvent) -> void:
	# Godot synthesizes mouse events from the primary touch on Android.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				magnify(.5 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.5)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				anchor = event.position
				pan_start = pan
				pressed = true
				moved = false
			elif pressed:
				pressed = false
				if not moved:
					var closest := ""
					var nearest := 14.0
					for id in points:
						var d := _pos(id).distance_to(event.position)
						if d < nearest:
							nearest = d
							closest = id
					if closest != "":
						picked.emit(closest)
			accept_event()
	elif event is InputEventMouseMotion and pressed:
		var delta: Vector2 = event.position-anchor
		if delta.length()>4:
			moved = true
		if moved:
			pan = pan_start + delta
			_limit_pan()
			queue_redraw()
			accept_event()
