extends RefCounted
## Sprite and palette indices generated together by tools/import_dex_art.py.
const TILE_SIZE := 64
const COLS := 16
const PAGE_SIZE := COLS * COLS
static var _index: Dictionary = {}

static func texture(species_id: int, form_key: String, shiny: bool) -> Texture2D:
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
