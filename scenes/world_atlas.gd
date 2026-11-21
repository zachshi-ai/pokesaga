extends Control
signal closed
signal trip_requested(region_id: String)

const UI := preload("res://core/field_ui.gd")
const Chart := preload("res://scenes/atlas_chart.gd")
const NAVY := Color("#224e4d")
const TEAL := Color("#347c64")
const PAPER := Color("#f4f2e5")
const KIND := {"city":"城市","town":"城镇","route":"道路","landmark":"地标","crossing":"通道","facility":"设施"}

var regions: Dictionary
var graph: Dictionary
var here_region := ""
var here_map := ""
var here_tile := Vector2.ZERO
var here_name := ""
var travel := false
var viewing_art := false
var region_id := ""
var place_id := ""
var chart
var scroll: ScrollContainer

func setup(catalog: Dictionary, map_data: Dictionary, for_travel: bool, tile := Vector2i.ZERO, location_name := "") -> void:
	regions = catalog
	graph = Data.load_json("res://content/world_graph.json")
	here_region = str(map_data.get("region",""))
	here_map = str(map_data.get("id",""))
	here_name = location_name if location_name != "" else str(map_data.get("name",""))
	here_tile = Vector2(tile)
	travel = for_travel
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_render()

func _btn(text: String, action: Callable, active := false) -> Button:
	var b := UI.button(text,action,active)
	b.custom_minimum_size = Vector2(0,30)
	b.add_theme_font_size_override("font_size",12)
	if active:
		b.add_theme_stylebox_override("normal",UI.box(TEAL,TEAL,5))
	return b

func _current_place() -> String:
	if region_id != here_region:
		return ""
	var nearest := INF
	var found := ""
	for p in regions[region_id].locations:
		if p.map == here_map:
			var dist := here_tile.distance_squared_to(Vector2(p.at[0],p.at[1]))
			if dist < nearest:
				found = p.id
				nearest = dist
	return found

func _render(preserve_scroll := 0) -> void:
	UI.clear(self)
	UI.sheet(self,PAPER)
	var world_view := region_id.is_empty()
	var region: Dictionary = regions.get(region_id,{})
	if viewing_art:
		_render_hoenn_art()
		return
	var band := ColorRect.new()
	band.color = NAVY
	UI.place(self,band,0,0,480,42)
	UI.place(band,_btn("‹ 返回",handle_back),6,5,52,32)
	var title := "地区领航" if travel else "世界全景地图"
	UI.place(band,UI.label(title if world_view else str(region.name),18,Color.WHITE),68,2,153,36)
	var location := UI.label("当前位置　"+here_name,11,Color("#bce8e8"))
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UI.place(band,location,210,5,260,30)
	chart = Chart.new()
	UI.place(self,chart,6,49,308,217)
	var points := {}
	var edges := []
	var current := ""
	if world_view:
		var plate: Array = graph.plate.size
		for id in graph.regions:
			var entry: Dictionary = graph.regions[id]
			points[id] = {"name":entry.name,"pos":Vector2(entry.at[0]/float(plate[0]),entry.at[1]/float(plate[1]))}
		var insets: Dictionary = Data.load_json("res://content/atlas_insets.json")
		for extra in graph.specials:
			if insets.has(extra.id):
				var xy: Array = insets[extra.id]
				points[extra.id] = {"name":extra.name, "minor":true, "layer":extra.kind=="layer","pos":Vector2(xy[0],xy[1])*.01}
		for passage in Data.world_passages:
			edges.append([passage.a,passage.b])
		current = here_region
		chart.setup("world",points,edges,current,"")
		chart.picked.connect(_select_region)
	else:
		for p in region.locations:
			points[p.id] = {"name":p.name,"town":p.kind in ["town","city"],"pos":Vector2(p.pos[0],p.pos[1])*.01}
		current = _current_place()
		chart.setup(region_id,points,region.connections,current,place_id)
		chart.picked.connect(_select_place)
	var list_title := "地区索引" if world_view else "地点索引"
	UI.place(self,UI.label(list_title,14,NAVY),323,46,151,24)
	scroll = UI.scroll(self,Vector2(320,73),Vector2(155,193))
	var list := UI.list_box(scroll,3)
	if world_view:
		for id in graph.regions:
			if regions.has(id):
				_row(list,regions[id].name,_select_region.bind(id),id==here_region)
		for special in graph.specials:
			if regions.has(special.id):
				_row(list,special.name,_select_region.bind(special.id),special.id==here_region)
	else:
		for p in region.locations:
			_row(list,str(p.name),_select_place.bind(str(p.id)),p.id==place_id)
	scroll.set_deferred("scroll_vertical",preserve_scroll)
	UI.place(self,_btn("−",func(): chart.magnify(-.5)),6,277,36,34)
	UI.place(self,_btn("＋",func(): chart.magnify(.5)),45,277,36,34)
	if world_view:
		UI.place(self,UI.label("选择地区，查看道路与城镇",12,NAVY),91,277,235,34)
	else:
		var txt := str(region.name)
		for p in region.locations:
			if p.id == place_id:
				txt = "%s · %s" % [p.name,KIND.get(p.kind,"地点")]
				break
		var info := UI.label(txt,12,NAVY)
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		UI.place(self,info,91,277,128 if region_id=="hoenn" else 213,34)
		if region_id=="hoenn":
			UI.place(self,_btn("丰缘地图",_show_hoenn_art),222,276,88,36)
	if travel and not world_view:
		UI.place(self,_btn("出发前往"+str(region.name),_depart,true),314,274,161,40)
	else:
		var button := _btn("定位当前地区",_locate)
		button.disabled = not regions.has(here_region)
		UI.place(self,button,320,275,154,38)

func _show_hoenn_art() -> void:
	viewing_art = true
	_render()

func _render_hoenn_art() -> void:
	var band := ColorRect.new()
	band.color = NAVY
	UI.place(self,band,0,0,480,42)
	UI.place(band,_btn("‹ 返回",handle_back),6,5,52,32)
	UI.place(band,UI.label("丰缘地区地图",18,Color.WHITE),68,2,177,36)
	UI.place(band,UI.label("宝可导航 · 绿宝石",11,Color("#bce8e8")),271,5,202,30)
	var sea := ColorRect.new()
	sea.color = NAVY
	UI.place(self,sea,0,42,480,278)
	chart = Chart.new()
	UI.place(self,chart,46,57,388,238)
	chart.setup("hoenn_map",{},[],"","")
	UI.place(self,_btn("−",func(): chart.magnify(-.5)),4,275,38,36)
	UI.place(self,_btn("＋",func(): chart.magnify(.5)),438,275,38,36)

func _row(list: VBoxContainer, text: String, action: Callable, active: bool) -> void:
	var b := _btn(text,action,active)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 34
	list.add_child(b)

func _select_region(id: String) -> void:
	if not regions.has(id):
		return
	region_id = id
	place_id = _current_place()
	if place_id.is_empty():
		var hub: Dictionary = regions[id].hub
		for p in regions[id].locations:
			if str(p.map)==str(hub.map) and p.at==hub.at:
				place_id = str(p.id)
				break
	_render()

func _select_place(id: String) -> void:
	var keep_zoom: float = chart.zoom
	var keep_pan: Vector2 = chart.pan
	var keep_scroll := scroll.scroll_vertical
	place_id = id
	_render(keep_scroll)
	chart.zoom = keep_zoom
	chart.pan = keep_pan
	chart.queue_redraw()

func _locate() -> void:
	_select_region(here_region)
	var current := _current_place()
	if not current.is_empty():
		_select_place(current)

func _depart() -> void:
	if is_queued_for_deletion() or not travel or not regions.has(region_id):
		return
	var destination := region_id
	_finish()
	trip_requested.emit(destination)

func _finish() -> void:
	if is_queued_for_deletion():
		return
	hide()
	queue_free()
	closed.emit()

func handle_back() -> void:
	if viewing_art:
		viewing_art = false
		_render()
	elif region_id != "":
		region_id = ""
		place_id = ""
		_render()
	else:
		_finish()
