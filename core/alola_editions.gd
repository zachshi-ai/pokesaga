extends RefCounted
## Keep each retelling's local events while carrying the same collection between them.
const Field=preload("res://core/alola_field.gd")
const Journey=preload("res://core/region_journey.gd")
const LOCAL_KEYS=["阿罗拉图鉴","Ｚ手环","Ｚ强力手环","洛托姆图鉴","诸岛巡礼之证","骑行装置","垂钓竿","太阳之笛","月亮之笛","虹色之花","谜之卡片","基格尔德多面体","银河队钥匙","奈克洛索尔合体器","奈克洛露奈合体器","阿罗拉的蛋"]
const LOCAL_STATE=["alola_roto","alola_tree","alola_scouts","alola_tree_best","alola_cave_exit"]

static func belongs(key:String) -> bool:
	for prefix in ["a_","as_","alola_","story_a_","story_as_","trainer_alola_","flash_alola_","berry:alola_","placed:alola_"]:
		if key.begins_with(prefix):return true
	return false

static func travel(current:Dictionary,to:String,mode:String) -> Dictionary:
	var from:=str(current.get("flags",{}).get("a_version",""))
	if from not in Field.VERSIONS or to not in Field.VERSIONS or from==to or current.get("map","")!="alola_home":return {}
	var save:=current.duplicate(true)
	var archive:Dictionary=save.get_or_add("alola_editions",{})
	var old:Dictionary={"choice":save.chapters.alola,"flags":{},"items":[],"state":{},"badges":save.regional_badges.alola}
	for k in save.flags.keys():
		if belongs(k):
			old.flags[k]=save.flags[k]
			save.flags.erase(k)
	for key in LOCAL_STATE:
		if save.has(key):old.state[key]=save[key];save.erase(key)
	if save.get("last_pokemon_center",{}).get("region","")=="alola":
		old.state.last_pokemon_center=save.last_pokemon_center
		save.erase("last_pokemon_center")
	for i in range(save.bag.size()-1,-1,-1):
		if save.bag[i].name in LOCAL_KEYS:
			old.items.push_front(save.bag[i])
			save.bag.remove_at(i)
	if save.get("hall_of_fame",{}).has("alola"):
		old.hall=save.hall_of_fame.alola
		save.hall_of_fame.erase("alola")
	var members:Array=save.party.duplicate()
	for box in save.get("boxes",[]):members.append_array(box.get("mons",[]))
	for mon in members:
		if mon is Dictionary and mon.get("alola_partner",false) and not mon.has("alola_origin"):mon.alola_origin=from
	archive[from]=old
	save.chapters.erase("alola")
	save.regional_badges.alola=[]
	if not archive.has(to):return Journey.begin(save,"alola",mode,to)
	var next:Dictionary=archive[to]
	save.chapters.alola=next.choice
	save.flags.merge(next.flags,true)
	save.bag.append_array(next.items)
	save.regional_badges.alola=next.badges
	if next.has("hall"):save.get_or_add("hall_of_fame",{}).alola=next.hall
	save.merge(next.state,true)
	save.map="alola_home";save.pos=Journey.HOMES.alola.at.duplicate();save.facing="down"
	for key in ["surfing","diving","bike"]:save[key]=false
	for key in ["location_label","field_elevation"]:save.erase(key)
	archive.erase(to)
	return save

static func menu(g) -> void:
	var current:=str(g._flags().get("a_version",""))
	var options:Array=Field.VERSIONS.filter(func(v):return v!=current)
	var labels:Array=[]
	for v in options:
		labels.append(Field.TITLES[Field.VERSIONS.find(v)]+("　继续巡礼" if g.save_data.get("alola_editions",{}).has(v) else "　开始巡礼"))
	labels.append("留在当前版本")
	g._pick("阿罗拉的其他版本",labels,func(i):
		if i>=options.size():return
		var target:String=options[i]
		var transfer:=func(mode:String):
			g.save_data.bag=g.bag_items
			var staged:=travel(g.save_data,target,mode)
			if staged.is_empty():g._dialog(["电脑空位不足。可以整理箱子或带队出发。"])
			else:g._load_chapter(staged)
		if g.save_data.get("alola_editions",{}).has(target):transfer.call("carried")
		else:g._pick("这次巡礼要带原来的队伍吗？",["带现有队伍出发","寄存队伍，重新组队"],func(n):transfer.call("carried" if n==0 else "boxed")))
