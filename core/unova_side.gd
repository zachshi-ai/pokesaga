extends RefCounted
## Field pickups and optional events in each Unova era. Positions in the source archives
## are absolute grid coordinates, including the hidden-item background events.
const Field := preload("res://core/unova_field.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const Party := preload("res://core/party.gd")
const Dex := preload("res://core/dex_variants.gd")
const Fusion := preload("res://core/fusion.gd")
static var archive: Dictionary={}
static var events: Array=[]

static func data() -> Dictionary:
	if archive.is_empty():
		archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_side_items.json"))
	return archive

static func book() -> Array:
	if events.is_empty():
		events=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_side_events.json"))
	return events

static func item_name(key: String) -> String:
	return str(data().items.get(key,[key])[0])

static func give(g,key: String,count:=1) -> void:
	if key.begins_with("TM") or key.begins_with("HM"):
		Field.give_machine(g,int(key.substr(2)),key.begins_with("HM"))
		return
	var row: Array=data().items.get(key,[])
	if row.is_empty():return
	var category:=str(row[1])
	if category in ["held","berry"]:
		for i in count:
			if category=="held":g._give_bag_item(row[0],"held",key)
			else:g._give_bag_item(row[0],"berry","",key.trim_suffix("_BERRY").to_lower())
	else:g._give_item(row[0],count,category)

static func local_cell(m: Dictionary, x: int, z: int) -> Array:
	var origin: Array=m.get("unova_origin",[0,0])
	var at:=[x-int(origin[0]),z-int(origin[1])]
	var size: Array=m.get("size",[0,0])
	if at[0]<0 or at[1]<0 or at[0]>=int(size[0]) or at[1]>=int(size[1]):return []
	return at

static func map_objects(m: Dictionary) -> Array:
	var result: Array=m.get("objects",[]).duplicate(true)
	var era:=str(m.get("unova_era",""))
	if not data().pickups.has(era):return result
	var zone:=str(m.get("unova_zone",""))
	var group:=zone if era=="b2" else str(int(m.get("unova_event_bank",-1)))
	for row in data().pickups[era].get(group,[]):
		var at:=local_cell(m,int(row[0]),int(row[1]))
		if at.is_empty():continue
		var script:=int(row[2])
		var hidden:=script>=8000
		var flag:="u_%s_pick_%s"%[era,script]
		result.append({"kind":"unova_hidden" if hidden else "item","at":at,"flag":flag,"unova_item":row[3],"count":int(row[4]),"native_fixture":hidden,"legacy_map":str(m.id)+"_"+era})
	if era=="b2":
		if zone=="underground_ruins":
			result.append({"kind":"unova_seal","at":[24,11],"native_fixture":true})
		if zone=="hidden_grotto":
			result.append({"kind":"unova_grotto_content","at":[15,12],"native_fixture":true})
			result.append({"kind":"unova_grotto_exit","at":[15,26],"native_fixture":true})
		for i in data().grottos.size():
			var grotto: Array=data().grottos[i]
			if zone!=grotto[0]:continue
			var at:=local_cell(m,int(grotto[1]),int(grotto[2]))
			if not at.is_empty():
				result.append({"kind":"unova_grotto","at":at,"native_fixture":true,"unova_grotto":i})
	return result

static func object_action(g,o: Dictionary) -> bool:
	if o.get("kind","")=="unova_seal":
		if g._flags().get("u2_champion",false):
			mark(g,"us_b2_ruin_switch")
			g._dialog(["脚下的古老机关沉入地面。大厅北方传来石门开启的声音。"])
		return true
	if o.get("kind","")=="unova_grotto_content":
		open_grotto(g,int(g.save_data.get("unova_grotto_visit",{}).get("index",-1)))
		return true
	if o.get("kind","")=="unova_grotto_exit":
		preload("res://core/unova_side_grotto.gd").leave(g)
		return true
	if o.has("unova_grotto"):
		preload("res://core/unova_side_grotto.gd").enter(g,int(o.unova_grotto))
		return true
	if not o.has("unova_item"):return false
	if g._flags().get(o.flag,false):return true
	var key:=str(o.unova_item)
	give(g,key,int(o.count))
	g._flags()[o.flag]=true
	g.world._draw_objects()
	g._persist()
	var label:=Field.machine_name(g,int(key.substr(2)),key.begins_with("HM")) if key.begins_with("TM") or key.begins_with("HM") else item_name(key)
	g._dialog(["%s%s%s。"%["在这里发现了" if o.kind=="unova_hidden" else "捡到了",label," ×%d"%int(o.count) if int(o.count)>1 else ""]])
	return true

static func active(row: Dictionary,flags: Dictionary) -> bool:
	for flag in row.get("requires",[]):
		if not flags.get(flag,false):return false
	for flag in row.get("until",[]):
		if flags.get(flag,false):return false
	return true

static func decorate(m: Dictionary,flags: Dictionary,npcs: Array) -> Array:
	var result:=npcs.duplicate(true)
	var zone:=str(m.get("unova_zone",""))
	var era:=str(m.get("unova_era",""))
	if zone=="" or era=="":return result
	var anchors: Dictionary=m.get("unova_anchors",{})
	if zone=="hidden_grotto" and int(flags.get("us_grotto_display",0))!=0:
		var display:=int(flags.us_grotto_display)
		var actor:={"role":"unova_grotto_resident","at":[15,12],"name":"隐藏洞穴","grotto_resident":true}
		if display>0:actor.field_art="unova_pokemon_%d"%display
		else:actor.field_art="unova_item_ball"
		result.append(actor)
	for row in book():
		if row.era!=era or row.zone!=zone or not active(row,flags):continue
		var at: Array=local_cell(m,int(row.pos[0]),int(row.pos[1])) if row.has("pos") else anchors.get(row.get("anchor","side1"),[])
		var actor: Dictionary={}
		if row.has("pos"):
			for i in range(result.size()-1,-1,-1):
				var existing: Dictionary=result[i]
				if same_cell(existing.get("at",[]),at) and not existing.has("unova_actor") and not existing.has("unova_side") and not existing.has("unova_trainer"):
					actor=result.pop_at(i)
					break
		var used: Dictionary={}
		for npc in result:
			if npc.get("at",[]).size()==2:used[Vector2i(int(npc.at[0]),int(npc.at[1]))]=true
		for warp in m.get("warps",[]):
			var p: Array=warp.get("at",[])
			if p.size()==2:used[Vector2i(int(p[0]),int(p[1]))]=true
		used[Vector2i(int(m.spawn[0]),int(m.spawn[1]))]=true
		at=load("res://core/unova_campaign.gd")._near(m,at,used)
		if at.is_empty():
			at=load("res://core/unova_campaign.gd")._near(m,anchors.get("side1",[]),used)
		if at.is_empty():continue
		actor.merge({"role":"unova_side_"+str(row.id),"unova_side":row.id,"at":at,"name":row.name,"unova_actor":row.name,"facing":"down","lines":[row.name]},true)
		if row.type=="encounter" or row.type=="weekday":
			actor.erase("unova_gfx")
			actor.erase("unova_model")
			actor.field_art="unova_pokemon_%d"%int(row.species)
		if row.has("field_art"):
			actor.erase("unova_gfx")
			actor.field_art=row.field_art
		if row.has("unova_cast"):actor.unova_actor=row.unova_cast
		result.append(actor)
	return result

static func same_cell(a: Array,b: Array) -> bool:
	return a.size()==2 and b.size()==2 and int(a[0])==int(b[0]) and int(a[1])==int(b[1])

static func mark(g,flag: String) -> void:
	g._flags()[flag]=true
	g.world.refresh_story_actors(g._flags())
	g._persist()

static func has_mon(g,id: int) -> bool:
	return g.save_data.party.any(func(m):return m is Dictionary and int(m.get("species_id",0))==id)

static func gift_mon(g,species: int,level: int) -> Dictionary:
	var mon:=Party.make(species,level,Field.moves_for(species,level,g._flags()))
	g._store_mon(mon)
	return mon

static func fight_wild(g,species: int,level: int,flag: String,after:=Callable(),shiny:="") -> void:
	if not g._has_party():g._dialog(["先和你的初始伙伴一起来吧。"]);return
	g._start_wild_battle(species,level,"",func(outcome):
		if outcome=="caught":
			mark(g,flag)
			if after.is_valid():after.call()
		elif outcome=="b" and g._party_fainted():g._blackout(),shiny)

static func talk(g,npc: Dictionary) -> bool:
	if npc.get("grotto_resident",false):
		open_grotto(g,int(g.save_data.get("unova_grotto_visit",{}).get("index",-1)))
		return true
	var id:=str(npc.get("unova_side",""))
	if id=="":return false
	for row in book():
		if row.id==id and row.era==Field.era(g._flags()) and active(row,g._flags()):
			interact(g,row)
			return true
	return false

static func interact(g,row: Dictionary) -> void:
	var flag:="us_"+str(row.id)
	match str(row.type):
		"gift":
			if g._flags().get(flag,false):g._dialog([row.get("after","它派上用场了吗？")],row.name);return
			give(g,row.key,int(row.get("count",1)))
			mark(g,flag)
			g._dialog([row.line,"得到了%s。"%item_name(row.key)],row.name)
		"encounter":
			if not preload("res://core/unova_side_quests.gd").legendaries_ready(g,row):return
			if row.has("item") and g._bag_count(item_name(row.item))<=0:
				g._dialog([row.get("missing","好像还缺少什么东西。")]);return
			if g._flags().get(flag,false):g._dialog(["这里恢复了平静。"]);return
			g._pick(row.line,["靠近","暂时离开"],func(i):
				if i!=0:return
				if int(row.species)==638 and row.era=="bw":mark(g,"us_bw_swords")
				var consumed: String={644:"DARK_STONE",488:"LUNAR_WING",485:"MAGMA_STONE"}.get(int(row.species),"") if row.era=="b2" else ""
				fight_wild(g,int(row.species),int(row.level),flag,func():
					if consumed!="" and g._bag_count(item_name(consumed))>0:g._consume_item(item_name(consumed));g._persist(),str(row.get("shiny",""))))
		"choice_gift":
			if g._flags().get(flag,false):g._dialog([row.after],row.name);return
			var names: Array=row.options.map(func(k):return item_name(k))
			names.append("再想想")
			g._pick(row.line,names,func(i):
				if i<row.options.size():
					give(g,row.options[i])
					mark(g,flag)
					g._dialog(["收下了%s。"%item_name(row.options[i])],row.name))
		"fossil":revive_fossil(g,row.name)
		"rod":
			var local_flag:="u2_super_rod" if row.era=="b2" else "u1_super_rod"
			if not g._flags().get(local_flag,false):
				if g._bag_count("厉害钓竿")==0:g._give_item("厉害钓竿",1,"key")
				mark(g,local_flag)
			g._dialog(["这支厉害钓竿交给你。站在水边试试看吧。"],row.name)
		_:preload("res://core/unova_side_quests.gd").interact(g,row)

static func revive_fossil(g,who: String) -> void:
	var fossils:={"COVER_FOSSIL":564,"PLUME_FOSSIL":566,"DOME_FOSSIL":140,"HELIX_FOSSIL":138,"OLD_AMBER":142,"ROOT_FOSSIL":345,"CLAW_FOSSIL":347,"SKULL_FOSSIL":408,"ARMOR_FOSSIL":410}
	var keys:=fossils.keys().filter(func(k):return g._bag_count(item_name(k))>0)
	if keys.is_empty():g._dialog(["我可以从化石里复原古代宝可梦。找到化石就带到博物馆来吧。"],who);return
	var labels:=keys.map(func(k):return item_name(k))
	labels.append("取消")
	g._pick("交给研究员哪块化石？",labels,func(i):
		if i>=keys.size():return
		var key: String=keys[i]
		if g._bag_count(item_name(key))<=0:return
		g._consume_item(item_name(key))
		var mon:=gift_mon(g,int(fossils[key]),25)
		g._persist()
		g._dialog(["化石里的%s恢复了生命！"%mon.name],who))

static func use_item(g,name: String) -> bool:
	return preload("res://core/unova_side_quests.gd").use_item(g,name)

static func open_grotto(g,index: int) -> void:
	preload("res://core/unova_side_grotto.gd").open(g,index)

static func step(g) -> bool:
	return preload("res://core/unova_side_grotto.gd").step(g)
