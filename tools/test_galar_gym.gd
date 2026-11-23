extends SceneTree
const Gym := preload("res://core/galar_gym.gd")
var failed:=false
var battle_script
func _initialize():call_deferred("run")
func check(pass_test:bool,label:String):
	if not pass_test:
		push_error("GALAR GYM: "+label)
		failed=true
func run():
	root.get_node("Data").load_core_tables()
	battle_script=load("res://core/battle.gd")
	var b=battle_script.new(793)
	var a:Dictionary=battle_script.make_combatant(810,50,[345,45])
	var spare:Dictionary=battle_script.make_combatant(133,50,[33])
	var ace:Dictionary=battle_script.make_combatant(830,50,[45,33])
	b.start([a,spare],[ace])
	b.galar_rules=true
	check(b.available_forms("a").is_empty(),"band and power spot required")
	b.galar_power_spot=true
	check(b.available_forms("a").is_empty(),"band required")
	b.galar_band=true
	check(b.available_forms("a").size()==1,"ordinary Grookey can Dynamax")
	var original:=int(a.max_hp)
	var species:=int(a.species_id)
	b.galar_ace=830
	a.galar_intent=true
	b.run_turn("move:0","move:0")
	check(b.galar_used.a and b.galar_used.b and a.galar_turns==2 and ace.galar_turns==2,"both sides transformed once on first move")
	check(a.max_hp==floori(1.5*original),"Dynamax HP")
	check(int(a.species_id)==species and b.galar_move(a,root.get_node("Data").move_of(45)).key=="MAX_GUARD","dex species intact and status moves map to Max Guard")
	check(a.pp[0]==root.get_node("Data").move_of(345).pp-1,"original move PP spent")
	b.run_turn("move:0","move:1")
	check(b.field.terrain=="grassy" and a.stages.spe<0 and a.galar_turns==1,"Max Overgrowth and Max Strike took effect")
	b.run_turn("move:1","move:1")
	check(not a.has("galar_turns") and not ace.has("galar_turns") and a.max_hp==original and a.hp<=original,"three turns restored original stats")
	check(b.available_forms("a").is_empty(),"cannot transform again")
	var c=battle_script.new(224)
	var eevee:Dictionary=battle_script.make_combatant(133,50,[33])
	c.start([eevee,spare],[battle_script.make_combatant(831,50,[33])])
	c.galar_rules=true;c.galar_power_spot=true;c.galar_band=true
	var maxhp:=int(eevee.max_hp)
	eevee.galar_intent=true;c.run_turn("move:0","move:0")
	c.run_turn("switch:1","move:0")
	check(c.active_a==1 and not eevee.has("galar_base_hp") and maxhp==eevee.max_hp and c.available_forms("a").is_empty(),"switch restores HP and consumes use")
	var d=battle_script.new(111)
	d.start([battle_script.make_combatant(888,70,[33])],[battle_script.make_combatant(830,50,[33])])
	d.galar_rules=true;d.galar_power_spot=true;d.galar_band=true
	check(d.available_forms("a").is_empty(),"Zacian excluded")
	if not failed:print("GALAR GYM PASS: band, venue, two independent sides, base PP, grass terrain, speed drop, three turns, switch, and restricted species")
	quit(1 if failed else 0)
