extends SceneTree
## Check all four event graphs and actual source teams, NPC lifetimes and subarea locks for all starters.
class Game:
	var flags: Dictionary
	var world: Dictionary
	func _flags() -> Dictionary:return flags

var errors: Array=[]
var checks:=0
func check(value: bool,reason: String) -> void:
	checks+=1
	if not value:errors.append(reason)
func _initialize() -> void:run.call_deferred()

func run() -> void:
	var c=load("res://core/alola_campaign.gd")
	var db=root.get_node("Data")
	check(db.load_core_tables(),"core data loaded")
	var cast=load("res://core/alola_cast.gd")
	var count:=0
	for v in ["sun","moon","ultra_sun","ultra_moon"]:
		var ultra: bool=v.begins_with("ultra")
		var sun: bool=v.ends_with("sun")
		var book: Dictionary=c.data()[v]
		count+=book.events.size()
		var veteran: Dictionary={"a_started":true,"a_version":v,"k_champion":true,"s_champion":true,"h_champion":true,"u2_champion":true}
		for mid in book.gates:check(not c.gate({"map":mid},veteran).is_empty(),v+" foreign save access "+mid)
		for s in [722,725,728]:
			var f:=veteran.duplicate()
			var g:=Game.new()
			f.a_starter=s
			g.flags=f
			var found: Array=[]
			for e in book.events:
				var map: Dictionary=db.load_map("alola",e.map)
				check(map.get("alola_native",false)!=false,"missing map "+e.map)
				g.world={"map_data":map}
				if e.id=="a_poipole_return":continue
				check(c.active(e,f),v+" prerequisites "+e.id)
				var speaker: Array=c.roster(map,f,map.get("npcs",[])).filter(func(row):return row.get("role","")==e.id)
				check(speaker.size()==1,v+" missing active actor "+e.id)
				if not speaker.is_empty():
					check(not cast.character(speaker[0]).is_empty(),v+" missing artwork "+e.who)
					check(speaker[0].at not in map.warps.map(func(w):return w.at),v+" actor over exit "+e.id)
				check(c.gate({"map":e.map},f).is_empty(),v+" inaccessible current event "+e.id)
				check(c.event(g,"talk",{"actor":e.id}).get("id","")==e.id,v+" talk "+e.id)
				check(c.event(g,"talk",{"actor":"stranger"}).is_empty(),v+" wrong speaker "+e.id)
				if e.id!="a_home":check(not c.active(e,veteran),v+" foreign save bypass "+e.id)
				for step in e.steps:
					if step.has("flag"):f[step.flag]=true
					if not step.has("battle"):continue
					var b: Dictionary=c.team(step.battle,f)
					check(not b.get("team",[]).is_empty(),v+" empty trainer "+e.id)
					for m in b.get("team",[]):
						for move in m.get("moves",[]):check(not db.move_of(int(move)).is_empty(),"missing move "+str(move))
					if e.id=="a_normal":check(b.team[0].level==12 and int(b.team[0].species)==(735 if sun else 20),v+" first trial species/level")
					if e.id=="a_first_battle":check(b.alola_starter_only and int(b.team[0].species)=={722:728,725:722,728:725}[s],v+" first battle rival")
					if step.battle.has("alola_totem_id") and b.team[0].species!=746:check("TOTEM" in b.team[0].form,"boss registers its own form "+e.id)
					if e.id=="a_water":check(int(b.team[0].species)==(752 if ultra else 746),v+" water trial form")
					if e.id=="a_ultra_necrozma":check(b.team[0].form=="NECROZMA_ULTRA" and int(b.team[0].level)==60,v+" tower boss")
					if e.id=="a_champion":check(b.team.size()==6 and b.name==("哈乌" if ultra else "库库伊"),v+" champion")
				found.append(e.id)
				f[e.id]=true
				check(not c.active(e,f),v+" repeated event "+e.id)
				check(not c.roster(map,f,[]).any(func(row):return row.role==e.id),v+" actor remained "+e.id)
			check(("a_fairy" in found)==ultra and ("a_ultra_sea" in found)!=ultra,v+" wrong version route")
			f.erase("a_champion")
			c.leave_league({"id":"alola_e4_rock"},{"id":"alola_league"},f)
			check(f.has("a_elite_rock"),v+" inside league")
			c.leave_league({"id":"alola_league"},{"id":"alola_lanakila"},f)
			check(not f.has("a_elite_rock") and not c.gate({"map":"alola_champion_room"},f).is_empty(),v+" reset league")
	var league=load("res://core/alola_league.gd")
	for version in ["sun","moon","ultra_sun","ultra_moon"]:
		var ultra: bool=version.begins_with("ultra")
		var flags:={"a_version":version,"a_started":true,"a_credits":true,"a_champion":true,"a_starter":728,"a_elite_flying":true}
		check(league.challengers(flags,1,4000000)==["哈乌"],"first title defense")
		flags.a_defenses=1
		check(league.challengers(flags,1,4000000)==(["露莎米奈"] if ultra else ["扎奥博"]),"monthly challenger")
		check(("格拉吉欧" in league.challengers(flags,2,4000000))!=ultra,"Gladion after credits")
		flags.as_rr_end=true
		flags.as_rr_completed_at=1
		var pool: Array=league.challengers(flags,2,4000000)
		check("格拉吉欧" in pool and ("古兹马" in pool)==ultra and ("马睿因" in pool)!=ultra,"title version cast")
		flags.a_title_active=true
		flags.a_title_opponent="哈乌"
		check(not c.gate({"map":"alola_champion_room"},flags).is_empty(),"old Elite Four flags cannot skip defense")
		for room in league.ROOMS:
			var e: Dictionary=league.event("alola_e4_"+room,flags)[0]
			var b: Dictionary=c.team(e.steps[1].battle,flags)
			check(b.team.size()==5 and b.team[0].level==(66 if ultra else 63),"Elite rematch party "+room)
			flags[e.id]=true
		for who in pool+(["露莎米奈"] if ultra else ["扎奥博"]):
			flags.a_title_opponent=who
			var e: Dictionary=league.event("alola_champion_room",flags)[0]
			var b: Dictionary=c.team(e.steps[1].battle,flags)
			check(b.team.size()>=5 and b.team[0].level>=59 and b.name==who,"challenger party "+who)
			check(not cast.character({"name":who}).is_empty(),"challenger artwork "+who)
		c.leave_league({"id":"alola_e4_rock"},{"id":"alola_lanakila"},flags)
		check(not flags.has("a_title_active") and flags.a_champion and flags.a_credits,"defense aborted")
	check_trial_sos()
	check_trial_items(db)
	for issue in errors:printerr("FAIL ",issue)
	print("ALOLA CAMPAIGN ", "PASS" if errors.is_empty() else "FAILED", " ",checks," checks, ",count," version events x 3 starters, ",errors.size()," failures")
	quit(0 if errors.is_empty() else 1)

func check_trial_items(db) -> void:
	var battle=load("res://core/battle.gd")
	var moves: Dictionary={}
	for m in db.moves.values():moves[str(m.key)] = int(m.id)
	var marowak: Dictionary=battle.make_combatant(105,40,[moves.FLARE_BLITZ],"MAROWAK_ALOLA")
	var target: Dictionary=battle.make_combatant(784,50,[moves.TAUNT],"")
	var b=battle.new(456)
	b.alola_rules=true
	b.start([marowak],[target])
	var normal: int=b.damage(b.cur_a(),b.cur_b(),db.move_of(moves.FLARE_BLITZ))
	b.rng.seed=456
	b.cur_a().held="THICK_CLUB"
	var club: int=b.damage(b.cur_a(),b.cur_b(),db.move_of(moves.FLARE_BLITZ))
	check(club>=normal*1.8,"Alolan Marowak's Thick Club doubles physical attack")
	b.rng.seed=983
	var fairy: Dictionary=db.move_of(moves.MOONBLAST)
	var full: int=b.damage(b.cur_a(),b.cur_b(),fairy)
	b.cur_b().berry="roseli"
	b.rng.seed=983
	check(b.damage(b.cur_a(),b.cur_b(),fairy)==full/2 and b.cur_b().berry=="","Roseli blocks Fairy weakness at full health")
	b.cur_b().types=["fire"]
	b.cur_b().hp=4
	b.cur_b().berry="roseli"
	b.damage(b.cur_a(),b.cur_b(),fairy)
	check(b.cur_b().berry=="roseli","resisted Fairy attack keeps Roseli even at low HP")
	b.cur_a().held="MENTAL_HERB"
	b._take_action("b","move:0")
	check(b.cur_a().get("taunt",0)==0 and b.cur_a().held=="","Mental Herb immediately removes Taunt")
	b._take_action("b","move:0")
	check(b.cur_a().get("taunt",0)>0,"Mental Herb works once")
	b.cur_a().berry="sitrus"
	b.cur_a().hp=10
	b._try_berry(b.cur_a())
	check(b.cur_a().hp==10+b.cur_a().max_hp/4,"Gen VII Sitrus heals a quarter")
	var plant: Dictionary=battle.make_combatant(754,40,[moves.SOLAR_BLADE],"")
	b.start([plant.duplicate(true)],[battle.make_combatant(784,50,[moves.TAUNT])])
	b.cur_a().held="POWER_HERB"
	b._take_action("a","move:0")
	check(b.cur_a().held=="" and b.cur_a().get("charging",{}).is_empty() and b.cur_b().hp<b.cur_b().max_hp,"Power Herb delivers same-turn Solar Blade")
	b.start([plant.duplicate(true)],[battle.make_combatant(784,50,[moves.TAUNT])])
	b.cur_a().held="POWER_HERB"
	b.field.set_weather("sun")
	b._take_action("a","move:0")
	check(b.cur_a().held=="POWER_HERB" and b.cur_a().get("charging",{}).is_empty() and b.cur_b().hp<b.cur_b().max_hp,"sunlight skips Solar Blade charge with herb intact")
	b.start([plant.duplicate(true)],[battle.make_combatant(784,50,[moves.TAUNT])])
	b._take_action("a","move:0")
	check(not b.cur_a().get("charging",{}).is_empty() and b.cur_b().hp==b.cur_b().max_hp,"Solar Blade charges when no herb or sun is present")

func check_trial_sos() -> void:
	var double=load("res://core/double_battle.gd")
	var b=double.new(2027)
	b.alola_rules=true
	b.alola_totem={"stat":"spe","stages":1,"ally_hp":0.5,"weather":"rain"}
	b.start([b.make_combatant(725,10,[33])],[b.make_combatant(752,20,[33]),b.make_combatant(751,18,[33]),b.make_combatant(284,18,[33])])
	check(b.lanes.b==[0,-1] and b.field.weather=="rain","Brooklet starts with rain before any SOS")
	b.completed_turns=1
	check(b.replacement("b",1)==1,"Dewpider answers at high boss HP")
	b.team_b[0].hp=int(b.team_b[0].max_hp*0.6)
	check(b.replacement("b",1)==2,"totem may call Masquerain first after heavy opening damage")
	b.team_b[1].fainted=true
	check(b.replacement("b",1)==-1,"second Brooklet ally waits until below half")
	b.team_b[0].hp=int(b.team_b[0].max_hp*0.4)
	check(b.replacement("b",1)==2,"second Brooklet ally enters below half health")
	b.alola_totem={"repeat_ally":true}
	b.start([b.make_combatant(725,10,[33])],[b.make_combatant(758,22,[33]),b.make_combatant(757,20,[33])])
	b.completed_turns=2
	b.team_b[1].fainted=true
	b.team_b[1].hp=0
	check(b.replacement("b",1)==1 and not b.team_b[1].fainted and b.team_b[1].hp==b.team_b[1].max_hp,"Salazzle calls a new healthy Salandit")
