extends RefCounted

const ART := "res://assets/platinum/actors/"
const DIRECTIONS := {"down":[0,3,4],"up":[1,5,6],"left":[2,7,8],"right":[9,10,11]}
static var records: Dictionary = {}
static var atlas: Texture2D
static var frames: Dictionary = {}

static func character(row: Dictionary) -> String:
	if records.is_empty(): records=JSON.parse_string(FileAccess.get_file_as_string(ART+"cast.json"))
	var key := str(row.get("platinum_gfx","")).trim_prefix("OBJ_EVENT_GFX_").to_lower()
	if key=="var_0" and (str(row.get("local_id","")).contains("COUNTERPART") or str(row.get("local_id","")).contains("DAWN")): key="dawn"
	if key in ["heroine","heroine_normal","dawn_normal"]: key="dawn"
	return key if records.has(key) else ""

static func draw(sprite: Sprite2D, identity: String, face: String, stride := 0) -> void:
	var idx := int(DIRECTIONS.get(face,DIRECTIONS.down)[clampi(stride,0,2)])
	var pose := identity+str(idx)
	if not frames.has(pose):
		if not atlas: atlas=load(ART+"cast.png")
		var rect: Array = records[identity]
		var frame := AtlasTexture.new()
		frame.atlas=atlas
		frame.region=Rect2(int(rect[0])+idx*int(rect[2]),int(rect[1]),int(rect[2]),32)
		frame.filter_clip=true
		frames[pose]=frame
	sprite.texture=frames[pose]
