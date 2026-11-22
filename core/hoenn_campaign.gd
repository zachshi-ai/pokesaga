extends RefCounted

const BOOK := "res://content/hoenn_campaign.json"
const Items := preload("res://core/hoenn_items.gd")
const STARTERS := [252,255,258]
const LEAGUE := ["h_sidney","h_phoebe","h_glacia","h_drake","h_wallace"]
static var _book: Dictionary
static var _by_map: Dictionary = {}
static var _story_npcs: Dictionary = {}

static func data() -> Dictionary:
	if _book.is_empty():
		_book = JSON.parse_string(FileAccess.get_file_as_string(BOOK))
		for e in _book.events:
			if not _by_map.has(e.map): _by_map[e.map] = []
			_by_map[e.map].append(e)
			if e.trigger.kind=="talk": _story_npcs.get_or_add(e.map,{})[int(e.trigger.actor)] = true
	return _book

static func role(i: int) -> String:
	return "h_actor_%d" % i

static func eligible(req: Array, flags: Dictionary) -> bool:
	for key in req:
		if not flags.get(key,false): return false
	return true

static func roster(map: Dictionary, flags: Dictionary, rows: Array) -> Array:
	var orig := str(map.get("emerald_original",""))
	var actors: Dictionary = data().actors.get(orig,{})
	var result := []
	var native_flags := flags.duplicate()
	for change in data().source_visibility:
		if flags.get(change.flag,false): native_flags.merge(change.changes,true)
	for source in rows:
		var row: Dictionary = source.duplicate(true)
		var local := int(row.get("local_id",0))
		var stages: Array = actors.get(str(local),[])
		var overridden: int = Items.actor_visibility(row,flags,str(map.get("source_id","")))
		if overridden == 0: continue
		if not stages.is_empty():
			var active := false
			for stage in stages:
				if eligible(stage.require,flags) and not stage.until.any(func(k): return flags.get(k,false)):
					row.at = stage.at
					if stage.name: row.name = stage.name
					active = true
					break
			if not active and overridden != 1: continue
		elif overridden != 1 and not preload("res://core/hoenn_field.gd").visible(row,native_flags): continue
		if orig=="MossdeepCity_SpaceCenter_1F" and local==9 and flags.has("h_stair_guard_at"):
			row.at=flags.h_stair_guard_at
		if orig=="SootopolisCity" and local==18 and flags.has("h_gym_door_at"):
			row.at=flags.h_gym_door_at
		if _story_npcs.get(orig,{}).has(local):
			# Only the campaign script may initiate these battles. Native scripts still
			# contain their original unconditional trainerbattle command.
			row.erase("battle")
			if row.has("source_trainer"):row.rematch_trainer=row.source_trainer
			row.erase("source_trainer")
		if local:
			row.role = role(local)
			if str(row.get("source_gfx","")).ends_with("VAR_0") and row.get("name","")=="小遥":
				row.source_gfx = "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL"
		result.append(row)
	if orig=="Route102" and flags.get("h_wally_outing",false) and not flags.get("h_wally_catch",false):
		result.append(data().tutorial_wally.duplicate(true))
	return result

static func event(g, kind: String, ctx: Dictionary) -> Dictionary:
	var flags: Dictionary = g._flags()
	var mp: String = g.world.map_data.get("emerald_original","")
	if not flags.get("h_started",false) or mp.is_empty(): return {}
	data()
	for e in _by_map.get(mp,[]):
		if not eligible(e.require,flags) or flags.get(e.id,false): continue
		var t: Dictionary = e.trigger
		match t.kind:
			"enter":
				if kind not in ["map_enter","step"]: continue
			"step":
				if kind not in ["map_enter","step"]: continue
				var r: Array = t.area
				var pos: Vector2i = g.world.player_pos
				if pos.x<r[0] or pos.x>=r[2] or pos.y<r[1] or pos.y>=r[3]: continue
			"talk":
				if kind!="talk" or ctx.get("actor","")!=role(int(t.actor)): continue
			"field":
				if kind!="field" or Vector2i(int(t.at[0]),int(t.at[1]))!=ctx.get("at"): continue
			_: continue
		return e
	return {}

static func gate(target: Dictionary, flags: Dictionary, current: Dictionary={}) -> String:
	var here: String=current.get("id","")
	if flags.get("h_started",false) and not flags.get("h_champion",false) and data().league_back.get(here,"") == target.get("map","_"):
		return "身后的门已经关闭。请向前挑战下一位丰缘联盟成员。"
	if target.get("region","")!="hoenn" or not flags.get("h_started",false): return ""
	if target.get("map","")=="em_mossdeep_city_space_center_2f" and not flags.get("h_rocket",false): return ""
	var rule: Dictionary = data().gates.get(target.get("map",""),{})
	return str(rule.message) if not rule.is_empty() and not eligible(rule.require,flags) else ""

static func team(cfg: Dictionary, flags: Dictionary) -> Dictionary:
	var keys := []
	if cfg.has("starter_teams"):
		var choice := STARTERS.find(int(flags.get("h_starter",0)))
		if choice >= 0: keys.append(cfg.starter_teams[choice])
	elif cfg.has("emerald_team"): keys.append(cfg.emerald_team)
	elif cfg.has("emerald_teams"): keys = cfg.emerald_teams
	if keys.is_empty(): return cfg
	var party := []
	for i in keys.size():
		for source in data().teams[keys[i]]:
			var mon: Dictionary = source.duplicate()
			if keys.size()>1: mon.trainer_group="first" if i==0 else "second"
			party.append(mon)
	return cfg.merged({"team":party},true)

static func abort_event(g) -> void:
	g.story_queue.clear()
	g.cur_story = {}
	g.story_abort = false

static func has_room(save: Dictionary) -> bool:
	var party = load("res://core/party.gd")
	if party.occupied(save.get("party",[])) < party.MAX_SIZE: return true
	var boxes: Array = save.get("boxes",[])
	if boxes.size() < party.BOX_COUNT: return true
	for i in party.BOX_COUNT:
		if boxes[i] is Dictionary and party.occupied(boxes[i].get("mons",[])) < party.BOX_SIZE: return true
	return false

static func prompt(g, act: Dictionary) -> bool:
	if act.has("hoenn_hall_team"):
		var ceremony=g._dialog(g.johto_league.record_lines(g.save_data,"hoenn"),"丰缘名人堂")
		ceremony.closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return true
	if act.has("hoenn_starter"):
		var flags: Dictionary = g._flags()
		if int(flags.get("h_starter",0)) in STARTERS: return false
		if not has_room(g.save_data):
			abort_event(g)
			g._dialog(["队伍和电脑箱都满了。先腾出一个位置，再从博士的背包里挑选伙伴。"],"小田卷博士")
			return true
		g._pick("博士的背包里有三个精灵球",["木守宫","火稚鸡","水跃鱼"],func(i):
			var sid: int = STARTERS[i]
			flags.h_starter = sid
			var dest: String = g._add_to_team(sid,5)
			g._persist()
			var feedback: String = "%s加入了队伍！" % g.get_node("/root/Data").species_of(sid).name if dest=="party" else "现有12位伙伴继续同行。%s已送入电脑箱，先借它帮博士解围。" % g.get_node("/root/Data").species_of(sid).name
			var d = g._dialog([feedback])
			d.closed.connect(g._story_step,CONNECT_ONE_SHOT),func(): abort_event(g))
		return true
	if act.has("hoenn_transport"):
		var options: Array = act.hoenn_transport.filter(func(r): return not r.has("require") or g._flags().get(r.require,false))
		g._pick("请选择目的地",options.map(func(r): return r.name),func(i):
			g._do_warp(options[i].target)
			g._story_step(),func(): abort_event(g))
		return true
	if act.has("hoenn_pillar_choice"):
		g._pick("烈空坐会在哪里？",["烟囱山","送神山","天空之柱"],func(i):
			if i==2:
				g._story_step()
			else:
				abort_event(g)
				g._dialog(["那儿似乎没有关于烈空坐的传说。再想想，131号水路上有什么？"],"米可利"),func(): abort_event(g))
		return true
	if act.has("hoenn_challenge"):
		var question=g._dialog(["我们要轮流和你比试！有把握连打三场吗？"],"熔岩队手下")
		question.ask("接受挑战","先下楼")
		question.answered.connect(func(yes: bool):
			if not yes:
				abort_event(g)
				g._do_warp({"region":"hoenn","map":"hoenn_space_center","at":[13,2],"hoenn_native":true}))
		question.closed.connect(func():
			if not g.cur_story.is_empty(): g._story_step(),CONNECT_ONE_SHOT)
		return true
	if act.has("hoenn_actor_walk"):
		actor_walk(g,act.hoenn_actor_walk)
		return true
	if act.has("hoenn_wally_tutorial"):
		wally_tutorial(g)
		return true
	if act.has("hoenn_weather_scene"):
		weather_scene(g)
		return true
	return false

static func actor_walk(g, move: Dictionary) -> void:
	g._escort_active=true
	g.panel_open+=1
	g.held_dir=""
	g.run_held=false
	g._set_hud_visible(false)
	if move.has("cast"):
		var temporary: Dictionary=g._flags().duplicate()
		temporary["h_"+str(move.cast)]=true
		g.world.refresh_story_actors(temporary)
	var path: String=move.get("path","")
	if move.get("stairs",false):
		if g.world.facing=="left":
			path="L"
			g._flags().h_stair_guard_at=[12,2]
		else:
			# From below, the guard steps aside without walking through the player.
			path="R" if g.world.facing=="up" else "D"
			g._flags().h_stair_guard_at=[14,2] if path=="R" else [13,3]
	if move.get("gym_door",false):
		path="L" if g.world.facing=="left" else "R"
		g._flags().h_gym_door_at=[30,33] if path=="L" else [32,33]
	await g.world.play_actor_paths(role(int(move.id)),path,"")
	g.panel_open-=1
	g._escort_active=false
	g._set_hud_visible(true)
	g._story_step()

static func wally_tutorial(g) -> void:
	var battle_core=load("res://core/battle.gd")
	var learner: Dictionary=battle_core.make_combatant(263,7,[33])
	var ralts: Dictionary=battle_core.make_combatant(280,5,[45])
	var overlay=CanvasLayer.new()
	overlay.layer=6
	g.add_child(overlay)
	var ui=load("res://scenes/battle_ui.gd").new()
	overlay.add_child(ui)
	ui.backdrop="grass"
	ui.setup([learner],[ralts],141)
	ui.state="watch"
	ui.menu.hide()
	ui.move_menu.hide()
	g.panel_open+=1
	g._escort_active=true
	g.held_dir=""
	g._set_hud_visible(false)
	ui.msg.text="满充派出了千里借给他的蛇纹熊。"
	await g.get_tree().create_timer(0.9).timeout
	ui.msg.text="满充：蛇纹熊，用撞击！"
	ui.battle.run_turn("move:0","move:0")
	var advance_hp=func(h: float): ui._draw_hp(ui.enemy_hp,roundi(h),int(ralts.max_hp))
	var tween=g.create_tween()
	tween.tween_method(advance_hp,float(ralts.max_hp),float(ralts.hp),0.45)
	await tween.finished
	ui.msg.text="满充投出精灵球……抓到拉鲁拉丝了！"
	ui.enemy_sprite.hide()
	await g.get_tree().create_timer(0.95).timeout
	overlay.queue_free()
	g.panel_open-=1
	g._escort_active=false
	g._set_hud_visible(true)
	g._story_step()

static func weather_scene(g) -> void:
	var original: Vector2i = g.world.player_pos
	g.world.warp_to(Vector2i(31,42))
	g._escort_active = true
	g.held_dir = ""
	g.run_held = false
	g.panel_open += 1
	g._set_hud_visible(false)
	g.world.refresh_story_actors(g._flags().merged({"h_scene":true},true))
	await g.world.play_actor_paths(role(11),"DDD","")
	await g.world.play_actor_paths(role(9),"LL","")
	await g.world.play_actor_paths(role(10),"RR","")
	g.world.refresh_story_actors(g._flags().merged({"h_peace":true},true))
	g.world.warp_to(original)
	g._escort_active = false
	g.panel_open -= 1
	g._set_hud_visible(true)
	g._story_step()

static func action(g, act: Dictionary) -> void:
	if act.has("hoenn_badge"): g._grant_badge(act.hoenn_badge)
	if act.has("hoenn_item"):
		if act.hoenn_item=="ITEM_RUNNING_SHOES": g._flags().h_running_shoes = true
		if Items.grant(g,act.hoenn_item): g._show_toast("获得了"+Items.name_for(act.hoenn_item)+"！")
	if act.has("hoenn_take"): Items.take(g,act.hoenn_take)
	if act.has("hoenn_seen"):
		load("res://core/dex_variants.gd").record(g.save_data,{"species_id":act.hoenn_seen},false)
	if act.has("hoenn_tm"):
		var db = g.get_node("/root/Data")
		for item_name in db.tm_map:
			if int(db.tm_map[item_name])==int(act.hoenn_tm):
				g._give_item(item_name,1,"tm")
				g._show_toast("获得了%s · %s！" % [item_name,db.move_of(int(act.hoenn_tm)).name])
				break

static func leave_league(current: Dictionary, next: Dictionary, flags: Dictionary) -> void:
	if current.get("region","")!="hoenn" or flags.get("h_wallace",false): return
	var room: String = current.get("id","")
	var dest: String = next.get("id","")
	var halls: Array = data().league_back.values()
	if (room in halls or data().league_back.has(room)) and not (dest in halls or data().league_back.has(dest)):
		reset_league(flags)

static func reset_league(flags: Dictionary) -> void:
	for f in LEAGUE:
		flags.erase(f)
		flags.erase("story_"+f)

static func lost_league(g, id: String) -> void:
	if id not in LEAGUE: return
	reset_league(g._flags())
	var center := {"region":"hoenn","map":str(data().events.filter(func(e):return e.id=="h_league")[0].map_id),"at":[3,3],"hoenn_native":true}
	g.save_data.last_pokemon_center = center
	g.save_data.get_or_add("centers",{})["hoenn"] = center
