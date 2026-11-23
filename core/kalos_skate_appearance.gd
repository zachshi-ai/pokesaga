extends RefCounted
## Field-only transforms keep world rendering independent of battle and menu services.
const CAPS := {"green":"丰缘原色","red":"朱红","blue":"宝蓝","black":"炭黑","yellow":"金黄"}
static var sheets: Dictionary

static func speed(field,previous: Vector2i,dir: Vector2i) -> float:
	if field.map_data.get("region","")!="kalos" or not field.running or not field.taken.get("k_skates",false):return 1.0
	var style: String=field.taken.get("ks_skate_mode","normal")
	if style=="dash" and dir==-previous:return .65
	if style=="parallel" and dir.x*previous.x+dir.y*previous.y==0:return .78
	return 1.0

static func pose(field,body: Sprite2D) -> void:
	body.rotation=0
	if not field.running or not field.walking or not field.map_data.get("kalos_native",false) or not field.taken.get("k_skates",false):return
	var style: String=field.taken.get("ks_skate_mode","normal")
	var t: float=clampf(field.walk_timer/maxf(field._step_duration,.01),0,1)
	if field.jumping and style in ["cosmic","spin","backflip"]:
		body.rotation=t*TAU*(-1.0 if style=="backflip" else 2.0 if style=="cosmic" else 1.0)
	elif style=="parallel":
		body.rotation=sin(t*TAU)*.12

static func sheet(original: Texture2D,tint: String,afloat: bool) -> Texture2D:
	if tint=="green" or not CAPS.has(tint):return original
	var key:=tint+("_surf" if afloat else "_walk")
	if not sheets.has(key):sheets[key]=load("res://assets/npc/kalos_cap_%s.png"%key)
	return sheets[key]
