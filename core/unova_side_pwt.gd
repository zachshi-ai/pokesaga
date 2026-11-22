extends RefCounted

const Facility := preload("res://core/unova_side_facilities.gd")
const Frontier := preload("res://core/frontier_rules.gd")
const Activities := preload("res://core/unova_side_activities.gd")
const Tower := preload("res://core/sinnoh_frontier.gd")
const SAVE_KEY := "unova_pwt_run"
const TITLES := {4:"帆巴锦标赛",12:"租借锦标赛",14:"混合锦标赛",5:"合众馆主赛",6:"关都馆主赛",7:"城都馆主赛",8:"丰缘馆主赛",9:"神奥馆主赛",10:"世界馆主赛",2:"属性专家赛",13:"租借大师赛",15:"混合大师赛",1:"冠军锦标赛"}
const STYLES := ["single","double","triple","rotation"]
const COUNTS := [3,4,6,4]
const STYLE_NAMES := ["单打","双打","三打","轮盘"]
const TYPES := ["normal","fighting","flying","poison","ground","rock","bug","ghost","steel","fire","water","grass","electric","psychic","ice","dragon","dark"]
const ROUNDS := ["第一轮","半决赛","决赛"]
const TICKETS := ["第一组租借券","第二组租借券","混合租借券"]
const MYTHICAL := [494,643,644,646,647,648,649]

static func available(flags: Dictionary,record: Dictionary,id: int) -> bool:
	if not flags.get("u2_pwt",false):return false
	var all_leaders:=true
	for n in range(5,10):
		if int(record.get(str(n),0))==0:all_leaders=false
	match id:
		4,12,14:return true
		5:return flags.get("u2_champion",false)
		6,7,8,9:return int(record.get("5",0))>0
		10,2:return all_leaders
		13:return all_leaders and int(record.get("12",0))>0
		15:return all_leaders and int(record.get("14",0))>0
		1:return int(record.get("10",0))>=10
	return false

static func open(g) -> void:
	var current: Dictionary=g.save_data.get(SAVE_KEY,{})
	if not current.is_empty():
		if current.team.is_empty():registration(g,current)
		else:lobby(g,current)
		return
	var record: Dictionary=g.save_data.get("unova_pwt_records",{})
	var ids:=TITLES.keys().filter(func(id):return available(g._flags(),record,id))
	var labels:=ids.map(func(id):return "%s　%d 冠"%[TITLES[id],int(record.get(str(id),0))])
	labels.append("兑换奖品（%d BP）"%int(g.save_data.get("unova_bp",0)))
	labels.append("离开")
	g._pick("宝可梦世界锦标赛",labels,func(i):
		if i>=ids.size():
			if i==ids.size():Facility.exchange(g)
			return
		var id:=int(ids[i])
		g._pick(TITLES[id],["单打 · 3 只","双打 · 4 只","三打 · 6 只","轮盘 · 4 只","返回"],func(style):
			if style==4:open(g);return
			var run:={"id":id,"style":style,"type":"","ticket":-1,"team":[],"options":[],"round":0,"remaining":0,"bracket":[]}
			if id==2:
				var badges: Dictionary=g.save_data.get("unova_pwt_expert",{})
				var types:=TYPES.map(func(t):return "%s　%d 冠"%[g.get_node("/root/Data").type_name(t),int(badges.get(t,0))])
				types.append("返回")
				g._pick("选择参赛属性",types,func(t):
					if t>=TYPES.size():open(g);return
					run.type=TYPES[t]
					registration(g,run))
			else:registration(g,run)))

static func rentals(id: int) -> bool:
	return id in [12,13]

static func mix(id: int) -> bool:
	return id in [14,15]

static func group(id: int) -> String:
	if id in [4,12,14]:return "pwt_regular"
	if id in range(5,10):return "pwt_leaders"
	return "pwt_masters"

static func entry_count(run: Dictionary) -> int:
	return COUNTS[int(run.style)]

static func types_of(mon: Dictionary) -> Array:
	var id:=int(mon.species_id)
	if not str(mon.get("form","")).is_empty() and id in [351,413,479,492,493,555,648]:
		var form_types: Array=mon.get("types",[])
		if not form_types.is_empty() and not form_types.has("fairy"):return form_types
	return Facility.data().pwt_types.get(str(id),mon.get("types",[]))

static func eligible(mon: Dictionary,run: Dictionary,selected: Array) -> bool:
	if mon.is_empty() or mon.get("is_egg",false):return false
	var id:=int(mon.species_id)
	if str(run.type)!="" and not types_of(mon).has(str(run.type)):return false
	if int(Facility.data().pwt_modes[int(run.id)-1][0])!=0:
		if mon.get("held","")=="SOUL_DEW" or 507 in mon.moves:return false
		if id in Tower.BANNED or id in MYTHICAL or id>649:return false
		for other in selected:
			if int(other.species_id)==id:return false
			if mon.get("held","")!="" and mon.get("held","")==other.get("held",""):return false
	return true

static func registration(g,run: Dictionary) -> void:
	if rentals(int(run.id)) and int(run.ticket)<0:
		g._pick("选择租借券",TICKETS+["返回"],func(i):
			if i>=TICKETS.size():open(g);return
			run.ticket=i
			run.options=rental_team(g,run,6,[],20)
			g.save_data[SAVE_KEY]=run
			g._persist()
			registration(g,run))
		return
	var options: Array=run.options if rentals(int(run.id)) else g.save_data.party
	select_mons(g,run,options,[],func(chosen):
		run.team=chosen if rentals(int(run.id)) else chosen.map(func(m):return Frontier.owner_team(m,25 if int(run.id)==4 else 50))
		run.options=[]
		run.bracket=bracket(run)
		g.save_data[SAVE_KEY]=run
		g._persist()
		lobby(g,run))

static func select_mons(g,run: Dictionary,options: Array,indices: Array,done: Callable) -> void:
	var count:=entry_count(run)
	var chosen:=indices.map(func(i):return options[i])
	if chosen.size()==count:done.call(chosen);return
	var allowed: Array=[]
	var labels: Array=[]
	for i in options.size():
		if i in indices or not options[i] is Dictionary or not eligible(options[i],run,chosen):continue
		var m: Dictionary=options[i]
		allowed.append(i)
		var move_names:Array=m.moves.map(func(n):return str(g.get_node("/root/Data").move_of(int(n)).get("name","?")))
		labels.append("%s　%s"%[m.name,"／".join(move_names)])
	labels.append("取消报名")
	var title: String="%s · 第 %d / %d 只"%[TITLES[int(run.id)],chosen.size()+1,count]
	if allowed.is_empty():title="符合参赛条件的宝可梦不足"
	g._pick(title,labels,func(i):
		if i>=allowed.size():
			g.save_data.erase(SAVE_KEY)
			g._persist()
			return
		select_mons(g,run,options,indices+[allowed[i]],done))

static func fixed(g,row: Array,level: int,iv: int) -> Dictionary:
	var ivs:={}
	var evs:={}
	for key in ["hp","attack","defense","special_attack","special_defense","speed"]:
		ivs[key]=iv
		evs[key]=mini(255,510/maxi(1,row[4].size())) if key in row[4] else 0
	var mon:=Activities.cast_mon(g,[row[0],level,row[1],row[2],"",row[0],ivs,evs,row[3]])
	mon.erase("film_species")
	mon.types=types_of(mon)
	mon.nature=row[3]
	if str(row[2]).ends_with("_BERRY"):mon.berry=str(row[2]).trim_suffix("_BERRY").to_lower()
	return mon

static func take_sets(g,pool: Array,sets: Array,count: int,level: int,iv: int,excluded: Array,type: String="") -> Array:
	var mons: Array=[]
	var items: Array=[]
	for other in excluded:
		if other.has("held"):items.append(str(other.held))
	var ids:=excluded.map(func(m):return int(m.species_id))
	var choices:=pool.duplicate()
	choices.shuffle()
	for index in choices:
		var row: Array=sets[int(index)]
		var sid:=int(row[0])
		if sid<=0 or sid in ids:continue
		if type!="" and type not in Facility.data().pwt_types.get(str(sid),[]):continue
		if row[2]!="NONE" and row[2] in items:continue
		ids.append(sid)
		items.append(row[2])
		mons.append(fixed(g,row,level,iv))
		if mons.size()==count:break
	return mons

static func rental_team(g,run: Dictionary,count: int,excluded: Array,iv: int) -> Array:
	var sets: Array=Facility.data().pwt_rental.sets
	var first:=range(209,559) if int(run.id)==13 else range(1,133)
	var second:=range(559,909) if int(run.id)==13 else range(133,209)
	# The opponent excludes the entrant's species, independently of its held items.
	var blacklist:=excluded.map(func(m):return {"species_id":m.species_id})
	if int(run.ticket)!=2:
		return take_sets(g,first if int(run.ticket)==0 else second,sets,count,50,iv,blacklist)
	var chosen:=take_sets(g,second,sets,mini(3,count),50,iv,blacklist)
	if chosen.size()<count:chosen.append_array(take_sets(g,first,sets,count-chosen.size(),50,iv,blacklist+chosen))
	return chosen

static func candidates(run: Dictionary) -> Array:
	var id:=int(run.id)
	var rules: Array=Facility.data().pwt_rules
	var indices: Array=[]
	for i in rules.size():
		var rule: Array=rules[i]
		var allowed: bool=(float(id) in rule[0]) if id in [4,10,12,13,14,15] else int(rule[1])==id
		if id==2:allowed=str(rule[2]) in [str(run.type),"null"]
		if allowed:indices.append(i)
	return indices

static func bracket(run: Dictionary) -> Array:
	var pool:=candidates(run)
	pool.shuffle()
	var rules: Array=Facility.data().pwt_rules
	var chosen: Array=[]
	var id:=int(run.id)
	var quotas: Array=[7,0,0]
	if id==4:quotas=[2,1,4]
	elif id in [12,14]:quotas=[2,2,3]
	elif id==1:chosen=pool
	elif id==2:quotas=[7,7,7]
	for n in 3:
		var rank:=3-n
		for i in pool.filter(func(t):return int(rules[t][3])==rank).slice(0,mini(7-chosen.size(),int(quotas[n]))):chosen.append(i)
	chosen.shuffle()
	chosen.sort_custom(func(a,b):return int(rules[a][3])>int(rules[b][3]))
	var result: Array=[-1,null,null,null,null,null,null,null]
	result[randi_range(4,7)]=chosen[0]
	result[randi_range(2,3)]=chosen[1]
	result[1]=chosen[2]
	var rest:=chosen.slice(3)
	rest.shuffle()
	for i in range(2,8):
		if result[i]==null:result[i]=rest.pop_back()
	return result

static func simulated(g,id: int,left: int,right: int) -> int:
	var a: Array=Facility.data().pwt_rules[left]
	var b: Array=Facility.data().pwt_rules[right]
	if int(a[3])!=int(b[3]):return left if int(a[3])>int(b[3]) else right
	if not rentals(id) and not mix(id) and int(a[6])<TYPES.size() and int(b[6])<TYPES.size():
		var chart=load("res://core/battle.gd").new()
		var attack: float=chart.effectiveness(TYPES[int(a[6])],[TYPES[int(b[6])]])
		var defend: float=chart.effectiveness(TYPES[int(b[6])],[TYPES[int(a[6])]])
		if attack!=defend:return left if (attack>defend)==(g.rng.randi_range(0,9)<7) else right
	return left if g.rng.randi_range(0,1)==0 else right

static func name_of(i: int) -> String:
	if i<0:return "小悠"
	if i<Facility.LEADERS.size():return Facility.LEADERS[i]
	return str(Facility.data().pwt_names[i])

static func opponent(g,run: Dictionary) -> void:
	if run.has("foes"):return
	var id:=int(run.id)
	var index:=int(run.bracket[1])
	var iv:=int(Facility.data().pwt_rules[index][4])
	var count:=entry_count(run)
	if rentals(id):run.foes=rental_team(g,run,count,run.team,iv)
	else:
		var table: Dictionary=Facility.data()[group(id)]
		var level:=25 if id==4 else 50
		var trainer: Array=table.trainers[index]
		run.foes=[]
		if bool(Facility.data().pwt_rules[index][5]) and int(trainer[2])>0:
			run.foes=take_sets(g,[int(trainer[2])],table.sets,1,level,iv,[],run.type)
		run.foes.append_array(take_sets(g,trainer[1],table.sets,count-run.foes.size(),level,iv,run.foes,run.type))
		if run.foes.size()<count:
			var extra:=take_sets(g,range(1,table.sets.size()),table.sets,count-run.foes.size(),level,iv,run.foes,run.type)
			run.foes.append_array(extra)
	if mix(id):
		var chosen:=range(count)
		chosen.shuffle()
		run.borrowed=chosen.slice(0,2 if int(run.style)==2 else 1)
	g._persist()

static func lobby(g,run: Dictionary) -> void:
	opponent(g,run)
	g._pick("%s · %s · %s"%[TITLES[int(run.id)],ROUNDS[int(run.round)],name_of(int(run.bracket[1]))],["开始对战","查看对阵","暂时休息","退出挑战"],func(i):
		if i==0:
			if mix(int(run.id)):trade_choices(g,run,[])
			else:fight(g,run,[])
		elif i==1:
			var lines: Array=[]
			for pair in range(0,run.bracket.size(),2):
				lines.append("%s　对　%s"%[name_of(int(run.bracket[pair])),name_of(int(run.bracket[pair+1]))])
			g._dialog(lines,"现轮对阵").closed.connect(func():lobby(g,run))
		elif i==3:
			g._pick("结束本次锦标赛？",["继续挑战","退出"],func(n):
				if n==1:finish(g,run,false)
				else:lobby(g,run)))

static func trade_choices(g,run: Dictionary,picked: Array) -> void:
	if picked.size()==run.borrowed.size():fight(g,run,picked);return
	var i:=picked.size()
	var ids:=range(run.foes.size()).filter(func(n):return n not in picked)
	var labels:=ids.map(func(n):return "%s　%s"%[run.foes[n].name,"／".join(run.foes[n].moves.map(func(m):return str(g.get_node("/root/Data").move_of(int(m)).name)))])
	labels.append("返回")
	g._pick("对手借用%s · 选你借用的宝可梦"%run.team[int(run.borrowed[i])].name,labels,func(n):
		if n==ids.size():lobby(g,run);return
		trade_choices(g,run,picked+[ids[n]]))

static func fight(g,run: Dictionary,picks: Array) -> void:
	var mine: Array=run.team.duplicate(true)
	var foes: Array=run.foes.duplicate(true)
	for i in picks.size():
		var a:=int(run.borrowed[i])
		var b:=int(picks[i])
		var traded: Dictionary=mine[a]
		mine[a]=foes[b]
		foes[b]=traded
	var style:=int(run.style)
	g._start_battle({"name":name_of(int(run.bracket[1])),"battle":{"platinum_battle":true,"tower":true,"player":mine,"enemy":foes,"double":style==1,"battle_type":STYLES[style]}},func(result):
		if result!="a":finish(g,run,false,true);return
		run.remaining=int(run.remaining)+mine.filter(func(m):return int(m.hp)>0).size()
		run.round=int(run.round)+1
		if int(run.round)==3:finish(g,run,true);return
		var next: Array=[-1]
		for pos in range(2,run.bracket.size(),2):
			next.append(simulated(g,int(run.id),int(run.bracket[pos]),int(run.bracket[pos+1])))
		run.bracket=next
		run.erase("foes")
		run.erase("borrowed")
		g._persist()
		lobby(g,run))

static func finish(g,run: Dictionary,won: bool,lost_match:=false) -> void:
	g.save_data.erase(SAVE_KEY)
	var message:="本次参赛结束。"
	if lost_match:
		var shard: String=["RED_SHARD","BLUE_SHARD","YELLOW_SHARD","GREEN_SHARD"].pick_random()
		Facility.side().give(g,shard)
		message+="获得了参赛奖%s。"%Facility.side().item_name(shard)
	if won:
		var id:=int(run.id)
		var record: Dictionary=g.save_data.get_or_add("unova_pwt_records",{})
		record[str(id)]=int(record.get(str(id),0))+1
		if id==2:
			var types: Dictionary=g.save_data.get_or_add("unova_pwt_expert",{})
			types[run.type]=int(types.get(run.type,0))+1
		var reward:=int(run.remaining) if id in [1,10] else int(Facility.data().pwt_modes[id-1][2][int(run.style)])
		g.save_data.unova_bp=int(g.save_data.get("unova_bp",0))+reward
		message="%s优胜！获得 %d BP。"%[TITLES[id],reward]
	g._persist()
	g._dialog([message],"宝可梦世界锦标赛")
