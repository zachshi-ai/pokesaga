extends SceneTree
## Exercise event/actor dispatch with a fresh chapter, including all three starter branches.
## A separate walk-through drives the actual field and battles.
var failed := []
var checks := 0
var campaign
class Field:
	var map_data: Dictionary
	var player_pos: Vector2i
class Game:
	var world := Field.new()
	var flags := {"s_started":true}
	func _flags() -> Dictionary: return flags

func expect(ok: bool, detail: String) -> void:
	checks+=1
	if not ok: failed.append(detail)

func _initialize() -> void: run.call_deferred()

func context(g, e: Dictionary) -> Dictionary:
	var trigger: Dictionary=e.trigger
	match trigger.kind:
		"enter": return {"kind":"map_enter"}
		"talk": return {"kind":"talk","local_id":trigger.actor}
		"field","step":
			var a: Array=trigger.areas[0]
			var p: Vector2i=Vector2i(int(a[0]),int(a[1]))-campaign.origin(g.world.map_data)
			if trigger.kind=="step": g.world.player_pos=p
			return {"kind":trigger.kind,"at":p}
	return {}

func run() -> void:
	campaign=load("res://core/sinnoh_campaign.gd")
	var book: Dictionary=campaign.data()
	var index: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/index.json"))
	var db=root.get_node("Data")
	for starter in campaign.STARTERS:
		var g := Game.new()
		# Existing global medals, champions and teammates must not satisfy Sinnoh prerequisites.
		g.flags.merge({"h_champion":true,"got_dex":true,"kanto_champion":true,"johto_victory_done":true})
		for e in book.events:
			if starter==387:
				var early=Game.new()
				early.world.map_data={"source_id":e.map}
				var c_early:=context(early,e)
				if e.require!=["s_started"]:expect(campaign.event(early,c_early.kind,c_early).is_empty() or campaign.event(early,c_early.kind,c_early).id!=e.id,"cross-region "+e.id)
			var mid: String=index[e.map]
			var map: Dictionary=db.load_map("sinnoh",mid)
			var mapped: bool=map.get("platinum_native",false)
			expect(mapped,"compiled Platinum map "+mid)
			g.world.map_data=map
			var ctx := context(g,e)
			expect(campaign.gate({"region":"sinnoh","map":mid},g.flags).is_empty(),"gate "+e.id)
			var ev: Dictionary=campaign.event(g,ctx.kind,ctx)
			expect(ev.get("id","")==e.id,"trigger "+e.id+" got "+ev.get("id","missing"))
			if mapped and e.trigger.kind=="talk":
				var roster: Array=campaign.roster(map,g.flags,map.npcs)
				var actors: Array=roster.filter(func(row):return row.local_id==e.trigger.actor)
				expect(actors.size()==1,"active actor "+e.id)
				if not actors.is_empty(): expect(Vector2i(int(actors[0].at[0]),int(actors[0].at[1]))==Vector2i(int(e.trigger.at[0]),int(e.trigger.at[1]))-campaign.origin(map),"position "+e.id)
			for act in e.steps:
				if act.has("sinnoh_starter"):g.flags.s_starter=starter
				if act.has("battle"):
					var cfg: Dictionary=campaign.team(act.battle,g.flags)
					expect(not cfg.get("team",[]).is_empty(),"battle "+e.id)
					if cfg.has("ally"):
						expect(not cfg.ally_team.is_empty() and cfg.team.any(func(m):return m.trainer_group=="second"),"tag "+e.id)
					if e.id=="s_first_battle":
						expect(int(cfg.team[0].species)=={387:390,390:393,393:387}[starter],"first matchup")
					if e.id=="s_cynthia":
						expect(cfg.team.map(func(m):return int(m.species))==[442,407,468,448,350,445],"Cynthia party")
						expect(int(cfg.team[-1].level)==62,"Cynthia Garchomp")
				if act.has("flag"):g.flags[act.flag]=true
			expect(campaign.event(g,ctx.kind,ctx).get("id","")!=e.id,"no repeat "+e.id)
			g.flags=JSON.parse_string(JSON.stringify(g.flags))
		expect(g.flags.get("s_champion",false),"champion")
		for n in range(1,9):expect(g.flags.get("s_badge_%d"%n,false),"badge %d"%n)
	var loss := Game.new()
	loss.flags.merge({"s_aaron":true,"s_bertha":true,"s_league_rival":true})
	campaign.lost_league(loss,"s_flint")
	expect(not loss.flags.has("s_aaron") and not loss.flags.has("s_bertha") and loss.flags.s_league_rival,"league loss resets only gauntlet")
	var shore={"source_id":"MAP_HEADER_VERITY_LAKEFRONT"}
	var dest={"region":"sinnoh","map":"sinnoh_verity","at":[46,54]}
	expect(campaign.destination(dest,{},shore).map=="sinnoh_lake_verity_low_water","first visit lake")
	expect(campaign.destination(dest,{"s_valor_saturn":true},shore).map=="sinnoh_verity","Mars lake")
	var hall := preload("res://core/johto_league.gd").new()
	var record := {"hall_of_fame":{"sinnoh":[{"name":"帝王拿波","level":67}]}}
	expect(hall.record_lines(record,"sinnoh")[0]=="神奥联盟 · 首次冠军队伍","regional name on the Hall of Fame screen")
	print("SINNOH CAMPAIGN ",checks," checks ", "PASS" if failed.is_empty() else "FAIL"," ",failed)
	quit(0 if failed.is_empty() else 1)
