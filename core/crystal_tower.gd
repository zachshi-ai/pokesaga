extends RefCounted
const LOBBY:="johto_battle_tower_1f"
const ROOM:="johto_battle_tower_battle_room"
const REWARDS:=["HP 增强剂","攻击增强剂","防御增强剂","速度增强剂","特攻增强剂"]
const BERRIES:={"MIRACLEBERRY":"lum","MINT_BERRY":"chesto","BERRY":"oran","GOLD_BERRY":"sitrus"}
static var table:Dictionary
static func data()->Dictionary:
	if table.is_empty():table=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/tower.json"))
	return table

static func roster(mid:String,rows:Array)->Array:
	if mid not in [LOBBY,ROOM]:return rows
	var out:=rows.duplicate(true)
	for npc in out:
		var pos:=Vector2i(int(npc.at[0]),int(npc.at[1]))
		if (mid==LOBBY and pos==Vector2i(3,3)) or (mid==ROOM and pos==Vector2i(0,3)):
			npc.crystal_quest="tower"
			npc.name="对战塔接待员"
	return out

static func talk(g):
	if not g.save_data.get("js_tower",{}).is_empty():
		var streak:=int(g.save_data.js_tower.round)
		g._pick("已胜%d场　接下来是第%d场"%[streak,streak+1],["继续挑战","结束挑战"],func(i):
			if i==0:fight(g)
			elif i==1:finish(g,false))
		return
	var levels: Array=[]
	for i in range(10,101,10):levels.append("Lv.%d 组"%i)
	g._pick("对战塔　选等级组，派三只不同伙伴连赢七场",levels,func(i):
		if i>=0 and i<levels.size():choose(g,(i+1)*10,[]))

static func eligible(p:Dictionary,selected:Array,limit:int)->bool:
	if p.is_empty() or p.get("is_egg",false) or int(p.level)>limit:return false
	if limit<70 and int(p.species_id) in [150,151,249,250,251]:return false
	var item:=str(p.get("held",""))
	if item=="":item=str(p.get("berry",""))
	for partner in selected:
		if int(partner.species_id)==int(p.species_id):return false
		if item!="" and item in [str(partner.get("held","")),str(partner.get("berry",""))]:return false
	return true

static func choose(g,level:int,selected:Array):
	if selected.size()==3:
		var team:Array=[]
		for p in selected:
			var healed:Dictionary=p.duplicate(true)
			healed.hp=healed.max_hp
			healed.status=""
			var pp:Array=[]
			for move in healed.moves:pp.append(int(g.get_node("/root/Data").move_of(int(move)).get("pp",10)))
			healed.pp=pp
			team.append(healed)
		g.save_data.js_tower={"round":0,"level":level,"party":team,"trainers":[],"opponent":[]}
		to_room(g,ROOM)
		fight(g)
		return
	var slots:Array=[]
	var labels:Array=[]
	for p in g.save_data.party:
		if p is Dictionary and eligible(p,selected,level):
			slots.append(p);labels.append("%s　Lv.%d"%[p.name,p.level])
	if slots.is_empty():
		g._dialog(["这一组需要三种不同宝可梦，等级不超过%d，携带物不能相同。"%level],"对战塔接待员")
		return
	g._pick("选择第%d位伙伴（Lv.%d组）"%[selected.size()+1,level],labels,func(i):
		if i>=0 and i<slots.size():choose(g,level,selected+[slots[i]]))

static func to_room(g,mid:String):
	var area:Dictionary=g.get_node("/root/Data").load_map("johto",mid)
	g._do_warp({"region":"johto","map":mid,"at":area.spawn,"hgss":true})
	g._persist()

static func opponent(g,run:Dictionary)->Array:
	var pool:Array=data().groups[str(run.level)].duplicate()
	var team:Array=[]
	var ids:=[]
	var items:=[]
	while team.size()<3 and not pool.is_empty():
		var row:Dictionary=pool.pop_at(g.rng.randi_range(0,pool.size()-1))
		if row.species in ids or (row.held!="NO_ITEM" and row.held in items):continue
		ids.append(row.species);items.append(row.held)
		team.append(row)
	return team

static func fixed_mon(mon:Dictionary,row:Dictionary):
	var stats:Array=row.stats
	mon.max_hp=int(stats[0]);mon.hp=mon.max_hp
	for i in 5:mon.stats[["atk","def","spe","spa","spd"][i]]=int(stats[i+1])
	mon.pp=row.pp.duplicate()
	if BERRIES.has(row.held):
		mon.berry=BERRIES[row.held];mon.held=""
	else:mon.held="" if row.held=="NO_ITEM" else ("BRIGHT_POWDER" if row.held=="BRIGHTPOWDER" else row.held)

static func fight(g):
	var run:Dictionary=g.save_data.js_tower
	if g.world.map_data.id!=ROOM:to_room(g,ROOM)
	if run.opponent.is_empty():
		var options:=range(data().trainers.size()).filter(func(i):return i not in run.trainers)
		run.trainers.append(options[g.rng.randi_range(0,options.size()-1)])
		run.opponent=opponent(g,run)
	g._persist()
	var name_text: String=data().trainers[int(run.trainers[-1])][1]
	var cfg:={"tower":true,"crystal_party":run.party,"team":run.opponent}
	g._start_battle({"name":"第%d战　%s"%[int(run.round)+1,name_text],"at":[0,0],"battle":cfg},func(result):
		if result!="a":finish(g,false);return
		run.round+=1
		run.opponent=[]
		if run.round>=7:finish(g,true)
		else:
			g._persist()
			g._pick("赢了第%d场。伙伴已恢复。"%run.round,["下一场","稍后继续"],func(i):
				if i==0:fight(g)))

static func finish(g,won:bool):
	var run:Dictionary=g.save_data.get("js_tower",{})
	if run.is_empty():return
	var count:=int(run.round)
	g._flags().js_tower_best=maxi(count,int(g._flags().get("js_tower_best",0)))
	g.save_data.erase("js_tower")
	to_room(g,LOBBY)
	if won:
		var prize:String=REWARDS[g.rng.randi_range(0,REWARDS.size()-1)]
		g._give_item(prize,5,"other");g._persist()
		g._dialog(["恭喜七连胜！获得了五份%s。"%prize],"对战塔接待员")
	else:g._dialog(["本轮结束，胜场数为%d。"%count],"对战塔接待员")
