extends RefCounted
const Party:=preload("res://core/party.gd")
const Encounter:=preload("res://core/encounter.gd")
static func observe(g) -> void:
	if not g._flags().get("sevii_network_online",false) or g._flags().get("fr_roamer_finished",false):return
	var paths: Dictionary=preload("res://core/frlg_sidequests.gd").data().roam_paths
	if not g.save_data.has("fr_roamer"):
		# FireRed's default branch is Raikou. This also covers the study edition's Pikachu.
		var sid: int={1:244,4:245}.get(int(g._flags().get("kanto_starter_species",25)),243)
		var mon:=Party.make(sid,50,Encounter.moves_for(sid,50))
		Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
		g.save_data.fr_roamer={"route":paths.keys()[g.rng.randi_range(0,paths.size()-1)],"mon":mon,"location":"","previous":0}
	var roam: Dictionary=g.save_data.fr_roamer
	var area: String=g.world.area_name().to_upper()
	var loc: String=g.world.map_data.id+"/"+area
	if loc==roam.location:return
	var old: String=roam.location
	roam.location=loc
	var adjacent: Array=paths.get(str(roam.route),[])
	var candidates: Array=paths.keys() if g.rng.randi_range(0,15)==0 or adjacent.is_empty() else adjacent.duplicate()
	var previous_route: int=int(roam.previous)
	candidates=candidates.filter(func(id):return int(id)!=previous_route)
	if not candidates.is_empty():roam.route=candidates[g.rng.randi_range(0,candidates.size()-1)]
	roam.previous=old.get_file().trim_prefix("ROUTE").to_int()

static func roll(g) -> bool:
	if not g.save_data.has("fr_roamer") or g.world.map_data.id!="kanto_main":return false
	var roam: Dictionary=g.save_data.fr_roamer
	var route:=str(g.world.area_name()).to_upper().trim_prefix("ROUTE").strip_edges().to_int()
	if int(roam.route)!=route or g.rng.randi_range(0,3)!=0:return false
	var mon: Dictionary=roam.mon
	g._start_wild_battle(int(mon.species_id),50,"",func(result):
		if result in ["caught","a"]:
			g._flags().fr_roamer_finished=true
			g.save_data.erase("fr_roamer")
		else:
			var routes: Array=preload("res://core/frlg_sidequests.gd").data().roam_paths.keys()
			routes.erase(str(roam.route))
			roam.route=routes[g.rng.randi_range(0,routes.size()-1)]
			if result=="b" and g._party_fainted():g._blackout()
		g._persist(),Party.shiny_kind(mon),0,mon)
	return true
