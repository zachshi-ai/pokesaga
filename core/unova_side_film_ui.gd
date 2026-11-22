extends "res://scenes/battle_ui.gd"
var movie: Dictionary

func _battle_engine(seed_value: int):
	var film:=preload("res://core/unova_side_film_battle.gd").new(seed_value)
	film.movie=movie
	return film

func _apply_appearance(sprite: TextureRect,mon: Dictionary) -> void:
	if not mon.has("film_asset"):
		super._apply_appearance(sprite,mon)
		return
	var path: String=mon.film_asset
	if sprite.get_meta("identity","")==path:return
	sprite.set_meta("identity",path)
	sprite.texture=load(path)
	sprite.pivot_offset=Vector2.ZERO
	var ground:=134.0-2.0*83.0
	sprite.set_meta("ground_y",ground)
	sprite.position.y=ground
	var effect=sprite.get_node("Appearance")
	effect.visible=false
	effect.set_process(false)
