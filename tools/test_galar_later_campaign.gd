extends SceneTree

var failures:=PackedStringArray()
var campaign
var later
var db

class Probe:
	var world: Dictionary
	var flags: Dictionary
	func _flags() -> Dictionary:return flags

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, why: String) -> void:
	if not ok:failures.append(why)

func check_member(mon: Dictionary, context: String) -> void:
	var sid:=int(mon.species)
	check(db.species_of(sid).get("id",0)==sid,context+" species "+str(sid))
	var form:=str(mon.get("form",""))
	check(form=="" or not db.form_of(sid,form).is_empty(),context+" "+str(sid)+" has missing form "+form)
	for mv in mon.get("moves",[]):
		check(not db.move_of(int(mv)).is_empty(),context+" move "+str(mv))

func story(version: String, starter: int) -> void:
	var p:=Probe.new()
	p.flags={"g_started":true,"g_version":version,"g_starter":starter,"g_badge_1":true,"g_partner":true,"a_champion":true,"h_champion":true}
	for e in campaign.data().events:p.flags[e.id]=true
	check(campaign.gate({"region":"armor","map":"armor_dojo"},p.flags)=="","expansion blocked by mainland")
	check(campaign.gate({"map":"galar_5"},p.flags)=="","v4.64 save cannot continue")
	check(campaign.gate({"map":"galar_stadium"},p.flags)!="","foreign champions skipped cup")
	check(campaign.gate({"map":"galar_tower_summit"},p.flags)!="","early summit unlocked")
	var n:=1
	for e in later.data().events:
		if e.get("version",version)!=version:continue
		for req in e.require:
			if str(req).begins_with("g_badge_") and not p.flags.has(req):
				n+=1
				check(req=="g_badge_"+str(n) and p.flags.has("g_gym_%d_ready"%n),e.id+" gym bypass")
				p.flags[req]=true
		var m: Dictionary=db.load_map("galar",e.map)
		p.world={"map_data":m}
		check(not m.is_empty(),e.id+" map")
		check(campaign.gate({"map":e.map},p.flags)=="",e.id+" current map gated")
		var scene: Dictionary=campaign.event(p,"talk",{"actor":e.id})
		check(scene.get("id","")==e.id,e.id+" trigger")
		if scene.is_empty():continue
		var visible: Array=campaign.roster(m,p.flags,m.npcs)
		var speaker: Array=visible.filter(func(a):return a.get("role","")==e.id)
		check(speaker.size()==1,e.id+" speaker count")
		if speaker.size():
			check(speaker[0].name==scene.who and "@" not in scene.who,e.id+" identity")
			var blocked:=visible.map(func(a):return Vector2i(a.at[0],a.at[1]))
			var at:=Vector2i(e.at[0],e.at[1])
			var choices: Array=[Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
			check(choices.any(func(v):
				var c:Vector2i=at+v
				return c not in blocked and c.x>=0 and c.y>=0 and c.y<m.tiles.size() and c.x<m.tiles[c.y].size() and int(m.tiles[c.y][c.x]) not in [1,2,6,7]),e.id+" has no approach")
		for step in scene.steps:
			if not step.has("battle"):continue
			var team: Dictionary=campaign.team(step.battle,p.flags)
			for mon in team.team+team.get("ally_team",[]):check_member(mon,e.id)
			if e.id=="g_champion":
				check(int(team.team[-1].species)==6 and team.galar_gmax and team.team.size()==6,"Leon Charizard")
			if e.id in ["g_eternatus","g_eternamax"]:
				check(str(db.move_of(int(team.team[0].moves[0])).key)=="DYNAMAX_CANNON","Eternatus move")
			if e.id=="g_hop_final":
				check(int(team.team[-1].species)==(888 if version=="shield" else 889),"Hop has wrong wolf "+version)
		p.flags[e.id]=true
		check(campaign.event(p,"talk",{"actor":e.id}).is_empty(),e.id+" repeat")
	check(n==8 and p.flags.has("g_champion") and p.flags.has("g_hop_final"),"unfinished story")

func field() -> void:
	var f: Dictionary=later.field_data()
	var total:=0
	for mid in f.trainers:
		var m: Dictionary=db.load_map("galar",mid)
		for n in f.trainers[mid]:
			total+=1
			var y:=int(n.at[1]);var x:=int(n.at[0])
			check(int(m.tiles[y][x]) not in [1,2,6,7],"trainer on solid "+n.name)
			for member in n.battle.team:check_member(member,n.name)
	check(total==45,"trainer count "+str(total))
	for version in ["sword","shield"]:
		var flags={"g_version":version,"g_partner":true,"g_champion":true}
		for mid in f.encounters:
			var table: Dictionary=campaign.encounters(mid,flags)
			check(not table.pool.is_empty() and table.rate>0,"empty habitat "+mid)
			for m in table.pool:
				check_member(m,mid)
				if mid in ["galar_wild_north","galar_lake_out"]:check(int(m.min)==60 and int(m.max)==60,"champion wild levels")
		var row: Dictionary=campaign.encounters("galar_5",flags)
		check(row.pool.any(func(m):return int(m.species)==(684 if version=="sword" else 682)),"missing Route 5 exclusive")
	for mid in ["galar_6","galar_8","galar_9","galar_10","galar_slope","galar_tangle","galar_lake_out"]:
		var m: Dictionary=db.load_map("galar",mid)
		for leaf in m.hoenn_art.p:
			if "/galar/habitats/" not in str(leaf[0]):continue
			check(int(m.tiles[int(leaf[2])][int(leaf[1])])==11,"visual patch lacks encounters "+mid)
	check(later.retaliate_compatible({"species_id":145,"form":"ZAPDOS_GALAR"},f),"Galarian Zapdos TM79")
	check(not later.retaliate_compatible({"species_id":145},f),"Kanto Zapdos TM79")
	check(not later.retaliate_compatible({"species_id":129},f),"Magikarp TM79")

func run() -> void:
	campaign=load("res://core/galar_campaign.gd")
	later=load("res://core/galar_later.gd")
	db=root.get_node("Data")
	check(db.load_core_tables(),"database")
	for version in ["sword","shield"]:
		for starter in [810,813,816]:story(version,starter)
	field()
	for error in failures:push_error(error)
	print("GALAR LATER CAMPAIGN ", "PASS" if failures.is_empty() else "FAIL", " | 6 version/partner routes, 45 trainers, 13 habitats, errors=",failures.size())
	quit(0 if failures.is_empty() else 1)
