extends RefCounted
## Area residents and one-time finds in the four Alola adventures.
const Activities := preload("res://core/alola_side_activities.gd")
const Field := preload("res://core/alola_field.gd")
const Party := preload("res://core/party.gd")
static var by_map: Dictionary
static var by_id: Dictionary
static var spare_tiles: Dictionary

static func rows() -> Dictionary:
	if by_id.is_empty():
		var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_side.json"))
		for row in data.events:
			by_map.get_or_add(row.map,[]).append(row)
			by_id[row.id]=row
	return by_id

static func eligible(row: Dictionary, flags: Dictionary, at_hour: int=-1) -> bool:
	if not flags.get("a_started",false):return false
	var version: String=flags.get("a_version","sun")
	var group: String="usum" if version.begins_with("ultra") else "sm"
	if row.versions not in ["all",group,version]:return false
	for key in row.require:
		if not flags.get(key,false):return false
	for key in row.get("until",[]):
		if flags.get(key,false):return false
	if flags.get("as_"+str(row.get("group",row.id)),false) and not row.get("repeat",false):return false
	var phase: String=row.get("phase","")
	if not phase.is_empty():
		var h:=Field.hour(flags) if at_hour<0 else at_hour
		return (phase=="day")==(h>=6 and h<18)
	return true

static func roster(map: Dictionary,flags: Dictionary,npcs: Array=[]) -> Array:
	if map.get("region","")!="alola":return npcs
	rows()
	var result:=npcs.duplicate()
	var occupied: Array=[map.get("spawn",[])]
	for edge in map.get("warps",[]):occupied.append(edge.at)
	for object in map.get("objects",[]):occupied.append(object.at)
	for n in result:occupied.append(n.at)
	var anchors: Dictionary=map.get("alola_anchors",{})
	for row in by_map.get(str(map.id),[]):
		if not eligible(row,flags):continue
		var at: Array=[]
		for i in range(12):
			var key: String="side%d"%(1+(int(row.get("slot",1))-1+i)%12)
			var candidate: Array=anchors.get(key,[])
			if candidate.size()==2 and not occupied.has(candidate):
				at=candidate
				break
		if at.is_empty():
			for candidate in extra_tiles(map):
				if not occupied.has(candidate):
					at=candidate
					break
		if at.is_empty():continue
		occupied.append(at)
		var actor:={"at":at,"name":row.name,"alola_actor":row.name,"role":"alola_side_"+str(row.id),"alola_side":row.id,"gfx":row.get("gfx","expert_m"),"facing":"down"}
		if row.action=="collect":actor.unova_prop="alola_"+str(row.kind)
		elif row.has("field_species"):actor.unova_prop="alola_mon_"+str(int(row.field_species))
		elif row.id=="mimikyu":actor.unova_prop="alola_mon_778"
		elif row.action in ["wild","cosmog"]:actor.unova_prop="alola_mon_"+str(int(row.species))
		elif row.name=="Ｚ纯晶台":actor.unova_prop="alola_crystal"
		result.append(actor)
	return result

## Crowded city blocks keep extra residents on connected open pavement.
static func extra_tiles(map: Dictionary) -> Array:
	if spare_tiles.has(map.id):return spare_tiles[map.id]
	var grid: Array=map.physics.collision
	var water: Array=map.physics.get("water",[])
	var occupied: Array=map.alola_anchors.values().duplicate()
	occupied.append(map.spawn)
	for edge in map.get("warps",[]):occupied.append(edge.at)
	for item in map.get("alola_item_tiles",[]):occupied.append(item.at)
	var result: Array=[]
	for index in 12:
		var origin: Array=map.alola_anchors.get("side%d"%(index+1),[])
		if origin.is_empty():continue
		for step in [[2,0],[0,2],[-2,0],[0,-2],[4,0],[0,-4]]:
			var x:=int(origin[0])+int(step[0])
			var y:=int(origin[1])+int(step[1])
			if y<1 or x<1 or y+1>=grid.size() or x+1>=grid[y].size():continue
			var open:=true
			for delta in [[0,0],[1,0],[-1,0],[0,1],[0,-1]]:
				var xx:=x+int(delta[0])
				var yy:=y+int(delta[1])
				if int(grid[yy][xx])!=0 or (not water.is_empty() and int(water[yy][xx])!=0) or occupied.has([xx,yy]):
					open=false
					break
			if open and not result.has([x,y]):
				result.append([x,y])
				occupied.append([x,y])
	spare_tiles[map.id]=result
	return result

static func refresh(g) -> void:
	g.world.refresh_story_actors(g._flags())
	g._persist()

static func complete(g,row: Dictionary) -> void:
	var flags: Dictionary=g._flags()
	flags["as_"+str(row.id)]=true
	match str(row.id):
		"report2sun","report2moon":flags.as_report2=true
		"report4sun","report4moon":flags.as_report4=true
		"vulpix_rescue":flags.as_vulpix_rescue_day=Time.get_date_string_from_system()
		"rr_end":flags.as_rr_completed_at=int(Time.get_unix_time_from_system())
	refresh(g)

static func grant_crystal(g,key: String) -> void:
	load("res://core/alola_z.gd").give(g,key)

static func give_mon(g,species: int,level: int,form_key: String="",moves: Array=[],perfect: int=0) -> Dictionary:
	var mon:=Party.make(species,level,Field.moves_for(species,level,g._flags(),form_key) if moves.is_empty() else moves,form_key)
	Party.init_alola_ivs(mon,g.appearance_rng,{},perfect)
	g._store_mon(mon)
	return mon

static func battle_cfg(g,row: Dictionary) -> Dictionary:
	var id=row.get("team",0)
	if id is Dictionary:id=id.get(g._flags().a_version,0)
	var cfg: Dictionary={}
	if int(id)>0:cfg=load("res://core/alola_campaign.gd").team({"alola_team":int(id)},g._flags())
	else:
		cfg.team=[]
		for foe in row.get("enemy",[]):cfg.team.append({"species":foe[0],"level":foe[1]})
	if row.has("ally"):
		var partner: int=582 if row.ally=="lillie" else 558
		var extra: int=544 if row.ally=="lillie" else 585
		var book=load("res://core/alola_campaign.gd")
		cfg.ally_team=book.team({"alola_team":partner},g._flags()).team
		for enemy in cfg.team:enemy.trainer_group="first"
		for enemy in book.team({"alola_team":extra},g._flags()).team:
			enemy.trainer_group="second"
			cfg.team.append(enemy)
		cfg.double=true
		cfg.ally="alola"
	if row.get("rental",false):
		var tree=preload("res://core/alola_side_tree.gd")
		cfg.platinum_battle=true
		cfg.crystal_party=tree.rentals(g)
		cfg.player=cfg.crystal_party
		cfg.enemy=tree.squad(g,tree.data().usum[209][1],3)

	return cfg

static func trainer(g,row: Dictionary) -> void:
	if not g._has_party() and not row.get("rental",false):
		g._dialog(["先带上能参加战斗的伙伴。"],row.name)
		return
	var intro=g._dialog([row.text],row.name)
	intro.closed.connect(func():
		g._start_battle({"name":row.name,"battle":battle_cfg(g,row)},func(outcome):
			if outcome=="a":
				if row.has("reward"):g._give_item(row.reward,1,"key")
				if row.has("balls"):g._give_item("究极球",row.balls,"ball")
				if row.has("crystal"):grant_crystal(g,row.crystal)
				if row.get("cube",false):
					g._flags().as_cube=true
					g._flags().as_stock=int(g._flags().get("as_stock",0))+40
					g._give_item("基格尔德多面体",1,"key")
					var mon:=give_mon(g,718,63,"ZYGARDE_10_POWER_CONSTRUCT")
					mon.ability=188
				if row.get("mega",false):
					g._flags().a_mega_ring=true
					g._give_item("钥石",1,"key")
					g._give_bag_item("胡地进化石","held","ALAKAZITE")
				complete(g,row)
			elif outcome=="b" and g._party_fainted():g._blackout()))

static func wild(g,row: Dictionary) -> void:
	if not g._has_party():
		g._dialog(["先去宝可梦中心把伙伴的体力恢复好。"])
		return
	var done: Callable=func(outcome):
		if outcome=="caught" or (row.get("ko_ok",false) and outcome=="a"):
			var flags: Dictionary=g._flags()
			if row.has("quota"):
				var counter: String="as_count_"+str(row.group)
				flags[counter]=int(flags.get(counter,0))+1
				if int(flags[counter])>=int(row.quota):
					flags["as_"+str(row.group)]=true
					if row.group in ["groves","grovem"]:flags.as_grove_done=true
				g._dialog(["本次报告的数量：%d／%d。"%[flags[counter],row.quota]],"调查记录")
			elif not row.get("repeat",false):flags["as_"+str(row.id)]=true
			if row.get("tapu",false) and not flags.get("as_tapunium",false):
				grant_crystal(g,"TAPUNIUM_Z")
				flags.as_tapunium=true
			refresh(g)
		elif outcome=="b" and g._party_fainted():g._blackout()
	g._start_wild_battle(int(row.species),int(row.level),str(row.get("form","")),done)

static func step(g) -> bool:
	if Activities.egg_step(g):return true
	if not g.world.wild_tile_here() or g.rng.randi_range(0,99)>=18:return false
	rows()
	for row in by_map.get(str(g.world.map_data.id),[]):
		if row.get("beast",false) and row.has("quota") and eligible(row,g._flags()):
			wild(g,row)
			return true
	return false

static func talk(g,npc: Dictionary) -> bool:
	if npc.get("alola_malasada_counter",false):
		preload("res://core/alola_side_towns.gd").visit(g,{"action":"malasada","name":npc.name})
		return true
	var id: String=npc.get("alola_side","")
	if id.is_empty():return false
	var row: Dictionary=rows().get(id,{})
	if row.is_empty() or not eligible(row,g._flags()):return true
	match str(row.action):
		"say":
			complete(g,row)
			g._dialog([row.text],row.name)
		"battle":trainer(g,row)
		"wild":
			g._pick(row.name,["靠近","离开"],func(i):
				if i==0:wild(g,row))
		"hypno","bear_actor","bear_show","bewear","ilima_invite","ilima_test","ilima_pedestal":preload("res://core/alola_side_hauoli.gd").play(g,row)
		"vulpix","malasada","family_duel":preload("res://core/alola_side_towns.gd").visit(g,row)
		"hyper":preload("res://core/alola_hyper_training.gd").open(g)
		"task":preload("res://core/alola_side_towns.gd").quest(g,row)
		"trade":preload("res://core/alola_side_towns.gd").trade(g,row)
		"dex":preload("res://core/alola_side_towns.gd").dex(g,row)
		"gift":
			Activities.gift(g,row)
		"item","money":
			if row.action=="item":g._give_item(row.item,int(row.count),row.get("category","other"))
			else:g.save_data.money+=int(row.amount)
			complete(g,row)
			var text: String="获得了%s ×%d。"%[row.item,row.count] if row.action=="item" else "收到 %d 元。"%row.amount
			g._dialog([row.get("text","")+row.get("version_text",{}).get(g._flags().a_version,"")+text],row.name)
		"crystal":
			var matches: bool=g.save_data.party.any(func(mon):
				if int(mon.get("species_id",0))!=int(row.get("needs_mon",0)):return false
				if row.get("cap",false):return str(mon.get("form","")) in ["PIKACHU_ORIGINAL","PIKACHU_HOENN","PIKACHU_SINNOH","PIKACHU_UNOVA","PIKACHU_KALOS","PIKACHU_ALOLA","PIKACHU_PARTNER"]
				return not row.has("form") or mon.get("form","")==row.form)
			if int(row.get("needs_mon",0))>0 and not matches:
				g._dialog(["请把%s带到这里，让我看看。"%g.get_node("/root/Data").species_of(int(row.needs_mon)).name],row.name)
				return true
			grant_crystal(g,row.key)
			complete(g,row)
		_:Activities.play(g,row)
	return true

static func use_item(g,label: String) -> bool:
	if g.world.map_data.get("region","")!="alola":return false
	if preload("res://core/alola_side_rotom.gd").use(g,label):return true
	match label:
		"谜之卡片":g._dialog(["致阿罗拉的首位冠军：我们在８号道路汽车旅馆的客房里等你。"])
		"基格尔德多面体":Activities.cube(g)
		"阿罗拉的蛋":g._dialog(["轻轻晃动的伊布蛋。带着它在阿罗拉继续走，累计 %d / %d 步。"%[g._flags().get("as_egg_steps",0),35*256]])
		"伊利马的一般Ｚ":g._dialog(["伊利马托付的纯晶。前往葱郁洞窟最深处，把它放回台座。"])
		"银河队钥匙":g._dialog(["赤日的钥匙。到彩虹火箭队城堡左翼的镜门控制台使用。"])
		_:return false
	return true

static func factor(g,key: String) -> float:
	if g.world.map_data.get("region","")!="alola" or not str(g._flags().get("a_version","")).begins_with("ultra"):return 1.0
	var now:=int(Time.get_unix_time_from_system())
	var times: Dictionary=g.save_data.get("alola_roto",{})
	if key=="encounter" and int(times.get("stealth",0))>now:return 0.0
	if int(times.get(key,0))<=now:return 1.0
	return {"catch":2.5,"exp":1.5,"money":3.0,"hatch":2.0,"encounter":1.5,"friendship":2.0,"bargain":0.5}.get(key,1.0)
