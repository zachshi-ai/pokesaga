extends SceneTree
## Exercise saved battery, practice and real battle hooks independently of the normal-input tour.
class Game extends Node:
	var save_data:Dictionary={"party":[],"flags":{"k_starter":656}}
	func _flags()->Dictionary:return save_data.flags
	func _persist():pass

var checks:=0
var failed:=0
var wall:=200000
var monotonic:=50000

func check(ok:bool,detail:String)->void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL ",detail)

func _initialize()->void:run.call_deferred()

func run()->void:
	var o=load("res://core/kalos_opowers.gd")
	var battle_core=load("res://core/battle.gd")
	var archive=root.get_node("Data")
	archive.load_core_tables()
	var g:=Game.new()
	root.add_child(g)
	o.time=func():return wall
	o.ticks=func():return monotonic
	var party=load("res://core/party.gd")
	var lead:Dictionary=party.make(656,10,[55,1])
	g.save_data.party=[lead]
	check(o.known(g._flags(),"capture") and o.known(g._flags(),"hp"),"starters carry two powers")
	for mid in o.GIFTS:
		var map:Dictionary=archive.load_map("kalos",mid)
		check(map.get("kalos_native",false)!=false,"original room "+mid)
		if "hatch" in o.GIFTS[mid]:
			check(o.roster(map,g._flags(),[]).is_empty(),"requires both style and all powers")
			g._flags().k_o_stylish=true
		var rows:Array=o.roster(map,g._flags(),[])
		check(rows.size()==1,"Mr Bonding appears "+mid)
		if rows.size()==1:
			check(rows[0].at not in map.warps.map(func(w):return w.at),"clear door "+mid)
		for key in o.GIFTS[mid]:g._flags()["k_o_got_"+key]=true
		check(o.roster(map,g._flags(),[]).is_empty(),"Mr Bonding leaves "+mid)
	check(o.NAMES.size()==17 and o.NAMES.keys().all(func(k):return o.known(g._flags(),k)),"all local powers")
	lead.hp=1
	o.use_power(g,"hp",1)
	check(lead.hp==21 and o.recharge(g.save_data).units==8,"heals real lead and charges energy")
	lead.pp[0]=0
	o.use_power(g,"pp",1)
	check(lead.pp[0]==5 and o.recharge(g.save_data).units==6,"restores real PP")
	o.use_power(g,"atk",1)
	var empty_result:String=o.use_power(g,"capture",1)
	check(empty_result.contains("能量不足") and o.recharge(g.save_data).units==3,"refuses unpayable cost")
	wall+=240
	check(o.recharge(g.save_data).units==4,"four minute recharge")
	o.use_power(g,"capture",1)
	var battle=battle_core.new(522)
	battle.start([battle_core.make_combatant(656,10,[1])],[battle_core.make_combatant(25,10,[1])])
	o.enter_battle(g,battle)
	check(is_equal_approx(battle.kalos_o_capture,1.5),"capture bonus installed")
	battle.run_turn("move:0","move:0")
	check(battle.team_a[0].stages.atk==1 and battle.kalos_o_stages.is_empty(),"stat effect on real battle turn")
	monotonic+=200000
	o.leave_battle(g,battle)
	check(o.rank(g,"capture")==1 and o.rank(g,"atk")==0,"battle pauses timed power, consumes stat power")
	monotonic+=180000
	check(o.rank(g,"capture")==0,"timed power expires")
	for key in o.NAMES:
		wall+=240*10
		o.use_power(g,key,1)
		check(o.rank(g,key)==1 if key not in ["hp","pp"] else true,"local effect "+key)
	check(o.rank(g,"stealth")==1 and o.rank(g,"encounter")==0,"stealth replaces encounter")
	var s:={}
	var distance:=0
	for i in 4:distance+=o.hatch_steps(g,s,1)
	check(distance==5,"egg speed keeps quarter steps")
	for lv in [1,2]:
		var count:=15 if lv==1 else 30
		for i in count:
			wall+=240*10
			o.use_power(g,"bargain",lv)
		check(o.grade(g._flags(),"bargain")==lv+1,"usage unlocks next level")
	wall+=240*10
	o.use_power(g,"bargain",3)
	check(o.factor(g,"bargain")==.5,"top level shop discount")
	o.time=Callable()
	o.ticks=Callable()
	g.free()
	print("KALOS O-POWERS ", "PASS" if failed==0 else "FAIL"," ",checks," checks")
	quit(1 if failed else 0)
