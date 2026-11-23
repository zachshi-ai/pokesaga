extends "res://scenes/battle_ui.gd"
var raid_config: Dictionary
var story_flags: Dictionary
var helper_bar: HBoxContainer

func _battle_engine(seed_value: int):
	var engine=preload("res://core/galar_raids.gd").new(seed_value)
	engine.prepare("solo" if raid_config.get("galar_solo_raid",false) else str(raid_config.galar_raid),enemy_team[0],raid_config.get("raid_helpers",engine.stadium_team(raid_config.get("id",""),story_flags)))
	return engine

func _build() -> void:
	super._build()
	helper_bar=HBoxContainer.new()
	helper_bar.position=Vector2(12,69)
	helper_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(helper_bar)
	for ally in battle.allies:
		var sprite:=TextureRect.new()
		sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.custom_minimum_size=Vector2(36,36)
		sprite.texture=load(Data.sprite_path(int(ally.species_id),str(ally.get("form",""))))
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.mouse_filter=Control.MOUSE_FILTER_IGNORE
		helper_bar.add_child(sprite)

func _refresh_hp() -> void:
	super._refresh_hp()
	if not is_instance_valid(helper_bar):return
	for i in battle.allies.size():
		helper_bar.get_child(i).modulate=Color.WHITE if battle.allies[i].hp>0 else Color(0.45,0.45,0.45,0.55)
