extends RefCounted
const Field=preload("res://core/alola_field.gd")
static var catalog:Dictionary
static var teams:Dictionary
static var ground:Dictionary
static var berries:Dictionary

static func data() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_routes.json"))
	return catalog

static func roster(map:Dictionary,flags:Dictionary,residents:Array) -> Array:
	var rows:=residents.duplicate()
	if map.get("alola_center",false):
		for service in [["nurse","护士","nurse","heal"],["mart","店员","clerk","shop"]]:
			rows.append({"at":map.alola_anchors[service[0]],"name":service[1],"gfx":service[2],"facing":"down",service[3]:true,"alola_shop":service[0]=="mart"})
	if not flags.get("a_starter",0):return rows
	if teams.is_empty():teams=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_trainers.json"))
	var v:String=flags.get("a_version","sun")
	for spot in map.get("alola_trainer_tiles",[]):
		var npc:Dictionary=data().trainers.get(str(int(spot.id)),{})
		var id:=str(int(npc.get("versions",{}).get(v,0)))
		if id=="0" or rows.any(func(n):return n.at==spot.at):continue
		var party:Array=teams[v].get(id,teams["ultra_sun" if v.begins_with("ultra") else "sun"].get(id,[]))
		if party.is_empty():continue
		var label:=str(npc["class"])+" "+str(npc.name)
		var flag:="a_trainer_"+id
		rows.append({"at":spot.at,"name":label,"alola_trainer":flag,"gfx":"lass" if npc["class"] in ["迷你裙","比基尼姐姐","香氛姐姐"] else "youngster","facing":"down","defeated":flags.get(flag,false),"battle":{"name":label,"team":party},"post":["今天的对战很精彩。"],"lines":["来一场对战吧！"]})
	return rows

static func objects(map:Dictionary) -> Array:
	var result:Array=[]
	if map.get("alola_center",false):result.append({"kind":"pc","name":"电脑","at":map.alola_anchors.pc})
	for spot in map.get("alola_item_tiles",[]):
		var item:Dictionary=data().items.get(str(int(spot.zone)),{}).get(str(int(spot.item)),{})
		if item.is_empty() or str(item.key).begins_with("TM"):continue
		result.append({"kind":"hidden" if spot.kind=="hidden" else "item","at":spot.at,"name":item.name,"alola_pickup":item,"flag":"a_pick_%s_%s_%s"%[int(spot.zone),int(spot.at[0]),int(spot.at[1])]})
	return result

static func pick(g,obj:Dictionary) -> bool:
	if not obj.has("alola_pickup"):return false
	var item:Dictionary=obj.alola_pickup
	if item.note!="" and not g._flags().get("a_nanu",false):
		g._show_toast("乌拉乌拉岛的大考验后再来看看。")
		return true
	var name:=str(item.name)
	var key:=str(item.key)
	var db=g.get_node("/root/Data")
	if key.begins_with("TM") and key.substr(2).is_valid_int():
		var number:=int(key.substr(2))
		Field.give_machine(g,number)
		g._flags()["a_machine_"+str(number)]=true
		name=Field.machine_name(g,number)
	elif key.ends_with("_BERRY") and db.berries.has(key.trim_suffix("_BERRY").to_lower()):
		for count in int(item.qty):g._give_bag_item(name,"berry","",key.trim_suffix("_BERRY").to_lower())
	elif db.held_items.has(key):
		for count in int(item.qty):g._give_bag_item(name,"held",key)
	elif db.evo_item_key(key)!="":g._give_item(db.evo_item_name(key),int(item.qty),"evo")
	elif key.ends_with("_BALL"):g._give_item(name,int(item.qty),"ball")
	else:g._give_item(name,int(item.qty),"heal" if int(item.get("medicine",0)) else "other")
	g.world.mark_taken(obj)
	g._persist()
	g._show_toast("找到了"+name+"！")
	return true

static func goods(g) -> Array:
	var flags:Dictionary=g._flags()
	var stock=[["精灵球",200,"ball"],["伤药",200,"heal"],["解毒药",200,"heal"],["解麻药",300,"heal"],["解眠药",100,"heal"]]
	if flags.get("a_hala",false):stock.append_array([["超级球",600,"ball"],["好伤药",700,"heal"],["离洞绳",1000,"other"],["除虫喷雾",400,"other"]])
	if flags.get("a_olivia",false):stock.append_array([["高级球",800,"ball"],["厉害伤药",1500,"heal"],["活力碎片",2000,"heal"]])
	if flags.get("a_nanu",false):stock.append_array([["全满药",2500,"heal"],["万灵药",400,"heal"]])
	return stock.map(func(row):return {"name":row[0],"price":row[1],"category":row[2]})


static func edition_objects(map:Dictionary,flags:Dictionary,base:Array) -> Array:
	var result:=base
	if Field.group(flags)=="18":
		if ground.is_empty():ground=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_ground.json"))
		var edits:Dictionary=ground.get(map.id,{})
		if not edits.is_empty():
			result=base.filter(func(o):return o.get("flag","") not in edits.omit)
			result.append_array(edits.add)
	if berries.is_empty():berries=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_berries.json"))
	result.append_array(berries.get(Field.group(flags),{}).get(map.id,[]))
	result.append_array(load("res://core/alola_machines.gd").field_objects(map,flags))
	return result


static func harvest(g,obj:Dictionary) -> void:
	var today:=Time.get_date_string_from_system()
	if g._flags().get(obj.pile_key,"")==today:
		g._dialog(["树下的果子已经拾净。明天再来看看。"])
		return
	var picks:Dictionary={}
	for i in g.rng.randi_range(3,5):
		var key:String=obj.alola_pile[g.rng.randi_range(0,obj.alola_pile.size()-1)]
		var name:String=g.get_node("/root/Data").berry_name(key)
		g._give_bag_item(name,"berry","",key)
		picks[name]=int(picks.get(name,0))+1
	g._flags()[obj.pile_key]=today
	g._persist()
	var labels=picks.keys().map(func(key):return "%s ×%d"%[key,picks[key]])
	g._dialog(["从树下拾到了"+"、".join(labels)+"。"])
