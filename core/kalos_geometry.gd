extends RefCounted

static var variants: Dictionary
static func phase(flags:Dictionary) -> String:
	if flags.get("k_last_lysandre",false) or flags.get("k_weapon",false):return "crater"
	if flags.get("k_two_buttons",false):return "weapon"
	return "stones"

static func town(world,plan:Dictionary,flags:Dictionary) -> Dictionary:
	if variants.is_empty():
		variants=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_geosenge.json"))
	var state:Dictionary=variants[phase(flags)]
	world.terrain_phase=phase(flags)
	world.emerald_collision=state.collision
	var art:=plan.duplicate()
	art.scene=["res://assets/kalos/maps/%s.png"%state.art,0,0]
	return art
