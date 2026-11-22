extends RefCounted
const Rules := preload("res://core/frontier_rules.gd")
const SEED_ORDER := [1,16,9,8,5,12,13,4,3,14,11,6,7,10,15,2]

static func strength(team: Array) -> int:
	var strength_points:=0
	var types: Array=[]
	for m in team:
		strength_points+=int(m.max_hp)
		for stat in ["atk","def","spa","spd","spe"]:strength_points+=int(m.stats.get(stat,0))
		for element in m.get("types",[]):
			if not element in types:types.append(element)
	return strength_points+floori(float(int(team[0].level)*types.size())/20.0)

static func bracket(f: Dictionary) -> void:
	if f.has("bracket"):return
	var entrants: Array=[{"name":"小悠","team":f.team,"player":true}]
	var names: Dictionary={}
	var attempts:=0
	while entrants.size()<16:
		var trainer:=Rules.draw(f)
		attempts+=1
		if names.has(trainer.name) and attempts<200:continue
		names[trainer.name]=true
		entrants.append(trainer)
	for entry in entrants:entry.rank_score=strength(entry.team)
	entrants.sort_custom(func(a,b):return int(a.rank_score)>int(b.rank_score) or int(a.rank_score)==int(b.rank_score) and bool(a.get("player",false)))
	var order: Array=SEED_ORDER.map(func(n):return entrants[int(n)-1])
	var player: int=order.find_custom(func(t):return t.get("player",false))
	var final_round:=f.duplicate(false)
	final_round.wins=int(f.wins)+3
	if Rules.symbol_at(final_round):
		var id:=15 if player<8 else 0
		order[id]=Rules.opponent(final_round)
		order[id].brain=true
	f.bracket=order
	f.rounds=[order.map(func(t):return t.name)]

static func coverage(a: Dictionary,b: Dictionary,engine) -> int:
	var score:=0
	var db=Engine.get_main_loop().root.get_node("Data")
	for mon in a.team:
		for move in mon.moves:
			var info: Dictionary=db.move_of(int(move))
			if int(info.get("power",0))<=0:continue
			for target in b.team:
				var ratio: float=engine.effectiveness_on(str(info.type),target)
				score+=2 if ratio>1.0 else (-2 if ratio==0 else (-1 if ratio<1.0 else 0))
	return score

static func opponent(f: Dictionary) -> Dictionary:
	bracket(f)
	var index: int=f.bracket.find_custom(func(e):return e.get("player",false))
	return f.bracket[index^1]

static func advance(f: Dictionary) -> void:
	var winners: Array=[]
	var engine=load("res://core/battle.gd").new(randi())
	for i in range(0,f.bracket.size(),2):
		var a: Dictionary=f.bracket[i]
		var b: Dictionary=f.bracket[i+1]
		if a.get("player",false) or a.get("brain",false):winners.append(a)
		elif b.get("player",false) or b.get("brain",false):winners.append(b)
		else:winners.append(a if coverage(a,b,engine)+randi_range(0,5)>=coverage(b,a,engine)+randi_range(0,5) else b)
	f.bracket=winners
	f.rounds.append(winners.map(func(e):return e.name))
