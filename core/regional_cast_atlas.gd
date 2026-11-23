extends RefCounted

var directory: String
var actor_key: String
const FACES := {"down":[0,3,4],"up":[1,5,6],"left":[2,7,8],"right":[9,10,11]}
var records: Dictionary
var atlas: Texture2D
var gallery: Texture2D
var textures: Dictionary
var portraits: Dictionary

func _init(region: String) -> void:
	directory="res://assets/"+region+"/"
	actor_key=region+"_actor"

func data() -> Dictionary:
	if records.is_empty():records=JSON.parse_string(FileAccess.get_file_as_string(directory+"cast.json"))
	return records

func character(row: Dictionary) -> String:
	var table: Dictionary=data().field
	var who: String=row.get(actor_key,row.get("name",""))
	return who if table.has(who) else ""

func draw(sprite: Sprite2D,identity: String,face: String,stride:=0) -> void:
	var i:=int(FACES.get(face,FACES.down)[clampi(stride,0,2)])
	var key:=identity+str(i)
	if not textures.has(key):
		if not atlas:atlas=load(directory+"cast.png")
		var pos: Array=data().field[identity]
		var tex:=AtlasTexture.new()
		tex.atlas=atlas
		tex.region=Rect2(int(pos[0])+i*int(pos[2]),int(pos[1]),int(pos[2]),32)
		tex.filter_clip=true
		textures[key]=tex
	sprite.texture=textures[key]

func portrait(speaker: String) -> Texture2D:
	var index: Dictionary=data().portraits
	if not index.has(speaker):return null
	if not portraits.has(speaker):
		if not gallery:gallery=load(directory+"portraits.png")
		var pos: Array=index[speaker]
		var tex:=AtlasTexture.new()
		tex.atlas=gallery
		tex.region=Rect2(int(pos[0]),int(pos[1]),64,64)
		tex.filter_clip=true
		portraits[speaker]=tex
	return portraits[speaker]
