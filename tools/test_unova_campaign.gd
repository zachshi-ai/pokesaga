extends SceneTree
## Check every default and optional storyline trigger with all three native starters and foreign progress.
class Game:
	var flags: Dictionary={}
	var world: Dictionary={"map_data":{},"player_pos":Vector2i.ZERO}
	func _flags() -> Dictionary:return flags

var failures:=0
func check(ok: bool, desc: String) -> void:
	if not ok:
		printerr("FAIL ",desc)
		failures+=1

func _initialize() -> void:call_deferred("run")
func run() -> void:
	var campaign=load("res://core/unova_campaign.gd")
	var db=root.get_node("Data")
	var book: Dictionary=campaign.data()
	for starter in [495,498,501]:
		var final_stage: Dictionary=campaign.evolution({"species_id":starter+1,"level":36})
		check(final_stage.get("to",0)==starter+2 and final_stage.get("form","")=="","native final stage")
		check(campaign.evolution({"species_id":starter+1,"level":36,"held":"EVERSTONE"}).is_empty(),"everstone")
		var game:=Game.new()
		game.flags={"u1_starter":starter,"u2_starter":starter,"u1_started":true,"h_champion":true,"s_champion":true,"kanto_champion":true}
		for e in book.events:
			var era:=int(e.era)
			db.set_unova_era("bw" if era==1 else "b2")
			if era==2:game.flags.u2_started=true
			game.world.map_data=db.load_map("unova",e.map)
			check(not game.world.map_data.is_empty(),"missing "+e.map)
			if game.world.map_data.is_empty():continue
			var kind: String="talk" if e.trigger.kind=="talk" else "step"
			var ctx:={"actor":e.trigger.actor}
			var early:=Game.new()
			early.world=game.world
			early.flags={"u1_started":true,"kanto_champion":true,"s_champion":true,"h_champion":true,"u2_started":era==2}
			if (e.require as Array).size()>1 or not str(e.require[0]).ends_with("_started"):
				check(campaign.event(early,kind,ctx).is_empty(),"foreign flags "+e.id)
			if e.id=="u1_dream_mist":game.flags.u1_dreamyard_cut=true
			if e.id=="u2_ship_switches":
				for i in 4:
					game.world.player_pos=campaign.SWITCHES[i]
					var physical: Dictionary=campaign.event(game,"step",{})
					check(physical.get("id","")=="u2_panel_%d"%(i+1),"original four floor switches")
					game.flags[physical.id]=true
			var found: Dictionary=campaign.event(game,kind,ctx)
			check(found.get("id","")==e.id,"current flag requirements "+e.id)
			check(campaign.gate({"region":"unova","map":e.map},game.flags).is_empty(),"map gate "+e.id)
			var rows: Array=campaign.roster(game.world.map_data,game.flags,game.world.map_data.get("npcs",[]))
			check(kind!="talk" or rows.any(func(row):return row.get("role","")==e.id),"actor "+e.id+" "+str(rows.map(func(r):return [r.name,r.at,r.get("role","")]))+" spawn "+str(game.world.map_data.get("spawn")))
			for step in e.steps:
				if not step.has("battle"):continue
				var battle: Dictionary=campaign.team(step.battle,game.flags)
				check(not battle.get("team",[]).is_empty(),"roster "+e.id)
				if battle.get("ally","")=="unova":check(not battle.ally_team.is_empty(),"ally "+e.id)
			game.flags[e.id]=true
			check(campaign.event(game,kind,ctx).is_empty(),"replay "+e.id)
		game.flags.u1_memory=true
		game.world.map_data=db.load_unova_map("unova_bw_home_1f","bw")
		check(campaign.event(game,"talk",{"actor":"u1_two_years"}).is_empty(),"memory does not restart")
		game.world.map_data=db.load_unova_map("unova_bw_home_2f","bw")
		check(campaign.event(game,"talk",{"actor":"u1_first_battle"}).is_empty(),"duplicate starter")
	print("UNOVA CHAPTER CONTRACTS ","PASS " if failures==0 else "FAILED ",book.events.size()," events × 3 starters; failures=",failures)
	quit(1 if failures else 0)
