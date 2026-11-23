extends Sprite2D
## A walking story partner occupies the tile the player just left without blocking backtracking.
var world
var cast=preload("res://core/sinnoh_cast.gd")
var tile: Vector2i
var header: String
var identity: String
var face: String
var target: Vector2
var stride:=0
var walking:=false

func follow(w,who: String,map_id: String,footing: Vector2i,direction: String):
	var is_new: bool=world==null or header!=map_id or identity!=who
	world=w
	tile=footing
	header=map_id
	identity=who
	face=direction
	stride=1-stride
	cast.draw(self,identity,face,stride+1)
	scale=Vector2.ONE*world._field_actor_scale()
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	target=Vector2(tile.x*16+8,(tile.y+1)*16)
	if texture:target.y-=texture.get_height()*scale.y*0.5
	z_index=100+tile.y*2
	if is_new or position.distance_to(target)>40:position=target
	walking=true

func _process(delta):
	if world==null:return
	if world.map_data.id!=header:
		queue_free()
		return
	if walking:
		position=position.move_toward(target,delta*140.0)
		if position==target:
			walking=false
			cast.draw(self,identity,face,0)
