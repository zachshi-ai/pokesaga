extends Control
## Cover illustration: PokeAPI/sprites c0542f7c51215d9672439012838c99f520596cbd,
## sprites/pokemon/other/official-artwork/10077.png (Primal Kyogre).
const UI := preload("res://core/field_ui.gd")
const KYOGRE := preload("res://assets/ui/title/primal_kyogre.png")
const OCEAN := preload("res://scenes/title_ocean.gdshader")
const ICE := Color("#e8fbff")
const AQUA := Color("#8ce8e0")
const MIDNIGHT := Color("#092a51")

signal start_requested(fresh: bool)
signal quit_requested

var new_button: Button
var continue_button: Button
var cancel_button: Button
var confirm_button: Button
var confirmation: Control
var status_line: Label
var illustration: TextureRect
var has_file := false
var time := 0.0

func setup(saved: Dictionary, file_exists: bool) -> void:
	has_file = file_exists
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sea := ColorRect.new()
	var shader_material := ShaderMaterial.new()
	shader_material.shader = OCEAN
	sea.material = shader_material
	add_child(sea)
	sea.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	illustration = UI.art("")
	illustration.texture = KYOGRE
	illustration.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	UI.place(self, illustration, 187, -6, 286, 289)

	var wordmark := UI.label("P O K É S A G A", 13, AQUA)
	UI.place(self, wordmark, 24, 47, 150, 26)
	var title := UI.label("宝可梦", 40, ICE)
	UI.place(self, title, 21, 69, 180, 54)
	var saga := UI.label("传说", 40, ICE)
	UI.place(self, saga, 21, 111, 146, 54)
	var title_font := FontVariation.new()
	title_font.base_font = get_theme_default_font()
	title_font.variation_embolden = 0.38
	for text in [title, saga]:
		text.add_theme_font_override("font", title_font)
		text.add_theme_constant_override("shadow_offset_x", 2)
		text.add_theme_constant_override("shadow_offset_y", 2)
		text.add_theme_color_override("font_shadow_color", Color("#07355a"))
	var rule := ColorRect.new()
	rule.color = AQUA
	UI.place(self, rule, 25, 170, 46, 2)

	if not saved.is_empty():
		continue_button = _button("继续冒险    ›", func(): start_requested.emit(false), true)
		UI.place(self, continue_button, 22, 200, 174, 41)
		continue_button.name = "Continue"
		var location := str(saved.get("location", ""))
		status_line = UI.label("%s  ·  %d 枚徽章" % [location, saved.get("badge_count", 0)], 10, ICE)
		UI.place(self, status_line, 24, 242, 220, 18)
	new_button = _button("新的冒险    ›", _on_new, saved.is_empty())
	UI.place(self, new_button, 22, 264 if continue_button else 204, 174, 39)
	new_button.name = "NewGame"
	if has_file and saved.is_empty():
		status_line = UI.label("原存档暂时无法读取。", 11, ICE)
		UI.place(self, status_line, 24, 248, 183, 22)
	set_process(true)

func _button(caption: String, action: Callable, primary: bool) -> Button:
	var b := UI.button(caption, action)
	var normal := Color("#92e7df") if primary else Color("#103859")
	var ink := MIDNIGHT if primary else ICE
	for key in ["normal", "hover", "pressed"]:
		var fill := normal if key == "normal" else normal.lightened(0.12)
		b.add_theme_stylebox_override(key, UI.box(fill, Color("#7ec4d7"), 5))
		b.add_theme_color_override("font_color" if key == "normal" else "font_" + key + "_color", ink)
	b.add_theme_font_size_override("font_size", 16)
	return b

func _process(delta: float) -> void:
	time += delta
	illustration.position.y = -6 + sin(time*0.72)*2.5

func _on_new() -> void:
	if is_instance_valid(confirmation):
		return
	if not has_file:
		start_requested.emit(true)
		return
	confirmation = ColorRect.new()
	confirmation.color = Color(0.015, 0.039, 0.09, 0.82)
	add_child(confirmation)
	confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UI.box(MIDNIGHT, AQUA, 8))
	UI.place(confirmation, card, 68, 72, 344, 174)
	UI.place(card, UI.label("开始新的冒险？", 23, ICE), 17, 17, 309, 32)
	UI.place(card, UI.wrapped("现有进度会替换为新档。", 15, AQUA), 18, 63, 300, 36)
	cancel_button = _button("保留原存档", _cancel, true)
	confirm_button = _button("重新开始", func(): start_requested.emit(true), false)
	UI.place(card, cancel_button, 17, 112, 147, 42)
	UI.place(card, confirm_button, 179, 112, 147, 42)
	cancel_button.grab_focus()

func _cancel() -> void:
	if is_instance_valid(confirmation):
		remove_child(confirmation)
		confirmation.queue_free()
		confirmation = null
	new_button.grab_focus()

func show_failure(message: String) -> void:
	if is_instance_valid(confirmation):
		_cancel()
	if not status_line:
		status_line = UI.label("", 11, ICE)
		UI.place(self, status_line, 23, 244, 423, 20)
	status_line.text = message

func handle_back() -> bool:
	if is_instance_valid(confirmation):
		_cancel()
	else:
		quit_requested.emit()
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		handle_back()
