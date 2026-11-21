extends RefCounted
## Named Johto event characters have their own GBA field sheets. Ordinary NPCs
## keep NpcAppearance's normal Emerald portraits. All feet align to a 16px tile.
const ROOT := "res://assets/johto_gba/actors/"
const SOURCE_FRAMES := {"down":[0,3,4],"up":[1,5,6],"left":[2,7,8],"right":[2,7,8]}
const FRUIT := {"红球果":"red","蓝球果":"blue","黄球果":"yellow","绿球果":"green","白球果":"white","黑球果":"black","粉球果":"pink"}
const EVENT_ROLES := {
	"j_well_boss":"proton","j_executive":"petrel","j_engine_boss":"ariana","j_broadcast_boss":"archer","j_gs_kurt":"kurt",
	"j_mr_pokemon":"gentleman","j_elm":"elm","j_oak":"prof_oak","j_eusine":"eusine","j_aide":"scientist_m",
	"j_dragon_elder":"old_man","j_true_director":"gentleman","j_fake_director":"gentleman"
}
const CHARACTER := {
	"fr_little_girl":"little_girl","johto_moms_friend":"woman_2","cr_elm":"elm","cr_rival":"silver","cr_scientist":"scientist_m","cr_officer":"policeman","cr_gentleman":"gentleman",
	"cr_oak":"prof_oak","cr_sage":"sage","cr_falkner":"falkner","cr_bugsy":"bugsy","cr_whitney":"whitney",
	"cr_lass":"lass","cr_morty":"morty","cr_chuck":"chuck","cr_jasmine":"jasmine","cr_pryce":"pryce","cr_clair":"clair",
	"cr_kurt":"kurt","cr_rocket":"rocket_m","cr_rocket_girl":"rocket_f","cr_slowpoke":"slowpoke","cr_youngster":"youngster",
	"cr_black_belt":"black_belt","cr_bird":"farfetchd","cr_sudowoodo":"sudowoodo","cr_eusine":"eusine","cr_raikou":"raikou",
	"cr_entei":"entei","cr_suicune":"suicune","cr_kimono_girl":"kimono","cr_amphy":"ampharos","cr_lance":"lance",
	"cr_dragon":"dragonite","cr_murkrow":"murkrow","cr_electrode":"electrode","cr_red_gyarados":"shiny_gyarados",
	"crystal_misty":"misty","crystal_blue":"blue","crystal_surge":"surge","crystal_sabrina":"sabrina","crystal_erika":"erika",
	"crystal_janine":"janine","crystal_brock":"brock","crystal_blaine":"blaine","crystal_red":"red_normal",
	"crystal_teacher":"girl_1","crystal_raikou":"raikou","crystal_entei":"entei","crystal_suicune":"suicune","crystal_lugia":"lugia",
	"crystal_ho_oh":"ho_oh","fr_snorlax":"snorlax","team_rocket_m":"rocket_m"
}
const NAMES := {
	"妈妈":"mom","阿银":"silver","劲敌":"silver","红发少年":"silver","米那君":"eusine","小葵":"beauty","胡桃":"girl_1",
	"龙之长老":"old_man","正辉":"bill","赤红":"red_normal","四天王 一树":"will","四天王 阿桔":"koga","四天王 希巴":"bruno",
	"四天王 梨花":"karen","冠军 阿渡":"lance","龙使者 阿渡":"lance","阿渡":"lance"
}
static var frames: Dictionary = {}
static var poses: Dictionary = {}
static var atlas: Texture2D

static func book() -> Dictionary:
	if frames.is_empty():
		frames = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"cast.json"))
	return frames

static func character(npc: Dictionary) -> String:
	if npc.has("apricorn"):
		return "fruit_empty" if npc.get("picked",false) else "fruit_"+str(FRUIT.get(npc.apricorn,"green"))
	var name_text := str(npc.get("name",""))
	if EVENT_ROLES.has(npc.get("role","")): return EVENT_ROLES[npc.role]
	if NAMES.has(name_text): return NAMES[name_text]
	return str(CHARACTER.get(npc.get("field_art",""),""))

static func facing(raw: Variant) -> String:
	if raw is int or raw is float:
		return ["up","down","left","right"][clampi(int(raw),0,3)]
	return str(raw) if SOURCE_FRAMES.has(str(raw)) else "down"

static func draw(sprite: Sprite2D, key: String, face: String, stride := 0) -> void:
	var shape: Array = book()[key]
	var columns := int(shape[3])
	var index := int(SOURCE_FRAMES.get(face,SOURCE_FRAMES.down)[clampi(stride,0,2)])
	sprite.flip_h = face=="right" and columns>1
	if columns==12 and face=="right":
		index = 9+clampi(stride,0,2)
		sprite.flip_h=false
	elif index>=columns:
		index = mini(int(SOURCE_FRAMES.get(face,SOURCE_FRAMES.down)[0]),columns-1)
	var id := key+"/"+str(index)
	if not poses.has(id):
		if atlas == null: atlas=load(ROOT+"cast.png")
		var frame := AtlasTexture.new()
		frame.atlas = atlas
		frame.region = Rect2(index*int(shape[1]),int(shape[0]),int(shape[1]),int(shape[2]))
		frame.filter_clip = true
		poses[id]=frame
	sprite.texture=poses[id]
