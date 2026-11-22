extends "res://core/battle.gd"
## Three Pokémon stay on the rotation platform. Turning the platform does not switch
## out a Pokémon, consume its move, reset its stat stages or activate entry hazards.
var platform := {"a":[],"b":[]}

func start(a_team: Array,b_team: Array) -> void:
	super.start(a_team,b_team)
	for side in ["a","b"]: fill_platform(side)

func fill_platform(side: String) -> void:
	var team: Array=team_a if side=="a" else team_b
	var front:=active_a if side=="a" else active_b
	var seats: Array=platform[side]
	for slot in seats.duplicate():
		if team[slot].fainted: seats.erase(slot)
	if front>=0 and front not in seats:
		if seats.size()>=3: seats.pop_back()
		seats.push_front(front)
	for i in team.size():
		if seats.size()==3: break
		if not team[i].fainted and i not in seats: seats.append(i)

func rotate(side: String, slot: int) -> bool:
	if slot not in platform[side] or (team_a if side=="a" else team_b)[slot].fainted:return false
	if side=="a":active_a=slot
	else:active_b=slot
	return true

func _do_switch(side: String,index: int,forced: bool=false) -> void:
	var old:=active_a if side=="a" else active_b
	if index in platform[side] and not forced:return
	super._do_switch(side,index,forced)
	var front:=active_a if side=="a" else active_b
	if front!=old:
		var seats: Array=platform[side]
		if old in seats: seats.erase(old)
		fill_platform(side)

func run_turn(player: String, _opponent: String) -> void:
	if over:return
	# Decide the opponent's rotation and move together before any move resolves.
	var slot:=active_b
	var selected:="move:0"
	var best:=-1.0
	for i in platform.b:
		var mon: Dictionary=team_b[i]
		if mon.fainted:continue
		for j in mon.moves.size():
			if int(mon.pp[j])<=0:continue
			var move: Dictionary=Data.move_of(int(mon.moves[j]))
			var score:=float(move.get("power",0))*effectiveness_on(str(move.type),cur_a())
			if move.type in mon.types:score*=1.5
			if move.category=="status":score=22.0
			score*=rng.randf_range(0.65,1.35)
			if score>best:
				best=score
				slot=i
				selected="move:%d"%j
	if slot!=active_b:
		rotate("b",slot)
		log.append("对手转动了队形，%s 来到前方！"%cur_b().name)
	super.run_turn(player,selected)
	fill_platform("a")
	fill_platform("b")
