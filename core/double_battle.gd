extends "res://core/battle.gd"
## Two positions per side. The paired Space Center trainers each replace their own
## fainted Pokémon. Move effects, accuracy, damage, PP and abilities use the shared battle engine.
var lanes := {"a":[-1,-1],"b":[-1,-1]}
var groups := {"a":["",""],"b":["",""]}

func start(a_team: Array,b_team: Array) -> void:
	super.start(a_team,b_team)
	if over: return
	for side in ["a","b"]:
		var team: Array = team_a if side=="a" else team_b
		if team.any(func(m):return m.has("trainer_group")):
			groups[side] = ["first","second"]
		for pos in 2: lanes[side][pos]=replacement(side,pos)
	focus(0,0)
	for side in ["a","b"]:
		if lanes[side][1]>=0:
			pair(side,1,0)
			_on_send_out(side)
	focus(0,0)

func replacement(side: String,pos: int) -> int:
	var team: Array = team_a if side=="a" else team_b
	for i in team.size():
		if i in lanes[side] or team[i].fainted: continue
		if str(team[i].get("trainer_group","")) == groups[side][pos]: return i
	return -1

func viable(side: String,pos: int) -> bool:
	if pos<0 or pos>=2: return false
	var i: int = lanes[side][pos]
	return i>=0 and not (team_a if side=="a" else team_b)[i].fainted

func choose_lane(side: String,preferred: int) -> int:
	if viable(side,preferred): return preferred
	if viable(side,1-preferred): return 1-preferred
	return -1

func focus(player_lane: int,enemy_lane: int) -> void:
	var a := choose_lane("a",player_lane)
	var b := choose_lane("b",enemy_lane)
	if a>=0: active_a = lanes.a[a]
	if b>=0: active_b = lanes.b[b]

func pair(side: String,pos: int,target: int) -> void:
	if side=="a": focus(pos,target)
	else: focus(target,pos)

func ai(side: String) -> String:
	var attacker: Dictionary = cur_a() if side=="a" else cur_b()
	var target: Dictionary = cur_b() if side=="a" else cur_a()
	var best := "move:0"
	var high := -1.0
	for i in attacker.moves.size():
		if int(attacker.pp[i])<=0: continue
		var mv: Dictionary = Data.move_of(int(attacker.moves[i]))
		var weight := float(mv.get("power",0)) * effectiveness_on(str(mv.get("type","normal")),target)
		if weight==0 and mv.get("category")=="status": weight = 14
		weight*=rng.randf_range(0.75,1.20)
		if weight>high:
			high=weight
			best="move:%d"%i
	return best

func round_actions(player_orders: Dictionary) -> void:
	if over: return
	var order := []
	for side in ["a","b"]:
		for pos in 2:
			if not viable(side,pos): continue
			var target: int = rng.randi_range(0,1)
			var command: Dictionary = player_orders.get(pos,{}) if side=="a" else {}
			target = choose_lane("b" if side=="a" else "a",int(command.get("target",target)))
			if target<0: continue
			pair(side,pos,target)
			var choice: String = command.get("move",ai(side))
			var who: Dictionary = cur_a() if side=="a" else cur_b()
			order.append({"side":side,"pos":pos,"move":choice,"target":target,"prio":_priority(side,choice),
				"speed":_speed(who)*(-1 if field.trick_room else 1),"tie":rng.randf()})
	order.sort_custom(func(l,r):
		if l.prio!=r.prio:return l.prio>r.prio
		if l.speed!=r.speed:return l.speed>r.speed
		return l.tie>r.tie)
	for action in order:
		var other := "b" if action.side=="a" else "a"
		if not viable(action.side,action.pos): continue
		var target := choose_lane(other,action.target)
		if target<0: continue
		pair(action.side,action.pos,target)
		_take_action(action.side,action.move)
		if action.move.begins_with("switch:"):
			lanes[action.side][action.pos]=active_a if action.side=="a" else active_b
	acting_side=""
	# Preserve the two active pairs for end-of-turn damage, including a fainted slot
	# until replacements enter. Never tick the same surviving Pokémon twice.
	for pos in 2:
		if lanes.a[pos]<0 or lanes.b[pos]<0: continue
		active_a=lanes.a[pos]
		active_b=lanes.b[pos]
		_end_of_turn()
		_end_of_turn_volatile()
		_end_of_turn_gmax()
		_end_of_turn_field(pos==0)
	for side in guard_turns: guard_turns[side]=maxi(0,int(guard_turns[side])-1)
	for side in ["a","b"]:
		for pos in 2:
			if viable(side,pos): continue
			var fresh := replacement(side,pos)
			lanes[side][pos]=fresh
			if fresh>=0:
				pair(side,pos,0)
				var entrant: Dictionary = (team_a if side=="a" else team_b)[fresh]
				log.append("%s 上场了！"%entrant.name)
				_on_send_out(side)
	var a_up := _any_alive(team_a)
	var b_up := _any_alive(team_b)
	if not a_up or not b_up:
		over=true
		winner="draw" if not a_up and not b_up else ("a" if a_up else "b")
	focus(0,0)
