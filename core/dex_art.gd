extends RefCounted
## Sprite and palette indices generated together by tools/import_dex_art.py.
const TILE_SIZE := 64
const COLS := 16
const PAGE_SIZE := COLS * COLS
static var _index: Dictionary = {}
static var _model_views: Dictionary = {}
static var _footlines: Array = []

## ORAS includes both sides. Later HOME illustrations supply a front view when available.
static func model_view(species_id: int, form_key: String, shiny: bool, back := false) -> Texture2D:
	if _model_views.is_empty():
		var file := FileAccess.get_file_as_string("res://content/oras_pokemon.json")
		var parsed: Variant = JSON.parse_string(file)
		if parsed is Dictionary:
			_model_views = parsed.forms
			_footlines = parsed.feet
	var forms: Dictionary = _model_views.get(str(species_id),{})
	var views: Array = forms.get(form_key,[])
	if views.is_empty():
		return null
	var slot := int(views[(2 if back else 0) + (1 if shiny else 0)])
	if slot < 0:
		return null
	@warning_ignore("integer_division")
	var page := slot / PAGE_SIZE
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/oras/pokemon/%d.webp" % page)
	@warning_ignore("integer_division")
	atlas.region = Rect2((slot%COLS)*96, (slot%PAGE_SIZE/COLS)*96, 96, 96)
	atlas.set_meta("footline",float(_footlines[slot])/96.0)
	atlas.filter_clip = true
	return atlas

static func texture(species_id: int, form_key: String, shiny: bool) -> Texture2D:
	var model := model_view(species_id, form_key, shiny)
	if model != null:
		return model
	if _index.is_empty():
		var data := FileAccess.get_file_as_string("res://content/dex_art.json")
		var parsed: Variant = JSON.parse_string(data)
		if parsed is Dictionary:
			_index = parsed
	var forms: Dictionary = _index.get(str(species_id), {})
	var slot := int(forms.get(form_key, -1))
	if slot < 0:
		return null
	@warning_ignore("integer_division")
	var page := slot / PAGE_SIZE
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/dex/%s_%d.png" % ["shiny" if shiny else "normal", page])
	@warning_ignore("integer_division")
	atlas.region = Rect2((slot % COLS) * TILE_SIZE, (slot % PAGE_SIZE / COLS) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	atlas.filter_clip = true
	return atlas
