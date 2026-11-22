extends RefCounted

const BOOK := "res://content/unova_campaign.json"
const Field := preload("res://core/unova_field.gd")
const Hoenn := preload("res://core/hoenn_campaign.gd")
const STARTERS := [495,498,501]
const STARTER_NAMES := ["藤藤蛇","暖暖猪","水水獭"]
const LEADERS := ["伯特","寇恩","天桐"]
const SWITCHES := [Vector2i(6,7),Vector2i(6,12),Vector2i(16,7),Vector2i(16,12)]
const ELITE := ["shauntal","grimsley","caitlin","marshal"]
static var _book: Dictionary
static var _maps: Dictionary
static var _cast: Dictionary
static var _component_key: String
static var _component: Dictionary

static func data() -> Dictionary:
	if _book.is_empty():
		_book=JSON.parse_string(FileAccess.get_file_as_string(BOOK))
		_cast=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_campaign_cast.json"))
		for e in _book.events: _maps.get_or_add(e.map,[]).append(e)
	return _book

static func chapter(flags: Dictionary) -> int:
	return 2 if Field.era(flags)=="b2" else 1

static func eligible(required: Array, flags: Dictionary) -> bool:
	for key in required:
		if not flags.get(key,false):return false
	return true

static func _active(e: Dictionary, flags: Dictionary) -> bool:
	return int(e.era)==chapter(flags) and not flags.get(e.id,false) and eligible(e.require,flags) and not (e.id=="u1_two_years" and flags.get("u2_started",false))

static func _who(name: String, flags: Dictionary) -> String:
	if name=="三曜道馆馆主":return LEADERS[maxi(0,STARTERS.find(int(flags.get("u1_starter",495))))]
	return name

static func event(g, kind: String, ctx: Dictionary) -> Dictionary:
	data()
	var flags: Dictionary=g._flags()
	if kind in ["step","map_enter"] and g.world.map_data.get("id","")=="unova_b2_zone_553" and flags.get("u2_board_ship",false) and not flags.get("u2_ship_switches",false):
		var switch_index:=SWITCHES.find(Vector2i(g.world.player_pos)+_point(g.world.map_data.get("unova_origin",[0,0])))
		var key:="u2_panel_%d"%(switch_index+1)
		if switch_index>=0 and not flags.get(key,false):
			return {"id":key,"steps":[{"flag":key},{"say":["踩下开关，隔壁传来一道电网断开的声音。"]}]}
	for entry in _maps.get(g.world.map_data.get("id",""),[]):
		if not _active(entry,flags):continue
		var trigger: Dictionary=entry.trigger
		if trigger.kind=="talk":
			if kind!="talk" or (ctx.get("actor","")!=trigger.actor and ctx.get("local_id","")!=trigger.actor):continue
		elif kind not in ["step","map_enter"]:continue
		if entry.who!="三曜道馆馆主":return entry
		var named: Dictionary=entry.duplicate(true)
		named.who=_who(entry.who,flags)
		for step in named.steps:
			if step.get("who","")==entry.who:step.who=named.who
		return named
	return {}

static func _point(at: Array) -> Vector2i:
	return Vector2i(int(at[0]),int(at[1]))

static func _component_for(map: Dictionary) -> Dictionary:
	var key: String=str(map.id)+str(map.get("unova_era",""))
	if key==_component_key:return _component
	_component_key=key
	_component={}
	var collision: Array=map.get("physics",{}).get("collision",[])
	if collision.is_empty():return _component
	var start:=_point(map.spawn)
	var pending: Array=[start]
	_component[start]=true
	var i:=0
	while i<pending.size():
		var cell: Vector2i=pending[i]
		i+=1
		for dir in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
			var dest: Vector2i=cell+dir
			if _component.has(dest) or dest.y<0 or dest.y>=collision.size() or dest.x<0 or dest.x>=collision[dest.y].size():continue
			if int(collision[dest.y][dest.x])!=0:continue
			_component[dest]=true
			pending.append(dest)
	return _component

static func _near(map: Dictionary, xy: Array, used: Dictionary) -> Array:
	if xy.size()!=2:return []
	var cell:=_point(xy)
	var comp:=_component_for(map)
	for radius in 7:
		for dx in range(-radius,radius+1):
			for dy in [radius-absi(dx),absi(dx)-radius]:
				var pos:=cell+Vector2i(dx,dy)
				if comp.has(pos) and not used.has(pos):
					var neighbors:=0
					for dir in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:
						if comp.has(pos+dir):neighbors+=1
					if neighbors>=2:return [pos.x,pos.y]
	return []

static func _actor(map: Dictionary, e: Dictionary, who: String, slot: String, used: Dictionary, flags: Dictionary) -> Dictionary:
	var name:=_who(who,flags)
	var native: Dictionary={}
	var binding: Dictionary=_cast.get(e.id,{}).get(name,{})
	var local:=int(binding.get("local_id",-1))
	for candidate in map.get("unova_cast",[]):
		if int(candidate.get("local_id",candidate.get("id",-2)))==local:
			native=candidate
			break
	var anchors: Dictionary=map.get("unova_anchors",{})
	var original: Array=native.get("at",[])
	if binding.has("source_at"):
		var local_cell:=_point(binding.source_at)-_point(map.get("unova_origin",[0,0]))
		original=[local_cell.x,local_cell.y]
	var at: Array=[]
	# Leader podiums may belong to another floor reached by the gym's lifts or rails.
	if (e.get("resident",false) or map.has("unova_mechanisms")) and original.size()==2 and not used.has(_point(original)):
		at=original
	else:at=_near(map,original,used)
	if at.size()!=2:at=_near(map,anchors.get(slot,[]),used)
	if at.size()!=2:return {}
	used[_point(at)]=true
	var role: String=e.id if slot=="story" else str(e.id)+"_"+slot
	var row: Dictionary={"at":at,"name":name,"role":role,"local_id":role,"unova_actor":name,"facing":native.get("facing","down"),"lines":[str(e.get("resident_line","我们还会再见的。"))]}
	if name=="控制面板":row.unova_prop="pc"
	elif binding.has("model"):row.unova_gfx=int(binding.model)
	if not native.is_empty():row.unova_source_actor=local
	return row

static func roster(map: Dictionary, flags: Dictionary, rows: Array) -> Array:
	data()
	var result:=[]
	var used: Dictionary={}
	var names: Dictionary={}
	var entries: Array=_maps.get(map.get("id",""),[])
	var reserved: Dictionary={}
	for e in entries:
		if int(e.era)!=chapter(flags):continue
		for binding in _cast.get(e.id,{}).values():
			if binding.has("local_id"):reserved[int(binding.local_id)]=true
	for r in rows:
		if reserved.has(int(r.get("unova_local_id",-1))):continue
		result.append(r)
		used[_point(r.at)]=true
	for w in map.get("warps",[]):used[_point(w.at)]=true
	used[_point(map.spawn)]=true
	# Active events get their native actor first, permanent Gym Leaders get the remaining positions.
	for done in [false,true]:
		for e in entries:
			if e.trigger.kind!="talk" or int(e.era)!=chapter(flags):continue
			if done:
				if not e.get("resident",false) or not flags.get(e.id,false):continue
			elif not _active(e,flags):continue
			var cast: Array=[e.who]
			if not done:cast.append_array(e.get("guests",[]))
			if e.who=="三曜道馆馆主":
				for leader in LEADERS:
					if leader!=_who(e.who,flags):cast.append(leader)
			for j in cast.size():
				var name:=_who(cast[j],flags)
				if names.has(name):continue
				var slot: String="story" if j==0 else "guest%d"%j
				var row:=_actor(map,e,name,slot,used,flags)
				if row.is_empty():continue
				if done:row.lines=["这枚徽章已经是你的了。下一个目标，就由你自己决定。"]
				result.append(row)
				names[name]=true
	return result

static func gate(target: Dictionary, flags: Dictionary, _current: Dictionary={}) -> String:
	if not eligible(target.get("unova_requires",[]),flags):return target.get("unova_denied","这条路还没有开放。")
	if target.get("region","unova")!="unova":return ""
	var mid: String=target.get("map","")
	if not mid.begins_with("unova_"):return ""
	var arc:=chapter(flags)
	if not flags.get("u1_started",false):return "" if mid in ["unova_nuvema","unova_bw_home_1f","unova_bw_home_2f"] else "先到鹿子镇，开始合众的旅程。"
	var rule: Dictionary=data().gates[str(arc)].get(mid,{})
	if not eligible(rule.get("require",[]),flags):return rule.message
	if mid=="unova_champion_room" and flags.get("u1_ghetsis" if arc==1 else "u2_champion",false):
		for key in ELITE:
			if not flags.get("u%d_again_%s"%[arc,key],false):return "再次挑战冠军前，需要在本轮重新击败四位天王。"
	return ""

static func team(cfg: Dictionary, flags: Dictionary) -> Dictionary:
	if not cfg.has("u_teams") and not cfg.has("u_variants"):return cfg
	var arc:=int(cfg.get("unova_era",chapter(flags)))
	var i:=maxi(0,STARTERS.find(int(flags.get("u%d_starter"%arc,0))))
	var keys: Array=[cfg.u_variants[i]] if cfg.has("u_variants") else cfg.u_teams
	var members: Array=[]
	for n in keys.size():
		for source in data().teams[keys[n]]:
			var pokemon: Dictionary=source.duplicate(true)
			if keys.size()>1:pokemon.trainer_group="first" if n==0 else "second"
			members.append(pokemon)
	var resolved:=cfg.merged({"team":members,"name":_who(cfg.name,flags)},true)
	if cfg.has("u_ally"):resolved.ally_team=data().teams[cfg.u_ally[i]].duplicate(true)
	return resolved

static func _clear_league(flags: Dictionary, arc: int, rematch: bool) -> void:
	for key in ELITE:
		var id:="u%d_%s%s"%[arc,"again_" if rematch else "",key]
		flags.erase(id)
		flags.erase("story_"+id)
	for key in ["alder_repeat","again_iris"]:
		flags.erase("u%d_%s"%[arc,key])

static func _league_map(map: Dictionary) -> bool:
	var zone:=str(map.get("unova_zone",""))
	return zone.begins_with("pokemon_league") or zone.begins_with("ns_castle")

static func leave_league(current: Dictionary, next_map: Dictionary, flags: Dictionary) -> void:
	if not _league_map(current) or _league_map(next_map):return
	var arc:=chapter(flags)
	var rematch:=bool(flags.get("u1_ghetsis" if arc==1 else "u2_champion",false))
	if rematch or not flags.get("u1_castle_rises" if arc==1 else "u2_iris",false):_clear_league(flags,arc,rematch)

static func lost_league(g, id: String) -> void:
	var arc:=chapter(g._flags())
	for key in ELITE+["alder","alder_repeat","iris"]:
		if id in ["u%d_%s"%[arc,key],"u%d_again_%s"%[arc,key]]:
			_clear_league(g._flags(),arc,g._flags().get("u1_ghetsis" if arc==1 else "u2_champion",false))
			return

static func _resume(g, lines: Array, who: String="") -> void:
	g._dialog(lines,who).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func _gift(g, sid: int, level: int, arc: int) -> String:
	var mon: Dictionary=load("res://core/party.gd").make(sid,level,Field.moves_for(sid,level,g._flags()))
	mon.berry=""
	if arc:mon.unova_partner=arc
	return g._store_mon(mon)

static func _room(g) -> bool:
	if Hoenn.has_room(g.save_data):return true
	Hoenn.abort_event(g)
	g._dialog(["队伍与电脑箱都满了。给新伙伴空出一个位置，再回来吧。"])
	return false

static func bed(g, front: Vector2i) -> bool:
	# Black 2 Frigate cabins 15 and 20 share these rectangular bed interaction regions.
	if g.world.map_data.get("unova_zone","") not in ["plasma_frigate_15","plasma_frigate_20"]:return false
	var cell:=front+_point(g.world.map_data.get("unova_origin",[0,0]))
	if cell.x not in [23,24,26,27] or cell.y not in [2,3,4,6,7,8,9]:return false
	g._pick("船舱的床铺很干净，要休息一下吗？",["休息","离开"],func(i):
		if i==0:
			g._heal_party()
			g._persist()
			g._dialog(["小悠和伙伴们睡了一觉，体力恢复了。"]),func():pass)
	return true

static func prompt(g, act: Dictionary) -> bool:
	var flags: Dictionary=g._flags()
	if act.get("battle",{}).get("battle_type","")=="rotation":
		var ready: Array=g.save_data.party.filter(func(m):return int(m.get("species_id",0))>0 and int(m.get("hp",0))>0 and not m.get("egg",false))
		if ready.size()<3:
			Hoenn.abort_event(g)
			g._dialog(["查尔斯：轮盘对战需要三只能够出战的伙伴。准备好以后再来找我吧！"])
			return true
	if act.has("unova_starter"):
		var arc:=int(act.unova_starter)
		var key:="u%d_starter"%arc
		if int(flags.get(key,0)) in STARTERS:return false
		if not _room(g):return true
		g._pick("选择合众的初始伙伴",STARTER_NAMES,func(i):
			var dest:=_gift(g,STARTERS[i],5,arc)
			flags[key]=STARTERS[i]
			g._persist()
			_resume(g,["%s%s。"%[STARTER_NAMES[i],"加入了队伍" if dest=="party" else "已寄存在电脑，初战时会和你一起出场"]]),func():Hoenn.abort_event(g))
		return true
	if act.has("unova_monkey"):
		if not _room(g):return true
		var i:=maxi(0,STARTERS.find(int(flags.get("u1_starter",495))))
		var sid: int=[515,511,513][i]
		var name: String=g.get_node("/root/Data").species_of(sid).name
		g._pick("带上%s吗？"%name,["一起旅行","下次再来"],func(j):
			if j==0:
				var dest:=_gift(g,sid,10,0)
				flags.u1_monkey=true
				g._persist()
				_resume(g,["%s%s。"%[name,"加入了队伍" if dest=="party" else "已送入电脑箱"]])
			else:Hoenn.abort_event(g),func():Hoenn.abort_event(g))
		return true
	if act.has("unova_dragon"):
		if flags.get("u1_reshiram_caught",false):return false
		if not _room(g):return true
		g._start_wild_battle(643,50,"",func(result):
			if result=="caught":
				flags.u1_reshiram_caught=true
				g._persist()
				g._story_step()
			else:
				Hoenn.abort_event(g)
				g._dialog(["雷希拉姆仍然在等待。整顿队伍，再次面对它吧。"]),"none")
		return true
	if act.has("unova_school"):
		var i:=maxi(0,STARTERS.find(int(flags.get("u2_starter",495))))
		var fights: Array=[]
		for entry in [["男学生",[169,747,749]],["女学生",[170,748,750]]]:
			fights.append({"battle":{"name":entry[0],"unova_era":2,"u_teams":["2/%d"%entry[1][i]]}})
			fights.append({"heal":true})
		g.story_queue=fights+g.story_queue
		g._story_step()
		return true
	if act.has("unova_pwt"):
		_pwt_pick(g,[])
		return true
	if act.has("unova_password"):
		if g._bag_count("等离子卡")<=0:
			Hoenn.abort_event(g)
			g._dialog(["面板需要等离子卡。守卫还在船上。"])
			return true
		_password(g)
		return true
	if act.has("unova_studio"):
		_film(g)
		return true
	return false

static func action(g, act: Dictionary) -> void:
	if act.has("heal") and g.cur_story.get("id","") in ["u1_first_battle","u1_cheren_home","u2_first_battle"]:
		# A transferred team may already occupy all twelve places; the opening partner can be in the PC.
		var partner: Dictionary=Field.partner(g.save_data,chapter(g._flags()))
		if not partner.is_empty():
			partner.hp=partner.max_hp
			partner.hp_text="%d/%d"%[int(partner.hp),int(partner.max_hp)]
			partner.erase("status")
			partner.pp=partner.moves.map(func(mid):return int(g.get_node("/root/Data").move_of(int(mid)).get("pp",1)))
	if act.has("unova_key") and g._bag_count(act.unova_key)==0:g._give_item(act.unova_key,1,"key")
	if act.has("unova_badge"):g._grant_badge(act.unova_badge)
	if act.has("unova_warp"):
		var map: Dictionary=g.get_node("/root/Data").load_map("unova",act.unova_warp)
		if not map.is_empty():g._do_warp({"region":"unova","map":act.unova_warp,"at":act.get("at",map.spawn),"facing":act.get("facing","down"),"unova_native":true})
	if act.has("unova_hall") or act.has("unova_repeat_hall"):
		var period: String=act.get("unova_hall",act.get("unova_repeat_hall",""))
		g.johto_league.register_team(g.save_data,"unova_"+period)
		g.johto_league.register_team(g.save_data,"unova")
		if period=="bw" or act.has("unova_repeat_hall"):_clear_league(g._flags(),chapter(g._flags()),true)
		g._flags()["u%d_hall_entries"%chapter(g._flags())]=int(g._flags().get("u%d_hall_entries"%chapter(g._flags()),0))+1

static func _password(g) -> void:
	var options:=["2202","7707","9909","捷克罗姆","雷希拉姆"]
	var clues:=["四个数字，首尾是 2，中间是 2 和 0。","四个数字，三个 7。第三位是 0。","四个数字，三个 9。第三位是 0。","象征理想的黑色传说宝可梦。","象征真实的白色传说宝可梦。"]
	var flags: Dictionary=g._flags()
	if not flags.has("u2_ship_code"):flags.u2_ship_code=randi()%options.size()
	var correct:=int(flags.u2_ship_code)
	g._pick("等离子卡提示 · "+clues[correct],options,func(i):
		if i==correct:g._story_step()
		else:
			Hoenn.abort_event(g)
			g._dialog(["面板闪出红灯。再核对一遍密码提示。"]),func():Hoenn.abort_event(g))

static func _film(g) -> void:
	var film: Dictionary=preload("res://core/unova_side_facilities.gd").data().movies[0]
	g._pick("利欧路小子，该怎么回应哈奇库侠？",["正合我意！","我该逃走了……"],func(line):
		preload("res://core/unova_side_activities.gd").film_battle(g,0,film,func(outcome):
			g._flags().u2_riolu_film_ending="good" if outcome=="a" and line==0 else "alternate"
			g._persist()
			g._story_step()),func():Hoenn.abort_event(g))

static func _pwt_pick(g, indexes: Array) -> void:
	var party: Array=g.save_data.get("party",[])
	var slots: Array=[]
	var options: Array=[]
	for i in party.size():
		if int(party[i].get("species_id",0))<=0 or i in indexes:continue
		slots.append(i)
		options.append(party[i].name)
	if indexes.size()==3 or slots.is_empty():
		if indexes.is_empty():
			Hoenn.abort_event(g)
			g._dialog(["请先带上能参赛的宝可梦。"])
			return
		var selected: Array=[]
		for i in indexes:selected.append(_pwt_mon(party[i]))
		_pwt_round(g,selected,0)
		return
	g._pick("帆巴锦标赛 · 选择第 %d 位出场伙伴"%(indexes.size()+1),options,func(i):_pwt_pick(g,indexes+[slots[i]]),func():Hoenn.abort_event(g))

static func _pwt_mon(source: Dictionary) -> Dictionary:
	var sid:=int(source.get("species",source.get("species_id",0)))
	var mon: Dictionary=load("res://core/battle.gd").make_combatant(sid,int(source.level),source.moves,str(source.get("form","")))
	for key in ["name","held","ability","shiny","shiny_kind"]:
		if source.has(key):mon[key]=source[key]
	mon.berry=source.get("berry","")
	return mon

static func _pwt_round(g, selected: Array, stage: int) -> void:
	var foe: String=["阿修","黑连","阿克罗玛"][stage]
	var pick:=maxi(0,STARTERS.find(int(g._flags().get("u2_starter",495))))
	var all_teams: Array=data().pwt
	var enemies: Array=[]
	for mon in all_teams[stage][pick if stage==0 else 0]:enemies.append(_pwt_mon(mon))
	g._start_battle({"name":foe,"battle":{"name":foe,"platinum_battle":true,"player":selected,"enemy":enemies}},func(result):
		if result!="a":
			Hoenn.abort_event(g)
			g._dialog(["这次没能捧起奖杯。再次报名就能从第一轮重新挑战。"],"大赛主持人")
		elif stage<2:_pwt_round(g,selected,stage+1)
		else:
			g.save_data.battle_points=int(g.save_data.get("battle_points",0))+1
			_resume(g,["小悠赢得了帆巴锦标赛，获得了 1 BP！"],"大赛主持人"))

static func use(g, name: String) -> bool:
	if g.world.map_data.get("region","")!="unova":return false
	match name:
		"城镇地图":g._open_world_atlas(false)
		"合众图鉴":g._open_dex()
		"C 装置":
			var flags: Dictionary=g._flags()
			var pending: Array=[]
			for row in data().events:
				if _active(row,flags) and row.route:
					var dest: Dictionary=g.get_node("/root/Data").load_map("unova",row.map)
					pending.append("%s · %s"%[str(dest.get("name","合众")), _who(row.who,flags)])
			var line: String="本篇的联盟挑战已经完成。" if pending.is_empty() else "接下来可前往："+"、".join(pending)
			g._pick("C 装置",["查看合众行程","打开地图","查看图鉴"],func(i):
				if i==0:g._dialog([line],"C 装置")
				elif i==1:g._open_world_atlas(false)
				else:g._open_dex())
		"装饰物盒":
			g._dialog(["把它带到雷文市音乐剧会馆，在团长处为宝可梦报名登台。"],name)
		"跑步鞋":g._dialog(["移动时按住 B 就能跑步。"],name)
		"光明石","等离子卡","阿克罗玛机器","给阿修的地图","龙之骨":
			var event_id: String={"光明石":"u1_reshiram","等离子卡":"u2_password","阿克罗玛机器":"u2_crustle","给阿修的地图":"u2_ranch_rival","龙之骨":"u1_skull_back"}[name]
			for e in data().events:
				if e.id!=event_id:continue
				var dest: Dictionary=g.get_node("/root/Data").load_map("unova",e.map)
				var reason: String="去%s，找%s。"%[dest.get("name","合众"),_who(e.who,g._flags())]
				if g._flags().get(e.id,false):reason="这个道具已经完成了它在故事中的用途。"
				elif not _active(e,g._flags()):reason+="先继续推进这里的故事。"
				elif g.world.map_data.id==e.map:reason="就在这里。走到%s旁边调查，就可以使用。"%_who(e.who,g._flags())
				g._dialog([reason],name)
				break
		_:return false
	return true

static func evolution(mon: Dictionary) -> Dictionary:
	var sid:=int(mon.get("species_id",0))
	var levels: Dictionary={495:17,496:36,498:17,499:36,501:17,502:36}
	if levels.has(sid) and str(mon.get("form","")).is_empty():
		if mon.get("held","")=="EVERSTONE" or int(mon.get("level",1))<int(levels[sid]):return {}
		return {"to":sid+1,"form":""}
	return preload("res://core/growth.gd").evolution_of(mon)
