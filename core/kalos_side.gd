extends RefCounted
## Optional field events in Kalos share the same inventory and party as every other region.
const Party := preload("res://core/party.gd")
const Dex := preload("res://core/dex_variants.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const Quest := preload("res://core/kalos_side_quests.gd")
const Maison := preload("res://core/kalos_side_maison.gd")
const Nursery := preload("res://core/kalos_side_nursery.gd")
static var archive: Dictionary
static var by_map: Dictionary
static var by_id: Dictionary

static func data() -> Dictionary:
	if archive.is_empty():
		archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_side.json"))
		for row in archive.events:
			by_map.get_or_add(str(row.map),[]).append(row)
			by_id[str(row.id)]=row
	return archive

static func stone_name(key: String) -> String:
	return str(data().stones.get(key,""))

static func give_stone(g,key: String) -> void:
	var label:=stone_name(key)
	if label!="":g._give_bag_item(label,"held",key)

static func version(flags: Dictionary) -> String:
	return str(flags.get("k_version","x")).to_lower()

static func eligible(row: Dictionary,flags: Dictionary,hour: int=-1) -> bool:
	for f in row.requires:
		if not flags.get(f,false):return false
	for f in row.until:
		if flags.get(f,false):return false
	if row.get("version","")!="" and row.version!=version(flags):return false
	if row.action=="dusk":
		return (int(Time.get_time_dict_from_system().hour) if hour<0 else hour)==20
	return true

static func roster_mon(g,id: int,level: int) -> Dictionary:
	return Party.make(id,level,preload("res://core/kalos_field.gd").moves_for(id,level))

static func mark(g,key: String) -> void:
	g._flags()[key]=true
	g.world.refresh_story_actors(g._flags())
	g._persist()

static func save_event(g,row: Dictionary) -> void:
	mark(g,"ks_"+str(row.id))

static func kanto_gift(g,done: Callable) -> void:
	if g._flags().get("ks_kanto_gift",false):
		done.call()
		return
	var options:=["妙蛙种子","小火龙","杰尼龟"]
	g._pick("布拉塔诺博士 · 想和谁一起旅行？",options,func(i):
		if i<0 or i>=3:return
		if not g._flags().get("ks_kanto_gift",false):
			var id:=int([1,4,7][i])
			var key:=str(["VENUSAURITE","CHARIZARDITE_"+version(g._flags()).to_upper(),"BLASTOISINITE"][i])
			g._store_mon(roster_mon(g,id,10))
			give_stone(g,key)
			g._flags().ks_kanto_species=id
			mark(g,"ks_kanto_gift")
			g._show_toast("收下了%s和%s。"%[options[i],stone_name(key)])
		done.call(),func():preload("res://core/hoenn_campaign.gd").abort_event(g))

static func decorate(m: Dictionary,flags: Dictionary,npcs: Array) -> Array:
	if not str(m.get("id","")).begins_with("kalos_"):return npcs
	data()
	var result:=npcs.duplicate()
	var anchors: Dictionary=m.get("kalos_anchors",{})
	var occupied: Array=[]
	for n in result:occupied.append(n.get("at",[]))
	for row in by_map.get(str(m.id),[]):
		if not eligible(row,flags):continue
		var at: Array=anchors.get(str(row.anchor),[])
		if at.is_empty():continue
		if occupied.has(at):
			for i in range(12,0,-1):
				var candidate: Array=anchors.get("side%d"%i,[])
				if not candidate.is_empty() and not occupied.has(candidate):
					at=candidate
					break
		if occupied.has(at):continue
		occupied.append(at)
		var actor:={"at":at,"name":row.name,"role":"kalos_side_"+str(row.id),"kalos_side":row.id,"gfx":row.gfx,"facing":"down"}
		if (str(row.gfx).begins_with("kalos_") or str(row.gfx).begins_with("fr_")) and ResourceLoader.exists("res://assets/npc/%s.png"%row.gfx):actor.field_art=row.gfx
		var cast: Dictionary=data().get("cast",{})
		if cast.has(row.name):actor.field_art=cast[row.name]
		if row.action=="wild_berry":actor.unova_prop="berry_tree"
		if row.id=="bird":
			var id:=Quest.bird_id(flags)
			actor.field_art={144:"fr_side_articuno",145:"fr_side_zapdos",146:"fr_side_moltres"}[id]
			actor.name={144:"急冻鸟",145:"闪电鸟",146:"火焰鸟"}[id]
		result.append(actor)
	return result

static func map_objects(m: Dictionary) -> Array:
	var originals: Array=m.get("objects",[])
	if m.get("id","")!="kalos_8":return originals
	var all:=originals.duplicate()
	for i in 3:
		var at: Array=m.get("kalos_anchors",{}).get(["side10","side11","side12"][i],[])
		if at.size()==2:all.append({"kind":"hidden" if i>0 else "item","at":at,"flag":"ks_heart_scale_%d"%i,"kalos_item":["心之鳞片","other"],"requires_moves":["SURF"] if i==2 else []})
	return all

static func object_action(_g,_o: Dictionary) -> bool:
	return false

static func talk(g,npc: Dictionary) -> bool:
	var id:=str(npc.get("kalos_side",""))
	if id=="":return false
	data()
	var row: Dictionary=by_id.get(id,{})
	if row.is_empty() or not eligible(row,g._flags()):return true
	match str(row.action):
		"recall","delete":preload("res://core/kalos_side_machines.gd").reminder(g,row.action=="delete")
		"skater":preload("res://core/kalos_side_city.gd").learn(g,row)
		"galette":preload("res://core/kalos_side_city.gd").galette(g)
		"boutique":preload("res://core/kalos_side_city.gd").boutique(g,row.couture)
		"coupon":
			g._give_item("折价券",1,"other")
			save_event(g,row)
			g._dialog(["这是当年配信的折价券。在服装店结账时使用，就能以半价买下选中的商品。"],row.name)
		"inver":preload("res://core/kalos_side_city.gd").inverse(g)
		"maison":Maison.open(g)
		"bp":Maison.exchange(g)
		"chateau":Maison.chateau(g)
		"daycare":Nursery.open(g)
		"safari":preload("res://core/kalos_side_explore.gd").safari(g)
		"orchard","plot","compost","wild_berry":preload("res://core/kalos_side_orchard.gd").interact(g,row)
		_:Quest.interact(g,row)
	return true

static func use_item(g,name: String) -> bool:
	if str(g.world.map_data.get("region",""))!="kalos":return false
	return Quest.use_item(g,name)

static func step(g) -> bool:
	if Nursery.step(g) or preload("res://core/kalos_side_explore.gd").step(g):return true
	return Quest.roam(g)
