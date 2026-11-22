extends RefCounted
const Campaign := preload("res://core/hoenn_campaign.gd")
const GYMS := ["ROXANNE","BRAWLY","WATTSON","FLANNERY","NORMAN","WINONA","TATE_AND_LIZA","JUAN"]
const LEADERS := ["杜鹃","藤树","铁旋","亚莎","千里","娜琪","枫和南","亚当"]

static func contacts() -> Dictionary:return Campaign.data().rematches

static func enrolled(flags: Dictionary,key: String) -> bool:
	var contact: String=contacts()[key].contact
	var badge:=GYMS.find(contact)
	if badge>=0:return bool(flags.get("h_badge_"+str(badge+1),false))
	if contact=="WALLY_VR":return bool(flags.get("h_wally_road",false))
	return flags.get("h_trainer_"+key,false)

static func name_for(key: String) -> String:
	var c: String=contacts()[key].contact
	var i:=GYMS.find(c)
	return LEADERS[i] if i>=0 else ("满充" if c=="WALLY_VR" else c.capitalize())

static func after_steps(g) -> void:
	if not g.world.map_data.has("emerald_original") or not g._flags().get("h_badge_5",false):return
	var f: Dictionary=g._flags()
	f.h_rematch_steps=mini(255,int(f.get("h_rematch_steps",0))+1)

static func arrive(g) -> void:
	var f: Dictionary=g._flags()
	if not g.world.map_data.has("emerald_original") or int(f.get("h_rematch_steps",0))<255:return
	var waiting: Dictionary=f.get_or_add("h_rematches_ready",{})
	for key in contacts():
		var row: Dictionary=contacts()[key]
		if row.contact in GYMS or row.map!=g.world.map_data.source_id or not enrolled(f,key):continue
		if waiting.get(key,false) or g.rng.randi_range(0,99)<=30:
			waiting[key]=true
			f.h_rematch_steps=0

static func after_battle(g,wild: bool) -> void:
	if not g.world.map_data.has("emerald_original") or not g._flags().get("h_champion",false):return
	var f: Dictionary=g._flags()
	var key:="h_match_wild" if wild else "h_match_trainer"
	f[key]=int(f.get(key,0))+1
	if int(f[key])%(60 if wild else 20)!=0 or g.rng.randi_range(0,99)>30:return
	var ready: Dictionary=f.get_or_add("h_rematches_ready",{})
	var fought: Dictionary=f.get("h_rematch_wins",{})
	var candidates: Array=[]
	var lowest:=5
	for who in GYMS:
		if who=="WATTSON" and not f.get("h_generator_reward",false):continue
		var id: String="TRAINER_"+who+"_1"
		if ready.get(id,false):continue
		var wins:=mini(3,int(fought.get(id,0)))
		if not f.get("h_generator_reward",false) and wins>=1:continue
		if wins<lowest:
			candidates.clear()
			lowest=wins
		if wins==lowest:candidates.append(id)
	if not candidates.is_empty():ready[candidates[g.rng.randi_range(0,candidates.size()-1)]]=true

static func talk(g,npc: Dictionary) -> bool:
	var key:=str(npc.get("rematch_trainer",npc.get("source_trainer","")))
	if str(npc.get("source_script","")).contains("WallyRematch"):key="TRAINER_WALLY_VR_2"
	if not g._flags().get("h_rematches_ready",{}).get(key,false) or not contacts().has(key):return false
	var row: Dictionary=contacts()[key]
	var idx:=mini(3,int(g._flags().get("h_rematch_wins",{}).get(key,0)))
	var team: Array=Campaign.data().teams[row.teams[idx]]
	var who:=name_for(key)
	var dual: bool=row.contact in GYMS or "_AND_" in str(row.contact)
	if dual and g.save_data.party.filter(func(m):return not m.is_empty() and int(m.get("hp",0))>0).size()<2:
		g._dialog(["这次是双打，带两只可以战斗的伙伴再来找我。"],who);return true
	g._pick("%s 想和你再比一场。"%who,["接受再战","下次再来"],func(i):
		if i!=0:return
		g._start_battle({"name":who,"battle":{"team":team,"double":dual}},func(result):
			if result=="a":
				g._flags().h_rematches_ready.erase(key)
				var wins: Dictionary=g._flags().get_or_add("h_rematch_wins",{})
				wins[key]=int(wins.get(key,0))+1
				g._persist()))
	return true

static func menu(g) -> void:
	g._pick("宝可导航",["地区地图","对战寻呼"],func(i):
		if i==0:g._open_world_atlas(false);return
		var list: Array=contacts().keys().filter(func(key):return enrolled(g._flags(),key))
		if list.is_empty():g._dialog(["和能登记的训练家交手后，他们就会出现在寻呼簿里。"]);return
		var ready: Dictionary=g._flags().get("h_rematches_ready",{})
		list.sort_custom(func(a,b):return bool(ready.get(a,false)) and not bool(ready.get(b,false)))
		g._pick("对战寻呼 · 已登记 %d 人"%list.size(),list.map(func(k):return ("⚔　" if ready.get(k,false) else "")+name_for(k)),func(j):
			var row: Dictionary=contacts()[list[j]]
			var id:=str(row.map).trim_prefix("MAP_")
			var places: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/index.json"))
			var map_id: String=places.get(row.map,"")
			var place: String=g.get_node("/root/Data").load_map("hoenn",map_id).get("name","") if map_id!="" else ""
			if place=="":place=id.replace("ROUTE","").replace("_"," ").capitalize()+("号道路" if id.begins_with("ROUTE") else "")
			g._dialog(["我在%s。%s"%[place,"来吧，这次我已经组好了队伍！" if ready.get(list[j],false) else "等伙伴准备好了，再来比一场吧。"]],name_for(list[j]))))
