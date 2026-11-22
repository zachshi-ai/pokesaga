extends RefCounted
const NAMES := {"tower":"对战塔","dome":"对战巨蛋","palace":"对战宫殿","arena":"对战竞技场","factory":"对战工厂","pike":"对战水管","pyramid":"对战金字塔"}
const BRAINS := {"tower":"莉拉","dome":"希尔斯","palace":"宇康","arena":"黄瓜香","factory":"达拉","pike":"小蓟","pyramid":"神代"}
const SYMBOLS := {"tower":"能力","dome":"战术","palace":"精神","arena":"毅力","factory":"知识","pike":"运气","pyramid":"英勇"}
const BOSS_AT := {"tower":[35,70],"dome":[20,40],"palace":[21,42],"arena":[28,56],"factory":[21,42],"pike":[28,140],"pyramid":[21,70]}
const BANNED := [150,151,249,250,251,382,383,384,385,386]
const RANGES := [[0,99],[80,119],[100,139],[120,159],[140,179],[160,199],[180,219],[200,299]]
const HARD := [[100,119],[120,139],[140,159],[160,179],[180,199],[200,219],[220,239],[200,299]]
const NATURES := ["勤奋","怕寂寞","勇敢","固执","顽皮","大胆","坦率","悠闲","淘气","乐天","胆小","急躁","认真","爽朗","天真","内敛","慢吞吞","冷静","害羞","马虎","温和","温顺","自大","慎重","浮躁"]
const NATURE_KEYS := ["HARDY","LONELY","BRAVE","ADAMANT","NAUGHTY","BOLD","DOCILE","RELAXED","IMPISH","LAX","TIMID","HASTY","SERIOUS","JOLLY","NAIVE","MODEST","MILD","QUIET","BASHFUL","RASH","CALM","GENTLE","SASSY","CAREFUL","QUIRKY"]
static var tables: Dictionary
var kind := ""
var exchanges := 0
var pair_slots := []
var minds := [0,0]
var skills := [0,0]
var initial_hp := [1,1]

static func data() -> Dictionary:
	if tables.is_empty():tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/emerald_frontier.json"))
	return tables

static func size_of_set(f: Dictionary) -> int:
	if f.pack!="main":return 3
	return 4 if f.kind=="dome" else (14 if f.kind=="pike" else 7)

static func symbol_at(f: Dictionary) -> int:
	if f.pack!="main" or f.mode!="单打":return 0
	var next:=int(f.wins)+1
	var milestones: Array=BOSS_AT[f.kind]
	return milestones.find(next)+1

static func owner_team(mon: Dictionary,level: int) -> Dictionary:
	var team=load("res://core/facility.gd").tower_team([mon])
	var result: Dictionary=team[0]
	result.level=level
	load("res://core/party.gd").recalc(result)
	result.hp=result.max_hp
	return result

static func make_mon(row: Dictionary,level: int) -> Dictionary:
	var mon: Dictionary=load("res://core/battle.gd").make_combatant(int(row.species),level,row.moves.map(func(x):return int(x)))
	mon.nature=row.nature
	if row.held.ends_with("_BERRY"):mon.berry=str(row.held).trim_suffix("_BERRY").to_lower()
	elif row.held!="NONE":mon.held=row.held
	var keys:=["hp","atk","def","spe","spa","spd"]
	var stats: Array=row.get("evs",[]).duplicate()
	if stats.is_empty():
		stats=[0,0,0,0,0,0]
		var attributes: Array=row.get("ev",[])
		for key in attributes:
			var i:=["HP","ATTACK","DEFENSE","SPEED","SP_ATTACK","SP_DEFENSE"].find(key)
			if i>=0:stats[i]=mini(255,floori(510.0/maxi(1,attributes.size())))
	for i in keys.size():
		var bonus:=floori((int(row.get("iv",31))-31+floori(int(stats[i])/4.0))*level/100.0)
		if i==0:
			mon.max_hp=maxi(1,int(mon.max_hp)+bonus)
			mon.hp=mon.max_hp
		else:mon.stats[keys[i]]=maxi(1,int(mon.stats[keys[i]])+bonus)
	return mon

static func draw(f: Dictionary,n: int=3) -> Dictionary:
	var pack: Dictionary=data()[f.pack]
	var tier:=mini(7,floori(float(f.wins)/size_of_set(f)))
	var lo:=0
	var hi: int=pack.trainers.size()-1
	if f.pack=="main":
		var range_row: Array=(HARD if (int(f.wins)+1)%size_of_set(f)==0 else RANGES)[tier]
		lo=range_row[0]
		hi=range_row[1]
	var trainer: Dictionary=pack.trainers[randi_range(lo,hi)]
	var entries: Array=trainer.pool.duplicate()
	entries.shuffle()
	var team: Array=[]
	var used: Array=[]
	var held: Array=[]
	for key in entries:
		var row: Dictionary=pack.sets[key]
		if int(row.species) in used or row.held!="NONE" and row.held in held:continue
		team.append(make_mon(row,f.level))
		used.append(int(row.species))
		held.append(row.held)
		if team.size()==n:break
	if team.size()<n:
		var rest: Array=pack.sets.keys()
		rest.shuffle()
		for k in rest:
			var row: Dictionary=pack.sets[k]
			if int(row.species) in used or row.held!="NONE" and row.held in held:continue
			used.append(int(row.species))
			held.append(row.held)
			team.append(make_mon(row,f.level))
			if team.size()==n:break
	return {"name":trainer.name,"team":team}

static func wild(f: Dictionary) -> Dictionary:
	var pools: Array=data()[str(f.kind)+("_open" if f.open else "_fixed")]
	var round_index:=floori(float(f.wins)/size_of_set(f))
	var pool: Array=pools[round_index%pools.size()] if f.kind=="pyramid" else pools[mini(pools.size()-1,round_index)]
	var row: Array=pool[randi()%pool.size()]
	var level:=int(f.level)-int(row[1]) if f.kind=="pike" or f.open else int(row[1])
	if f.kind=="pyramid":level+=randi_range(-5,5)
	var mon: Dictionary=load("res://core/battle.gd").make_combatant(int(row[0]),clampi(level,1,100),row[2].map(func(x):return int(x)))
	return {"name":"野生的"+str(mon.name),"team":[mon]}

static func opponent(f: Dictionary) -> Dictionary:
	var tier:=symbol_at(f)
	if tier==0:return draw(f,4 if f.mode=="双打" and f.kind=="tower" else 3)
	var team: Array
	if f.kind=="factory":team=draw(f).team
	else:team=data().brains[f.kind][tier-1].map(func(r):return make_mon(r,f.level))
	return {"name":BRAINS[f.kind],"team":team}

static func moveslot(mon: Dictionary, index: int) -> int:
	return int(mon.moves[clampi(index,0,mon.moves.size()-1)])

static func choose(battle,side: String,palace: bool) -> String:
	var mon: Dictionary=battle.cur_a() if side=="a" else battle.cur_b()
	var target: Dictionary=battle.cur_b() if side=="a" else battle.cur_a()
	var category: int=-1
	if palace:
		var nk:=str(mon.get("nature","DOCILE"))
		if nk in NATURES:nk=NATURE_KEYS[NATURES.find(nk)]
		var chances: Array=data().nature.get(nk,data().nature.DOCILE)
		var half:=2 if int(mon.hp)*2<=int(mon.max_hp) else 0
		var roll: int=battle.rng.randi_range(0,99)
		category=0 if roll<chances[half] else (1 if roll<chances[half]+chances[half+1] else 2)
	var selected := -1
	var high := -1000.0
	for i in mon.moves.size():
		if i>=mon.pp.size() or int(mon.pp[i])<=0:continue
		var move: Dictionary=data_move(battle,int(mon.moves[i]))
		var move_kind: int=data().move_groups.get(str(int(mon.moves[i])),0 if move.get("category","")!="status" else 2)
		if palace and category!=move_kind:continue
		var value: float=battle.rng.randf()*35.0
		if not palace:value+=float(move.get("power",0))*battle.effectiveness_on(str(move.get("type","normal")),target)
		if value>high:
			selected=i
			high=value
	if selected<0:return "palace_wait" if palace else "move:0"
	return "move:%d"%selected

static func data_move(_battle, move: int) -> Dictionary:
	return Engine.get_main_loop().root.get_node("Data").move_of(move)

func turn(battle,player: String) -> void:
	var foe:=choose(battle,"b",kind=="palace")
	if kind=="palace" and player.begins_with("move"):player=choose(battle,"a",true)
	if kind!="arena":
		battle.run_turn(player,foe)
		return
	var current: Array=[battle.active_a,battle.active_b]
	if current!=pair_slots:
		pair_slots=current
		exchanges=0
		minds=[0,0]
		skills=[0,0]
		initial_hp=[maxi(1,battle.cur_a().hp),maxi(1,battle.cur_b().hp)]
	var pair: Array=[battle.cur_a(),battle.cur_b()]
	var hp_before: Array=[pair[0].hp,pair[1].hp]
	for i in 2:
		var move:=moveslot(pair[i],int([player,foe][i].get_slice(":",1)))
		minds[i]+=int(data().mind.get(str(move),0))
	battle.run_turn(player,foe)
	for i in 2:
		if int(pair[1-i].hp)<int(hp_before[1-i]):skills[i]+=1
	exchanges+=1
	if exchanges!=3 or battle.over or battle.active_a!=current[0] or battle.active_b!=current[1]:return
	var votes: Array=[0,0]
	for pair_score in [minds,skills,[floori(100.0*pair[0].hp/initial_hp[0]),floori(100.0*pair[1].hp/initial_hp[1])]]:
		for i in 2:
			if pair_score[i]>=pair_score[1-i]:votes[i]+=1 if pair_score[i]==pair_score[1-i] else 2
	battle.log.append("三回合裁定　心／技／体　%d 比 %d" % votes)
	for i in 2:
		if votes[i]<=votes[1-i]:
			pair[i].hp=0
			pair[i].fainted=true
	battle._check_end()
