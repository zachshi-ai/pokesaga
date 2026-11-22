extends RefCounted
## The two generations of Unova zones use separate native encounter tables and machines.
const Encounter := preload("res://core/encounter.gd")
const HM_KEYS := ["CUT","FLY","SURF","STRENGTH","WATERFALL","DIVE"]
const TOWNS := {
	"unova_nuvema":"鹿子镇","unova_accumula":"唐草镇","unova_striaton":"三曜市",
	"unova_nacrene":"七宝市","unova_castelia":"飞云市","unova_nimbasa":"雷文市",
	"unova_driftveil":"帆巴市","unova_mistralton":"吹寄市","unova_icirrus":"雪花市",
	"unova_opelucid":"双龙市","unova_league":"宝可梦联盟","unova_aspertia":"桧扇市",
	"unova_floccesy":"算木镇","unova_virbank":"立涌市","unova_lentimas":"山路镇",
	"unova_lacunosa":"笼目镇","unova_undella":"涟漪镇","unova_humilau":"青海波市",
	"unova_black_city":"黑色市",
}
const LAND_WEIGHTS := [20,20,10,10,10,10,5,5,4,4,1,1]
const WATER_WEIGHTS := [60,30,5,4,1]
static var book: Dictionary
static var pools: Dictionary

static func data() -> Dictionary:
	if book.is_empty():
		book=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_field.json"))
	return book

static func era(flags: Dictionary) -> String:
	return "b2" if flags.get("u2_started",false) and not flags.get("u1_memory",false) else "bw"

static func flag_prefix(flags: Dictionary) -> String:
	return "u2_" if era(flags)=="b2" else "u1_"

static func partner(save: Dictionary, chapter: int) -> Dictionary:
	for mon in save.get("party",[]):
		if mon is Dictionary and int(mon.get("unova_partner",0))==chapter: return mon
	for box in save.get("boxes",[]):
		for mon in box.get("mons",[]):
			if int(mon.get("unova_partner",0))==chapter: return mon
	return {}

static func learnset(species: int, flags: Dictionary) -> Array:
	return data().training[era(flags)].levels.get(str(species),[])

static func moves_for(species: int, level: int, flags: Dictionary) -> Array:
	return Encounter.moves_for(species,level,learnset(species,flags))

static func season(month: int) -> int:
	return posmod(month-1,4)

static func habitat(map: Dictionary, flags: Dictionary, method: String, month: int) -> Dictionary:
	var period := era(flags)
	var original := str(map.get("unova_encounter","")).trim_suffix(".0")
	if period=="b2" and not original.begins_with("ENCOUNTERS_"): original="ENCOUNTERS_"+original.to_upper()
	var index:=season(month)
	var key: String="%s/%s/%s/%d"%[period,original,method,index]
	if pools.has(key): return pools[key]
	var seasons: Array=data().encounters[period].get(original,[])
	var result := {"rate":0.0,"pool":[]}
	if not seasons.is_empty():
		var table: Dictionary=seasons[0 if seasons.size()==1 else index]
		result.phenomenon_setting=int(table.get("phenomenon_setting",0))
		var entries: Array=table.get(method,[])
		if not entries.is_empty():
			result.rate=float(entries[0])/100.0
			var weights:=LAND_WEIGHTS if method in ["grass","dark_grass","shaking_grass"] else WATER_WEIGHTS
			for i in entries[1].size():
				var row: Array=entries[1][i]
				var id:=int(row[0])
				if id==0:continue
				var form:=""
				if id in [585,586] and index>0:
					form=("DEERLING_" if id==585 else "SAWSBUCK_")+["SPRING","SUMMER","AUTUMN","WINTER"][index]
				elif id==550 and int(row[3])==1: form="BASCULIN_BLUE_STRIPED"
				result.pool.append({"species":id,"min":row[1],"max":row[2],"weight":weights[i],"form":form})
	pools[key]=result
	return result

static func land_method(map: Dictionary, at: Vector2i, on_sea: bool) -> String:
	if on_sea: return "surf"
	var rows: Array=map.get("physics",{}).get("dark_grass",[])
	if at.y>=0 and at.y<rows.size() and at.x>=0 and at.x<len(rows[at.y]) and int(rows[at.y][at.x])!=0:
		return "dark_grass"
	return "grass"

static func can_fish(g, rod: String) -> bool:
	return rod=="厉害钓竿" and g._flags().get(flag_prefix(g._flags())+"super_rod",false)

static func machine_name(g, number: int, hidden: bool) -> String:
	var move:=int(data().training[era(g._flags())].machines.get(str(number+100 if hidden else number),0))
	if move==0:return ""
	return "合众%s%02d・%s"%["秘传学习器" if hidden else "招式学习器",number,g.get_node("/root/Data").move_of(move).name]

static func give_machine(g, number: int, hidden: bool) -> void:
	var name:=machine_name(g,number,hidden)
	if name.is_empty():return
	if hidden:g._flags()[flag_prefix(g._flags())+"hm_"+str(number)]=true
	if g._bag_count(name)==0:g._give_item(name,1,"tm")
	g._persist()

static func allowed(g, key: String) -> bool:
	var index:=HM_KEYS.find(key)
	return index>=0 and g._flags().get(flag_prefix(g._flags())+"hm_"+str(index+1),false) and g._party_has_move(key)

static func teach(g, number: int, hidden: bool) -> void:
	var name:=machine_name(g,number,hidden)
	if name.is_empty() or g._bag_count(name)==0:return
	var tables: Dictionary=data().training[era(g._flags())]
	var move:=int(tables.machines[str(number+100 if hidden else number)])
	var labels: Array=[]
	var slots: Array=[]
	for i in g.save_data.party.size():
		var mon: Dictionary=g.save_data.party[i]
		var id:=int(mon.get("species_id",0))
		if id==0:continue
		var matches: Array=tables.compatible.get(str(id),[])
		if not matches.any(func(v):return int(v)==move) and not (id>649 and g._can_learn_move(id,move)):continue
		slots.append(i)
		labels.append(str(mon.name))
	if slots.is_empty():g._dialog(["同行的伙伴都学不会这个招式。"],name)
	else:g._pick(name,labels,func(i):g._tm_teach_one(move,int(slots[i]),str(g.get_node("/root/Data").move_of(move).name),true))

const FEATHERS := {"体力之羽":"hp","肌力之羽":"atk","抵抗之羽":"def","智力之羽":"spa","精神之羽":"spd","瞬发之羽":"spe"}

static func use(g, name: String) -> bool:
	if FEATHERS.has(name):
		var candidates: Array=g.save_data.party.filter(func(mon):return not mon.is_empty() and int(mon.get("species_id",0))>0)
		if candidates.is_empty():g._dialog(["先带上一只宝可梦。"])
		else:g._pick("把%s给谁？"%name,candidates.map(func(mon):return mon.name),func(i):
			var mon: Dictionary=candidates[i]
			var stats: Dictionary=mon.get("effort",{})
			var stat: String=FEATHERS[name]
			var total:=0
			for value in stats.values():total+=int(value)
			if total>=510 or int(stats.get(stat,0))>=252:g._dialog(["这项基础点数已经无法再增加了。"]);return
			stats[stat]=int(stats.get(stat,0))+1
			mon.effort=stats
			preload("res://core/party.gd").recalc(mon,true)
			g._consume_item(name)
			g._persist()
			g._dialog(["%s的%s基础点数增加了。"%[mon.name,g.STAT_CN[stat]]]))
		return true
	for hidden in [true,false]:
		var prefix:="合众秘传学习器" if hidden else "合众招式学习器"
		if name.begins_with(prefix):
			teach(g,int(name.trim_prefix(prefix).get_slice("・",0)),hidden)
			return true
	return false

static func hm_menu(g) -> void:
	var labels: Array=[]
	var ids: Array=[]
	for i in HM_KEYS.size():
		if g._flags().get(flag_prefix(g._flags())+"hm_"+str(i+1),false):
			labels.append(machine_name(g,i+1,true))
			ids.append(i+1)
	if ids.is_empty():
		g._dialog(["这一段合众旅程还没有取得秘传学习器。"])
		return
	g._pick("合众秘传学习器",labels,func(i):
		var n:=int(ids[i])
		if n==2 and allowed(g,"FLY"):
			g._pick("飞翔",["使用飞翔","教给队员"],func(choice):
				if choice==0:g._open_fly()
				else:teach(g,n,true))
		else:teach(g,n,true))

static func fly(g) -> void:
	if not allowed(g,"FLY") or not g.world.map_data.get("allow_fly",TOWNS.has(g.world.map_data.id)):
		g._dialog(["需要在可起飞的户外，取得本段的飞翔学习器，并带上会飞翔的宝可梦。"])
		return
	var names: Array=[]
	var maps: Array=[]
	for mid in TOWNS:
		if g._flags().get(flag_prefix(g._flags())+"visited_"+str(mid),false):
			maps.append(mid)
			names.append(TOWNS[mid])
	if names.is_empty():return
	g._pick("要飞到哪里？",names,func(i):
		var map: Dictionary=g.get_node("/root/Data").load_map("unova",maps[i])
		g._do_warp({"region":"unova","map":maps[i],"at":map.spawn,"facing":"down","unova_native":true})
		g._persist())
