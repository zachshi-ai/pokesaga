extends Node2D
## Visibility groups and facing-sensitive triggers from Platinum's Distortion World overlay.

const FACING := ["up", "down", "left", "right"]
var actors: Dictionary = {}
var rules: Array
var world
var active_mask: int
var previous := Vector2i(-1, -1)
var previous_facing := ""

func setup(owner_world, plan: Dictionary) -> void:
	world = owner_world
	rules = plan.triggers
	active_mask = int(world.taken.get("pl_rift_scenery", {}).get(world.map_data.id, plan.visible))
	for row in plan.sprites:
		var sprite := Sprite2D.new()
		sprite.centered = false
		sprite.texture = load(row[5])
		sprite.position = Vector2(int(row[1]) * 16 + 8 + int(row[3]), int(row[2]) * 16 + 8 + int(row[4]))
		# A walkable platform sits beneath the player's feet, even on its lowest edge.
		sprite.z_index = 1
		add_child(sprite)
		var group := int(row[0])
		if not actors.has(group):
			actors[group] = []
		actors[group].append(sprite)
		sprite.visible = (active_mask & (1 << group)) != 0
	set_process(not rules.is_empty())

func _process(_delta: float) -> void:
	if world.walking or (world.player_pos == previous and world.facing == previous_facing):
		return
	previous = world.player_pos
	previous_facing = world.facing
	var next := active_mask
	for rule in rules:
		if FACING[int(rule[1])] != previous_facing:
			continue
		var area := Rect2i(int(rule[3]), int(rule[4]), int(rule[5]), int(rule[6]))
		if area.has_point(previous):
			var bit := 1 << int(rule[0])
			next = (next | bit) if rule[2] else (next & ~bit)
	if next == active_mask:
		return
	for group: int in actors:
		if ((next ^ active_mask) & (1 << group)) != 0:
			for sprite: Sprite2D in actors[group]:
				sprite.visible = (next & (1 << group)) != 0
	active_mask = next
	world.taken.get_or_add("pl_rift_scenery", {})[world.map_data.id] = next
