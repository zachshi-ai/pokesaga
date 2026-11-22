extends RefCounted
const LODGE := "MAP_HEADER_VILLA"
const RESORT := "MAP_HEADER_RESORT_AREA"
const VISITORS := [["RIVAL"],["COUNTERPART"],["PROF_ROWAN"],["MOM"],["ROARK"],["GARDENIA"],["FANTINA"],["MAYLENE"],["CRASHER_WAKE"],["BYRON"],["CANDICE"],["VOLKNER"],["CYNTHIA"],["FLINT","VOLKNER"],["MAYLENE","CANDICE"]]
const OUTSIDE := ["PROF_ROWAN","ROARK","GARDENIA","MAYLENE","BYRON"]
const DROP_IN := ["FANTINA","CRASHER_WAKE","CANDICE","CYNTHIA"]
const WELCOME := {"table":0,"small_sofa":1,"bookshelf":2,"houseplant":5,"piano":12}
const NAMES := {"RIVAL":"阿驯","COUNTERPART":"小光","PROF_ROWAN":"山梨博士","MOM":"妈妈","ROARK":"瓢太","GARDENIA":"菜种","FANTINA":"梅丽莎","MAYLENE":"阿李","CRASHER_WAKE":"吉宪","BYRON":"东瓜","CANDICE":"小菘","VOLKNER":"电次","CYNTHIA":"竹兰","FLINT":"大叶"}
static var tables: Dictionary

class FurnitureLayer extends Node2D:
	func _process(_delta: float) -> void:
		if get_parent().map_data.get("source_id","")!=LODGE:
			queue_free()

static func data() -> Dictionary:
	if tables.is_empty():tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_villa.json"))
	return tables

static func stock(g) -> Dictionary:return g._flags().get_or_add("s_villa_furniture",{})

static func available(g,key: String) -> bool:
	var save: Dictionary=g.save_data
	var owned:=stock(g)
	match key:
		"music_box":return owned.has("rack")
		"tea_set":return owned.has("guest_set")
		"piano":return maxi(int(save.get("s_hall_entries",0)),save.get("sinnoh_hall_history",[]).size())>=10
		"guest_set":return int(save.get("s_battleground_battles",0))>=50
		"wall_clock":return int(save.get("s_berries_planted",0))>=50
		"masterpiece":return int(save.get("s_eggs_hatched",0))>=30
		"chandelier":return int(save.get("s_pedometer",0))>=300000
		"pokemon_bust":
			var records: Dictionary=save.get("s_frontier_records",{})
			for kind in ["tower","factory","hall","castle","arcade"]:
				if not records.keys().any(func(k):return str(k).get_slice("_",0)==kind and int(records[k])>=1):return false
		"pokemon_bust_silver":return save.get("s_frontier_prints",{}).values().any(func(v):return int(v)>=1)
	return true

static func daily(g) -> bool:
	var f: Dictionary=g._flags()
	var today:=Time.get_date_string_from_system()
	if f.get("s_villa_day","")==today:return false
	f.s_villa_day=today
	var count:=stock(g).size()
	var tier:=2 if count>=12 else (1 if count>=8 else 0)
	f.s_villa_guest=g.rng.randi_range(0,[4,12,15][tier]-1) if g.rng.randi_range(0,99)<=[25,75,90][tier] else -1
	f.s_villa_inside=false
	g._persist()
	return true

static func guest(f: Dictionary) -> Array:
	var i:=int(f.get("s_villa_guest",-1))
	return VISITORS[i] if i>=0 and i<VISITORS.size() else []

static func visibility(map: String, local: String, f: Dictionary) -> int:
	var who:=local.trim_prefix("LOCALID_")
	if map==RESORT:
		if who=="SCHOOL_KID_M":return int(not f.get("s_villa_deed",false))
		if who in OUTSIDE:return int(f.get("s_villa_deed",false) and who in guest(f) and not f.get("s_villa_inside",false))
	if map!=LODGE:return -1
	if who=="BOOK":return 0
	if who=="SCHOOL_KID_M":return int(not f.get("s_villa_furniture",{}).has("table"))
	if who=="DELIVERY_GUY":return 0
	if who in NAMES:return int(who in guest(f) and (guest(f).size()>1 or (who not in OUTSIDE and who not in DROP_IN) or f.get("s_villa_inside",false)))
	return -1

static func repaint(g) -> void:
	var layer=g.world.get_node_or_null("VillaFurniture")
	if is_instance_valid(layer):g.world.remove_child(layer);layer.queue_free()
	layer=FurnitureLayer.new();layer.name="VillaFurniture";g.world.add_child(layer)
	var floor: Array=g.world.map_data.physics.collision.duplicate(true)
	g.world.emerald_collision=floor
	var atlas: Texture2D=load("res://assets/platinum/villa.png")
	for key in stock(g):
		var row: Dictionary=data()[key]
		var cut: Array=row.texture
		for placement in row.placements:
			var pos: Array=placement.anchor
			var b: Array=placement.bounds
			var sprite:=Sprite2D.new();sprite.centered=false;sprite.texture=atlas
			sprite.region_enabled=true;sprite.region_rect=Rect2(cut[0],cut[1],cut[2],cut[3])
			sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position=Vector2(pos[0]+row.offset[0],pos[1]+row.offset[1])
			sprite.z_index=g.world.Z_ACTOR+int(pos[1]/16)*2-1
			layer.add_child(sprite)
			if b.size()==4:
				for y in range(int(b[1]),int(b[3])+1):
					for x in range(int(b[0]),int(b[2])+1):floor[y][x]=1
	if stock(g).has("table"):
		var book:=Sprite2D.new();book.centered=false;book.texture=atlas;book.region_enabled=true
		book.region_rect=Rect2(425,92,13,11);book.position=Vector2(194,104)
		book.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;book.z_index=g.world.Z_ACTOR+16
		layer.add_child(book)
	layer.set_meta("count",stock(g).size())

static func action(tag: String,value: String="") -> Dictionary:
	return {"id":"s_villa_interaction","steps":[{"sinnoh_villa":tag,"value":value}]}

static func event(g,kind: String,ctx: Dictionary) -> Dictionary:
	var map: Dictionary=g.world.map_data
	var header: String=map.get("source_id","")
	if header not in [LODGE,RESORT]:return {}
	if not g._flags().get("s_villa_deed",false):return {}
	if daily(g):g.world.refresh_story_actors(g._flags())
	if header==LODGE and (kind=="map_enter" or not g.world.has_node("VillaFurniture")):repaint(g)
	var local: String=ctx.get("local_id",ctx.get("actor",""))
	if header==RESORT:
		if kind=="talk" and local.trim_prefix("LOCALID_") in guest(g._flags()) and not g._flags().get("s_villa_inside",false):return action("invite",local.trim_prefix("LOCALID_"))
		return {}
	if kind=="step" and g.world.player_pos==Vector2i(10,7) and not g._flags().get("s_villa_inside",false):
		var group:=guest(g._flags())
		if group.size()==1 and group[0] in DROP_IN:return action("arrive",group[0])
	if kind=="talk" and local in ["LOCALID_BOOK","LOCALID_SCHOOL_KID_M"]:return action("orders")
	if kind=="field":
		var at: Vector2i=ctx.at
		if at in [Vector2i(11,7),Vector2i(13,7),Vector2i(12,8)]:return action("orders")
		for key in stock(g):
			for p in data()[key].placements:
				var b: Array=p.bounds
				if b.size()==4 and at.x>=b[0] and at.y>=b[1] and at.x<=b[2] and at.y<=b[3]:return action("inspect",key)
	return {}

static func handle(g,op: String,value: String) -> void:
	if op=="arrive":
		g._flags().s_villa_inside=true;g.world.refresh_story_actors(g._flags());g._persist()
		g._dialog(["打扰了，可以在你的别墅休息一会儿吗？"],NAMES[value]).closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return
	if op=="invite":
		g._pick("邀请%s到别墅坐坐？"%NAMES[value],["请进","再见"],func(i):
			if i==0:g._flags().s_villa_inside=true;g.world.refresh_story_actors(g._flags());g._persist()
			g._story_step(),g._story_step)
		return
	if op=="inspect":
		g._dialog(["这件%s是你从别墅订单里选购的。"%data()[value].name],"别墅").closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return
	var owned:=stock(g)
	var list: Array=[]
	var labels: Array=[]
	for key in data():
		if owned.is_empty() and key!="table":continue
		if not available(g,key):continue
		var row: Dictionary=data()[key]
		labels.append("%s　%s"%[row.name,"已送达" if owned.has(key) else ("免费" if int(row.price)==0 else "₽%d"%int(row.price))])
		list.append(key)
	g._pick("别墅订货单　余额 ₽%d"%int(g.save_data.money),labels,func(i):
		var key: String=list[i]
		var row: Dictionary=data()[key]
		var cost:=int(row.price)
		if owned.has(key):g._dialog(["这件家具已经送到了。"]).closed.connect(g._story_step,CONNECT_ONE_SHOT);return
		if int(g.save_data.money)<cost:g._dialog(["还差 ₽%d。"%(cost-int(g.save_data.money))]).closed.connect(g._story_step,CONNECT_ONE_SHOT);return
		g._pick("订购%s？"%row.name,["确认订购","取消"],func(j):
			if j!=0:g._story_step();return
			g.save_data.money=int(g.save_data.money)-cost
			owned[key]=true
			var message: Array=["%s已经送达。"%row.name]
			if WELCOME.has(key):
				g._flags().s_villa_guest=WELCOME[key]
				g._flags().s_villa_inside=true
				message.append("%s来参观你的新家具了。"%NAMES[guest(g._flags())[0]])
			repaint(g);g.world.warp_to(Vector2i(10,6));g.world.facing="down"
			g.world.refresh_story_actors(g._flags());g._refresh_hud();g._persist()
			g._dialog(message,"送货员").closed.connect(g._story_step,CONNECT_ONE_SHOT),g._story_step),g._story_step)
