extends "res://core/battle.gd"
## Evaluate the nine native Pokéstar battle objectives at each turn boundary.
var movie: Dictionary

func run_turn(a_choice: String,b_choice: String) -> void:
	if over:return
	var used:=0
	if a_choice.begins_with("move:"):
		var slot:=int(a_choice.substr(5))
		if slot>=0 and slot<cur_a().moves.size():used=int(cur_a().moves[slot])
	super.run_turn(a_choice,b_choice)
	var k:=int(movie.rule)
	var target:=int(movie.target)
	var down:=0
	var target_down:=false
	var other_down:=false
	for foe in team_b:
		if int(foe.hp)>0:continue
		down+=1
		if int(foe.get("film_species",foe.species_id))==target:target_down=true
		else:other_down=true
	var player_down:=team_a.all(func(m):return int(m.hp)<=0)
	var all_down:=down==team_b.size()
	var last:=completed_turns>=int(movie.turns)
	var success:=false
	var fail:=false
	match k:
		0:success=all_down and down>=int(movie.turns);fail=down<completed_turns or (all_down and not success)
		1:success=all_down
		2:success=target_down and used==int(movie.move);fail=(target_down and not success) or other_down
		3:success=target_down
		4:success=target_down;fail=other_down
		5:success=not target_down and down==team_b.size()-1;fail=target_down
		6:success=last;fail=all_down
		7:success=last;fail=down>0
		8:success=player_down;fail=all_down
	if k!=8 and player_down:fail=true
	if last and not success:fail=true
	if success or fail:
		over=true
		winner="a" if success and not fail else "b"
		log.append("导演喊道：停机！")

func damage(attacker: Dictionary,defender: Dictionary,move: Dictionary) -> int:
	var dealt:=super.damage(attacker,defender,move)
	if attacker.get("held","")=="EXPERT_BELT" and effectiveness_on(str(move.get("type","")),defender)>1.0:
		dealt=roundi(dealt*1.2)
	return dealt
