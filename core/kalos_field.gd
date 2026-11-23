extends RefCounted

const Encounter := preload("res://core/encounter.gd")
const HM := ["CUT","FLY","SURF","STRENGTH","WATERFALL"]
const BADGES := [1,4,3,2,8]
const RODS := {"破旧钓竿":"old_rod","好钓竿":"good_rod","厉害钓竿":"super_rod"}
const TOWNS := {"kalos_vaniville":"朝香镇","kalos_aquacorde":"名水镇","kalos_santalune":"白檀市","kalos_lumiose":"密阿雷市","kalos_camphrier":"古木镇","kalos_ambrette":"古香镇","kalos_cyllage":"遥香市","kalos_geosenge":"石香镇","kalos_shalour":"娑罗市","kalos_coumarine":"比翼市","kalos_laverre":"香薰市","kalos_dendemille":"风絮镇","kalos_anistar":"百刻市","kalos_couriway":"连理镇","kalos_snowbelle":"映雪市","kalos_kiloude":"奇楠市","kalos_league":"宝可梦联盟"}
static var tables: Dictionary

static func data() -> Dictionary:
	if tables.is_empty():
		tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_field.json"))
	return tables

static func learnset(species: int) -> Array:
	return data().levels.get(str(species),[])

static func moves_for(species: int, level: int) -> Array:
	return Encounter.moves_for(species,level,learnset(species))

static func allowed(g, key: String) -> bool:
	var index:=HM.find(key)
	if index<0: return key=="ROCK_SMASH" and g._party_has_move(key)
	var flags: Dictionary=g._flags()
	return flags.get("k_hm_%d"%(index+1),false) and flags.get("k_badge_%d"%BADGES[index],false) and g._party_has_move(key)

static func machine_name(g, number: int, hidden: bool) -> String:
	var move:=int(data().machines.get(str(number+100 if hidden else number),0))
	if move==0:return ""
	return "卡洛斯%s%02d・%s"%["秘传学习器" if hidden else "招式学习器",number,g.get_node("/root/Data").move_of(move).name]

static func give_machine(g, number: int, hidden: bool) -> void:
	var name:=machine_name(g,number,hidden)
	if name.is_empty():return
	if hidden:g._flags()["k_hm_%d"%number]=true
	if g._bag_count(name)==0:g._give_item(name,1,"tm")
	g._persist()

static func teach(g, number: int, hidden: bool) -> void:
	var name:=machine_name(g,number,hidden)
	if name.is_empty() or g._bag_count(name)==0:return
	var move:=int(data().machines[str(number+100 if hidden else number)])
	var names: Array=[]
	var slots: Array=[]
	for i in g.save_data.party.size():
		var mon: Dictionary=g.save_data.party[i]
		var species:=int(mon.get("species_id",0))
		var matches: Array=data().compatible.get(str(species),[])
		if species<=0 or not (matches.has(float(move)) or (species>721 and g._can_learn_move(species,move))):continue
		names.append(mon.name)
		slots.append(i)
	if names.is_empty():g._dialog(["同行的伙伴都学不会这个招式。"],name)
	else:g._pick(name,names,func(i):g._tm_teach_one(move,int(slots[i]),str(g.get_node("/root/Data").move_of(move).name),true))

static func use(g, name: String) -> bool:
	for hidden in [true,false]:
		var prefix:="卡洛斯秘传学习器" if hidden else "卡洛斯招式学习器"
		if name.begins_with(prefix):
			teach(g,int(name.trim_prefix(prefix).get_slice("・",0)),hidden)
			return true
	return false

static func hm_menu(g) -> void:
	var labels: Array=[]
	var ids: Array=[]
	for i in HM.size():
		if g._flags().get("k_hm_%d"%(i+1),false):
			ids.append(i+1)
			labels.append(machine_name(g,i+1,true))
	if ids.is_empty():
		g._dialog(["还没有在卡洛斯取得秘传学习器。"])
		return
	g._pick("卡洛斯秘传学习器",labels,func(i):
		var n:=int(ids[i])
		if n==2 and allowed(g,"FLY"):
			g._pick("飞翔",["使用飞翔","教给队员"],func(choice):
				if choice==0:fly(g)
				else:teach(g,n,true))
		else:teach(g,n,true))

static func fly(g) -> void:
	if not allowed(g,"FLY") or not g.world.map_data.get("allow_fly",TOWNS.has(g.world.map_data.id)):
		g._dialog(["要在户外起飞，并持有比翼市的植物徽章、飞翔学习器和会飞翔的伙伴。"])
		return
	var towns:=TOWNS.keys().filter(func(mid):return g._flags().get("k_visited_"+mid,false))
	if towns.is_empty():return
	g._pick("要飞到哪里？",towns.map(func(mid):return TOWNS[mid]),func(i):
		var dest: Dictionary=g.get_node("/root/Data").load_map("kalos",towns[i])
		g._do_warp({"region":"kalos","map":towns[i],"at":dest.spawn,"facing":"down"})
		g._persist())

static func habitat(map: Dictionary, flags: Dictionary, method: String) -> Array:
	var zone:=str(map.get("kalos_zone","")).trim_suffix(".0")
	var table: Dictionary=data().wild.get(zone,{}).get(flags.get("k_version","x"),{})
	var pool: Array=[]
	for slot in table.get(method,[]):
		var id:=int(slot[0])
		var form:=preload("res://core/kalos_forms.gd").key(id,int(slot[1]))
		pool.append({"species":id,"form":form,"min":slot[2],"max":slot[3],"weight":slot[4]})
	return pool

static func terrain(map: Dictionary,at: Vector2i,water: bool) -> String:
	if water:return "surf"
	var layers: Dictionary=map.get("physics",{})
	for kind in ["yellow_flowers","purple_flowers","red_flowers","rough_terrain"]:
		var rows: Array=layers.get(kind,[])
		if at.y>=0 and at.y<rows.size() and at.x>=0 and at.x<rows[at.y].size() and int(rows[at.y][at.x])!=0:return kind
	var zone:=str(map.get("kalos_zone","")).trim_suffix(".0")
	var methods: Dictionary=data().wild.get(zone,{}).get("x",{})
	if methods.has("grass"):return "grass"
	for family in ["rough_terrain","yellow_flowers","purple_flowers","red_flowers","ambush_shadow","ambush_dust"]:
		if methods.has(family):return family
	return "grass"
