extends RefCounted
## The field script anchors use Platinum's original x,z, including its outdoor matrix.
const BOOK := "res://content/sinnoh_campaign.json"
const INDEX := "res://content/platinum_native/index.json"
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Party := preload("res://core/party.gd")
const Encounter := preload("res://core/encounter.gd")
const Side := preload("res://core/sinnoh_side.gd")
const Amity := preload("res://core/sinnoh_amity.gd")
const Villa := preload("res://core/sinnoh_villa.gd")
const STARTERS := [387,390,393]
const REMATCH := ["s_again_aaron","s_again_bertha","s_again_flint","s_again_lucian","s_again_cynthia","s_again_hall_walk","s_again_hall"]
const LEAGUE := ["s_aaron","s_bertha","s_flint","s_lucian","s_cynthia"]
static var _book: Dictionary
static var _events: Dictionary
static var _map_ids: Dictionary

static func data() -> Dictionary:
	if _book.is_empty():
		_book=JSON.parse_string(FileAccess.get_file_as_string(BOOK))
		_map_ids=JSON.parse_string(FileAccess.get_file_as_string(INDEX))
		for entry in _book.events+_book.get("postgame",[]):
			_events.get_or_add(entry.map,[]).append(entry)
	return _book

static func eligible(required: Array, flags: Dictionary) -> bool:
	for key in required:
		if not flags.get(key,false): return false
	return true

static func origin(map: Dictionary) -> Vector2i:
	var xy: Array=map.get("platinum_origin",[0,0])
	return Vector2i(int(xy[0]),int(xy[1]))

static func local_pos(map: Dictionary, at: Array) -> Array:
	var pos := Vector2i(int(at[0]),int(at[1]))-origin(map)
	return [pos.x,pos.y]

static func event(g, kind: String, ctx: Dictionary) -> Dictionary:
	var flags: Dictionary=g._flags()
	if not flags.get("s_started",false): return {}
	data()
	var map: Dictionary=g.world.map_data
	var original: Vector2i=g.world.player_pos+origin(map)
	if g.world is Node and map.get("source_id","") in [Villa.LODGE,Villa.RESORT]:
		var visit:=Villa.event(g,kind,ctx)
		if not visit.is_empty():return visit
	if map.get("source_id","")==Amity.PARK:
		var park:=Amity.step(g,kind,ctx)
		if not park.is_empty():return park
	elif g.world is Node and g.world.has_node("AmityCompanion"):
		Amity.stop(g)
	for entry in _events.get(map.get("source_id",""),[]):
		if flags.get(entry.id,false) or not eligible(entry.require,flags): continue
		var trigger: Dictionary=entry.trigger
		match trigger.kind:
			"talk":
				var actor: String=ctx.get("local_id",ctx.get("actor",""))
				if actor=="LOCALID_GALACTIC_HQ_DOOR_EAST":actor="LOCALID_GALACTIC_HQ_DOOR_WEST"
				if kind=="talk" and actor==trigger.actor:return entry
			"enter":
				if kind in ["step","map_enter"]: return entry
			"step","field":
				var coord := original
				if trigger.kind=="step":
					if kind not in ["step","map_enter"]: continue
				elif kind=="field":
					coord=Vector2i(ctx.at)+origin(map)
				else: continue
				for area in trigger.areas:
					if Rect2i(int(area[0]),int(area[1]),int(area[2]),int(area[3])).has_point(coord): return entry
	return {}

static func _overlay_row(id: String, stage: Dictionary) -> Dictionary:
	var sprite := "STRENGTH_BOULDER" if "BOULDER" in id else "CYRUS"
	if id.ends_with("_GIRATINA"): sprite="GIRATINA_ORIGIN"
	if stage.has("sprite"): sprite=stage.sprite
	if id.ends_with("_CYNTHIA"): sprite="CYNTHIA"
	if id.ends_with("_PORTAL"):
		return {"local_id":id,"source_id":id,"name":stage.name,"field_art":"sinnoh_rift","in_water_pose":true,"at":stage.at}
	return {"local_id":id,"source_id":id,"platinum_gfx":"OBJ_EVENT_GFX_"+sprite,"name":stage.name,"at":stage.at,"facing":"down"}

static func roster(map: Dictionary, flags: Dictionary, rows: Array) -> Array:
	var header: String=map.get("source_id","")
	var arcs: Dictionary=data().actors.get(header,{})
	var hidden: Dictionary=data().initial_visibility.duplicate()
	for stage in data().changes:
		if flags.get(stage,false): hidden.merge(data().changes[stage],true)
	if flags.get("s_national_dex",false): hidden["FLAG_HIDE_VICTORY_ROAD_1F_COLLECTOR"]=true
	for leader in ["aaron","bertha","flint","lucian"]:
		if header=="MAP_HEADER_POKEMON_LEAGUE_"+leader.to_upper()+"_ROOM":
			var prefix: String="s_again_" if flags.get("s_champion",false) else "s_"
			hidden["FLAG_HIDE_POKEMON_LEAGUE_"+leader.to_upper()+"_ROOM_EXIT_DOOR"]=bool(flags.get(prefix+leader,false))
	if flags.get("s_national_dex",false) and flags.get("s_fight_area_tag",false): hidden["FLAG_HIDE_FIGHT_AREA_BLOCKADE"]=true
	var departed: Dictionary={}
	var timings: Dictionary=data().get("departures",{}).get(header,{})
	for stage in timings:
		if flags.get(stage,false):departed.merge(timings[stage],true)
	var originals := rows.duplicate()
	for local in arcs:
		if str(local).begins_with("DIST_WORLD_MAP_OBJECT_"):
			originals.append(_overlay_row(local,arcs[local][0]))
	var result := []
	for original in originals:
		var local := str(original.get("local_id",original.get("source_id","")))
		if header==Amity.PARK and local=="LOCALID_FOLLOWER_MON":continue
		var visitor:=Villa.visibility(header,local,flags)
		if visitor==0:continue
		var row: Dictionary=original.duplicate()
		if arcs.has(local):
			var active: Dictionary={}
			for stage in arcs[local]:
				if eligible(stage.require,flags) and not stage.until.any(func(k): return flags.get(k,false)):
					active=stage
					break
			if active.is_empty(): continue
			if active.has("at"):
				var native_at: Array=flags.get("s_push_"+local,active.at)
				row.at=local_pos(map,native_at)
			if not active.name.is_empty(): row.name=active.name
			row.role=local
			row.erase("battle")
			row.erase("source_trainer")
			row.erase("platinum_trainer")
			if local=="LOCALID_COUNTERPART": row.platinum_gfx="OBJ_EVENT_GFX_DAWN"
		elif visitor!=1 and (departed.get(local,false) or hidden.get(row.get("source_flag",""),false)) and Side.visibility(row,flags)!=1:
			continue
		result.append(row)
	return result

static func team(cfg: Dictionary, flags: Dictionary) -> Dictionary:
	var keys: Array=cfg.get("s_teams",[])
	var choice := STARTERS.find(int(flags.get("s_starter",0)))
	if cfg.has("s_starter_teams") and choice>=0: keys=[cfg.s_starter_teams[choice]]
	if flags.get("s_charon_arrested",false) and cfg.has("s_strong_team"):keys=[cfg.s_strong_team]
	if keys.is_empty(): return cfg
	var party := []
	for i in keys.size():
		for mon in data().teams[keys[i]]:
			var row: Dictionary=mon.duplicate()
			if keys.size()>1: row.trainer_group="first" if i==0 else "second"
			party.append(row)
	var resolved := cfg.merged({"team":party},true)
	if cfg.has("s_ally") and choice>=0: resolved.ally_team=data().teams[cfg.s_ally[choice]]
	return resolved

static func destination(target: Dictionary, flags: Dictionary, current: Dictionary) -> Dictionary:
	var header: String=current.get("source_id","")
	var mid: String=target.get("map","")
	var actual := ""
	if header=="MAP_HEADER_MT_CORONET_6F" and mid in ["sinnoh_spear","sinnoh_spear_pillar_distorted","sinnoh_spear_pillar_dialga","sinnoh_spear_pillar_palkia"]:
		actual="sinnoh_spear_pillar_distorted" if flags.get("s_spear_tag",false) and not flags.get("s_giratina",false) else "sinnoh_spear"
		if flags.get("s_champion",false) and flags.get("s_spear_history",false):
			if flags.get("s_pick_VisibleItems_MtCoronet4FRooms1And2_AdamantOrb",false) and not flags.get("s_caught_483",false): actual="sinnoh_spear_pillar_dialga"
			elif flags.get("s_pick_VisibleItems_MtCoronet4FRooms1And2_LustrousOrb",false) and not flags.get("s_caught_484",false): actual="sinnoh_spear_pillar_palkia"
	elif header=="MAP_HEADER_VERITY_LAKEFRONT" and mid in ["sinnoh_verity","sinnoh_lake_verity_low_water"]:
		actual="sinnoh_verity" if flags.get("s_valor_saturn",false) else "sinnoh_lake_verity_low_water"
	elif header=="MAP_HEADER_VALOR_LAKEFRONT" and mid in ["sinnoh_valor","sinnoh_lake_valor_drained"]:
		actual="sinnoh_lake_valor_drained" if flags.get("s_library",false) and not flags.get("s_giratina",false) else "sinnoh_valor"
	elif header=="MAP_HEADER_ACUITY_LAKEFRONT" and mid in ["sinnoh_acuity","sinnoh_lake_acuity_low_water"]:
		actual="sinnoh_acuity" if flags.get("s_verity_mars",false) else "sinnoh_lake_acuity_low_water"
	if actual.is_empty(): return target
	var variants: Dictionary=target.get("platinum_alternates",{})
	if variants.has(actual): return target.merged(variants[actual],true)
	if actual==mid: return target
	return target.merged({"map":actual},true)

static func gate(target: Dictionary, flags: Dictionary, current: Dictionary={}) -> String:
	if target.get("region","")!="sinnoh" or not flags.get("s_started",false): return ""
	var mid: String=target.get("map","")
	if mid=="sinnoh_villa" and not flags.get("s_villa_deed",false):return "先在名胜区的别墅门前和原屋主见面。"
	var rule: Dictionary=data().gates.get(mid,{})
	if not rule.is_empty() and not eligible(rule.require,flags): return rule.message
	if flags.get("s_champion",false):
		var rooms := ["aaron","bertha","flint","lucian","champion"]
		for i in range(1,rooms.size()):
			if mid in ["sinnoh_pokemon_league_"+rooms[i]+"_room","sinnoh_pokemon_league_elevator_to_"+rooms[i]+"_room"] and not flags.get(REMATCH[i-1],false):return "请先战胜上一位四天王。"
		if mid in ["sinnoh_pokemon_league_hallway_to_hall_of_fame","sinnoh_pokemon_league_hall_of_fame"] and not flags.get("s_again_cynthia",false):return "请先完成本次联盟挑战。"
		if mid.begins_with("sinnoh_battle_frontier") and not flags.get("s_fight_area_tag",false):return "先在对战区门前与阿驯组队挑战电次和大叶。"
	if current.get("region","")=="sinnoh":
		var rooms := ["aaron","bertha","flint","lucian","champion"]
		for i in rooms.size():
			if current.get("id","")=="sinnoh_pokemon_league_"+rooms[i]+"_room" and mid=="sinnoh_pokemon_league_elevator_to_"+rooms[i]+"_room":
				return "身后的门已关闭，请继续向前挑战神奥联盟。"
	return ""

static func lost_league(g, id: String) -> void:
	if id not in LEAGUE and id not in REMATCH:return
	_reset_league(g._flags())

static func _reset_league(flags: Dictionary) -> void:
	var active: Array=REMATCH if flags.get("s_champion",false) else LEAGUE
	for key in active:
		flags.erase(key)
		flags.erase("story_"+key)

static func leave_league(current: Dictionary, next: Dictionary, flags: Dictionary) -> void:
	var header: String=current.get("source_id","")
	if header==Amity.PARK and next.get("source_id","")!=Amity.PARK:flags.erase(Amity.WALKER)
	if not header.begins_with("MAP_HEADER_POKEMON_LEAGUE_") or "POKECENTER" in header: return
	var dest: String=next.get("source_id","")
	if dest.begins_with("MAP_HEADER_POKEMON_LEAGUE_") and not "POKECENTER" in dest: return
	_reset_league(flags)

static func prompt(g, act: Dictionary) -> bool:
	if act.has("sinnoh_villa_offer"):
		g._pick("接下名胜区的别墅？",["收下别墅","以后再说"],func(i):
			if i==0:g._story_step()
			else:Hoenn.abort_event(g),func():Hoenn.abort_event(g))
		return true
	if act.has("sinnoh_villa"):
		Villa.handle(g,act.sinnoh_villa,act.get("value",""))
		return true
	if act.has("sinnoh_amity"):
		Amity.handle(g,act.sinnoh_amity)
		return true
	if act.has("sinnoh_strength_pass"):
		if not g._flags().get("s_hm_4",false):
			Hoenn.abort_event(g)
			g._dialog(["你还没拿到怪力吧？去码头坐船，到钢铁岛找亚玄。"],"阿驯")
		else:g._story_step()
		return true
	if act.has("sinnoh_starter"):
		if int(g._flags().get("s_starter",0)) in STARTERS: return false
		if not Hoenn.has_room(g.save_data):
			Hoenn.abort_event(g)
			g._dialog(["先在队伍或电脑里留出一个位置，再来挑选你的伙伴。"],"山梨博士")
			return true
		g._pick("选择神奥的初始伙伴",["草苗龟","小火焰猴","波加曼"],func(i):
			var id: int=STARTERS[i]
			var mon := Party.make(id,5,Side.moves_for(id,5))
			mon.sinnoh_partner=true
			var dest: String=g._store_mon(mon)
			g._flags().s_starter=id
			g._persist()
			var message := "队伍已满，它将先在初战中与你并肩战斗，随后回到电脑箱。" if dest=="box" else "它加入了你的队伍！"
			var dlg=g._dialog([str(g.get_node("/root/Data").species_of(id).name)+"回应了你。"+message])
			dlg.closed.connect(g._story_step,CONNECT_ONE_SHOT),func():Hoenn.abort_event(g))
		return true
	if act.has("sinnoh_walk"):
		_walk(g,act.sinnoh_walk)
		return true
	if act.has("sinnoh_quiz"):
		g._pick("你的回答",["是","否"],func(i):
			if i==0: g._story_step()
			else:
				Hoenn.abort_event(g)
				g._dialog(["再想一想，下次可以重新回答。"],"促销小丑"),func():Hoenn.abort_event(g))
		return true
	if act.has("sinnoh_egg"):
		if not Side.give_egg(g,int(act.sinnoh_egg),"s_togepi"):
			Hoenn.abort_event(g)
			return true
		return false
	if act.has("sinnoh_boulder"):
		_push_boulder(g,act.sinnoh_boulder)
		return true
	if act.has("sinnoh_repeat_hall"):
		var team_record := {"party":g.save_data.party,"flags":{}}
		g.johto_league.register_team(team_record,"sinnoh")
		var history: Array=g.save_data.get_or_add("sinnoh_hall_history",[])
		if history.is_empty():history.append(g.save_data.hall_of_fame.sinnoh.duplicate(true))
		g.save_data.s_hall_entries=int(g.save_data.get("s_hall_entries",1))+1
		history.append(team_record.hall_of_fame.sinnoh)
		if history.size()>30:history.pop_front()
		g._persist()
		var lines: Array=["神奥名人堂 · 本次优胜队伍"]
		for m in team_record.hall_of_fame.sinnoh:lines.append("%s　Lv.%d"%[m.name,m.level])
		var awards=g._dialog(lines,"神奥名人堂")
		awards.closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return true
	if act.has("sinnoh_hall_team"):
		var dlg=g._dialog(g.johto_league.record_lines(g.save_data,"sinnoh"),"神奥名人堂")
		dlg.closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return true
	return false

static func _walk(g, move: Dictionary) -> void:
	g._escort_active=true
	g.panel_open+=1
	g.held_dir=""
	g.run_held=false
	g._set_hud_visible(false)
	var player_path := ""
	if move.has("player_lane"):
		var lane: Array=move.player_lane
		var y: int=g.world.player_pos.y
		# A continued save may already be on the conversation tile.
		if y<=int(lane[0]) and y>int(lane[1]):
			player_path="U".repeat(y-int(lane[1]))
	await g.world.play_actor_paths(move.actor,move.path,player_path)
	g.panel_open-=1
	g._escort_active=false
	g._set_hud_visible(true)
	g._story_step()

static func _push_boulder(g, puzzle: Dictionary) -> void:
	if not Side.field_unlocked(g,"STRENGTH"):
		Hoenn.abort_event(g)
		g._dialog(["这块巨石需要用怪力推动。到钢铁岛向亚玄取得学习器，再让同行的伙伴学会怪力。"])
		return
	var local: String=g.cur_story.trigger.actor
	var map: Dictionary=g.world.map_data
	var pos: Vector2i=g.world.player_pos+g.world._dir_vec()
	var ahead: Vector2i=pos+g.world._dir_vec()
	var native := ahead+origin(map)
	var pit := Vector2i(int(puzzle.pit[0]),int(puzzle.pit[1]))
	if native==pit:
		g._flags().erase("s_push_"+local)
		g._story_step()
		return
	if "B6F" in local and native in [Vector2i(75,67),Vector2i(79,67),Vector2i(100,68),Vector2i(105,68),Vector2i(85,56),Vector2i(85,57),Vector2i(85,52),Vector2i(85,53)]:
		g._flags().erase("s_drop_"+str(puzzle.spirit))
		g._flags().erase("s_push_"+local)
		Hoenn.abort_event(g)
		g.world.refresh_story_actors(g._flags())
		g._persist()
		g._dialog(["岩石滚进了另一处深渊。在上一层可以重新找到它。"])
		return
	if g.world.is_blocked(ahead):
		Hoenn.abort_event(g)
		g._pick("前面推不动了。",["换个方向","让这块石头回到起点"],func(i):
			if i==1:
				g._flags().erase("s_push_"+local)
				g.world.refresh_story_actors(g._flags())
				g._persist())
		return
	g._flags()["s_push_"+local]=[native.x,native.y]
	Hoenn.abort_event(g)
	g.world.refresh_story_actors(g._flags())
	g.world.warp_to(pos)
	g._persist()

static func action(g, act: Dictionary) -> void:
	if act.has("sinnoh_seen"):
		for id in act.sinnoh_seen: preload("res://core/dex_variants.gd").record(g.save_data,{"species_id":id},false)
	if act.has("sinnoh_badge"): g._grant_badge(act.sinnoh_badge)
	if act.has("sinnoh_hm"): Side.give_machine(g,int(act.sinnoh_hm))
	if act.has("sinnoh_tm"): Side.give(g,"TM%02d"%int(act.sinnoh_tm))
	if act.has("sinnoh_warp"):
		data()
		var target: Dictionary=act.sinnoh_warp
		var map_id: String=_map_ids["MAP_HEADER_"+str(target.header).to_upper()]
		var map: Dictionary=g.get_node("/root/Data").load_map("sinnoh",map_id)
		g._do_warp({"map":map_id,"region":"sinnoh","at":local_pos(map,target.at),"platinum_native":true})
