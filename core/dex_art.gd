extends RefCounted
## Sprite and palette indices generated together by tools/import_dex_art.py.
const TILE_SIZE := 64
const COLS := 16
const PAGE_SIZE := COLS * COLS
static var indices: Dictionary = {}
static var feet: Dictionary = {}

static func texture(species_id: int, form_key: String, shiny: bool, back := false) -> Texture2D:
	var side := "back_" if back else ""
	if not indices.has(side):
		indices[side] = JSON.parse_string(FileAccess.get_file_as_string("res://content/dex_%sart.json" % side))
		feet[side] = JSON.parse_string(FileAccess.get_file_as_string("res://content/dex_%sfeet.json" % side))
	var forms: Dictionary = indices[side].get(str(species_id), {})
	var slot := int(forms.get(form_key, -1))
	if slot < 0:
		return null
	@warning_ignore("integer_division")
	var page := slot / PAGE_SIZE
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/dex/%s%s_%d.png" % [side, "shiny" if shiny else "normal", page])
	@warning_ignore("integer_division")
	atlas.region = Rect2((slot % COLS) * TILE_SIZE, (slot % PAGE_SIZE / COLS) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	atlas.set_meta("feet", feet[side][slot])
	atlas.filter_clip = true
	return atlas

## These three gender differences are visible only from behind. The Pokédex
## shows that detail, while an opposing battler faces the player.
static func battle_texture(species_id: int, form_key: String, shiny: bool, back: bool) -> Texture2D:
	if not back and form_key in ["TORCHIC_FEMALE", "BUIZEL_FEMALE", "FLOATZEL_FEMALE"]:
		form_key = ""
	return texture(species_id, form_key, shiny, back)
