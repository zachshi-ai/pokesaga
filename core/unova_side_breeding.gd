extends RefCounted

const FR := preload("res://core/frlg_sidequests.gd")
const Party := preload("res://core/party.gd")
const Field := preload("res://core/unova_field.gd")
const Care := preload("res://core/sinnoh_day_care.gd")
const STATS := ["hp","atk","def","spe","spa","spd"]
const POWER := {"POWER_WEIGHT":"hp","POWER_BRACER":"atk","POWER_BELT":"def","POWER_ANKLET":"spe","POWER_LENS":"spa","POWER_BAND":"spd"}
const MYTHICAL := [151,251,385,386,489,490,491,492,493,494,647,648,649]

static func quests():
	return load("res://core/unova_side_quests.gd")

static func data() -> Dictionary:
	return quests().special().breeding

static func state(g) -> Dictionary:
	return g.save_data.get_or_add("unova_daycare_"+Field.era(g._flags()),{"parents":[],"clock":0})

static func compatibility(g,a: Dictionary,b: Dictionary) -> int:
	var ia:=int(a.species_id)
	var ib:=int(b.species_id)
	var ga: Array=data().get(str(ia),{}).get("groups",[])
	var gb: Array=data().get(str(ib),{}).get("groups",[])
	if ga.is_empty() or gb.is_empty() or "NO_EGGS_DISCOVERED" in ga or "NO_EGGS_DISCOVERED" in gb or "UNDISCOVERED" in ga or "UNDISCOVERED" in gb or ia==132 and ib==132:return 0
	if ia!=132 and ib!=132:
		if a.get("sex","")==b.get("sex","") or not a.get("sex","") in ["female","male"] or not b.get("sex","") in ["female","male"]:return 0
		if not ga.any(func(k):return k in gb):return 0
	var foreign:=int(a.get("ot_id",0))!=int(b.get("ot_id",0))
	var rate:=70 if ia==ib and foreign else 50 if ia==ib or foreign else 20
	if g._flags().get("us_b2_oval",false):rate={20:40,50:80,70:88}[rate]
	return rate

static func make_egg(g,a: Dictionary,b: Dictionary) -> Dictionary:
	var mother: Dictionary=a if a.get("sex","")=="female" or int(b.species_id)==132 else b
	var father: Dictionary=b if is_same(mother,a) else a
	if int(mother.species_id)==132:
		mother=father
		father=a if is_same(mother,b) else b
	var id:=int(data()[str(int(mother.species_id))].baby)
	if Care.INCENSE.has(id):
		var pair: Array=Care.INCENSE[id]
		if str(a.get("held",""))!=pair[0] and str(b.get("held",""))!=pair[0]:id=int(pair[1])
	if id in [29,32]:id=29 if g.rng.randi_range(0,1)==0 else 32
	if id in [313,314]:id=313 if g.rng.randi_range(0,1)==0 else 314
	if id in [490,489]:id=489
	var dex: Dictionary=data()[str(id)]
	var moves:=Field.moves_for(id,1,g._flags())
	var heritage: Array=father.moves.map(func(n):return int(n))
	var learned: Array=Field.learnset(id,g._flags())
	var train: Dictionary=Field.data().training[Field.era(g._flags())]
	for move in heritage:
		var possible: bool=dex.moves.any(func(n):return int(n)==int(move))
		if not possible:
			possible=mother.moves.any(func(v):return int(v)==int(move)) and learned.any(func(v):return int(v[1])==int(move))
		if not possible:
			for machine in train.compatible.get(str(id),[]):
				if int(train.machines.get(str(int(machine)),0))==int(move):possible=true;break
		if possible:Care.add_move(moves,int(move))
	var mon:=Party.make(id,1,moves)
	var stones: Array=[a,b].filter(func(m):return m.get("held","")=="EVERSTONE")
	if not stones.is_empty() and (Field.era(g._flags())=="b2" or g.rng.randi_range(0,1)==0):mon.nature=stones.pick_random().get("nature",mon.nature)
	var parents: Array=[a,b]
	parents.shuffle()
	var fixed: Dictionary={}
	for parent in parents:
		if POWER.has(parent.get("held","")):
			var stat: String=POWER[parent.held]
			fixed[stat]=int(parent.get("ivs",{}).get(stat,15))
			break
	var stats:=STATS.duplicate()
	stats.shuffle()
	mon.ivs={}
	for stat in STATS:mon.ivs[stat]=g.rng.randi_range(0,31)
	for stat in stats:
		if fixed.size()>=3:break
		if not fixed.has(stat):fixed[stat]=int(parents.pick_random().get("ivs",{}).get(stat,15))
	mon.ivs.merge(fixed,true)
	var hidden:=int(quests().side().data().hidden_abilities.get(str(int(mother.species_id)),0))
	if hidden>0 and int(mother.get("ability",0))==hidden and int(father.species_id)!=132 and g.rng.randi_range(0,99)<60:
		mon.ability=int(quests().side().data().hidden_abilities.get(str(id),mon.ability))
		mon.ability_name=g.get_node("/root/Data").abilities.get(int(mon.ability),{}).get("name","")
	Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
	Party.recalc(mon,true)
	return {"mon":mon,"steps":maxi(1,int(dex.cycles))*255}

static func open(g) -> void:
	var s:=state(g)
	var labels: Array=[]
	if s.has("egg"):labels.append("领取宝可梦蛋")
	var max_parents:=2 if Field.era(g._flags())=="b2" or g._flags().get("u1_bike",false) else 1
	if s.parents.size()<max_parents:labels.append("寄放伙伴")
	for e in s.parents:
		var mon:=Care.preview(e)
		labels.append("领回%s　Lv.%d"%( [mon.name,mon.level]))
	labels.append("离开")
	g._pick("3号道路 · 宝可梦培育屋",labels,func(i):
		var choice: String=labels[i]
		if choice=="领取宝可梦蛋":
			if Party.occupied(g.save_data.party)+g.save_data.get("unova_nursery_eggs",[]).size()>=Party.MAX_SIZE:g._dialog(["请在队伍里腾出位置。"]);return
			g.save_data.get_or_add("unova_nursery_eggs",[]).append(s.egg)
			s.erase("egg")
			g._give_item("合众的蛋",1,"key")
			g._persist()
			g._dialog(["你接过了一个宝可梦蛋。"])
		elif choice=="寄放伙伴":
			if Party.occupied(g.save_data.party)<=1:g._dialog(["请至少留下一个能陪你旅行的伙伴。"]);return
			FR.pick_party(g,"寄放哪只伙伴？",func(m):return not m.has("fused_part") and not m.get("is_egg",false),func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				if not g.save_data.party.any(func(m):return not is_same(m,mon) and int(m.get("hp",0))>0):g._dialog(["请至少留下一只能战斗的伙伴。"]);return
				g.save_data.party.remove_at(slot)
				s.parents.append({"mon":mon,"steps":0})
				g._persist()
				g._dialog(["培育屋开始照顾%s。"%mon.name]))
		elif choice.begins_with("领回"):
			var index: int=i-(1 if s.has("egg") else 0)-(1 if s.parents.size()<max_parents else 0)
			var e: Dictionary=s.parents[index]
			var mon:=Care.preview(e)
			var cost:=100+100*(int(mon.level)-int(e.mon.level))
			g._pick("领回%s需要 %d 元。"%[mon.name,cost],["领回","取消"],func(n):
				if n!=0:return
				if int(g.save_data.money)<cost or Party.occupied(g.save_data.party)>=Party.MAX_SIZE:g._dialog(["请检查余额和队伍空位。"]);return
				for pair in Field.learnset(int(mon.species_id),g._flags()):
					if int(pair[0])>int(e.mon.level) and int(pair[0])<=int(mon.level):Care.add_move(mon.moves,int(pair[1]))
				Party.recalc(mon,true)
				mon.pp=mon.moves.map(func(id):return int(g.get_node("/root/Data").move_of(int(id)).get("pp",1)))
				g.save_data.money-=cost
				s.parents.remove_at(index)
				g._store_mon(mon)
				g._persist()
				g._dialog(["%s回到了你的队伍。"%mon.name])))

static func step(g) -> bool:
	var current: Dictionary=g.save_data.get("unova_daycare_"+Field.era(g._flags()),{})
	if not current.is_empty():
		for entry in current.parents:entry.steps=int(entry.steps)+1
		current.clock=(int(current.clock)+1)%256
		if current.clock==0 and current.parents.size()==2 and not current.has("egg"):
			var a: Dictionary=current.parents[0].mon
			var b: Dictionary=current.parents[1].mon
			if g.rng.randi_range(0,99)<compatibility(g,a,b):current.egg=make_egg(g,a,b);g._persist()
	var eggs: Array=g.save_data.get("unova_nursery_eggs",[])
	var pace:=2 if g.save_data.party.any(func(m):return int(m.get("ability",0)) in [40,49]) else 1
	var hatched: Array=[]
	for i in range(eggs.size()-1,-1,-1):
		var egg: Dictionary=eggs[i]
		egg.steps=int(egg.steps)-pace
		if egg.steps>0:continue
		eggs.remove_at(i)
		g._consume_item("合众的蛋")
		g._store_mon(egg.mon)
		g._record_hatch()
		hatched.append("%s从蛋里孵出来了！"%egg.mon.name)
	if hatched.is_empty():return false
	g._persist()
	g._dialog(hatched)
	return true

static func charms(g) -> void:
	var q=quests()
	var list: Array=g.save_data.get("dex",{}).get("caught",[])
	var caught: Dictionary={}
	for id in list:caught[int(id)]=true
	var national_left:=0
	for i in range(1,650):
		if i not in MYTHICAL and not caught.has(i):national_left+=1
	var local_left: int=q.special().regional.filter(func(id):return not caught.has(int(id))).size()
	if local_left==0 and not g._flags().get("us_b2_oval",false):q.grant(g,"OVAL_CHARM","us_b2_oval","红豆杉博士");return
	if national_left==0 and not g._flags().get("us_b2_shiny",false):q.grant(g,"SHINY_CHARM","us_b2_shiny","红豆杉博士");return
	g._dialog(["合众图鉴还需收服 %d 种，全国图鉴还需收服 %d 种。"%( [local_left,national_left])],"红豆杉博士")
