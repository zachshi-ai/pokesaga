extends RefCounted

static var levels: Dictionary

static func learnset(species: int, form := "") -> Array:
	if levels.is_empty():
		levels = JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_moves.json"))
	return levels.get(form, levels.get(str(species), []))

static func moves_for(species: int, level: int, form := "") -> Array:
	return load("res://core/encounter.gd").moves_for(species, level, learnset(species, form))
