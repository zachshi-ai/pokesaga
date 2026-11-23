extends RefCounted
const Party := preload("res://core/party.gd")
const Field := preload("res://core/kalos_field.gd")
const TYPES := ["一般","格斗","飞行","毒","地面","岩石","虫","幽灵","钢","火","水","草","电","超能力","冰","龙","恶","妖精"]
const FRIENDS := ["三色堇","可尔妮","莎莉娜","玛琪艾儿","查克洛","提耶鲁诺","紫罗兰","帅哥","希特隆","帕琦拉","志米","福爷","柚丽嘉","葛吉花","得抚","朵拉塞娜","多罗巴","玛绣"]
static var catalog: Dictionary

static func data() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_safari.json"))
	return catalog

static func side():
	return load("res://core/kalos_side.gd")

static func safari(g) -> void:
	var labels: Array=[]
	for i in TYPES.size():labels.append("%s · %s属性"%[FRIENDS[i],TYPES[i]])
	labels.append("离开")
	g._pick("朋友狩猎区 · 本地名片",labels,func(i):
		if i>=TYPES.size():return
		var book: Dictionary=g.save_data.get_or_add("kalos_safari_cards",{})
		var key:=str(i)
		if not book.has(key):
			var species: Array=[]
			for slot in data().safari[i]:
				var roll: int=g.rng.randi_range(1,100);var chosen: Array=slot[-1]
				for entry in slot:
					roll-=int(entry[2])
					if roll<=0:chosen=entry;break
				species.append(int(chosen[0]))
			book[key]=species
		g.save_data.kalos_safari_type=i
		g._persist();g._dialog(["已选择%s的狩猎区。进入草地后，可以遇到这张名片固定的三种Lv.30宝可梦。"%FRIENDS[i]],"狩猎区接待员"))

static func safari_mon(g,id: int) -> Dictionary:
	var mon: Dictionary=side().roster_mon(g,id,30)
	var traits: Array=data().abilities.get(str(id),[0,0,0])
	if traits[2] and g.rng.randi_range(0,2)==0:mon.ability=int(traits[2])
	else:mon.ability=int(traits[1]) if traits[1] and g.rng.randi_range(0,1)==1 else int(traits[0])
	mon.ability_name=g.get_node("/root/Data").abilities.get(int(mon.ability),{}).get("name","")
	var stats:=["hp","atk","def","spa","spd","spe"]
	mon.ivs={}
	for stat in stats:mon.ivs[stat]=g.rng.randi_range(0,31)
	for n in 2:
		var stat=stats.pop_at(g.rng.randi_range(0,stats.size()-1));mon.ivs[stat]=31
	var kind:="none"
	for n in 5+2*int(bool(g._flags().get("ks_shiny",false))):
		kind=Party.roll_shiny(g.appearance_rng)
		if kind!="none":break
	Party.set_shiny_kind(mon,kind);mon.kalos_stationary=true
	return mon

static func use_radar(g) -> void:
	if not g.world.wild_tile_here() or g.world.surfing:
		g._dialog(["请站在可以遇见野生宝可梦的普通草丛里使用。"]);return
	var state: Dictionary=g.save_data.get_or_add("kalos_radar",{"charge":50,"chain":0})
	if int(state.get("charge",50))<50:
		g._dialog(["还需要走 %d 步为探测器充电。"%(50-int(state.charge))]);return
	var pool:=Field.habitat(g.world.map_data,g._flags(),Field.terrain(g.world.map_data,g.world.player_pos,false))
	if pool.is_empty():
		for method in ["grass","tall-grass","yellow-flowers","purple-flowers","red-flowers"]:
			pool=Field.habitat(g.world.map_data,g._flags(),method)
			if not pool.is_empty():break
	if pool.is_empty():g._dialog(["这里没有可以探测的普通草丛。"]);return
	var field=g.world;var origin: Vector2i=field.player_pos
	var patches: Array=[]
	for y in range(origin.y-4,origin.y+5):
		for x in range(origin.x-4,origin.x+5):
			var p:=Vector2i(x,y)
			if p==origin or field.is_blocked(p) or field.tile_at(p)!=11:continue
			patches.append([x,y])
	if patches.is_empty():g._dialog(["身边没有其他可以摇晃的草丛。"]);return
	state.charge=0
	state.map=str(field.map_data.id)
	state.patch=patches[g.rng.randi_range(0,patches.size()-1)]
	state.slot=pool[g.rng.randi_range(0,pool.size()-1)]
	show_patch(field,state.patch)
	g._persist()
	g._dialog(["草丛摇动了！向%s走，到小地图坐标（%d，%d）的草丛调查。"%[direction(origin,Vector2i(state.patch[0],state.patch[1])),state.patch[0],state.patch[1]]])

static func clear_patch(field) -> void:
	var reference: WeakRef=field.get_meta("kalos_radar_marker") if field.has_meta("kalos_radar_marker") else null
	if reference!=null:
		var marker=reference.get_ref()
		if is_instance_valid(marker):
			field._obj_nodes.erase(marker)
			marker.queue_free()
		field.remove_meta("kalos_radar_marker")

static func show_patch(field,at: Array) -> void:
	var point:=Vector2i(int(at[0]),int(at[1]))
	if field.has_meta("kalos_radar_marker"):
		var previous=field.get_meta("kalos_radar_marker").get_ref()
		if is_instance_valid(previous) and not previous.is_queued_for_deletion() and previous.get_meta("tile")==point:
			return
		clear_patch(field)
	var marker:=Sprite2D.new()
	marker.set_meta("tile",point)
	marker.texture=preload("res://assets/npc/kalos_mega_glint.png")
	marker.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	marker.position=(Vector2(point)+Vector2(.5,.5))*field.TILE
	marker.z_index=field.Z_ACTOR+point.y*2-1
	field.add_child(marker)
	field._obj_nodes.append(marker)
	field.set_meta("kalos_radar_marker",weakref(marker))
	var pulse:=marker.create_tween().set_loops()
	pulse.tween_property(marker,"modulate:a",.22,.30)
	pulse.tween_property(marker,"modulate:a",1.0,.30)

static func direction(a: Vector2i,b: Vector2i) -> String:
	var d:=b-a
	return ("北" if d.y<0 else "南" if d.y>0 else "")+("西" if d.x<0 else "东" if d.x>0 else "")

static func step(g) -> bool:
	var mid:=str(g.world.map_data.id)
	if mid=="kalos_friend_safari" and g.world.wild_tile_here() and g.save_data.has("kalos_safari_type") and g.rng.randf()<0.13:
		var key:=str(int(g.save_data.kalos_safari_type));var ids: Array=g.save_data.kalos_safari_cards[key]
		var id:=int(ids[g.rng.randi_range(0,2)])
		var mon:=safari_mon(g,id)
		g._start_wild_battle(id,30,"",Callable(),mon.shiny_kind,0,mon);return true
	var state: Dictionary=g.save_data.get("kalos_radar",{})
	if state.is_empty():return false
	state.charge=mini(50,int(state.get("charge",50))+1)
	if not state.has("patch"):return false
	if state.map!=mid:
		clear_patch(g.world)
		state.erase("patch");state.chain=0;return false
	show_patch(g.world,state.patch)
	var p: Vector2i=g.world.player_pos
	if int(state.patch[0])!=p.x or int(state.patch[1])!=p.y:return false
	clear_patch(g.world)
	var slot: Dictionary=state.slot
	var id:=int(slot.get("species",slot.get("id",0)))
	if state.get("last",0) and g.rng.randf()<0.8:id=int(state.last)
	if id<=0:state.erase("patch");return false
	state.erase("patch")
	var level:=int(slot.get("min",slot.get("level",5)))
	g._start_wild_battle(id,level,"",func(result):
		if result in ["caught","a"]:
			state.chain=int(state.get("chain",0))+1 if int(state.get("last",0))==id else 1
			state.last=id;state.charge=50
			g._show_toast("探测器连锁　%d"%int(state.chain))
		else:state.chain=0;state.erase("last")
		if result=="b" and g._party_fainted():g._blackout()
		g._persist())
	return true

static func dowse(g) -> void:
	var pos: Vector2i=g.world.player_pos
	var closest: Array=[];var dist:=99999
	for o in g.world.objects:
		if not o.get("hidden",false) and not str(o.get("kind","")).contains("hidden"):continue
		if g._flags().get(str(o.get("flag","")),false):continue
		var pt: Array=o.get("at",[])
		if pt.size()!=2:continue
		var delta: int=pos.distance_squared_to(Vector2i(int(pt[0]),int(pt[1])))
		if delta<dist:closest=pt;dist=delta
	if closest.is_empty():g._dialog(["探宝器没有反应。附近没有尚未发现的隐藏道具。"]);return
	var target:=Vector2i(int(closest[0]),int(closest[1]))
	g._dialog(["信号就在脚边。" if target==pos else "探针指向%s，离你约 %d 格。"%[direction(pos,target),absi(target.x-pos.x)+absi(target.y-pos.y)]])
