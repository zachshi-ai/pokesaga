extends Node2D
## ORAS terrain, baked from the region's actual walk grid and authored landmark anchors.
## Stream large overworlds in map-space chunks; interior rooms stay resident.
const TEXDIR := "res://assets/oras/field/"
const CELL := 16
const REGION := 32
const CHUNK := 22
const COUNT := 37
const WATER := [2, 22, 28]

static var _plans: Dictionary = {}
static var _tiles: TileSet
static var _props: Dictionary = {}

var owner_world: Node2D
var extent := Vector2i.ZERO
var terrain := PackedByteArray()
var ground: TileMapLayer
var trim: TileMapLayer
var props_by_chunk := {}
var active := {}
var current := Vector2i(-9999, -9999)

static func plan_for(data: Dictionary) -> Dictionary:
	if _plans.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/oras_fields.json"))
		if parsed is Dictionary:
			_plans = parsed
	return _plans.get("%s/%s" % [data.get("region",""),data.get("id","")], {})

static func _tileset() -> TileSet:
	if _tiles:
		return _tiles
	_tiles = TileSet.new()
	_tiles.tile_size = Vector2i(REGION,REGION)
	for i in 2:
		var src := TileSetAtlasSource.new()
		src.texture = load(TEXDIR + ("terrain.png" if i == 0 else "edges.png"))
		src.texture_region_size = Vector2i(REGION,REGION)
		_tiles.add_source(src, i)
		for y in (COUNT if i == 0 else 4):
			for x in 16:
				src.create_tile(Vector2i(x,y))
	return _tiles

func setup(world: Node2D, plan: Dictionary) -> void:
	owner_world = world
	var size_data: Array = plan.s
	extent = Vector2i(int(size_data[0]), int(size_data[1]))
	terrain = Marshalls.base64_to_raw(plan.t).decompress(extent.x * extent.y, FileAccess.COMPRESSION_DEFLATE)
	if plan.has("backdrop"):
		var room := Sprite2D.new()
		room.texture = load(TEXDIR + str(plan.backdrop) + ".png")
		room.centered = false
		room.z_index = 2
		room.scale = Vector2(extent * CELL) / room.texture.get_size()
		add_child(room)
	ground = _layer()
	trim = _layer()
	trim.z_index = 1
	for p in plan.p:
		var chunk := _chunk(Vector2i(int(p[1]), int(p[2])))
		if not props_by_chunk.has(chunk):
			props_by_chunk[chunk] = []
		props_by_chunk[chunk].append(p)
	_refresh()
	set_process(extent.x > CHUNK or extent.y > CHUNK)

func _layer() -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.tile_set = _tileset()
	layer.scale = Vector2.ONE * (float(CELL)/REGION)
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.collision_enabled = false
	layer.navigation_enabled = false
	layer.occlusion_enabled = false
	add_child(layer)
	return layer

@warning_ignore("integer_division")
func _chunk(v: Vector2i) -> Vector2i:
	return Vector2i(v.x / CHUNK, v.y / CHUNK)

func _process(_delta: float) -> void:
	if not is_instance_valid(owner_world):
		return
	_refresh()

func _refresh() -> void:
	var center := _chunk(owner_world.get("player_pos"))
	if center == current:
		return
	current = center
	var wanted := {}
	for y in range(maxi(0, center.y-1), mini(_chunk(extent-Vector2i.ONE).y, center.y+1)+1):
		for x in range(maxi(0, center.x-1), mini(_chunk(extent-Vector2i.ONE).x, center.x+1)+1):
			var key := Vector2i(x,y)
			wanted[key] = true
			if not active.has(key):
				_change(key,true)
	for old in active.keys():
		if not wanted.has(old):
			_change(old,false)

func _change(key: Vector2i, show_chunk: bool) -> void:
	var start := key * CHUNK
	var end := (start + Vector2i(CHUNK,CHUNK)).min(extent)
	for y in range(start.y,end.y):
		for x in range(start.x,end.x):
			var cell := Vector2i(x,y)
			if show_chunk:
				var value := _at(x,y)
				var variant := (x % 4) + (y % 4) * 4
				ground.set_cell(cell,0,Vector2i(variant,value))
				_edge(cell,value)
			else:
				ground.erase_cell(cell)
				trim.erase_cell(cell)
	if show_chunk:
		var objects := Node2D.new()
		add_child(objects)
		for p in props_by_chunk.get(key,[]):
			_add_prop(objects,p)
		active[key] = objects
	else:
		active[key].queue_free()
		active.erase(key)

func _at(x: int, y: int) -> int:
	if x < 0 or x >= extent.x or y < 0 or y >= extent.y:
		return 30
	return terrain[y * extent.x + x]

func _edge(cell: Vector2i, value: int) -> void:
	var style := -1
	if value in WATER:
		style = 0
	elif value in [3,10,24]:
		style = 1
	elif value == 15:
		style = 2
	elif value == 6:
		style = 3
	if style == -1:
		return
	var mask := 0
	var dirs := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for i in 4:
		var neighbor: Vector2i = cell+dirs[i]
		var other := _at(neighbor.x,neighbor.y)
		if other == 30:
			continue
		if (style == 0 and other not in WATER) or (style == 1 and other in [0,1,4,11,21]) or (style == 2 and other != 15) or (style == 3 and other not in [5,6]):
			mask |= 1 << i
	if mask:
		trim.set_cell(cell,1,Vector2i(mask,style))

static func prop_texture(kind: String) -> Texture2D:
	if not _props.has(kind):
		var path := TEXDIR + kind + ".png"
		_props[kind] = load(path) if ResourceLoader.exists(path) else null
	return _props[kind]

func _add_prop(parent: Node2D, p: Array) -> void:
	var kind := str(p[0])
	var texture := prop_texture(kind)
	if texture == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.centered = false
	var width := float(p[3]) * CELL
	var height := float(p[4]) * CELL
	if kind in ["streetlamp","banner","statue","pc","clock","planter"]:
		var fit := minf(width / texture.get_width(), height / texture.get_height())
		width = fit * texture.get_width()
		height = fit * texture.get_height()
	sprite.scale = Vector2(width,height)/texture.get_size()
	sprite.position = Vector2((float(p[1])+0.5)*CELL-width/2, (float(p[2])+1)*CELL-height)
	sprite.z_index = 100 + int(p[2])*2 - 1
	parent.add_child(sprite)
