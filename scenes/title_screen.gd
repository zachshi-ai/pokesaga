extends Control
## Rayquaza is assembled from Emerald’s original 240 × 160 title tilemap.
const UI := preload("res://core/field_ui.gd")
const COVER := preload("res://assets/emerald/ui/rayquaza_title.png")
const MARKINGS := preload("res://scenes/title_markings.gdshader")
const ICE := Color("#fff8d6")
const AQUA := Color("#f9e780")
const MIDNIGHT := Color("#155048")

signal start_requested(fresh: bool, origin: String)
signal quit_requested

var johto_button: Button
var new_button: Button
var selected_origin := "kanto"
var continue_button: Button
var cancel_button: Button
var confirm_button: Button
var confirmation: Control
var status_line: Label
var has_file := false

func setup(saved: Dictionary, file_exists: bool) -> void:
	has_file = file_exists
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cover := UI.art("")
	cover.texture = COVER
	cover.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cover.stretch_mode = TextureRect.STRETCH_SCALE
	var palette := ShaderMaterial.new()
	palette.shader = MARKINGS
	cover.material = palette
	UI.place(self,cover,0,0,480,320)

	var wordmark := UI.label("P O K É S A G A", 13, AQUA)
	UI.place(self,wordmark,24,12,180,24)
	var title := UI.label("宝可梦传说", 36, ICE)
	UI.place(self,title,21,31,275,55)
	var title_font := FontVariation.new()
	title_font.base_font = get_theme_default_font()
	title_font.variation_embolden = 0.38
	title.add_theme_font_override("font", title_font)
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_color_override("font_shadow_color", MIDNIGHT)

	if not saved.is_empty():
		continue_button = _button("继续冒险    ›", func(): start_requested.emit(false, ""), true)
		UI.place(self, continue_button, 22, 200, 174, 41)
		continue_button.name = "Continue"
		var location := str(saved.get("location", ""))
		status_line = UI.label("%s  ·  %d 枚徽章" % [location, saved.get("badge_count", 0)], 10, ICE)
		UI.place(self, status_line, 24, 242, 220, 18)
	new_button = _button("关都 · 新的冒险", _on_new.bind("kanto"), saved.is_empty())
	UI.place(self, new_button, 22, 264 if continue_button else 204, 174, 39)
	new_button.name = "NewGame"
	johto_button = _button("城都 · 新的冒险", _on_new.bind("johto"), saved.is_empty())
	UI.place(self, johto_button, 207, 264 if continue_button else 204, 174, 39)
	johto_button.name = "NewJohto"
	if has_file and saved.is_empty():
		status_line = UI.label("原存档暂时无法读取。", 11, ICE)
		UI.place(self, status_line, 24, 248, 183, 22)

func _button(caption: String, action: Callable, primary: bool) -> Button:
	var b := UI.button(caption, action)
	var normal := Color("#FAE186") if primary else Color("#155048")
	var ink := MIDNIGHT if primary else ICE
	for key in ["normal", "hover", "pressed"]:
		var fill := normal if key == "normal" else normal.lightened(0.12)
		b.add_theme_stylebox_override(key, UI.box(fill, Color("#afc694"), 3))
		b.add_theme_color_override("font_color" if key == "normal" else "font_" + key + "_color", ink)
	b.add_theme_color_override("font_focus_color", ink)
	b.add_theme_font_size_override("font_size", 16)
	return b

func _on_new(origin: String) -> void:
	if is_instance_valid(confirmation):
		return
	selected_origin = origin
	if not has_file:
		start_requested.emit(true, selected_origin)
		return
	confirmation = ColorRect.new()
	confirmation.color = Color(0.015, 0.039, 0.09, 0.82)
	add_child(confirmation)
	confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UI.box(MIDNIGHT, AQUA, 4))
	UI.place(confirmation, card, 68, 72, 344, 174)
	UI.place(card, UI.label("从若叶镇重新出发？" if selected_origin == "johto" else "从真新镇重新出发？", 23, ICE), 17, 17, 309, 32)
	UI.place(card, UI.label("现有进度会替换为新档。", 15, AQUA), 18, 63, 300, 36)
	cancel_button = _button("保留原存档", _cancel, true)
	confirm_button = _button("重新开始", func(): start_requested.emit(true, selected_origin), false)
	UI.place(card, cancel_button, 17, 112, 147, 42)
	UI.place(card, confirm_button, 179, 112, 147, 42)
	cancel_button.grab_focus()

func _cancel() -> void:
	if is_instance_valid(confirmation):
		remove_child(confirmation)
		confirmation.queue_free()
		confirmation = null
	(johto_button if selected_origin == "johto" else new_button).grab_focus()

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
