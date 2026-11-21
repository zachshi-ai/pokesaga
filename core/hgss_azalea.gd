extends RefCounted

const Field := preload("res://core/hgss_field.gd")
const HEADER := "MAP_AZALEA_GYM"
const INITIAL := [0,1,2,7]
const PROP := "res://assets/johto_gba/props/spinarak_cart.png"
static var layout: Dictionary = {}

static func active(world) -> bool:
	return world.map_data.get("hgss",{}).get("header","")==HEADER

static func data() -> Dictionary:
	if layout.is_empty(): layout = Field.read_file("res://content/hgss/azalea.json")
	return layout

static func draw(world) -> void:
	if not active(world): return
	var book := data()
	for id in world.taken.get("hgss_azalea_cars",INITIAL):
		var sprite := Sprite2D.new()
		sprite.name="SpinarakCar%d"%int(id)
		sprite.texture=load(PROP)
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered=false
		var tile := Vector2(Field.vec(book.stops[int(id)]))
		sprite.position=tile*16+Vector2(-11,-5)
		sprite.z_index=world.Z_ACTOR+int(tile.y)*2-2
		world.add_child(sprite)
		world._tile_nodes.append(sprite)

static func flip(game) -> bool:
	if not active(game.world): return false
	var ahead: Vector2i = game.world.player_pos + game.world._dir_vec()
	for sw in data().switches:
		if ahead!=Vector2i(int(sw[0]),int(sw[1])): continue
		var bit := 1 << int(sw[2])
		var flags: Dictionary = game._flags()
		var state := int(flags.get("hgss_azalea_switches",0)) ^ bit
		flags["hgss_azalea_switches"]=state
		game.snd.play_sfx("confirm")
		game._show_toast(("红色" if bit==2 else "蓝色")+"道岔已切换。")
		game._persist()
		return true
	return false

static func board(game) -> bool:
	var world = game.world
	if not active(world): return false
	var book := data()
	var index := -1
	for i in book.pads.size():
		if Field.vec(book.pads[i])==world.player_pos:
			index=i
			break
	if index<0: return false
	var flags: Dictionary=game._flags()
	var cars: Array=flags.get("hgss_azalea_cars",INITIAL).duplicate()
	var slot:=cars.find(index)
	if slot<0: return false
	var route: Array=book.routes[index][int(flags.get("hgss_azalea_switches",0))]
	if route.is_empty(): return false
	var path: Array=book.paths[route[1]].duplicate()
	var reverse:=index in [3,4,5,9,10,11]
	if reverse:path.reverse()
	var arrival: Vector2i = Field.vec(path.back()) + (Vector2i.DOWN*2 if reverse else Vector2i.UP)
	var car: Sprite2D=world.get_node_or_null("SpinarakCar%d"%index)
	if not is_instance_valid(car): return false
	world.finish_walk()
	world.facing="down" if reverse else "up"
	game.held_dir=""
	game.panel_open+=1
	var tween: Tween=world.create_tween()
	var last:=Vector2(Field.vec(path[0]))
	for vertex in path:
		var next:=Vector2(Field.vec(vertex))
		if last!=next:
			tween.tween_method(func(at: Vector2):
				car.position=at*16+Vector2(-11,-5)
				car.z_index=world.Z_ACTOR+int(at.y)*2-2
				world.render_pos=at+(Vector2.DOWN if reverse else Vector2.ZERO)
				world._sync_player(),last,next,last.distance_to(next)*0.09)
		last=next
	tween.tween_callback(func():
		cars[slot]=int(route[0])
		flags["hgss_azalea_cars"]=cars
		car.name="SpinarakCar%d"%int(route[0])
		world.warp_to(arrival)
		game.panel_open-=1
		game._persist())
	return true
