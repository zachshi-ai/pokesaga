extends "res://core/battle.gd"
## Three independent allies support the player's active Pokémon. They never enter the save party.
var allies: Array = []

static func stadium_team(id: String,flags: Dictionary) -> Array:
	var leaders:={"g_raid_763":841 if flags.get("g_version","sword")=="sword" else 842,"g_raid_130":834,"g_raid_324":851}
	if not leaders.has(id):return []
	var partner:=int({810:818,813:812,816:815}.get(int(flags.get("g_starter",810)),818))
	var signature:=int({818:691,812:706,815:708}[partner])
	var leader:=int(leaders[id])
	return [[partner,60,signature],[862,62,400],[leader,62,{841:716,842:715,834:242,851:643}[leader]]]

func prepare(kind: String, boss: Dictionary, helpers: Array) -> void:
	var roster := helpers
	if roster.is_empty() and kind!="solo":
		roster = [[832,52,34],[888,70,709,"ZACIAN_CROWNED"],[889,70,710,"ZAMAZENTA_CROWNED"]] if kind=="eternamax" else [[832,60,34],[862,60,400],[763,60,651]]
	for row in roster:
		var mon := make_combatant(int(row[0]),int(row[1]),[int(row[2])],str(row[3]) if row.size()>3 else "")
		allies.append(mon)
	boss.max_hp = int(boss.max_hp) * (2 if kind=="eternamax" else 3)
	boss.hp = boss.max_hp

func _side_of(mon: Dictionary) -> String:
	return "a" if allies.has(mon) else super._side_of(mon)

func _assist(attacker: Dictionary, defender: Dictionary, move_id: int) -> void:
	var move: Dictionary=Data.move_of(move_id)
	if move.is_empty():return
	log.append("%s 对 %s 使用了%s！"%[attacker.name,defender.name,move.name])
	var dealt := damage(attacker,defender,move)
	_set_hp(defender,maxi(0,int(defender.hp)-dealt),log.size()-1)
	if int(defender.hp)==0:
		defender.fainted=true
		log.append("%s 倒下了。"%defender.name)

func _take_action(side: String, choice: String) -> void:
	if side=="b" and choice.begins_with("move:"):
		var targets := [cur_a()] + allies.filter(func(m):return m.hp>0)
		var target: Dictionary = targets[rng.randi_range(0,targets.size()-1)]
		if not is_same(target,cur_a()):
			var moves: Array=cur_b().moves.filter(func(id):return int(Data.move_of(id).get("power",0))>0)
			if not moves.is_empty():
				_assist(cur_b(),target,int(moves[rng.randi_range(0,moves.size()-1)]))
				return
	super._take_action(side,choice)

func run_turn(a_choice: String,b_choice: String) -> void:
	super.run_turn(a_choice,b_choice)
	for ally in allies:
		if over:break
		if int(ally.hp)>0:
			_assist(ally,cur_b(),int(ally.moves[0]))
			_check_end()
