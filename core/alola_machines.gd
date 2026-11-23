extends RefCounted
const Field = preload("res://core/alola_field.gd")
static var catalog:Dictionary
const DANCER := ["alola_melemele_meadow","alola_royal","alola_ulaula_meadow","alola_poni_meadow"]

static func book(flags:Dictionary) -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_machines.json"))
	return catalog[Field.group(flags)]

static func area(row:Dictionary,mid:String) -> bool:
	return row.map==mid or row.map=="alola_lake_sunne" and mid=="alola_lake_moone"

static func available(row:Dictionary,flags:Dictionary) -> bool:
	return row.require=="" or flags.get(row.require,false)

static func field_objects(map:Dictionary,flags:Dictionary) -> Array:
	var result:Array=[]
	for number in book(flags):
		var row:Dictionary=book(flags)[number]
		if row.kind!="field" or not row.has("at") or not area(row,map.id):continue
		result.append({"kind":"item","at":row.at,"name":"招式学习器%02d"%int(number),"alola_machine":number,"flag":"a_machine_"+number})
	if map.id=="alola_hauoli_mall" and Field.group(flags)=="18" and flags.get("a_mall_cleanup",false) and not flags.get("a_machine_48",false):
		for i in 6:
			var at:Array=map.alola_anchors["side%d"%(i+1)]
			result.append({"kind":"item","name":"纸屑","at":at,"alola_litter":i,"flag":"a_mall_litter_"+str(i)})
	return result

static func roster(map:Dictionary,flags:Dictionary,residents:Array) -> Array:
	if not flags.get("a_starter",0):return residents
	var services:Dictionary={}
	for number in book(flags):
		var row:Dictionary=book(flags)[number]
		if Field.group(flags)=="18" and number=="75" and int(flags.get("a_dancer_wins",0))<3:continue
		if row.kind=="field" or not area(row,map.id) or not available(row,flags) or flags.get("a_machine_"+number,false):continue
		var owner:String=row.get("speaker","招式学习器店员" if row.kind=="shop" else "道路训练家" if row.get("route_challenge",false) else "当地居民")
		services.get_or_add(owner,[]).append(number)
	var wins:=int(flags.get("a_dancer_wins",0))
	if Field.group(flags)=="18" and wins<3 and map.id==DANCER[wins]:services["剧团演员"]=["dancer"]
	var result:=residents.duplicate()
	for owner in services:
		for key in map.get("alola_anchors",{}):
			if not key.begins_with("trainer"):continue
			var at:Array=map.alola_anchors[key]
			if result.any(func(r):return r.at==at):continue
			result.append({"name":owner,"at":at,"gfx":"clerk" if owner=="招式学习器店员" else "scientist" if owner=="库库伊博士" else "youngster","facing":"down","alola_machines":services[owner]})
			break
	return result

static func take(g,number:String) -> bool:
	var row:Dictionary=book(g._flags())[number]
	if not available(row,g._flags()):
		g._dialog(["还需要先取得这里的骑行资格或完成当地的考验。"])
		return false
	if row.get("night",false) and Field.hour(g._flags()) in range(6,18):
		g._dialog(["等入夜以后再来吧。"]);return false
	if row.get("next_day",false):
		var day:=int(Time.get_unix_time_from_system())/86400
		var last:=int(g._flags().get("a_plant_visit",-2))
		if last!=day-1:
			g._flags().a_plant_visit=day;g._persist();g._dialog(["明天再来发电厂找我吧。"]);return false
	if row.get("route_challenge",false):
		for trainer in g.world.npcs:
			if trainer.has("alola_trainer") and not g._flags().get(trainer.alola_trainer,false):
				g._dialog(["先与这里的道路训练家都对战一次，再来领招式学习器。"]);return false
	if number=="27" and Field.group(g._flags())=="18" and not g._flags().get("a_machine_21",false):
		g._dialog(["先去找店里的智挥猩吧。"]);return false
	if Field.group(g._flags())=="18":
		match number:
			"8":
				if g._bag_count(Field.machine_name(g,62))==0:
					g._dialog(["我的炽焰咆哮虎想学杂技。等你找到招式学习器62，再来帮它吧。"]);return false
				if not g._flags().get("a_royal_acrobatics",false):
					g._flags().a_royal_acrobatics=true;g._persist()
					g._dialog(["炽焰咆哮虎学会了杂技！怪力还想借一颗棱瓜果练习。"]);return false
				if g._bag_count("棱瓜果")==0:g._dialog(["我的怪力还在等棱瓜果。"]);return false
				g._consume_item("棱瓜果")
			"48":
				if not g._flags().get("a_mall_cleanup",false):
					g._flags().a_mall_cleanup=true;g._persist()
					for o in field_objects(g.world.map_data,g._flags()):
						if o.has("alola_litter"):g.world.objects.append(o)
					g.world._draw_objects()
					g._dialog(["可以帮我和臭泥收拾商场吗？把地上的六处纸屑捡起来。"]);return false
				for i in 6:
					if not g._flags().get("a_mall_litter_"+str(i),false):
						g._dialog(["商场里还有纸屑。找齐后再来吧。"]);return false
			"66","75":
				var needed:="a_tm_bewear" if number=="66" else "a_dancer_final"
				if not g._flags().get(needed,false):
					quest_battle(g,616 if number=="66" else 539,"黑带训练家" if number=="66" else "剧团演员",func():
						g._flags()[needed]=true
						take(g,number))
					return false
	var cost:=int(row.get("price",0))
	if row.kind=="shop":cost=int(cost*load("res://core/alola_side.gd").factor(g,"bargain"))
	if int(g.save_data.money)<cost:g._dialog(["钱还不够。"]);return false
	var name:=Field.machine_name(g,int(number))
	if g._bag_count(name)>0:
		g._dialog(["你已经拿过这个招式学习器。"]);return false
	g.save_data.money-=cost
	Field.give_machine(g,int(number))
	g._flags()["a_machine_"+number]=true
	g._persist()
	g.world.refresh_story_actors(g._flags())
	g._dialog(["获得了"+name+"！可以在背包里反复教给能学会的伙伴。"])
	return true

static func talk(g,npc:Dictionary) -> bool:
	if not npc.has("alola_machines"):return false
	var slots:Array=npc.alola_machines
	if slots==["dancer"]:
		var stage:=int(g._flags().get("a_dancer_wins",0))
		quest_battle(g,536+stage,"剧团演员",func():
			g._flags().a_dancer_wins=stage+1;g._persist()
			g.world.refresh_story_actors(g._flags());g._dialog(["下次来%s看看我的新舞步吧。"%g.get_node("/root/Data").load_map("alola",DANCER[stage+1]).name]))
		return true
	var options:Array=[]
	for number in slots:
		var row:Dictionary=book(g._flags())[number]
		var price:=int(row.get("price",0))
		if row.kind=="shop":price=int(price*load("res://core/alola_side.gd").factor(g,"bargain"))
		options.append(Field.machine_name(g,int(number))+("  ₽%d"%price if price else ""))
	options.append("返回")
	g._pick(str(npc.name),options,func(i):if i<slots.size():take(g,slots[i]))
	return true

static func quest_battle(g,id:int,who:String,won:Callable) -> void:
	if not g._has_party():g._dialog(["先带上能战斗的伙伴吧。"]);return
	var team:Array=load("res://core/alola_campaign.gd").trainer(id,g._flags())
	g._start_battle({"name":who,"battle":{"name":who,"team":team}},func(outcome):
		if outcome=="a":won.call()
		elif g._party_fainted():g._blackout())
