extends RefCounted

const TREASURES := {"小蘑菇":250,"大蘑菇":2500,"芳香蘑菇":6250,"金珠":5000,"巨大金珠":10000,"珍珠":700,"大珍珠":3750,"星砂":1000,"星之碎片":4900,"美丽之羽":100}
const REPEL := {"除虫喷雾":100,"白银喷雾":200,"黄金喷雾":250}
static var pickups: Dictionary

static func objects(map: Dictionary) -> Array:
	if pickups.is_empty():pickups=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_pickups.json"))
	return pickups.get(map.id,[])

static func take(g,obj: Dictionary) -> bool:
	if not obj.has("kalos_item"):return false
	if g._flags().get(obj.flag,false):return true
	for move in obj.requires_moves:
		if not g._party_can_move(move):
			g._show_toast(g._field_move_hint(move,{"SURF":"冲浪","CUT":"居合斩","WATERFALL":"攀瀑","STRENGTH":"怪力","ROCK_SMASH":"碎岩"}.get(move,move)))
			return true
	var item: Array=obj.kalos_item
	match item[1]:
		"held":g._give_bag_item(item[0],"held",item[2])
		"berry":g._give_bag_item(item[0],"berry","",item[2])
		_:g._give_item(item[0],1,item[1])
	g._flags()[obj.flag]=true
	g._persist()
	g.world._draw_objects()
	g._show_toast("找到了%s！"%item[0])
	return true

static func entering(g,next: Dictionary) -> void:
	var region:=str(g.world.map_data.get("region",""))
	if region not in ["alola","kalos"] or next.get("region","")!=region:return
	var slot:=region+"_cave_exit"
	if next.get("allow_fly",false):
		g.save_data.erase(slot)
		return
	var cave:bool=next.get("physics",{}).has("wild_any") if region=="kalos" else str(next.get("alola_location","")).contains("cave") or next.id in ["alola_sandy_cave","alola_hill","alola_canyon","alola_diglett_tunnel","alola_lanakila"]
	if not g.world.map_data.get("allow_fly",false) or not cave:return
	var spot: Vector2i=g.world.player_pos
	for offset in [-g.world._dir_vec(),Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]:
		var cell: Vector2i=spot+Vector2i(offset)
		if not g.world.is_blocked(cell) and not g.world.is_water(cell) and g.world.warp_at(cell).is_empty():
			g.save_data[slot]={"region":region,"map":g.world.map_data.id,"at":[cell.x,cell.y],"facing":"down"}
			break

static func use(g,name: String) -> bool:
	if name in REPEL:
		if int(g.save_data.get("js_repel",0))>0:
			g._dialog(["上一瓶喷雾的效果还在。"])
			return true
		g.save_data.js_repel=REPEL[name]
		g._consume_item(name)
		g._persist()
		g._show_toast("%s会持续%d步。"%[name,REPEL[name]])
		return true
	if name!="离洞绳":return false
	var exit: Dictionary=g.save_data.get(str(g.world.map_data.region)+"_cave_exit",{})
	if exit.is_empty():g._dialog(["这处场地没有通往洞外的绳索落点。"])
	else:g._pick("用离洞绳回到进洞处？",["离开洞窟","继续探索"],func(i):
		if i!=0:return
		g._do_warp(exit)
		if g.world.map_data.id==exit.map:
			g._consume_item(name)
			g._persist())
	return true

static func counter(g,npc: Dictionary) -> bool:
	if npc.get("kalos_intro_potion",false):
		if g._flags().get("k_aquacorde_potion",false):
			g._dialog(["伤药能回复宝可梦的体力。"],npc.name)
		else:
			g._give_item("伤药",1,"heal")
			g._flags().k_aquacorde_potion=true
			g._persist()
			g._dialog(["出发旅行了？这瓶伤药带上吧。"],npc.name)
		return true
	if not (npc.get("kalos_shop",false) or npc.get("alola_shop",false)):return false
	var bag: Array=g.bag_items.filter(func(item):return item.name in TREASURES and int(item.count)>0)
	if bag.is_empty():return false
	g._pick("友好商店",["购买道具","出售宝物","离开"],func(i):
		if i==0:g._open_shop(npc)
		elif i==1:
			g._pick("要卖出哪一件？",bag.map(func(item):return "%s　¥%d"%[item.name,TREASURES[item.name]]),func(j):
				var key: String=bag[j].name
				if g._bag_count(key)>0:
					g._consume_item(key)
					g.save_data.money+=int(TREASURES[key])
					g._persist()
					g._show_toast("已售出%s。"%key)))
	return true
