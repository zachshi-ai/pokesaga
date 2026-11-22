extends RefCounted
## The Frontier uses copies of the player's team. HP, moves, loans and Castle Points stay in each challenge.
const Party := preload("res://core/party.gd")
const LABELS := {"tower":"对战塔","factory":"对战工厂","hall":"对战舞台","castle":"对战城堡","arcade":"对战轮盘"}
const BRAINS := {"tower":["tower_tycoon_palmer","桄榔"],"factory":["factory_head_thorton","捩木"],"hall":["hall_matron_argenta","凯特"],"castle":["castle_valet_darach","石兰"],"arcade":["arcade_star_dahlia","大丽"]}
const TYPES := ["normal","fire","water","electric","grass","ice","fighting","poison","ground","flying","psychic","bug","rock","ghost","dragon","dark","steel"]
const BANNED := [150,151,249,250,251,382,383,384,385,386,483,484,487,489,490,491,492,493]
const EV := {"hp":"hp","attack":"atk","defense":"def","speed":"spe","special_attack":"spa","special_defense":"spd"}
static var book: Dictionary = {}

static func data() -> Dictionary:
	if book.is_empty(): book=JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/frontier.json"))
	return book

static func talk(g,npc: Dictionary) -> bool:
	var mid := str(g.world.map_data.id)
	var kind := mid.trim_prefix("sinnoh_battle_")
	var script := str(npc.get("source_script",""))
	if mid=="sinnoh_battle_frontier" and script in ["BattleFrontier_AttendantSouthwest","BattleFrontier_AttendantSoutheast"]:
		exchange(g,"left" if script.ends_with("Southwest") else "right")
		return true
	if not LABELS.has(kind): return false
	if script.ends_with("_SingleAttendant"):
		desk(g,kind)
		return true
	return false

static func exchange(g,side: String) -> void:
	var items = load("res://core/sinnoh_side.gd")
	var stock: Array=data().shops[side]
	var labels := []
	for row in stock:
		labels.append("%s　%d BP" % [items.item_name(row[0]),int(row[1])])
	labels.append("返回")
	g._pick("交换服务　%d BP" % int(g.save_data.get("battle_points",0)),labels,func(i):
		if i>=stock.size(): return
		var row: Array=stock[i]
		var key: String=row[0]
		var price:=int(row[1])
		if int(g.save_data.get("battle_points",0))<price:
			g._dialog(["战斗点数不够。"])
			return
		g._pick("用 %d BP 交换%s？" % [price,items.item_name(key)],["交换","返回"],func(j):
			if j!=0: return
			if int(g.save_data.get("battle_points",0))<price: return
			g.save_data.battle_points-=price
			items.give(g,key)
			g._persist()
			g._dialog(["换到了%s。" % items.item_name(key)])))

static func desk(g,kind: String) -> void:
	if not g._flags().get("s_champion",false):
		g._dialog(["取得神奥冠军资格后，开拓区会为你登记挑战。"],LABELS[kind])
		return
	var run: Dictionary=g.save_data.get("s_frontier_run",{})
	if not run.is_empty():
		if run.kind!=kind:
			g._dialog(["你正在%s挑战。请先回那里的柜台继续或结束挑战。"%LABELS[run.kind]])
		else: round_menu(g,run)
		return
	g._pick(LABELS[kind],["报名挑战（单打）","报名双打挑战","查看开拓记录","返回"],func(i):
		if i in [0,1]:enroll(g,kind,"single" if i==0 else "double")
		elif i==2:show_records(g,kind))

static func key_for(kind: String,mode: String,level: int) -> String:
	var key:=kind if mode=="single" else kind+"_double"
	return key+"_open" if kind=="factory" and level==100 else key

static func run_key(run: Dictionary) -> String:
	return key_for(run.kind,run.get("mode","single"),int(run.level))

static func hall_field(run: Dictionary,name: String) -> String:
	return name+"_double" if run.get("mode","single")=="double" else name

static func entrants(kind: String,mode: String) -> int:
	if kind=="hall":return 2 if mode=="double" else 1
	return 4 if kind=="tower" and mode=="double" else 3

static func show_records(g,kind: String) -> void:
	var lines: Array=[]
	var records: Dictionary=g.save_data.get("s_frontier_records",{})
	var earnings: Dictionary=g.save_data.get("s_frontier_earned_bp",{})
	var prints: Dictionary=g.save_data.get("s_frontier_prints",{})
	for mode in ["single","double"]:
		for level in ([50,100] if kind=="factory" else [50]):
			var key:=key_for(kind,mode,level)
			var title:=("单打" if mode=="single" else "双打")+(" Lv.%d"%level if kind=="factory" else "")
			lines.append("%s　最高 %d 连胜　累计 %d BP"%[title,int(records.get(key,0)),int(earnings.get(key,0))])
			if mode=="single" and int(prints.get(key,0))>0:
				lines.append("金色纪念印花" if int(prints[key])==2 else "银色纪念印花")
	g._dialog(lines,LABELS[kind]+" · 开拓记录")

static func template(key: String) -> Dictionary:
	return data().hall[key] if key.begins_with("hall_") else data().sets[key]

static func fixed(set_key: String, lv: int) -> Dictionary:
	var row:=template(set_key)
	var mon := Party.make(int(row.species),lv,row.moves)
	mon.berry=""
	mon.held="" if row.held=="NONE" else row.held
	if str(row.held).ends_with("_BERRY"): mon.berry=str(row.held).trim_suffix("_BERRY").to_lower()
	mon.frontier_set=set_key
	mon.nature=row.nature
	var ev := {}
	for stat in row.ev: ev[EV[stat]]=mini(255, floori(510.0/maxi(1,row.ev.size())))
	mon.effort=ev
	Party.recalc(mon)
	mon.hp=mon.max_hp
	return mon

static func options(g,kind: String,count: int,level: int,available: Array=[],mode:="single") -> Array:
	var keys := available.duplicate()
	if keys.is_empty():
		var streak := int(g.save_data.get("s_frontier_streak",{}).get(key_for(kind,mode,level),0))
		var trainers: Array = data().trainers.keys().filter(func(k):
			var t: Dictionary=data().trainers[k]
			var rank := mini(260, floori(streak/7.0)*40)
			return int(t.index)>=rank and int(t.index)<rank+50 and t.sets.size()>=count)
		if trainers.is_empty(): keys=data().sets.keys()
		else: keys=data().trainers[trainers[g.rng.randi_range(0,trainers.size()-1)]].sets.duplicate()
	# A single trainer's small list may not contain six distinct rental choices.
	# Fill remaining rentals from other legal sets when a factory draft needs six.
	if kind=="factory" and count==6:
		var rest: Array=data().sets.keys().filter(func(k):return not keys.has(k))
		if keys.size()<20:
			for i in mini(20-keys.size(),rest.size()):
				keys.append(rest.pop_at(g.rng.randi_range(0,rest.size()-1)))
	var team := []
	var species := {}
	var items := {}
	while not keys.is_empty() and team.size()<count:
		var key: String=keys.pop_at(g.rng.randi_range(0,keys.size()-1))
		var row:=template(key)
		if species.has(row.species) or (row.held!="NONE" and items.has(row.held)): continue
		species[row.species]=true
		items[row.held]=true
		team.append(fixed(key,level))
	return team

static func pick(g,title: String, mons: Array,count: int,selected: Array,done: Callable,hall:=false) -> void:
	var slots := []
	var labels := []
	for i in mons.size():
		var m: Dictionary=mons[i]
		if m.is_empty() or m.get("is_egg",false) or int(m.species_id) in BANNED or i in selected: continue
		if hall and int(m.level)<30:continue
		if hall and count==2:
			if selected.is_empty():
				if not mons.any(func(other):return other is Dictionary and not is_same(other,m) and int(other.get("species_id",0))==int(m.species_id) and int(other.get("level",0))>=30 and not other.get("is_egg",false)):continue
			elif int(m.species_id)!=int(mons[selected[0]].species_id):continue
		elif selected.any(func(s):return int(mons[s].species_id)==int(m.species_id) or (m.get("held","")!="" and mons[s].get("held","")==m.held)): continue
		slots.append(i)
		labels.append("%s  Lv.%d"%[m.name,int(m.level)])
	if slots.size()==0:
		g._dialog(["双打舞台需要两只同种、各不低于 Lv.30 的宝可梦。" if hall and count==2 else "请检查队伍数量、参赛等级以及种类和携带道具限制。"],title)
		return
	g._pick("%s　%d / %d"%[title,selected.size()+1,count],labels,func(i):
		var choice := selected+[slots[i]]
		if choice.size()==count: done.call(choice.map(func(s):return mons[s].duplicate(true)))
		else: pick(g,title,mons,count,choice,done,hall))

static func enroll(g,kind: String,mode:="single") -> void:
	var count:=entrants(kind,mode)
	if kind=="factory":
		g._pick("租借组别",["Lv.50","公开级 Lv.100"],func(i):
			var level:=50 if i==0 else 100
			var rental:=options(g,kind,6,level,[],mode)
			pick(g,"挑选租用宝可梦",rental,count,[],func(team):register(g,kind,mode,team,level)))
	else:
		pick(g,LABELS[kind]+(" · 双打" if mode=="double" else " · 单打"),g.save_data.party,count,[],func(team):
			var level:=50
			if kind=="hall":
				level=0
				for mon in team:level=maxi(level,int(mon.level))
			register(g,kind,mode,team,level),kind=="hall")

static func register(g,kind: String,mode: String,team: Array,level: int) -> void:
	if g.save_data.has("s_frontier_run"):return
	var run := {"kind":kind,"mode":mode,"team":team,"round":0,"level":level,"phase":"ready"}
	var key:=run_key(run)
	for m in team:
		if kind!="hall" and int(m.level)>level:m.level=level
		if kind!="factory":m.erase("trainer_group")
		Party.recalc(m)
		if kind in ["arcade","castle"]:
			m.held=""
			m.berry=""
	var streaks: Dictionary=g.save_data.get_or_add("s_frontier_streak",{})
	run.win=int(streaks.get(key,0))
	var species_field:=hall_field(run,"s_hall_species")
	if kind=="hall":
		if int(g.save_data.get(species_field,0))!=int(team[0].species_id):
			run.win=0
			g.save_data[hall_field(run,"s_hall_ranks")]={}
		g.save_data[species_field]=int(team[0].species_id)
	run.cp=int(g.save_data.get("s_castle_cp_double" if mode=="double" else "s_castle_cp",10))
	heal(g,run.team)
	g.save_data.s_frontier_run=run
	g._persist()
	round_menu(g,run)

static func heal(g,team: Array) -> void:
	for m in team:
		m.hp=m.max_hp
		m.erase("status")
		m.pp=m.moves.map(func(id):return int(g.get_node("/root/Data").move_of(id).get("pp",1)))

static func round_menu(g,run: Dictionary) -> void:
	if run.get("phase","")=="swap":
		swap_menu(g,run)
		return
	var opts := ["开始下一场","暂时休息","放弃挑战"]
	if run.kind=="castle": opts.insert(1,"使用城堡点数（%d CP）"%int(run.cp))
	g._pick("%s · %s　%d 连胜"%[LABELS[run.kind],"双打" if run.get("mode","single")=="double" else "单打",int(run.win)],opts,func(i):
		if i==0: next_battle(g,run)
		elif str(opts[i]).begins_with("使用"): castle(g,run)
		elif opts[i]=="放弃挑战":
			g._pick("结束这次连续挑战？",["继续挑战","结束"],func(choice):
				if choice==1: finish(g,run,false)
				else: round_menu(g,run)))

static func castle(g,run: Dictionary) -> void:
	g._pick("城堡点数　%d CP"%int(run.cp),["回复一只的 HP（10 CP）","回复一只的 PP（8 CP）","侦察下场种族（1 CP）","返回"],func(i):
		if i==3: round_menu(g,run);return
		var price: int=[10,8,1][i]
		if int(run.cp)<price:
			g._dialog(["城堡点数不够。"]).closed.connect(func():round_menu(g,run),CONNECT_ONE_SHOT)
			return
		if i==2:
			opponents(g,run)
			run.cp-=price
			g._persist()
			g._dialog(["对手派出："+ "、".join(run.enemy.map(func(m):return m.name))]).closed.connect(func():round_menu(g,run),CONNECT_ONE_SHOT)
		else:
			g._pick("选择队员",run.team.map(func(m):return "%s　%d/%d HP"%[m.name,m.hp,m.max_hp]),func(j):
				var m: Dictionary=run.team[j]
				if i==0: m.hp=m.max_hp
				else: m.pp=m.moves.map(func(id):return int(g.get_node("/root/Data").move_of(id).get("pp",1)))
				run.cp-=price
				g._persist()
				round_menu(g,run)))

static func boss_tier(run: Dictionary) -> String:
	if run.get("mode","single")!="single":return ""
	var count:=int(run.win)+1
	if count==(50 if run.kind=="hall" else 21):return "silver"
	if count==(170 if run.kind=="hall" else 49):return "gold"
	return ""

static func opponents(g,run: Dictionary) -> void:
	if run.has("enemy"): return
	var tier:=boss_tier(run)
	var available: Array=[]
	if tier!="":
		available=data().trainers[BRAINS[run.kind][0]+"_"+tier].sets
	if run.kind=="hall":
		var hall: Dictionary=data().hall
		var dex=g.get_node("/root/Data")
		var ranks: Dictionary=g.save_data.get(hall_field(run,"s_hall_ranks"),{})
		var chosen:=str(run.get("hall_type","normal"))
		var rank:=clampi(int(ranks.get(chosen,0)),0,9)
		var groups: Array=[[1,154],[1,154],[1,270],[1,270],[1,270],[155,375],[155,375],[155,375],[271,hall.size()],[376,hall.size()]]
		var bounds: Array=groups[rank]
		var sid:=int(run.team[0].species_id) if run.has("team") else 0
		if tier=="gold": bounds=[376,hall.size()]
		if tier=="silver":
			var found: Array=hall.keys().filter(func(k):return int(hall[k].species)==sid)
			var index:=hall.size() if found.is_empty() else int(str(found[0]).trim_prefix("hall_"))
			bounds=[1,154] if index<155 else ([155,270] if index<271 else ([271,375] if index<376 else [376,hall.size()]))
		for i in range(bounds[0],int(bounds[1])+1):
			var key:="hall_"+str(i)
			var species:=int(hall[key].species)
			if (tier!="" and species!=sid) or (tier=="" and chosen in dex.species_of(species).types): available.append(key)
	var mode:=str(run.get("mode","single"))
	var size:=entrants(run.kind,mode)
	var foe_level:=int(run.level)
	if run.kind=="hall" and tier=="":
		var ranks: Dictionary=g.save_data.get(hall_field(run,"s_hall_ranks"),{})
		var cleared:=ranks.keys().filter(func(t):return t!=run.hall_type and int(ranks[t])>0).size()
		var root:=sqrt(float(run.level))
		var rank:=int(ranks.get(run.hall_type,0))
		foe_level=clampi(ceili(run.level-3*root+rank*maxf(1.0,run.level/(5.0*root))+cleared*0.5),1,run.level)
	run.enemy=options(g,run.kind,size,foe_level,available,mode)
	if run.kind=="hall" and mode=="double" and run.enemy.size()==1:
		# Some early type ranges contain just one species. Both opponent slots
		# must still be present in a double battle.
		run.enemy.append(run.enemy[0].duplicate(true))
	run.opponent=BRAINS[run.kind][1] if tier!="" else "开拓区训练家"
	g._persist()

static func next_battle(g,run: Dictionary) -> void:
	if run.kind=="hall" and not run.has("hall_type"):
		var ranks: Dictionary=g.save_data.get_or_add(hall_field(run,"s_hall_ranks"),{})
		var types:=TYPES.filter(func(t):return int(ranks.get(t,0))<10)
		if types.is_empty():types=TYPES.duplicate()
		g._pick("选择挑战属性",types.map(func(t):return "%s　等级 %d"%[g.get_node("/root/Data").type_name(t),mini(10,1+int(ranks.get(t,0)))]),func(i):
			run.hall_type=types[i]
			next_battle(g,run))
		return
	opponents(g,run)
	if run.kind=="arcade" and not run.has("roulette"):
		roulette(g,run)
		return
	var config := {"platinum_battle":true,"player":run.team,"enemy":run.enemy,"tower":true,"double":run.get("mode","single")=="double"}
	g._start_battle({"name":run.opponent,"battle":config},func(result):
		if result!="a":finish(g,run,false);return
		run.win+=1
		run.round+=1
		if run.kind=="castle":
			run.cp+=run.team.filter(func(m):return int(m.hp)>0).size()*3
			for m in run.team: m.erase("status")
		else: heal(g,run.team)
		if run.kind=="hall":
			var ranks: Dictionary=g.save_data.get_or_add(hall_field(run,"s_hall_ranks"),{})
			ranks[run.hall_type]=int(ranks.get(run.hall_type,0))+1
		run.erase("hall_type")
		run.erase("roulette")
		var next := int(run.win)
		if run.get("mode","single")=="single" and next in ([50,170] if run.kind=="hall" else [21,49]):
			var prints: Dictionary=g.save_data.get_or_add("s_frontier_prints",{})
			prints[run_key(run)]=2 if next in [49,170] else maxi(1,int(prints.get(run_key(run),0)))
		var records: Dictionary=g.save_data.get_or_add("s_frontier_records",{})
		records[run_key(run)]=maxi(int(records.get(run_key(run),0)),next)
		if run.round>=(10 if run.kind=="hall" else 7): finish(g,run,true);return
		if run.kind=="factory":run.phase="swap"
		else:run.erase("enemy")
		g._persist()
		round_menu(g,run))

static func roulette(g,run: Dictionary) -> void:
	var events:=["平稳对战","己方中毒","对方中毒","己方麻痹","对方麻痹","己方体力下降","对方体力下降"]
	var cursor: Array=[g.rng.randi_range(0,events.size()-1)]
	g._pick("轮盘转动中",["按下停止"],func(_i):
		run.roulette=events[cursor[0]]
		var target: Array=run.team if int(cursor[0])%2==1 else run.enemy
		for m in target:
			if int(cursor[0]) in [1,2]:m.status="psn"
			elif int(cursor[0]) in [3,4]:m.status="par"
			elif int(cursor[0]) in [5,6]:m.hp=maxi(1,floori(int(m.hp)*0.8))
		g._persist()
		g._dialog(["轮盘停在「%s」。"%run.roulette]).closed.connect(func():next_battle(g,run),CONNECT_ONE_SHOT))
	var panel=g.menu_layer.get_child(-1)
	var button: Button=panel.find_children("*","Button",true,false)[0]
	var timer:=Timer.new()
	panel.add_child(timer)
	timer.timeout.connect(func():
		cursor[0]=(int(cursor[0])+1)%events.size()
		button.text="按下停止　"+events[cursor[0]])
	timer.start(0.18)

static func swap_menu(g,run: Dictionary) -> void:
	var labels: Array=["沿用现有队伍"]
	labels.append_array(run.enemy.map(func(m):return "交换 "+str(m.name)))
	g._pick("租用交换",labels,func(i):
		if i==0:
			run.erase("enemy")
			run.phase="ready"
			g._persist()
			round_menu(g,run)
			return
		var loan: Dictionary=run.enemy[i-1].duplicate(true)
		g._pick("归还哪一只？",run.team.map(func(m):return m.name),func(j):
			for k in run.team.size():
				if k!=j and int(run.team[k].species_id)==int(loan.species_id):
					g._dialog(["不能租用两只相同种类的宝可梦。"]).closed.connect(func():swap_menu(g,run),CONNECT_ONE_SHOT)
					return
			run.team[j]=loan
			heal(g,run.team)
			run.erase("enemy")
			run.phase="ready"
			g._persist()
			round_menu(g,run)))

static func finish(g,run: Dictionary,won: bool) -> void:
	var streaks: Dictionary=g.save_data.get_or_add("s_frontier_streak",{})
	var key:=run_key(run)
	streaks[key]=run.win if won else 0
	if run.kind=="castle":g.save_data["s_castle_cp_double" if run.get("mode","single")=="double" else "s_castle_cp"]=run.cp if won else 10
	if run.kind=="hall" and not won:g.save_data.erase(hall_field(run,"s_hall_ranks"))
	var points := 0
	if won:
		var schedule: Array=data().bp[run.kind]
		var size:=10 if run.kind=="hall" else 7
		var index:=mini(schedule.size()-1,floori(float(run.win)/size))
		points=20 if run.get("mode","single")=="single" and run.win in ([50,170] if run.kind=="hall" else [21,49]) else int(schedule[index])
		var earnings: Dictionary=g.save_data.get_or_add("s_frontier_earned_bp",{})
		earnings[key]=int(earnings.get(key,0))+points
		g.save_data["battle_points"]=int(g.save_data.get("battle_points",0))+points
	g.save_data.erase("s_frontier_run")
	g._persist()
	g._dialog(["完成本组挑战，获得 %d BP。"%points if won else "本次挑战结束。","本次连胜 %d 场。"%int(run.win)],LABELS[run.kind])
