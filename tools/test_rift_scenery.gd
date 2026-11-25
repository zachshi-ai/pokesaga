extends SceneTree
## Exercise a source show/hide trigger on foot, and restore its state after re-entering.

const Field := preload("res://core/emerald_field.gd")
const Rift := preload("res://core/platinum_rift_scenery.gd")
const DIRECTIONS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

func _initialize() -> void:
	run.call_deferred()

func rift_of(world) -> Node:
	for child in world.get_children():
		if child is Field and not child.is_queued_for_deletion():
			for sub in child.get_children():
				if sub is Rift: return sub
	return null

func exercise(world, data: Dictionary, show: bool) -> bool:
	var artwork = rift_of(world)
	for rule in data.hoenn_art.rift.triggers:
		if bool(rule[2]) != show: continue
		var group := int(rule[0])
		var bit := 1 << group
		if not artwork.actors.has(group) or bool(artwork.active_mask & bit) == show: continue
		var direction: Vector2i = DIRECTIONS[int(rule[1])]
		for x in range(int(rule[3]), int(rule[3])+int(rule[5])):
			for y in range(int(rule[4]), int(rule[4])+int(rule[6])):
				var target := Vector2i(x,y)
				var start := target-direction
				if world.is_blocked(start) or world.is_water(start) or world.is_blocked(target) or world.is_water(target): continue
				world.warp_to(start)
				if not world._warp_from(start,direction).is_empty() or not world.can_step(direction): continue
				if not world.step(direction): continue
				world.tick_walk(1.0)
				artwork._process(0.0)
				if world.player_pos!=target or bool(artwork.active_mask & bit) != show: continue
				for sprite in artwork.actors[group]:
					if sprite.visible != show: return false
				print(data.id, " group=", group, " visible=", show, " at=", target)
				return true
	return false

func run() -> void:
	var world = preload("res://core/world.gd").new()
	root.add_child(world)
	var db := root.get_node("Data")
	var data: Dictionary = db.load_map("sinnoh","sinnoh_distortion_world_b3f")
	world.load_map(data)
	if not exercise(world,data,false) or not exercise(world,data,true):
		push_error("Visible and hidden platforms were not exercised on foot")
		quit(1)
		return
	var mask: int = rift_of(world).active_mask
	world.load_map(db.load_map("sinnoh","sinnoh_distortion_world_1f"))
	world.load_map(data)
	if rift_of(world).active_mask != mask:
		push_error("Visibility flags lost on returning to B3F")
		quit(1)
		return
	world.load_map(db.load_map("dream","dream_cottage"))
	var field_extent: Vector2i = world.tile_size * 16
	if world.cam.limit_left+world.cam.limit_right != field_extent.x or world.cam.limit_top+world.cam.limit_bottom != field_extent.y:
		push_error("Small room camera is off center")
		quit(1)
		return
	print("RIFT SCENERY PASS")
	quit()
