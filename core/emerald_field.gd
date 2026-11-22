extends Node2D
## Native 16px Emerald metatiles, streamed against the game's logical map coordinates.
const ART := "res://assets/emerald/field/"
const INDEX := "res://content/emerald_fields.json"
const CELL := 16
const CHUNK := 22

static var _catalog: Dictionary = {}
static var _atlas_columns: int
static var _tiles: TileSet
static var _textures: Dictionary = {}

var world: Node2D
var extent: Vector2i
var ground_data: PackedByteArray
var above_data: PackedByteArray
var ground: TileMapLayer
var above: TileMapLayer
var props_by_chunk := {}
var active := {}
var current := Vector2i(-100,-100)

static func plan_for(data: Dictionary) -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string(INDEX))
	if data.has("hoenn_art"): return data.hoenn_art
	return _catalog.maps.get("%s/%s" % [data.get("region",""),data.get("id","")], {})

static func _tileset() -> TileSet:
	if _tiles:
		return _tiles
	_tiles = TileSet.new()
	_tiles.tile_size = Vector2i(CELL,CELL)
	var src := TileSetAtlasSource.new()
	src.texture = load(ART+"tiles.png")
	_atlas_columns = floori(float(src.texture.get_width()) / CELL)
	src.texture_region_size = _tiles.tile_size
	_tiles.add_source(src,0)
	for n in int(_catalog.tiles):
		src.create_tile(_atlas_coord(n))
	var switches := TileSetAtlasSource.new()
	switches.texture=load(ART+"kanto_puzzles.png")
	switches.texture_region_size=Vector2i(CELL,CELL)
	_tiles.add_source(switches,1)
	for y in floori(switches.texture.get_height()/float(CELL)):
		for x in 16: switches.create_tile(Vector2i(x,y))
	var hoenn := TileSetAtlasSource.new()
	hoenn.texture=load("res://assets/hoenn_native/tiles.png")
	hoenn.texture_region_size=Vector2i(CELL,CELL)
	_tiles.add_source(hoenn,2)
	var meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/atlas.json"))
	for n in int(meta.tiles): hoenn.create_tile(Vector2i(n%64,floori(n/64.0)))
	if meta.has("animated"):
		var water:=TileSetAtlasSource.new()
		water.texture=load("res://assets/hoenn_native/water.png")
		water.texture_region_size=Vector2i(CELL,CELL)
		_tiles.add_source(water,3)
		for n in int(meta.animated):
			var atlas:=Vector2i((n%8)*8,floori(n/8.0))
			water.create_tile(atlas)
			water.set_tile_animation_columns(atlas,8)
			water.set_tile_animation_frames_count(atlas,8)
			water.set_tile_animation_speed(atlas,3.75)
	return _tiles

@warning_ignore("integer_division")
static func _atlas_coord(id: int) -> Vector2i:
	return Vector2i(id % _atlas_columns, id / _atlas_columns)

static func prop_texture(kind: String) -> Texture2D:
	if not _textures.has(kind):
		_textures[kind] = load(ART+kind+".png")
	return _textures[kind]

func setup(owner_world: Node2D,plan: Dictionary, overrides: Array = []) -> void:
	world = owner_world
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	extent = Vector2i(plan.s[0],plan.s[1])
	ground_data = _unpack(plan.t)
	if plan.has("a"):
		above_data = _unpack(plan.a)
	for row in overrides:
		var offset := (int(row[1])*extent.x+int(row[0]))*2
		ground_data.encode_u16(offset,int(row[2]))
		if not above_data.is_empty(): above_data.encode_u16(offset,int(row[3]))
	ground = _layer()
	if not above_data.is_empty():
		above = _layer()
		above.z_index = 997
	for prop in plan.p:
		var key := _chunk(Vector2i(prop[1],prop[2]))
		if not props_by_chunk.has(key):
			props_by_chunk[key] = []
		props_by_chunk[key].append(prop)
	_refresh()
	set_process(extent.x>CHUNK or extent.y>CHUNK)

func _unpack(content: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(content).decompress(extent.x*extent.y*2,FileAccess.COMPRESSION_DEFLATE)

func _layer() -> TileMapLayer:
	var node := TileMapLayer.new()
	node.tile_set = _tileset()
	node.collision_enabled = false
	node.navigation_enabled = false
	node.occlusion_enabled = false
	add_child(node)
	return node

@warning_ignore("integer_division")
func _chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x/CHUNK,cell.y/CHUNK)

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var center := _chunk(world.get("player_pos"))
	if center==current:
		return
	current = center
	var wanted := {}
	var last := _chunk(extent-Vector2i.ONE)
	for y in range(maxi(center.y-1,0),mini(center.y+1,last.y)+1):
		for x in range(maxi(center.x-1,0),mini(center.x+1,last.x)+1):
			var key := Vector2i(x,y)
			wanted[key] = true
			if not active.has(key):
				_change(key,true)
	for key in active.keys():
		if not wanted.has(key):
			_change(key,false)

func _change(key: Vector2i,show_chunk: bool) -> void:
	var start := key*CHUNK
	var end := (start+Vector2i(CHUNK,CHUNK)).min(extent)
	for y in range(start.y,end.y):
		for x in range(start.x,end.x):
			var pos := Vector2i(x,y)
			var offset := (y*extent.x+x)*2
			if show_chunk:
				_set_tile(ground,pos,ground_data.decode_u16(offset))
				if above:
					_set_tile(above,pos,above_data.decode_u16(offset))
			else:
				ground.erase_cell(pos)
				if above:
					above.erase_cell(pos)
	if show_chunk:
		var objects := Node2D.new()
		add_child(objects)
		for p in props_by_chunk.get(key,[]):
			var sprite := Sprite2D.new()
			sprite.texture = prop_texture(p[0])
			sprite.centered = false
			var anchor: Array = _catalog.anchors[p[0]]
			sprite.position = Vector2(p[1]*CELL+8-anchor[0],(p[2]+1)*CELL-anchor[1])
			sprite.z_index = 99+int(p[2])*2
			objects.add_child(sprite)
		active[key] = objects
	else:
		active[key].queue_free()
		active.erase(key)

func _set_tile(layer: TileMapLayer,pos: Vector2i,id: int) -> void:
	if world.map_data.has("emerald_original"):
		if id>=49152:
			var index:=id-49152
			layer.set_cell(pos,3,Vector2i((index%8)*8,floori(index/8.0)))
		elif id: layer.set_cell(pos,2,Vector2i(id%64,floori(id/64.0)))
	elif id>=32768:
		var n:=id-32768
		layer.set_cell(pos,1,Vector2i(n%16,floori(n/16.0)))
	elif id!=0:
		layer.set_cell(pos,0,_atlas_coord(id))
