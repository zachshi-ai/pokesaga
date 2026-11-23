extends SceneTree
## Gym rewards, Gigantamax availability, doubles and competition interference.
const League := preload("res://core/galar_league_gyms.gd")
const Giant := preload("res://core/galar_dynamax.gd")
var errors:=0

class BagProbe extends Node:
	var save_data:={"party":[]}
	var taught:int
	func _bag_count(_name):return 1
	func _pick(_title,choices,callback):
		if not choices.is_empty():callback.call(0)
	func _tm_teach_one(move:int,_slot:int,_name:String,_reusable:bool):taught=move
	func _dialog(_text):pass

func check(ok:bool,message:String):
	if not ok:
		push_error(message)
		errors+=1

func _initialize():call_deferred("run")
func run():
	var db=root.get_node("Data")
	db.load_core_tables()
	var engine=load("res://core/battle.gd")
	var doubles=load("res://core/double_battle.gd")
	var probe:=BagProbe.new()
	root.add_child(probe)
	for n in range(2,9):
		for v in ["sword","shield"]:
			var cfg:=League.section(n,{"g_version":v})
			var species:=int(League.data().machine_compatibility[str(int(cfg.move))][0])
			probe.save_data.party=[{"species_id":species,"name":"练习伙伴"}]
			probe.taught=0
			check(League.use_item(probe,League.item_name(probe,cfg)),str(cfg.leader)+" machine in actual bag dispatcher")
			check(probe.taught==int(cfg.move),str(cfg.leader)+" teaching callback")
		check(not League.ok({"g_badge_1":true,"badge_8":true},n),"needs this Gym's story qualification")
		var flags={League.key(n,"ready"):true}
		check(not League.ok(flags,n),"previous Galar badge required")
		flags["g_badge_%d"%(n-1)]=true
		check(League.ok(flags,n),"local requirements met")
	probe.queue_free()
	var field=load("res://core/world.gd").new()
	root.add_child(field)
	field.taken={"g_version":"shield"}
	for version_id in ["sword","shield"]:
		field.taken.g_version=version_id
		for n in [4,6]:
			for part in ["mission","pitch"]:
				var name:=League.id(n,part)
				field.load_map(db.load_map("galar",name))
				var path:="res://assets/galar/league_gyms/"+name+("_shield.png" if version_id=="shield" else ".png")
				var found:=false
				for layer in field._tile_nodes:
					for node in layer.get_children():
						if node is Sprite2D and node.texture!=null and node.texture.resource_path==path:found=true
				check(found,"Actual field sprite did not load "+path)
	field.queue_free()
	var b=doubles.new(472)
	var fighter:Dictionary=engine.make_combatant(68,80,[238,45])
	var pal:Dictionary=engine.make_combatant(133,80,[45])
	var rival:Dictionary=engine.make_combatant(132,80,[45])
	var ace:Dictionary=engine.make_combatant(884,80,[45,82])
	b.start([fighter,pal],[rival,ace])
	b.galar_rules=true
	b.galar_band=true
	b.galar_ace=884
	check(not Giant.available(b,"a"),"Piers-style non-spot forbids Dynamax even with the Band")
	b.galar_power_spot=true
	fighter.gmax_factor=true
	ace.gmax_factor=true
	fighter.galar_intent=true
	check(b.galar_move(fighter,db.move_of(238)).key=="G_MAX_CHI_STRIKE","pending Gigantamax previews actual signature move")
	var hp:=int(fighter.max_hp)
	var orders={0:{"move":"move:1","target":0},1:{"move":"move:0","target":0}}
	b.round_actions(orders)
	check(fighter.form=="MACHAMP_GMAX" and ace.form=="DURALUDON_GMAX","both sides can Gigantamax, including second lane")
	check(fighter.galar_turns==2 and ace.galar_turns==2 and not pal.has("galar_turns"),"both sides get one independent three-turn use")
	Giant.special_hit(b,fighter,rival,{"key":"G_MAX_CHI_STRIKE"})
	check(fighter.crit_stage==1 and pal.crit_stage==1,"Chi Strike boosted both active allies")
	pal.last_move=45
	pal.pp[0]=7
	Giant.special_hit(b,ace,pal,{"key":"G_MAX_DEPLETION"})
	check(pal.pp[0]==5,"Depletion affects last-used PP on the other lane")
	Giant.special_hit(b,fighter,rival,{"key":"G_MAX_RESONANCE"})
	check(b.field.has_screen("a","reflect") and b.field.has_screen("a","light_screen"),"Resonance protects both categories")
	Giant.special_hit(b,ace,pal,{"key":"G_MAX_TERROR"})
	check(pal.trapped,"Terror prevents switching")
	b.focus(0,1)
	ace.fainted=true
	Giant.lingering(b)
	check(not pal.trapped,"Terror released when originating lane faints")
	ace.fainted=false
	b.round_actions(orders);b.round_actions(orders)
	check(not fighter.has("galar_base_hp") and fighter.form=="" and fighter.max_hp==hp and ace.form=="","three turns restored original form/HP for both lanes")
	var wild=engine.new(72)
	var fast:Dictionary=engine.make_combatant(6,80,[53])
	var target:Dictionary=engine.make_combatant(37,24,[45])
	wild.start([fast],[target])
	var opponent:Dictionary=engine.make_combatant(273,20,[33])
	opponent=engine.normalize_team([opponent])[0]
	var record:={"won":false}
	opponent.scorecard=record
	wild.galar_competitor=opponent
	wild.galar_target_rival=true
	var initial:=int(target.hp)
	wild._take_action("a","move:0")
	check(target.hp==initial and wild.cur_b()==target and wild.galar_competitor.is_empty(),"attacking the competitor keeps the actual wild target alive")
	var wolf:Dictionary=engine.make_combatant(888,70,[45])
	var no_giant=engine.new(74)
	no_giant.start([wolf],[target]);no_giant.galar_power_spot=true;no_giant.galar_band=true
	check(not Giant.available(no_giant,"a"),"Zacian is still excluded")
	if errors==0:print("GALAR LATER GYMS PASS: 14 version-specific TM dispatches, story gates, actual G-Max previews, both double lanes, G-Max effects, restoration and competitive targeting.")
	quit(1 if errors else 0)
