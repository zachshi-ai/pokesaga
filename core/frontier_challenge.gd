extends RefCounted
const Rules := preload("res://core/frontier_rules.gd")
const Dome := preload("res://core/frontier_dome.gd")
const Maze := preload("res://core/frontier_maze.gd")
const PIKE := "em_battle_frontier_battle_pike_three_path_room"
const TENTS := {"slateport":"factory","verdanturf":"palace","fallarbor":"arena"}
const TENT_PRIZES := {"slateport":"万灵药","verdanturf":"巢穴球","fallarbor":"厉害伤药"}
const RUN := "h_frontier_run"
const PASS_ITEM := "开拓通行证"

static func book(g) -> Dictionary:
	return g.save_data.get_or_add("emerald_frontier",{"bp":0,"records":{},"symbols":{},"best":{}})

static func passbook(g) -> void:
	var b:=book(g)
	var lines: Array=["对战点数　%d BP" % int(b.bp)]
	for kind in Rules.NAMES:
		var level: int=b.symbols.get(kind,0)
		lines.append("%s　%s%s象征" % [Rules.NAMES[kind],["未取得 · ","银 · ","金 · "][level],Rules.SYMBOLS[kind]])
	g._dialog(lines,"开拓通行证")

static func talk(g,npc: Dictionary) -> bool:
	var name_text:=str(npc.get("source_script",""))
	var map_id:=str(g.world.map_data.id)
	var f: Dictionary=g._flags().get(RUN,{})
	if map_id==Maze.FLOOR and npc.has("frontier_key") and f.get("kind","")=="pyramid":
		var key:=str(npc.frontier_key)
		if key in f.cleared:g._dialog(["出口在这一层更深处。"]);return true
		if name_text=="BattlePyramid_FindItemBall":
			f.cleared.append(key)
			var bag: Dictionary=f.get_or_add("kit",{})
			var item: String=["好伤药","活力碎片","万灵药"][randi()%3]
			bag[item]=int(bag.get(item,0))+1
			g._persist()
			g._dialog(["捡到%s，放进了金字塔背包。" % item])
		else:
			f.current_tile=key
			f.opponent=Rules.draw(f,1)
			start_battle(g,f)
		return true
	if map_id==PIKE and f.get("kind","")=="pike":
		if name_text.ends_with("HintGiver"):g._dialog(["%s那扇门后%s。" % [["左边","中间","右边"][int(f.hint)],["传来训练家的脚步声","有两个声音","有人在轻声吟唱","传来树叶摩擦声","有人能治疗伙伴","静悄悄的"][int(f.doors[int(f.hint)])]]])
		else:manage(g,f)
		return true
	if map_id=="em_battle_frontier_reception_gate":
		if not name_text.get_slice("_EventScript_",1) in ["Greeter","FrontierPassGuide","FacilityGuide","RulesGuide"]:return false
		if not g._flags().get("h_champion",false):g._dialog(["登记名人堂后，欢迎来挑战七种赛制。"]);return true
		if g._bag_count(PASS_ITEM)==0:
			g._give_item(PASS_ITEM,1,"key");g._persist()
			g._dialog(["这是你的开拓通行证，七枚象征和赢得的点数都会记在上面。"],"开拓区接待员")
		else:passbook(g)
		return true
	if map_id=="em_battle_frontier_scotts_house" and name_text.ends_with("_Scott"):
		scott(g);return true
	if map_id=="em_battle_frontier_lounge7" and name_text.ends_with("MoveTutor"):
		tutor(g,name_text.ends_with("RightMoveTutor"));return true
	if map_id=="em_battle_frontier_ranking_hall" and name_text.ends_with("Attendant"):
		var best: Dictionary=book(g).best
		var rows: Array=[]
		for k in best:rows.append("%s　%d" % [record_name(str(k)),int(best[k])])
		g._dialog(rows if not rows.is_empty() else ["纪录板等待你的第一次挑战。"],"最高纪录")
		return true
	if map_id=="em_battle_frontier_exchange_service_corner" and name_text.contains("Clerk"):
		exchange(g,name_text.get_slice("_EventScript_",1));return true
	if not name_text.ends_with("Attendant") or not ("_lobby" in map_id):return false
	var kind: String=""
	var pack: String="main"
	for k in Rules.NAMES:
		if "_battle_frontier_battle_"+k+"_lobby" in map_id:kind=k;break
	for k in TENTS:
		if k+"_town_battle_tent_lobby" in map_id or k+"_city_battle_tent_lobby" in map_id:
			kind=TENTS[k];pack=k;break
	if kind=="":return false
	if pack=="main" and not g._flags().get("h_champion",false):
		g._dialog(["请先在丰缘联盟登入名人堂。"],"接待员");return true
	if name_text.ends_with("LinkMultisAttendant"):
		g._dialog(["这个柜台供两位训练家联机组队。旁边的多人赛柜台可以邀请场内训练家。"]);return true
	var mode: String="多人" if name_text.ends_with("MultisAttendant") else ("双打" if name_text.ends_with("DoublesAttendant") else "单打")
	if not f.is_empty():
		if f.lobby!=map_id or f.mode!=mode:
			g._pick("还有一项进行中的挑战。",["保留挑战","退出原挑战"],func(i):
				if i==1:finish(g,f,false))
		else:manage(g,f)
	else:
		var labels:=["等级 50","公开等级","查看纪录"] if pack=="main" else ["参加挑战","查看纪录"]
		g._pick(("%s · %s"%[Rules.NAMES[kind],mode]) if pack=="main" else "对战帐篷",labels,func(i):
			if i==labels.size()-1:passbook(g);return
			prepare(g,kind,pack,mode,i==1))
	return true

static func record_name(key: String) -> String:
	var parts:=key.split("|")
	return "%s · %s · %s" % [Rules.NAMES.get(parts[0],parts[0]),parts[1],parts[2]]

static func prepare(g, kind: String, pack: String, mode: String, open_level: bool) -> void:
	if pack=="main" and g._bag_count(PASS_ITEM)==0:g._give_item(PASS_ITEM,1,"key")
	var key:="%s|%s|%s" % [kind if pack=="main" else pack,mode,"公开" if open_level else "定级"]
	var f: Dictionary={"kind":kind,"pack":pack,"mode":mode,"record":key,"level":50 if pack=="main" else 30,"open":open_level,
		"lobby":g.world.map_data.id,"return_at":[g.world.player_pos.x,g.world.player_pos.y],"wins":int(book(g).records.get(key,0)),
		"stage":"entry","team":[],"opponent":{},"party_slots":[]}
	var options: Array=[]
	if kind=="factory":
		if open_level:f.level=100
		options=Rules.draw(f,6).team
	else:
		for m in g.save_data.party:
			if m is Dictionary and not m.is_empty() and not m.get("is_egg",false) and int(m.get("hp",0))>0 and int(m.get("species_id",0)) not in Rules.BANNED:
				if pack=="main" and not open_level and int(m.level)>50:continue
				options.append(m)
	var amount:=4 if mode=="双打" and kind=="tower" else (2 if mode=="多人" else 3)
	if options.size()<amount:
		g._dialog(["请带 %d 只不同种类的可参赛宝可梦。等级 50 组只接受 50 级及以下的队员，较高等级可以报名公开组。" % amount],"接待员");return
	choose_team(g,f,options,[],amount,func(selected):
		if kind!="factory":
			if open_level or pack!="main":
				for m in selected:f.level=maxi(f.level,int(m.level))
			for m in selected:f.team.append(Rules.owner_team(m,mini(int(m.level),int(f.level))))
		else:f.team=selected.duplicate(true)
		if mode=="多人":
			var ally: Array=Rules.draw(f,2).team
			for m in f.team:m.trainer_group="first"
			for m in ally:m.trainer_group="second";f.team.append(m)
		g._flags()[RUN]=f
		g._persist()
		next_stage(g,f))

static func choose_team(g,f: Dictionary,options: Array,selected: Array,amount: int,cb: Callable) -> void:
	if selected.size()==amount:cb.call(selected);return
	var available: Array=[]
	for mon in options:
		var held:=str(mon.get("held",""))
		var berry:=str(mon.get("berry",""))
		if selected.any(func(x):return int(x.species_id)==int(mon.species_id) or held!="" and x.get("held","")==held or berry!="" and x.get("berry","")==berry):continue
		available.append(mon)
	if available.is_empty():g._dialog(["可参赛队员不足。请换用不同种类、不同携带物。"]);return
	var opts:=available.map(func(m):return "%s　Lv.%d" % [m.name,m.level])
	g._pick("选出第 %d / %d 只%s" % [selected.size()+1,amount,"租用宝可梦" if f.kind=="factory" else "宝可梦"],opts+["取消"],func(i):
		if i<available.size():choose_team(g,f,options,selected+[available[i]],amount,cb))

static func manage(g,f: Dictionary) -> void:
	var opts:=["继续挑战","退出挑战"]
	if f.kind=="pyramid" and f.has("kit"):opts.insert(1,"金字塔背包")
	g._pick("%s　纪录 %d" % [Rules.NAMES[f.kind],f.wins],opts,func(i):
		if opts[i]=="退出挑战":finish(g,f,false);return
		if opts[i]=="金字塔背包":kit_menu(g,f);return
		if f.stage=="battle":start_battle(g,f)
		elif f.stage=="swap":swap_menu(g,f)
		elif f.stage=="dome":dome_select(g,f)
		elif f.stage=="paths":warp(g,PIKE,[6,8])
		elif f.stage=="floor" and g.world.map_data.id!=Maze.FLOOR:warp(g,Maze.FLOOR,Maze.apply(g.get_node("/root/Data").load_map("hoenn",Maze.FLOOR),f).spawn)
		elif f.stage=="floor":return
		else:next_stage(g,f))


static func warp(g,id: String,at: Array) -> void:
	g._do_warp({"region":"hoenn","map":id,"at":at,"hoenn_native":true})
	g._persist()

static func next_stage(g,f: Dictionary) -> void:
	if f.pack=="main" and f.kind=="pike" and Rules.symbol_at(f)==0:
		f.stage="paths"
		f.doors=[randi()%6,randi()%6,randi()%6]
		f.hint=randi()%3
		warp(g,PIKE,[6,8]);return
	if f.pack=="main" and f.kind=="pyramid" and not f.get("at_peak",false):
		f.stage="floor"
		f.floor_seed=randi()
		f.cleared=[]
		f.kit=f.get("kit",{"好伤药":1,"活力碎片":1})
		var generated:=Maze.apply(g.get_node("/root/Data").load_map("hoenn",Maze.FLOOR),f)
		warp(g,Maze.FLOOR,generated.spawn);return
	f.opponent=Dome.opponent(f) if f.kind=="dome" else Rules.opponent(f)
	if f.kind=="dome":
		f.stage="dome";g._persist();dome_select(g,f);return
	start_battle(g,f)

static func dome_select(g,f: Dictionary) -> void:
	var opponents: Array=f.opponent.team
	var stage: String=["十六强","八强","半决赛","决赛"][4-int(log(float(f.bracket.size()))/log(2.0))]
	g._pick("对战巨蛋 · "+stage,["查看对手并选出两只","查看锦标赛对阵表"],func(i):
		if i==1:
			var lines: Array=[]
			for j in range(0,f.bracket.size(),2):
				lines.append("%s　对　%s" % [f.bracket[j].name,f.bracket[j+1].name])
			g._dialog(lines,"锦标赛对阵表").closed.connect(func():dome_select(g,f))
			return
		g._dialog(["对手%s，登记队员为%s。请选两只上场。" % [f.opponent.name,"、".join(opponents.map(func(m):return m.name))]],"赛前情报").closed.connect(func():
			choose_team(g,f,f.team,[],2,func(selected):
				f.dome_team=selected
				start_battle(g,f))))


static func battle_room(f: Dictionary) -> String:
	if f.pack!="main":return str(f.lobby).trim_suffix("_lobby")+"_battle_room"
	if f.kind=="pike":return "em_battle_frontier_battle_pike_room_final" if Rules.symbol_at(f)>0 else "em_battle_frontier_battle_pike_room_normal"
	if f.kind=="pyramid":return ""
	if f.kind=="tower" and f.mode=="多人":return "em_battle_frontier_battle_tower_multi_battle_room"
	return "em_battle_frontier_battle_%s_battle_room" % f.kind

static func resume(g) -> void:
	var f: Dictionary=g._flags().get(RUN,{})
	if f.is_empty() or f.get("stage","")!="battle" or is_instance_valid(g.active_battle):return
	if g.world.map_data.id in [battle_room(f),Maze.FLOOR,"em_battle_frontier_battle_pyramid_top"]:
		manage(g,f)

static func start_battle(g,f: Dictionary) -> void:
	if not is_instance_valid(g) or is_instance_valid(g.active_battle):return
	f.stage="battle"
	var room:=battle_room(f)
	if not room.is_empty() and room!=g.world.map_data.id:
		var m: Dictionary=g.get_node("/root/Data").load_map("hoenn",room)
		warp(g,room,m.spawn)
	g._persist()
	var layer:=CanvasLayer.new()
	layer.layer=3
	g.add_child(layer)
	var doubles: bool=f.mode in ["双打","多人"] or f.get("pike_double",false)
	var ui=load("res://scenes/double_battle_ui.gd").new() if doubles else load("res://scenes/battle_ui.gd").new()
	layer.add_child(ui)
	ui.frontier_rules=Rules.new()
	ui.frontier_rules.kind=f.kind
	if f.kind=="pyramid":ui.frontier_kit=func():kit_menu(g,f,ui)
	g.active_battle=ui
	g.held_dir=""
	g._set_hud_visible(false)
	var mine: Array=f.get("dome_team",f.team).duplicate(true)
	var foe: Array=f.opponent.team.duplicate(true)
	if f.kind=="dome":foe=foe.slice(0,2)
	ui.setup(mine,foe,randi(),[],f.opponent.name)
	if f.mode=="多人":ui.companion=true
	if doubles:ui.battle.palace=f.kind=="palace"
	ui.finished.connect(func(result):
		g.active_battle=null
		g._set_hud_visible(true)
		layer.queue_free()
		if not g._flags().has(RUN):return
		if result!="a":finish(g,f,false);return
		if f.kind in ["pike","pyramid"]:
			for i in mini(f.team.size(),ui.battle.team_a.size()):
				for key in ["hp","pp","status","fainted"]:f.team[i][key]=ui.battle.team_a[i].get(key,f.team[i].get(key))
		f.erase("pike_double")
		if f.kind=="pyramid" and f.has("current_tile"):
			f.cleared.append(f.current_tile)
			f.erase("current_tile")
			f.stage="floor";g._persist();return
		advance(g,f))

static func advance(g,f: Dictionary) -> void:
	var b:=book(g)
	var symbol:=Rules.symbol_at(f)
	if f.kind=="dome" and f.has("bracket"):Dome.advance(f)
	if symbol>0:b.symbols[f.kind]=maxi(symbol,int(b.symbols.get(f.kind,0)))
	f.wins=int(f.wins)+1
	b.records[f.record]=f.wins
	b.best[f.record]=maxi(int(b.best.get(f.record,0)),f.wins)
	if int(f.wins)%Rules.size_of_set(f)==0:
		var prize: String
		if f.pack=="main":
			var row: Array=Rules.data().bp[mini(Rules.data().bp.size()-1,floori(float(f.wins)/Rules.size_of_set(f))-1)][Rules.NAMES.keys().find(f.kind)]
			var mode_i:=1 if f.mode=="双打" else (2 if f.mode=="多人" else 0)
			var points:=int(row[mini(row.size()-1,mode_i)])+(10 if symbol>0 else 0)
			b.bp=mini(9999,int(b.bp)+points)
			prize="本组完成，获得 %d BP。" % points
		else:
			var item: String=TENT_PRIZES[f.pack]
			g._give_item(item,1,"ball" if item.ends_with("球") else "heal")
			prize="三连胜！领到了%s。" % item
		if symbol:prize+=" 获得%s%s象征！" % ["银" if symbol==1 else "金",Rules.SYMBOLS[f.kind]]
		finish(g,f,true)
		g._dialog([prize],"接待员");return
	f.erase("at_peak")
	f.stage="ready"
	if f.kind not in ["pyramid","pike"] and g.world.map_data.id!=f.lobby:warp(g,f.lobby,f.return_at)
	g._persist()
	if f.kind=="factory":f.stage="swap";g._persist();swap_menu(g,f)
	elif f.kind=="pyramid" or f.kind=="pike":next_stage(g,f)
	else:manage(g,f)

static func swap_menu(g,f: Dictionary) -> void:
	g._pick("与刚才的对手交换一只租用宝可梦？",["继续使用本队","交换"],func(i):
		if i==0:next_stage(g,f);return
		g._pick("归还哪一只？",f.team.map(func(m):return m.name),func(slot):
			var candidates: Array=f.opponent.team.filter(func(m):return not f.team.any(func(t):return t!=f.team[slot] and int(t.species_id)==int(m.species_id)))
			if candidates.is_empty():next_stage(g,f);return
			g._pick("换入哪一只？",candidates.map(func(m):return m.name),func(idx):
				f.team[slot]=candidates[idx].duplicate(true)
				next_stage(g,f))))

static func field_step(g) -> bool:
	var f: Dictionary=g._flags().get(RUN,{})
	if f.is_empty() or not g.world.pending_warp.is_empty():return false
	var mid: String=g.world.map_data.id
	var pos: Vector2i=g.world.player_pos
	if f.get("stage","")=="paths" and mid==PIKE and pos.y==3 and pos.x in [2,6,10]:
		var event: int=f.doors[[2,6,10].find(pos.x)]
		if event<2 or event==3:
			f.opponent=Rules.draw(f,1 if event==3 else (2 if event==1 else 3))
			f.pike_double=event==1
			if event==3:f.opponent=Rules.wild(f)
			start_battle(g,f)
		else:
			var line: String
			if event==2:
				var eligible: Array=f.team.filter(func(m):return int(m.hp)>0 and m.get("status","")=="")
				if not eligible.is_empty():eligible[0].status=["psn","par","slp","brn"][randi()%4]
				line="一位神秘的训练家让伙伴陷入了异常状态。"
			elif event==4:
				for m in f.team:m.hp=m.max_hp;m.status="";m.fainted=false
				line="医生帮你的队伍恢复了体力。"
			else:line="这个房间安静无事，可以继续前进。"
			g._dialog([line]).closed.connect(func():advance(g,f))
		return true
	if f.get("stage","")=="floor" and mid==Maze.FLOOR:
		var exit_at: Array=g.world.map_data.pyramid_exit
		if pos==Vector2i(exit_at[0],exit_at[1]):
			if Rules.symbol_at(f)>0:
				f.at_peak=true
				warp(g,"em_battle_frontier_battle_pyramid_top",[17,10])
				next_stage(g,f)
			else:advance(g,f)
			return true
		if randi()%42==0:
			f.current_tile="wild"
			f.opponent=Rules.wild(f)
			start_battle(g,f);return true
	return false

static func kit_menu(g,f: Dictionary,ui=null) -> void:
	var team: Array=f.team if ui==null else ui.battle.team_a
	var items: Array=f.kit.keys().filter(func(k):return int(f.kit[k])>0)
	if items.is_empty():g._dialog(["金字塔背包空了。"]);return
	g._pick("金字塔背包",items.map(func(k):return "%s ×%d"%[k,f.kit[k]]),func(i):
		var item: String=items[i]
		g._pick("给哪一只使用？",team.map(func(m):return "%s　%d/%d"%[m.name,m.hp,m.max_hp]),func(idx):
			var m: Dictionary=team[idx]
			if item=="活力碎片" and int(m.hp)==0:m.hp=maxi(1,int(m.max_hp)/2);m.fainted=false
			elif item=="好伤药" and int(m.hp)>0 and int(m.hp)<int(m.max_hp):m.hp=mini(m.max_hp,int(m.hp)+50)
			elif item=="万灵药" and m.get("status","")!="":m.status=""
			else:g._dialog(["现在使用没有效果。"]);return
			f.kit[item]=int(f.kit[item])-1
			if ui!=null and is_instance_valid(ui):
				ui._begin_resolve()
				ui.pending=["使用了%s。" % item]
				ui._queue_turn("item","")
				ui.msg.text=""
				ui.wait=ui._dur(0.1)
			g._persist()))

static func finish(g,f: Dictionary,won_set: bool) -> void:
	if not won_set:book(g).records[f.record]=0
	g._flags().erase(RUN)
	if g.world.map_data.id!=f.lobby:warp(g,f.lobby,f.return_at)
	g._persist()
	if not won_set:g._dialog(["本次挑战结束，个人最高纪录已保存。"],"接待员")

static func exchange(g,clerk: String) -> void:
	var b:=book(g)
	var shop: Dictionary
	match clerk:
		"VitaminClerk":shop={"攻击增强剂":1,"防御增强剂":1,"特攻增强剂":1,"特防增强剂":1,"速度增强剂":1,"HP 增强剂":1}
		"HoldItemClerk":shop={"LEFTOVERS":48,"WHITE_HERB":48,"QUICK_CLAW":48,"MENTAL_HERB":48,"BRIGHT_POWDER":64,"CHOICE_BAND":64,"KINGS_ROCK":64,"FOCUS_BAND":64,"SCOPE_LENS":64}
		"DecorClerk1":shop={"亲吻海报":16,"亲吻靠垫":32,"迷唇娃玩偶":32,"波克比玩偶":48,"喵喵玩偶":48,"皮皮玩偶":48,"百变怪玩偶":48,"火球鼠玩偶":80,"菊草叶玩偶":80,"小锯鳄玩偶":80}
		"DecorClerk2":shop={"拉普拉斯玩偶":128,"卡比兽玩偶":128,"妙蛙花玩偶":256,"喷火龙玩偶":256,"水箭龟玩偶":256}
		_:return
	var originals: Array=[]
	for id in Rules.data().prices:
		if str(id).begins_with("DECOR_"):originals.append(id)
	if clerk.begins_with("DecorClerk"):
		var offset:=0 if clerk.ends_with("1") else 10
		for i in shop.size():shop[shop.keys()[i]]=Rules.data().prices[originals[offset+i]]
	elif clerk=="HoldItemClerk":
		for key in shop:shop[key]=Rules.data().prices.get("ITEM_"+key,shop[key])
	var keys:=shop.keys()
	var db=g.get_node("/root/Data")
	g._pick("可用 %d BP" % b.bp,keys.map(func(k):return "%s　%d BP" % [db.item_name(k) if clerk=="HoldItemClerk" else k,shop[k]]),func(i):
		var k: String=keys[i]
		if int(b.bp)<shop[k]:g._dialog(["对战点数还不够。"]);return
		b.bp=int(b.bp)-int(shop[k])
		if clerk=="HoldItemClerk":g._give_bag_item(db.item_name(k),"held",k)
		elif clerk=="VitaminClerk":g._give_item(k,1,"heal")
		else:preload("res://core/hoenn_base.gd").add_decoration(g,originals[(0 if clerk.ends_with("1") else 10)+i])
		g._persist()
		g._dialog(["兑换好了。"]))

static func scott(g) -> void:
	var b:=book(g)
	if not b.get("welcome",false):
		b.welcome=true
		b.bp=int(b.bp)+1
		g._persist()
		g._dialog(["欢迎来到对战开拓区！先送给你 1 BP，去试试不同设施吧。"],"亚希达");return
	for rank_num in [1,2]:
		var key: String=["","lansat","starf"][rank_num]
		if b.get(key,false) or not Rules.NAMES.keys().all(func(k):return int(b.symbols.get(k,0))>=rank_num):continue
		b[key]=true
		var name_text: String=g.get_node("/root/Data").berry_name(key)
		g._give_bag_item(name_text,"berry","",key)
		g._persist()
		g._dialog(["集齐七枚象征的纪念，这颗%s送给你！" % name_text],"亚希达");return
	var tower_best:=0
	for k in b.best:
		if str(k).begins_with("tower|"):tower_best=maxi(tower_best,int(b.best[k]))
	for threshold in [50,100]:
		var shield: String="银盾" if threshold==50 else "金盾"
		if tower_best>=threshold and not b.get(shield,false):
			b[shield]=true
			preload("res://core/hoenn_base.gd").add_decoration(g,"SILVER_SHIELD" if threshold==50 else "GOLD_SHIELD")
			g._persist()
			g._dialog(["对战塔 %d 连胜！请收下%s。" % [threshold,shield]],"亚希达");return
	passbook(g)

static func tutor(g,right: bool) -> void:
	var ids: Array=[111,173,189,129,196,203,244,8,9,7] if right else [135,69,138,5,25,34,157,68,86,14]
	var prices: Array=[16,24,24,24,24,48,48,48,48,48] if right else [16,24,24,24,48,48,48,48,48,48]
	var db=g.get_node("/root/Data")
	var options: Array=[]
	for i in ids.size():options.append("%s　%d BP" % [db.move_of(ids[i]).name,prices[i]])
	g._pick("招式教学习馆　%d BP" % book(g).bp,options,func(i):
		var cost: int=prices[i]
		if int(book(g).bp)<cost:g._dialog(["对战点数还不够。"]);return
		var learn: Array=Rules.data().learn.get(str(ids[i]),[])
		var slots: Array=[]
		for slot in g.save_data.party.size():
			var m=g.save_data.party[slot]
			if m is Dictionary and not m.is_empty() and learn.any(func(s):return int(s)==int(m.species_id)) and not m.moves.any(func(v):return int(v)==ids[i]):slots.append(slot)
		if slots.is_empty():g._dialog(["队伍中没有能够新学这招的宝可梦。"]);return
		g._pick("教给谁？",slots.map(func(s):return g.save_data.party[s].name),func(n):
			g._tm_teach_one(ids[i],slots[n],db.move_of(ids[i]).name,true,func():
				book(g).bp=int(book(g).bp)-cost
				g._persist())))
