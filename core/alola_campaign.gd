extends RefCounted
## The four adventures share one save. Only the chosen version's actors, teams and gates are visible.
const STARTERS := [722,725,728]
const NAMES := ["木木枭","火斑喵","球球海狮"]
const E4 := ["fighting","rock","ghost","flying"]
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Party := preload("res://core/party.gd")
const Field := preload("res://core/alola_field.gd")
const League := preload("res://core/alola_league.gd")
const Z := preload("res://core/alola_z.gd")
static var book: Dictionary
static var teams: Dictionary
static var trials: Dictionary
static var index: Dictionary

static func data() -> Dictionary:
	if book.is_empty():
		book=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_campaign.json"))
		for v in book:
			index[v]={}
			for e in book[v].events:index[v].get_or_add(e.map,[]).append(e)
	return book

static func version(flags: Dictionary) -> String:
	return flags.get("a_version","sun")

static func active(e: Dictionary,flags: Dictionary) -> bool:
	if flags.get(e.id,false) or (e.id=="a_poipole_return" and flags.get("a_poipole_received",false)):return false
	for key in e.require:
		if not flags.get(key,false):return false
	return true

static func events_for(mid: String,flags: Dictionary) -> Array:
	data()
	return index.get(version(flags),{}).get(mid,[])+League.event(mid,flags)

static func event(g,kind: String,ctx: Dictionary) -> Dictionary:
	if kind!="talk" or not g._flags().get("a_started",false):return {}
	for e in events_for(g.world.map_data.id,g._flags()):
		if e.id in [ctx.get("actor",""),ctx.get("local_id","")] and active(e,g._flags()):return e
	return {}

static func _anchor(m: Dictionary,key: String,used: Array) -> Array:
	var anchors: Dictionary=m.get("alola_anchors",{})
	for slot in [key]+anchors.keys():
		var at: Array=anchors.get(slot,[])
		if at.size()==2 and at not in used:return at
	return []

static func roster(m: Dictionary,flags: Dictionary,rows: Array=[]) -> Array:
	var result: Array=rows.duplicate()
	if not flags.get("a_started",false):return result
	var occupied: Array=[m.get("spawn",[])]
	for row in rows:occupied.append(row.at)
	for warp in m.get("warps",[]):occupied.append(warp.at)
	var seen: Array=[]
	for e in events_for(m.id,flags):
		if not active(e,flags):continue
		var cast: Array=[e.who]+e.get("guests",[])
		for i in cast.size():
			var who: String=cast[i]
			if who in seen:continue
			var at:=_anchor(m,e.anchor if i==0 else "guest"+str(i),occupied)
			if at.is_empty():continue
			var id: String=e.id if i==0 else "%s_guest%d"%[e.id,i]
			var appearance: String="莉莉艾（决心）" if who=="莉莉艾" and flags.get("a_lusamine",false) else who
			result.append({"at":at,"name":who,"gfx":"scientist" if who=="以太研究员" else "expert_m","alola_actor":appearance,
				"role":id,"local_id":id,"facing":"down","lines":[e.steps[0].say[0] if i==0 else "我们一起看看"+str(e.who)+"那边的情况。"]})
			occupied.append(at)
			seen.append(who)
	return result

static func gate(target: Dictionary,flags: Dictionary,_current: Dictionary={}) -> String:
	if target.get("region","alola")!="alola":return ""
	var mid: String=target.get("map","")
	if not flags.get("a_started",false):return "" if mid in ["alola_home","alola_home_1f","alola_hauoli_outskirts"] else "先从美乐美乐岛的家开始巡礼。"
	var v:=version(flags)
	var title_gate:=League.gate(mid,flags)
	if not title_gate.is_empty():return title_gate
	var boundary:=preload("res://core/alola_map_access.gd").gate(mid,v,flags,str(_current.get("id","")))
	if not boundary.is_empty():return boundary
	if mid in ["alola_altar","alola_moone"] and (mid=="alola_altar")!=v.ends_with("sun"):return "另一座祭坛属于平行世界。"
	if mid=="alola_champion_room" and not flags.get("a_champion",false):
		for n in E4:
			if not flags.get("a_elite_"+n,false):return "先完成本轮四天王的挑战。"
	var rule: Dictionary=data()[v].gates.get(mid,{})
	return rule.message if not rule.is_empty() and not flags.get(rule.require,false) else ""

static func trainer(id: int,flags: Dictionary) -> Array:
	if teams.is_empty():teams=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_trainers.json"))
	var v:=version(flags)
	var base: String="ultra_sun" if v.begins_with("ultra") else "sun"
	return teams.get(v,{}).get(str(id),teams[base].get(str(id),[])).duplicate(true)

static func team(cfg: Dictionary,flags: Dictionary) -> Dictionary:
	var resolved:=cfg.duplicate(true)
	if cfg.has("alola_totem_id"):
		if trials.is_empty():trials=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_campaign_totems.json"))
		var t: Dictionary=trials["ultrasunultramoon" if version(flags).begins_with("ultra") else "sunmoon"][str(int(cfg.alola_totem_id))]
		resolved.merge(t.duplicate(true),true)
	elif cfg.has("alola_variants") or cfg.has("alola_team"):
		var index_of:=maxi(0,STARTERS.find(int(flags.get("a_starter",0))))
		var id: int=cfg.alola_variants[index_of] if cfg.has("alola_variants") else cfg.alola_team
		resolved.team=trainer(id,flags)
		if cfg.has("alola_other"):
			for m in resolved.team:m.trainer_group="first"
			for m in trainer(int(cfg.alola_other),flags):
				m.trainer_group="second"
				resolved.team.append(m)
		if cfg.has("alola_ally"):resolved.ally_team=trainer(int(cfg.alola_ally[index_of]),flags)
	return resolved

static func partner(save: Dictionary) -> Dictionary:
	var members: Array=save.get("party",[]).duplicate()
	for box in save.get("boxes",[]):
		if box is Dictionary:members.append_array(box.get("mons",[]))
	for mon in members:
		if mon is Dictionary and mon.get("alola_partner",false) and mon.get("alola_origin",version(save.flags))==version(save.flags):return mon
	return {}

static func _room(g) -> bool:
	if Hoenn.has_room(g.save_data):return true
	Hoenn.abort_event(g)
	g._dialog(["队伍和电脑都满了。请先空出一个位置，再回来找我。"])
	return false

static func _say(g,lines: Array,who: String="") -> void:
	g._dialog(lines,who).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func _starter(g) -> void:
	g._pick("选择阿罗拉的初始伙伴",NAMES,func(i):
		var sid: int=STARTERS[i]
		var mon:=Party.make(sid,5,Field.moves_for(sid,5,g._flags()))
		Party.init_alola_ivs(mon,g.appearance_rng)
		mon.alola_partner=true
		mon.alola_origin=version(g._flags())
		mon.berry=""
		var location: String=g._store_mon(mon)
		g._flags().a_starter=sid
		g._persist()
		_say(g,[NAMES[i]+("加入了队伍！" if location=="party" else "已送入电脑，和哈乌的初战时会到你身边。")]),func():Hoenn.abort_event(g),STARTERS)

static func _capture(g,sid: int,lv: int) -> void:
	var key: String="a_caught_"+str(sid)
	if g._flags().get(key,false):
		g._story_step()
		return
	if not _room(g):return
	g._start_wild_battle(sid,lv,"",func(result):
		if result=="caught":
			g._flags()[key]=true
			g._persist()
			g._story_step()
		else:
			Hoenn.abort_event(g)
			g._dialog(["伙伴安静地等着你。准备好精灵球后，可以再来挑战。"]),"none")

static func _quiz(g,q: Dictionary) -> void:
	g._pick(q.question,q.choices,func(i):
		if i==int(q.correct):g._story_step()
		else:
			g._dialog(["再仔细观察一下。"]).closed.connect(func():_quiz(g,q),CONNECT_ONE_SHOT),func():Hoenn.abort_event(g))

static func prompt(g,act: Dictionary) -> bool:
	if act.has("alola_starter"):
		if int(g._flags().get("a_starter",0)) in STARTERS:return false
		if _room(g):_starter(g)
	elif act.has("alola_quiz"):_quiz(g,act.alola_quiz)
	elif act.has("alola_circuit"):
		var puzzle=preload("res://core/alola_trial_games.gd")
		var round_number:=int(act.alola_circuit)
		puzzle.circuit(g,round_number,[0,3,6] if round_number==0 else puzzle.GOALS[round_number-1])
	elif act.has("alola_royal"):preload("res://core/alola_trial_games.gd").royal(g)
	elif act.has("alola_z_demo"):
		preload("res://core/alola_trial_games.gd").z_lesson(g)
	elif act.has("alola_demo"):
		Hoenn.catch_demonstration(g,734,3,[33],744,5,[33],["库库伊派出岩狗狗，拦下了猫鼬少。","岩狗狗，用撞击！先降低对方的体力。","红白球落在草丛里，一下，两下……捉到了！"])
	elif act.has("alola_capture"):_capture(g,int(act.alola_capture),int(act.level))
	elif act.has("alola_poipole"):
		if g._flags().get("a_poipole_received",false):return false
		g._pick("带毒贝比一起去阿罗拉吗？",["一起出发","稍后再来"],func(i):
			if i==0:
				if not _room(g):return
				var gift:=Party.make(803,40,Field.moves_for(803,40,g._flags()))
				Party.init_alola_ivs(gift,g.appearance_rng)
				g._store_mon(gift)
				g._flags().a_poipole_received=true
				g._persist()
			if i==1 and g._flags().get("a_poipole",false):Hoenn.abort_event(g)
			else:g._story_step(),func():Hoenn.abort_event(g))
	else:return false
	return true

static func action(g,act: Dictionary) -> void:
	if act.has("alola_defend"):League.act(g,act.alola_defend)
	if act.has("alola_key") and g._bag_count(act.alola_key)==0:g._give_item(act.alola_key,1,"key")
	if act.has("alola_take") and g._bag_count(act.alola_take)>0:g._consume_item(act.alola_take)
	if act.has("alola_crystal"):Z.give(g,act.alola_crystal)
	if act.has("alola_starter_crystal"):
		var i:=STARTERS.find(int(g._flags().get("a_starter",0)))
		if i>=0:Z.give(g,["DECIDIUM_Z","INCINIUM_Z","PRIMARIUM_Z"][i])
	if act.has("alola_stamp"):g._grant_badge(act.alola_stamp)
	if act.has("alola_petals"):
		for color in ["粉红","橙色","绿色","蓝色","红色","黄色","紫色"]:
			g._consume_item(color+"花瓣")
		g._give_item("虹色之花",1,"key")
	if act.has("alola_hall"):g.johto_league.register_team(g.save_data,"alola")
	if act.has("alola_warp"):
		var m: Dictionary=g.get_node("/root/Data").load_map("alola",act.alola_warp)
		g._do_warp({"region":"alola","map":m.id,"at":m.spawn,"facing":"down"})

static func lost_league(g,stage: String) -> void:
	if stage.begins_with("a_title_"):League.clear(g._flags())
	if stage.begins_with("a_elite_") or stage=="a_champion":_reset_league(g._flags())

static func _in_league(mid: String) -> bool:
	return mid.begins_with("alola_e4_") or mid in ["alola_league","alola_champion_room"]

static func leave_league(current: Dictionary,destination: Dictionary,flags: Dictionary) -> void:
	if flags.get("a_title_active",false) and _in_league(current.get("id","")) and not _in_league(destination.get("id","")):League.clear(flags)
	if not flags.get("a_champion",false) and _in_league(current.get("id","")) and not _in_league(destination.get("id","")):_reset_league(flags)

static func _reset_league(flags: Dictionary) -> void:
	for section in E4:
		flags.erase("a_elite_"+section)
		flags.erase("story_a_elite_"+section)

static func use_fusion(g,item_name: String) -> bool:
	var solar:=item_name=="奈克洛索尔合体器"
	if not solar and item_name!="奈克洛露奈合体器":return false
	var form: String="NECROZMA_DUSK_MANE" if solar else "NECROZMA_DAWN_WINGS"
	var species: int=791 if solar else 792
	var party: Array=g.save_data.party
	var options: Array=[]
	var labels: Array=[]
	for i in party.size():
		var m: Dictionary=party[i]
		if int(m.get("species_id",0))!=800:continue
		if m.get("form","")==form and m.has("fused_part"):
			options.append([i,-1])
			labels.append("分离 · 第%d位 %s Lv.%d"%[i+1,m.name,m.level])
		elif str(m.get("form","")).is_empty() and not m.has("fused_part"):
			for j in party.size():
				var part: Dictionary=party[j]
				if int(part.get("species_id",0))==species and not part.has("fused_part"):
					options.append([i,j])
					labels.append("合体 · 第%d位奈克洛兹玛 ＋ 第%d位%s Lv.%d"%[i+1,j+1,part.name,part.level])
	if options.is_empty():
		g._dialog(["请把奈克洛兹玛和%s放进队伍。已经合体的伙伴也可以用这台仪器分离。"%("索尔迦雷欧" if solar else "露奈雅拉")],item_name)
		return true
	g._pick(item_name,labels,func(idx):_fusion_pair(g,options[idx],form,667 if solar else 668))
	return true

static func _fusion_pair(g,choice: Array,form: String,signature: int) -> void:
	var party: Array=g.save_data.party
	var nec: Dictionary=party[int(choice[0])]
	var combining: bool=int(choice[1])>=0
	var fusion=load("res://core/fusion.gd")
	var msg: String
	if combining:
		var fainted: bool=int(nec.hp)==0
		msg=fusion.fuse(party,choice[0],choice[1],form)
		if msg.is_empty():return
		Party.set_form(nec,form)
		if fainted:nec.hp=0;nec.hp_text="0/%d"%int(nec.max_hp)
	else:
		if Party.occupied(party)>=Party.MAX_SIZE:
			g._dialog(["分离后，另一位伙伴会回到队伍里。请先留出一个位置。"])
			return
		msg=fusion.unfuse(party,int(choice[0]))
		Party.set_form(nec,"")
		var index: int=nec.moves.find(signature)
		if index>=0:
			nec.moves.remove_at(index)
			nec.pp.remove_at(index)
			if nec.moves.is_empty():
				nec.moves.append(93)
				nec.pp.append(int(g.get_node("/root/Data").move_of(93).pp))
	g.save_data.party=Party.compact(party)
	load("res://core/dex_variants.gd").record(g.save_data,nec,true)
	g._persist()
	if combining:
		var slot: int=g.save_data.party.find(nec)
		g._tm_teach_one(signature,slot,g.get_node("/root/Data").move_of(signature).name,true)
	else:g._dialog([msg])
