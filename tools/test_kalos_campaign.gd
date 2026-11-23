extends SceneTree
## Verify each NPC, original trainer variant, and map/room gate across X/Y and all three starters.
class Game:
	var flags: Dictionary={}
	var world: Dictionary={"map_data":{}}
	func _flags() -> Dictionary:return flags

var checks:=0
var failures:=0

func expect(ok: bool, reason: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",reason)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var campaign=load("res://core/kalos_campaign.gd")
	var cast=load("res://core/kalos_cast.gd")
	var db=root.get_node("Data")
	var book: Dictionary=campaign.data()
	var teams: Dictionary=campaign.trainer_data().teams
	expect(teams.size()==784,"original trainer records")
	expect(teams["526"][-1].held=="GYARADOSITE" and teams["276"][-1].held=="GARDEVOIRITE","two final Mega ace stones")
	expect(teams["276"].map(func(m):return int(m.species))==[701,697,699,711,706,282],"Diantha exact six species and order")
	expect(teams["276"].map(func(m):return int(m.level))==[64,65,65,65,66,68],"Diantha exact levels")
	var gym_names:=["紫罗兰","查克洛","可尔妮","福爷","希特隆","玛绣","葛吉花","得抚"]
	var league_names:=["帕琦拉","志米","雁铠","朵拉塞娜","卡露妮"]
	for who in gym_names+league_names+["弗拉达利","多罗巴","莎娜","提耶鲁诺","莎莉娜"]:
		expect(not cast.character({"kalos_actor":who}).is_empty() and cast.portrait(who)!=null,"field and dialogue character "+who)
	for version in ["x","y"]:
		for starter in [650,653,656]:
			var sim:=Game.new()
			sim.flags={"k_started":true,"k_starter":starter,"k_version":version,"kanto_champion":true,"s_champion":true,"h_champion":true,"u2_champion":true}
			for e in book.events:
				var mid: String=e.map
				var m: Dictionary=db.load_map("kalos",mid)
				expect(m.get("kalos_native",false)!=false,"Kalos geometry "+mid)
				if m.is_empty():continue
				sim.world.map_data=m
				var ctx:={"actor":e.id}
				if e.id=="k_badge_3":
					expect(campaign.event(sim,"talk",ctx).is_empty(),"skaters prevent bypass")
					for n in [83,84,146,147]:sim.flags["k_trainer_"+str(n)]=true
				if e.id=="k_badge_8":
					expect(campaign.event(sim,"talk",ctx).is_empty(),"ice switches prevent bypass")
					sim.flags.k_ice_bridge_last=true
				var isolated:=Game.new()
				isolated.world=sim.world
				isolated.flags={"k_started":true,"u2_champion":true,"s_champion":true,"h_champion":true,"kanto_champion":true}
				if e.require!=["k_started"]:
					expect(campaign.event(isolated,"talk",ctx).is_empty(),"foreign save bypass "+e.id)
				expect(campaign.event(sim,"talk",ctx).get("id","")==e.id,"missing current event "+e.id)
				expect(campaign.event(sim,"talk",{"actor":"different_actor"}).is_empty(),"wrong actor "+e.id)
				expect(campaign.gate({"region":"kalos","map":mid},sim.flags).is_empty(),"gate blocks legitimate route "+e.id)
				var rows: Array=campaign.roster(m,sim.flags,m.get("npcs",[]))
				var active: Array=rows.filter(func(r):return r.get("role","")==e.id)
				expect(active.size()==1,"visible speaker "+e.id)
				if active.size()==1:
					var pos: Array=active[0].at
					expect(pos not in m.warps.map(func(w):return w.at),"door collision "+e.id)
					expect(int(m.physics.collision[int(pos[1])][int(pos[0])])==0,"standable speaker "+e.id)
					expect(cast.character(active[0])!="","missing field appearance "+e.id)
					if e.has("on_approach"):
						sim.world.npcs=rows
						expect(campaign.event(sim,"map_enter",{"x":pos[0],"y":pos[1]}).get("id","")==e.id,"approach starts scene "+e.id)
					if e.get("on_entry",false):
						expect(campaign.event(sim,"map_enter",{"x":m.spawn[0],"y":m.spawn[1]}).get("id","")==e.id,"arrival starts scene "+e.id)
				for step in e.steps:
					if not step.has("battle"):continue
					var cfg: Dictionary=campaign.team(step.battle,sim.flags)
					expect(not cfg.get("team",[]).is_empty(),"missing battle "+e.id)
					if cfg.get("ally","")=="kalos":expect(not cfg.get("ally_team",[]).is_empty(),"missing ally "+e.id)
					if e.id=="k_first_battle":expect(int(cfg.team[0].species)=={650:656,653:650,656:653}[starter] and cfg.kalos_starter_only,"Shauna opening match")
					if e.id=="k_mega_trial":expect(cfg.kalos_trial and cfg.team[0].held=="LUCARIONITE","tower trial")
				sim.flags[e.id]=true
				expect(campaign.event(sim,"talk",ctx).is_empty(),"repeated event "+e.id)
				if not e.has("resident"):
					expect(not campaign.roster(m,sim.flags,[]).any(func(r):return r.role==e.id),"NPC left after "+e.id)
			var corridor:=sim.flags.duplicate(true)
			corridor.erase("k_parade")
			corridor.erase("k_diantha")
			campaign.leave_league({"id":"kalos_e4_malva"},{"id":"kalos_zone_247"},corridor)
			expect(corridor.has("k_elite_malva"),"return lift retains Elite wins")
			campaign.leave_league({"id":"kalos_league_hall"},{"id":"kalos_champion_stairs"},corridor)
			expect(corridor.has("k_elite_malva"),"champion stairs retain Elite wins")
			campaign.leave_league({"id":"kalos_league_lobby"},{"id":"kalos_league"},corridor)
			expect(not corridor.has("k_elite_malva"),"leaving the League clears this attempt")
			var repeat_game:=sim.flags.duplicate(true)
			campaign.leave_league({"id":"kalos_champion_room"},{"id":"kalos_home_2f"},repeat_game)
			expect(not campaign.gate({"map":"kalos_champion_room"},repeat_game).is_empty(),"champion rematch corridor")
			expect(repeat_game.k_badge_8 and repeat_game.k_champion,"championship record retained")
	for rule in book.gates:
		expect(not campaign.gate({"map":rule},{"k_started":true,"s_champion":true}).is_empty(),"external party map lock "+str(rule))
	print("KALOS CAMPAIGN ", "PASS" if failures==0 else "FAILED", " ",checks," checks, ",book.events.size()," events × 6 paths, ",failures," failures")
	quit(1 if failures else 0)
