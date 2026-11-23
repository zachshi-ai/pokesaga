extends RefCounted

static var atlas := preload("res://core/regional_cast_atlas.gd").new("alola")

static func data() -> Dictionary:
	return atlas.data()

static func character(row: Dictionary) -> String:
	return atlas.character(row)

static func draw(sprite: Sprite2D, identity: String, face: String, stride := 0) -> void:
	atlas.draw(sprite, identity, face, stride)

static func portrait(speaker: String) -> Texture2D:
	return atlas.portrait(speaker)
