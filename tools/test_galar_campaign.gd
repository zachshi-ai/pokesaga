extends SceneTree

var Campaign
var errors:=PackedStringArray()

class StoryProbe:
	var world: Dictionary
	var flags: Dictionary
	func _flags() -> Dictionary:return flags

func check(ok: bool,message: String) -> void:
	if not ok:errors.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Campaign=load("res://core/galar_campaign.gd")
	var db=root.get_node("Data")
	check(db.load_core_tables(),"load species and moves")
	for v in ["sword","shield"]:
		for starter: int in Campaign.STARTERS:
			var probe:=StoryProbe.new()
			probe.flags={"g_started":true,"g_version":v,"g_starter":starter,"a_champion":true,"h_champion":true}
			check(not Campaign.gate({"map":"galar_turffield_pitch_room"},probe.flags).is_empty(),"foreign badges unlocked Galar")
			for e in Campaign.data().events:
				var m: Dictionary=db.load_map("galar",e.map)
				probe.world={"map_data":m}
				check(not m.is_empty(),"missing "+e.map)
				check(Campaign.gate({"map":e.map},probe.flags)=="","locked current scene "+e.id)
				var npcs: Array=Campaign.roster(m,probe.flags,m.npcs)
				var actor:=npcs.filter(func(n):return n.get("role","")==e.id)
				check(actor.size()==1,"missing actor "+e.id)
				check(Campaign.event(probe,"talk",{"actor":e.id}).get("id","")==e.id,"talk "+e.id)
				check(Campaign.event(probe,"talk",{"actor":"aliased"}).is_empty(),"foreign actor "+e.id)
				for npc in npcs:
					if npc.get("role","").begins_with(e.id):
						var p:=Vector2i(npc.at[0],npc.at[1])
						check(not m.tiles[p.y][p.x] in [1,2,6,7],"actor on wall "+e.id+" "+npc.name)
						check(npc.at!=m.spawn,"actor on spawn "+e.id)
				for step in e.steps:
					if not step.has("battle"):continue
					var cfg: Dictionary=Campaign.team(step.battle,probe.flags)
					var st:=str(cfg.get("galar_hop",""))
					if st!="":
						var party: Array=cfg.ally_team if st=="ally" else cfg.team
						check(int(party[-1].species)==Campaign.STARTERS[(Campaign.STARTERS.find(starter)+2)%3],"wrong Hop partner")
					for mon in cfg.team:
						check(db.species_of(int(mon.species)).get("id",0)==int(mon.species),"bad foe "+e.id)
						check(mon.get("form","")=="" or not db.form_of(int(mon.species),mon.form).is_empty(),"missing form "+e.id)
				probe.flags[e.id]=true
				check(Campaign.event(probe,"talk",{"actor":e.id}).is_empty(),"repeat "+e.id)
			check(Campaign.gate({"map":"galar_5"},probe.flags)!="","future route open")
			probe.flags.g_badge_1=true
			check(Campaign.gate({"map":"galar_5"},probe.flags)=="","old world blocked after badge")
			check(Campaign.encounters("galar_1",{}).get("rate",1)==0,"wild before starter")
	var items=load("res://core/galar_items.gd")
	for id in [810,813,816,25,52,745]:check(items.swift_compatible({"species_id":id}),"missing Swift compatible species "+str(id))
	for form in ["MEOWTH_GALAR","FARFETCHD_GALAR","LYCANROC_MIDNIGHT","LYCANROC_DUSK"]:
		var base_id: int=52 if form=="MEOWTH_GALAR" else (83 if form=="FARFETCHD_GALAR" else 745)
		check(not items.swift_compatible({"species_id":base_id,"form":form}),"wrongly taught Swift "+form)
	check(not items.swift_compatible({"species_id":129}),"Magikarp learned Swift")
	var battle_script=load("res://core/battle.gd")
	for pair in [["MIRACLE_SEED",22],["CHARCOAL",52],["MYSTIC_WATER",55]]:
		var engine=battle_script.new(647)
		engine.galar_rules=true
		engine.start([battle_script.make_combatant(151,60,[pair[1]])],[battle_script.make_combatant(143,60,[33])])
		var before: int=engine.rng.state
		var baseline: int=engine.damage(engine.cur_a(),engine.cur_b(),db.move_of(pair[1]))
		engine.rng.state=before
		engine.cur_a().held=pair[0]
		var boosted: int=engine.damage(engine.cur_a(),engine.cur_b(),db.move_of(pair[1]))
		check(boosted>baseline and absf(float(boosted)-1.2*baseline)<=1.2,"incorrect Galar item damage "+str(pair[0]))
	for e in Campaign.data().side_events:
		var m: Dictionary=db.load_map("galar",e.map)
		check(int(m.tiles[int(e.at[1])][int(e.at[0])]) not in [1,2,6,7],"side event on wall "+e.id)
	for mid in Campaign.data().trainers:
		var map_data: Dictionary=db.load_map("galar",mid)
		var roster: Array=Campaign.roster(map_data,{"g_started":true,"g_catching":true},map_data.npcs)
		check(roster.filter(func(n):return n.has("battle")).size()==Campaign.data().trainers[mid].size(),"road trainers "+mid)
	for v in ["sword","shield"]:
		var flags={"g_partner":true,"g_version":v}
		for mid in Campaign.data().encounters:
			var habitat: Dictionary=Campaign.encounters(mid,flags)
			for row in habitat.pool:
				check(db.species_of(int(row.species)).get("id",0)==int(row.species),"encounter species "+mid)
				check(row.get("form","")=="" or not db.form_of(int(row.species),row.form).is_empty(),"encounter form "+mid)
		var fire_id:=37 if v=="sword" else 58
		check(Campaign.encounters("galar_3",flags).pool.any(func(m):return int(m.species)==fire_id),"exclusive Route 3 species "+v)
	for err in errors:push_error(err)
	print("GALAR CHAPTER ",("PASS " if errors.is_empty() else "FAIL "),6*Campaign.data().events.size()," version/starter events; errors=",errors.size())
	quit(1 if errors.size() else 0)
