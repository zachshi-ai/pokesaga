extends SceneTree
## A redraw may place a wall on an old coordinate. Nearby disconnected floors, NPCs, warp cells,
## and dry-land saves that became water must not capture the restored player.
class Reader extends "res://core/world.gd":
	func _ready() -> void: pass
	func _rebuild(_story_flags: Variant = null) -> void: pass

func _initialize() -> void:
	call_deferred("check")

func check() -> void:
	var field := Reader.new()
	root.add_child(field)
	var tiles := []
	for y in 8:
		var row := []
		for x in 10:
			row.append(1 if x in [0,9] or y in [0,7] or x==5 else 0)
		tiles.append(row)
	tiles[2][3]=2
	field.load_map({"id":"migration_room","region":"galar","size":[10,8],"spawn":[1,1],"tiles":tiles,
		"npcs":[{"at":[2,3]}],"warps":[{"at":[4,3],"to":{"region":"galar","map":"galar_1","at":[1,1]}}]})
	var ok := true
	for old in [Vector2i(3,2),Vector2i(2,3),Vector2i(4,3),Vector2i(6,4),Vector2i(12,12)]:
		var fresh := field.restored_field_position(old,false)
		if fresh.x>=5 or field.is_water(fresh) or field.is_blocked(fresh) or not field.warp_at(fresh).is_empty(): ok=false
	ok = ok and field.restored_field_position(Vector2i(3,2),true)==Vector2i(3,2)
	ok = ok and field.restored_field_position(Vector2i(4,5),false)==Vector2i(4,5)
	# A Kalos lift may have delivered the player to a platform without a walking connection.
	field.map_data["kalos_furniture_feet"] = [[5,4]]
	ok = ok and field.restored_field_position(Vector2i(6,4),false)==Vector2i(6,4)
	var moved := field.restored_field_position(Vector2i(5,4),false)
	ok = ok and moved.x < 5 and not field.is_blocked(moved)
	if ok:print("REGIONAL FIELD SAVE MIGRATION PASS")
	else:push_error("REGIONAL FIELD SAVE MIGRATION FAIL")
	quit(0 if ok else 1)
