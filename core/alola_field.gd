extends RefCounted
const WILD_CLUB_SPECIES := [104,105]

const VERSIONS := ["sun","moon","ultra_sun","ultra_moon"]
const TITLES := ["《太阳》","《月亮》","《究极之日》","《究极之月》"]
const TOWNS := ["alola_iki","alola_hauoli","alola_heahea","alola_paniola","alola_konikoni","alola_malie","alola_tapu","alola_seafolk","alola_league"]
const RIDES := {"tauros":"肯泰罗冲撞","stoutland":"长毛狗搜寻","lapras":"拉普拉斯游泳","charizard":"喷火龙飞行","mudsdale":"重泥挽马奔驰","sharpedo":"巨牙鲨喷射","machamp":"怪力猛推"}
static var tables: Dictionary

static func data() -> Dictionary:
	if tables.is_empty():tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_field.json"))
	return tables

static func group(flags: Dictionary) -> String:
	return "18" if str(flags.get("a_version","sun")).begins_with("ultra") else "17"

static func hour(flags: Dictionary) -> int:
	var shift:=12 if flags.get("a_version","sun") in ["moon","ultra_moon"] else 0
	return (int(Time.get_time_dict_from_system().hour)+shift+(12 if flags.get("a_reverse_world",false) else 0))%24

static func learnset(species: int,flags: Dictionary,form := "") -> Array:
	var book:Dictionary=data().levels[group(flags)]
	return book.get(form,book.get(str(species),[]))

static func moves_for(species: int,level: int,flags: Dictionary,form := "") -> Array:
	return load("res://core/encounter.gd").moves_for(species,level,learnset(species,flags,form))

static func habitat(map: Dictionary,flags: Dictionary,method: String) -> Array:
	var location:String=map.get("alola_location","")
	var table:Dictionary=data().wild.get(flags.get("a_version","sun"),{})
	var night:=hour(flags)<6 or hour(flags)>=18
	var result: Array=[]
	for slot in table.get(location,{}).get(method,[]):
		# These are story-controlled encounters, even where the cartridge labels them as walking.
		if int(slot[0]) in range(785,807):continue
		if slot[5].any(func(id):return (int(id)==4 and night) or (int(id)==5 and not night)):continue
		result.append({"species":int(slot[0]),"form":slot[1],"min":int(slot[2]),"max":int(slot[3]),"weight":maxi(1,int(slot[4]))})
	return result

static func evolution(g,mon:Dictionary) -> Dictionary:
	if mon.is_empty() or mon.get("held","")=="EVERSTONE":return {}
	var sid:=int(mon.get("species_id",0))
	var level:=int(mon.get("level",1))
	var form:=str(mon.get("form",""))
	var local_hour:=hour(g._flags())
	var night:=local_hour<6 or local_hour>=18
	var sun:bool=g._flags().get("a_version","sun") in ["sun","ultra_sun"]
	if sid==19 and form=="RATTATA_ALOLA" and not night:return {}
	if sid==52 and form=="MEOWTH_ALOLA":
		return {"to":53,"form":"PERSIAN_ALOLA"} if int(mon.get("friendship",0))>=220 else {}
	if sid==104 and form=="":
		return {"to":105,"form":"MAROWAK_ALOLA"} if night and level>=28 else {}
	if sid==744 and level>=25:
		if form=="ROCKRUFF_OWN_TEMPO":
			return {"to":745,"form":"LYCANROC_DUSK"} if group(g._flags())=="18" and local_hour==17 else {}
		if sun and not night:return {"to":745,"form":""}
		if not sun and night:return {"to":745,"form":"LYCANROC_MIDNIGHT"}
		return {}
	if sid==790 and level>=53:return {"to":791 if sun else 792,"form":""}
	return load("res://core/growth.gd").evolution_of(mon)

static func machine_name(g,number:int) -> String:
	var id:=int(data().machines[group(g._flags())].get(str(number),0))
	if id<=0:return ""
	return "阿罗拉招式学习器%02d・%s"%[number,g.get_node("/root/Data").move_of(id).name]

static func give_machine(g,number: int) -> void:
	var name:=machine_name(g,number)
	if not name.is_empty() and g._bag_count(name)==0:g._give_item(name,1,"tm")

static func use(g,name:String) -> bool:
	if name=="骑行装置" and g.world.map_data.region=="alola":
		ride_menu(g)
		return true
	if not name.begins_with("阿罗拉招式学习器"):return false
	if g._bag_count(name)==0:return true
	var n:=int(name.trim_prefix("阿罗拉招式学习器").get_slice("・",0))
	var move:=int(data().machines[group(g._flags())].get(str(n),0))
	var book:Dictionary=data().compatible[group(g._flags())]
	var labels: Array=[]
	var slots: Array=[]
	for i in g.save_data.party.size():
		var mon:Dictionary=g.save_data.party[i]
		var matches:Array=book.get(str(mon.get("form","")),book.get(str(int(mon.get("species_id",0))),[]))
		if move>0 and matches.any(func(id):return int(id)==move):
			slots.append(i)
			labels.append(mon.name)
	if slots.is_empty():g._dialog(["同行的伙伴都学不会这个招式。"],name)
	else:g._pick(name,labels,func(i):g._tm_teach_one(move,slots[i],str(g.get_node("/root/Data").move_of(move).name),true))
	return true

static func allowed(flags:Dictionary,key:String) -> bool:
	var ride:String={"ROCK_SMASH":"tauros","FLY":"charizard","SURF":"lapras","STRENGTH":"machamp"}.get(key,"")
	return not ride.is_empty() and flags.get("a_ride_"+ride,false)

static func fly(g) -> void:
	var ids:Array=TOWNS.filter(func(mid):return g._flags().get("a_visited_"+mid,false))
	if not allowed(g._flags(),"FLY") or ids.is_empty():
		g._dialog(["需要先登记喷火龙，才能飞往已经到访的地方。"])
		return
	var d=g.get_node("/root/Data")
	g._pick("要飞到哪里？",ids.map(func(mid):return d.load_map("alola",mid).name),func(i):
		var dest:Dictionary=d.load_map("alola",ids[i])
		g._do_warp({"region":"alola","map":ids[i],"at":dest.spawn,"alola_native":true})
		g._persist())

static func ride_menu(g) -> void:
	var rides:=RIDES.keys().filter(func(id):return g._flags().get("a_ride_"+id,false))
	if rides.is_empty():
		g._dialog(["岛屿之王哈拉会帮你登记第一位坐骑伙伴。"])
		return
	g._pick("宝可骑行",rides.map(func(id):return RIDES[id]),func(i):
		var ride:String=rides[i]
		if ride=="charizard":
			fly(g)
			return
		g._flags().a_active_ride=ride
		match ride:
			"lapras","sharpedo":g._show_toast(g.world.toggle_surf())
			"tauros":g._show_toast("肯泰罗准备好了。对着碎岩按 A 冲撞。")
			"machamp":g._show_toast("怪力准备好了。站在巨石旁按 A 推动。")
			"stoutland":
				var best:=999
				var delta:=Vector2i.ZERO
				for obj in g.world.objects:
					if obj.get("kind","")!="hidden" or g.world.taken.get(g.world._object_key(obj),false):continue
					var step:Vector2i=Vector2i(int(obj.at[0]),int(obj.at[1]))-g.world.player_pos
					if absi(step.x)+absi(step.y)<best:
						best=absi(step.x)+absi(step.y)
						delta=step
				g._show_toast("这里没有闻到气味。" if best==999 else "脚下有气味！" if best==0 else "气味来自"+("东边" if delta.x>0 else "西边" if delta.x<0 else "南边" if delta.y>0 else "北边"))
			"mudsdale":g._show_toast("重泥挽马准备好了，可以穿过崎岖的岩路。")
		g._persist())
