extends RefCounted

const ART := "res://assets/kalos/"
const FACES := {"down":[0,3,4],"up":[1,5,6],"left":[2,7,8],"right":[9,10,11]}
static var records: Dictionary
static var atlas: Texture2D
static var gallery: Texture2D
static var textures: Dictionary
static var portraits: Dictionary

static func data() -> Dictionary:
	if records.is_empty():records=JSON.parse_string(FileAccess.get_file_as_string(ART+"cast.json"))
	return records

static func character(row: Dictionary) -> String:
	var table: Dictionary=data().field
	var who: String=row.get("kalos_actor",row.get("name",""))
	return who if table.has(who) else ""

static func draw(sprite: Sprite2D,identity: String,face: String,stride:=0) -> void:
	var i:=int(FACES.get(face,FACES.down)[clampi(stride,0,2)])
	var key:=identity+str(i)
	if not textures.has(key):
		if not atlas:atlas=load(ART+"cast.png")
		var pos: Array=data().field[identity]
		var tex:=AtlasTexture.new()
		tex.atlas=atlas
		tex.region=Rect2(int(pos[0])+i*int(pos[2]),int(pos[1]),int(pos[2]),32)
		tex.filter_clip=true
		textures[key]=tex
	sprite.texture=textures[key]

static func portrait(speaker: String) -> Texture2D:
	var index: Dictionary=data().portraits
	if not index.has(speaker):return null
	if not portraits.has(speaker):
		if not gallery:gallery=load(ART+"portraits.png")
		var pos: Array=index[speaker]
		var tex:=AtlasTexture.new()
		tex.atlas=gallery
		tex.region=Rect2(int(pos[0]),int(pos[1]),64,64)
		tex.filter_clip=true
		portraits[speaker]=tex
	return portraits[speaker]
