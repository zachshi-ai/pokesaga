extends RefCounted

const TOWNS := {"sinnoh_twinleaf":"双叶镇","sinnoh_sandgem":"真砂镇","sinnoh_jubilife":"祝庆市","sinnoh_oreburgh":"黑金市","sinnoh_floaroma":"花苑镇","sinnoh_eterna":"百代市","sinnoh_hearthome":"家缘市","sinnoh_solaceon":"随意镇","sinnoh_veilstone":"帷幕市","sinnoh_pastoria":"野原市","sinnoh_celestic":"神和镇","sinnoh_canalave":"水脉市","sinnoh_snowpoint":"雪峰市","sinnoh_sunyshore":"滨海市","sinnoh_league":"神奥宝可梦联盟","sinnoh_fight":"对战区","sinnoh_survival":"生存区","sinnoh_resort":"名胜区"}
static var habitats: Dictionary = {}

static func field(mid: String) -> Dictionary:
	if habitats.is_empty():
		habitats=JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/habitats.json"))
	return habitats.get(mid,{})

static func lighthouse_lift(g) -> void:
	if g._escort_active: return
	g._escort_active=true
	g.panel_open+=1
	g.held_dir=""
	g.run_held=false
	g._set_hud_visible(false)
	var entry: Dictionary=g.save_data.get("return_passages",{}).get("sinnoh_vista_lighthouse_elevator",{})
	var up: bool=entry.get("map","sinnoh_sunyshore")=="sinnoh_sunyshore"
	g._show_toast("灯塔电梯上行" if up else "灯塔电梯下行")
	g.world.facing="down"
	g.snd.play_sfx("door")
	await g.get_tree().create_timer(0.45).timeout
	g._escort_active=false
	g.panel_open-=1
	g._set_hud_visible(true)
	if g.world.map_data.id!="sinnoh_vista_lighthouse_elevator": return
	g._do_warp({"region":"sinnoh","map":"sinnoh_lighthouse" if up else "sinnoh_sunyshore","at":[6,10] if up else [54,55],"facing":"down","platinum_native":true})
	g._persist()

static func land(area: Dictionary, hour: int) -> Array:
	var slots: Array=area.get("land",[])
	if slots.is_empty() or (hour>=4 and hour<10): return slots
	var species: Array = area.get("day" if hour>=10 and hour<20 else "night",[])
	if species.size()!=2: return slots
	slots=slots.duplicate(true)
	for i in 2:
		if int(species[i])>0: slots[2+i].species=species[i]
	return slots

static func fly(flags: Dictionary) -> Array:
	var spots := []
	for mid in TOWNS:
		if flags.get("s_visited_"+mid,false):
			spots.append({"name":TOWNS[mid],"map":"sinnoh/"+mid,"at":[]})
	return spots

static func partner(save: Dictionary) -> Dictionary:
	for mon in save.get("party",[]):
		if mon.get("sinnoh_partner",false): return mon
	for box in save.get("boxes",[]):
		for mon in box.get("mons",[]):
			if mon.get("sinnoh_partner",false): return mon
	return {}

const OBSTACLES := {"FieldMoves_CutTree":"cut","FieldMoves_Rock":"rock","FieldMoves_Boulder":"boulder"}
static var people: Dictionary = {}

static func populate(map: Dictionary) -> void:
	if people.is_empty(): people=JSON.parse_string(FileAccess.get_file_as_string("res://content/platinum_native/people.json"))
	for actor in map.get("npcs",[]).duplicate():
		var script := str(actor.get("source_script",""))
		if OBSTACLES.has(script):
			map.get_or_add("objects",[]).append({"at":actor.at,"legacy_at":actor.at.duplicate(),"kind":OBSTACLES[script],"platinum_obstacle":true})
			map.npcs.erase(actor)
			continue
		var gfx := str(actor.get("platinum_gfx",""))
		if gfx=="OBJ_EVENT_GFX_POKECENTER_NURSE" and ("Pokecenter" in script or "Nurse" in script):
			actor.name="护士"
			actor.heal=true
		elif script.ends_with("_CommonVendor") or script.ends_with("_SpecialtyVendor"):
			actor.name="店员"
			actor.shop=true
		elif not actor.has("name"):
			actor.name={"OBJ_EVENT_GFX_MOM":"妈妈","OBJ_EVENT_GFX_BARRY":"阿驯","OBJ_EVENT_GFX_PROF_ROWAN":"山梨博士","OBJ_EVENT_GFX_CYNTHIA":"竹兰","OBJ_EVENT_GFX_LOOKER":"帅哥","OBJ_EVENT_GFX_GRUNT_M":"银河队队员","OBJ_EVENT_GFX_GRUNT_F":"银河队队员","OBJ_EVENT_GFX_SCIENTIST_M":"研究员","OBJ_EVENT_GFX_SCIENTIST_F":"研究员"}.get(gfx,"")
		var trainer: String = actor.get("source_trainer",{}).get("id",script)
		if people.trainers.has(trainer):
			var original: Dictionary = people.trainers[trainer]
			actor.name=original.name
			actor.platinum_trainer=trainer
			actor.lines=original.lines
			actor.post=original.post
			actor.battle={"team":original.party,"double":original.double}
		elif people.speeches.has(actor.get("source_script","")):
			actor.lines=people.speeches[actor.source_script]
	for obj in map.get("objects",[]):
		if obj.get("kind")=="sign" and people.speeches.has(obj.get("source_script","")):
			obj.lines=people.speeches[obj.source_script]
			obj.text="\n".join(obj.lines)

static func challenge(g) -> bool:
	if not g._flags().get("s_starter",0) or g.panel_open or not g.cur_story.is_empty(): return false
	var world=g.world
	for actor in world.npcs:
		if not actor.has("platinum_trainer") or actor.get("defeated",false): continue
		var delta: Vector2i = {"up":Vector2i.UP,"right":Vector2i.RIGHT,"down":Vector2i.DOWN,"left":Vector2i.LEFT}.get(actor.get("facing","down"),Vector2i.DOWN)
		var pos := Vector2i(int(actor.at[0]),int(actor.at[1]))
		for n in int(actor.get("source_trainer",{}).get("sight_range",0)):
			pos+=delta
			if pos==world.player_pos:
				g.held_dir=""
				g.run_held=false
				g._talk_to_npc(actor)
				return true
			if world.is_blocked(pos) or not world._npc_at(pos).is_empty(): break
	return false
