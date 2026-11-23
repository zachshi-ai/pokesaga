extends RefCounted
## The X and Y versions share story progress; only the legendary, gifts and ending differ.

const Field := preload("res://core/kalos_field.gd")
const Hoenn := preload("res://core/hoenn_campaign.gd")
const Party := preload("res://core/party.gd")
const STARTERS := [650,653,656]
const NAMES := ["哈力栗","火狐狸","呱呱泡蛙"]
const ELITE := ["malva","siebold","wikstrom","drasna"]
static var book: Dictionary
static var trainers: Dictionary
static var by_map: Dictionary

static func data() -> Dictionary:
	if book.is_empty():
		book=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_campaign.json"))
		for e in book.events:by_map.get_or_add(e.map,[]).append(e)
	return book

static func trainer_data() -> Dictionary:
	if trainers.is_empty():trainers=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_trainers.json"))
	return trainers

static func eligible(required: Array, flags: Dictionary) -> bool:
	for flag in required:
		if not flags.get(flag,false):return false
	return true

static func active(e: Dictionary, flags: Dictionary) -> bool:
	if e.id=="k_reclaim_lucario" and flags.get("k_lucario_received",false):return false
	return flags.get("k_started",false) and eligible(e.require,flags) and not flags.get(e.id,false)

static func partner(save: Dictionary) -> Dictionary:
	for mon in save.get("party",[]):
		if mon is Dictionary and mon.get("kalos_partner",false):return mon
	for box in save.get("boxes",[]):
		if not box is Dictionary:continue
		for mon in box.get("mons",[]):
			if mon is Dictionary and mon.get("kalos_partner",false):return mon
	for mon in save.get("box",[]):
		if mon is Dictionary and mon.get("kalos_partner",false):return mon
	return {}

static func event(g,kind: String,ctx: Dictionary) -> Dictionary:
	if kind not in ["talk","step","map_enter"]:return {}
	data()
	var mid: String=g.world.map_data.id
	if mid=="kalos_forest" and kind=="step":update_forest_partner(g)
	var flags: Dictionary=g._flags()
	for e in by_map.get(mid,[]):
		if not active(e,flags):continue
		if e.id=="k_badge_3" and not preload("res://core/kalos_gyms.gd").SKATERS.all(func(n):return flags.get("k_trainer_"+str(n),false)):continue
		if e.id=="k_badge_8" and not flags.get("k_ice_bridge_last",false):continue
		if kind=="talk":
			if e.id in [ctx.get("actor",""),ctx.get("local_id","")]:return e
		elif e.get("on_entry",false) and (kind=="map_enter" or e.id=="k_parade"):
			return e
		elif e.has("on_approach"):
			for row in g.world.npcs:
				if row.get("role","")!=e.id:continue
				var distance: int=absi(int(row.at[0])-int(ctx.x))+absi(int(row.at[1])-int(ctx.y))
				if distance<=int(e.on_approach):return e
	return {}

static func update_forest_partner(g) -> void:
	if not g._flags().get("k_forest_friends",false) or g._flags().get("k_rules",false):return
	var companion=g.world.get_node_or_null("KalosWalkingPartner")
	if not is_instance_valid(companion) or companion.is_queued_for_deletion():
		companion=preload("res://core/sinnoh_companion.gd").new()
		companion.name="KalosWalkingPartner"
		companion.cast=preload("res://core/kalos_cast.gd")
		g.world.add_child(companion)
	var tile:=Vector2i(g.world.player_pos)-Vector2i(g.world.last_dir)
	companion.follow(g.world,"莎娜",str(g.world.map_data.id),tile,str(g.world.facing))

static func forest_partner_action(g) -> bool:
	if g.world.map_data.get("id","")!="kalos_forest":return false
	var companion=g.world.get_node_or_null("KalosWalkingPartner")
	if not is_instance_valid(companion) or companion.is_queued_for_deletion():return false
	if Vector2i(g.world.player_pos)+Vector2i(g.world._dir_vec())!=companion.tile:return false
	g._heal_party()
	g._persist()
	g._dialog(["累了吗？把宝可梦交给我照顾一下……好了，大家又精神起来了！"],"莎娜")
	return true

static func _position(map: Dictionary, slot: String, used: Array) -> Array:
	var anchors: Dictionary=map.get("kalos_anchors",{})
	for key in [slot,"story","guest1","guest2","guest3","guest4","side1","side2","side3"]:
		var at: Array=anchors.get(key,[])
		if at.size()==2 and at not in used:return at
	return []

static func roster(map: Dictionary,flags: Dictionary,rows: Array) -> Array:
	data()
	var result:=rows.duplicate()
	var used: Array=[map.get("spawn",[])]
	for row in rows:used.append(row.at)
	for warp in map.get("warps",[]):used.append(warp.at)
	var names: Array=[]
	for residents in [false,true]:
		for e in by_map.get(str(map.get("id","")),[]):
			if residents:
				if not e.has("resident") or not flags.get(e.id,false):continue
			elif not active(e,flags):continue
			var cast: Array=[e.who]
			if not residents:cast.append_array(e.get("guests",[]))
			for i in cast.size():
				var who: String=cast[i]
				if who in names:continue
				var slot: String=e.anchor if i==0 else "guest"+str(i)
				var positions: Array=e.get("positions",[])
				var at: Array=positions[i] if i<positions.size() and positions[i] not in used else _position(map,slot,used)
				if at.is_empty():continue
				var identity: String=e.id if i==0 else str(e.id)+"_guest"+str(i)
				var lines: Array=[e.get("resident","我在听。")] if residents else [guest_line(who)]
				var npc: Dictionary={"at":at,"name":who,"kalos_actor":who,"role":identity,"local_id":identity,"facing":"down","lines":lines}
				result.append(npc)
				names.append(who)
				used.append(at)
	return result

static func guest_line(who: String) -> String:
	match who:
		"莎娜":return "能和大家一起经历这些，我会一直记得。"
		"莎莉娜":return "下一步，一起想想要怎么走。"
		"提耶鲁诺":return "刚才那个动作，我想编进舞步里。"
		"多罗巴":return "等我把刚才见到的宝可梦记下来。"
		"路卡利欧":return "路卡利欧安静地注视着你。"
		"卡比兽":return "卡比兽在呼呼大睡，背上的肚皮一上一下。"
		"ＡＺ":return "巨人沉默地望向远方。"
		"暴雪王":return "暴雪王抖落了枝梢的雪。"
	return "对方转身，等着听接下来的谈话。"

static func gate(target: Dictionary,flags: Dictionary,_current: Dictionary={}) -> String:
	if target.get("region","kalos")!="kalos":return ""
	var mid: String=target.get("map","")
	if not mid.begins_with("kalos_"):return ""
	if not flags.get("k_started",false):
		return "" if mid in ["kalos_vaniville","kalos_home_1f","kalos_home_2f"] else "先到朝香镇，开始卡洛斯的旅程。"
	if not eligible(target.get("kalos_requires",[]),flags):return target.get("kalos_denied","这条路还没有开放。")
	if mid=="kalos_champion_room" and flags.get("k_parade",false):
		for slug in ELITE:
			if not flags.get("k_again_"+slug,false):return "本轮的四位天王尚未全部获胜。"
		return ""
	var rule: Dictionary=data().gates.get(mid,{})
	if not eligible(rule.get("require",[]),flags):return rule.get("message","前路还未开启。")
	return ""

static func _trainer(key,flags: Dictionary) -> Array:
	var source:=trainer_data()
	var id:=str(int(key))
	if flags.get("k_version","x")=="y" and source.y.has(id):return source.y[id].duplicate(true)
	return source.teams.get(id,[]).duplicate(true)

static func team(cfg: Dictionary,flags: Dictionary) -> Dictionary:
	if not cfg.has("kalos_team") and not cfg.has("kalos_variants"):return cfg
	var idx:=maxi(0,STARTERS.find(int(flags.get("k_starter",0))))
	var id=cfg.kalos_variants[idx] if cfg.has("kalos_variants") else cfg.kalos_team
	var party:=_trainer(id,flags)
	if cfg.has("kalos_other"):
		for m in party:m.trainer_group="first"
		for m in _trainer(cfg.kalos_other,flags):
			m.trainer_group="second"
			party.append(m)
	var resolved:=cfg.merged({"team":party},true)
	if cfg.has("kalos_ally"):resolved.ally_team=_trainer(cfg.kalos_ally[idx],flags)
	return resolved

static func _clear_league(flags: Dictionary,repeat: bool) -> void:
	for slug in ELITE:
		var id: String=("k_again_" if repeat else "k_elite_")+slug
		flags.erase(id)
		flags.erase("story_"+id)
	if repeat:
		flags.erase("k_again_champion")
		flags.erase("story_k_again_champion")

static func _is_league(mid: String) -> bool:
	return mid in ["kalos_league_lobby","kalos_league_hall","kalos_zone_247","kalos_zone_248","kalos_zone_249","kalos_zone_250","kalos_champion_stairs","kalos_champion_room","kalos_hall_of_fame"] or mid.begins_with("kalos_e4_")

static func leave_league(current: Dictionary,next_map: Dictionary,flags: Dictionary) -> void:
	if not _is_league(current.get("id","")) or _is_league(next_map.get("id","")):return
	if flags.get("k_parade",false) or not flags.get("k_diantha",false):_clear_league(flags,flags.get("k_parade",false))

static func lost_league(g,id: String) -> void:
	if id.begins_with("k_elite_") or id.begins_with("k_again_") or id=="k_diantha":_clear_league(g._flags(),g._flags().get("k_parade",false))

static func _resume(g,lines: Array,who: String="") -> void:
	g._dialog(lines,who).closed.connect(g._story_step,CONNECT_ONE_SHOT)

static func _room(g) -> bool:
	if Hoenn.has_room(g.save_data):return true
	Hoenn.abort_event(g)
	g._dialog(["队伍和电脑箱都满了。先在宝可梦中心空出一个位置，再回来。"])
	return false

static func _pick_starter(g) -> void:
	g._pick("选择卡洛斯的初始伙伴",NAMES,func(i):
		var id: int=STARTERS[i]
		var mon:=Party.make(id,5,Field.moves_for(id,5))
		mon.kalos_partner=true
		mon.berry=""
		var place: String=g._store_mon(mon)
		g._flags().k_starter=id
		g._persist()
		_resume(g,["%s%s。"%[NAMES[i],"加入了队伍" if place=="party" else "寄存在电脑里，初战时仍会和你一起出场"]],"提耶鲁诺"),func():Hoenn.abort_event(g))

static func _lucario(g,follow: Callable) -> void:
	g._pick("接下可尔妮的路卡利欧吗？",["一起旅行","留在塔上"],func(i):
		if i==0:
			if not _room(g):return
			var mon:=Party.make(448,32,[612,14,319,198])
			mon.held="LUCARIONITE"
			mon.berry=""
			var where: String=g._store_mon(mon)
			g._flags().k_lucario_received=true
			g._persist()
			g._dialog(["路卡利欧带着路卡利欧进化石，%s。"%("加入了队伍" if where=="party" else "在电脑中等你")],"可尔妮").closed.connect(follow,CONNECT_ONE_SHOT)
		else:
			follow.call(),func():Hoenn.abort_event(g))

static func _next_pc_cell(save: Dictionary) -> Vector2i:
	if Party.occupied(save.get("party",[]))<Party.MAX_SIZE:return Vector2i(-1,-1)
	var boxes: Array=save.get("boxes",[])
	for index in Party.BOX_COUNT:
		if index>=boxes.size():return Vector2i(index,0)
		if not boxes[index] is Dictionary:continue
		var slots: Array=boxes[index].get("mons",[])
		for slot in Party.BOX_SIZE:
			if slot>=slots.size() or not slots[slot] is Dictionary or slots[slot].is_empty():return Vector2i(index,slot)
	return Vector2i(-1,-1)

static func _legend_after_capture(g) -> void:
	var flags: Dictionary=g._flags()
	var name: String=g.get_node("/root/Data").species_of(int(flags.k_legend_caught)).name
	var address: Array=flags.get("k_legend_pc",[])
	var boxes: Array=g.save_data.get("boxes",[])
	if address.size()==2 and int(address[0])<boxes.size():
		var slots: Array=boxes[int(address[0])].get("mons",[])
		var pos:=int(address[1])
		if pos<slots.size() and slots[pos] is Dictionary and int(slots[pos].get("species_id",0))==int(flags.k_legend_caught):
			var choices:=["留在电脑"]
			var party: Array=g.save_data.party
			for m in party:choices.append("换下 "+str(m.get("name","空位")))
			var finish:=func(i):
				if i>0 and i<=party.size():
					var old=party[i-1]
					party[i-1]=slots[pos]
					slots[pos]=old
				flags.erase("k_legend_pc")
				g._persist()
				_resume(g,["%s选择了你。能源供应已经中断。"%name])
			g._pick("队伍已满 · 要立刻带上%s吗？"%name,choices,finish,func():finish.call(0))
			return
	flags.erase("k_legend_pc")
	_resume(g,["%s选择了你。能源供应已经中断。"%name])

static func _legend(g) -> void:
	var flags: Dictionary=g._flags()
	var id:=717 if flags.get("k_version","x")=="y" else 716
	var name: String=g.get_node("/root/Data").species_of(id).name
	var available:=_next_pc_cell(g.save_data)
	g._dialog(["%s睁开眼睛，甩开通往最终兵器的导管！"%name],name).closed.connect(func():
		g._start_wild_battle(id,50,"",func(outcome):
			if outcome=="caught":
				flags.k_legend_caught=id
				if available.x>=0:flags.k_legend_pc=[available.x,available.y]
				g._persist()
				_legend_after_capture(g)
			else:
				Hoenn.abort_event(g)
				g._dialog(["%s仍然站在能源室中。整顿伙伴，再来回应它吧。"%name]),"none"),CONNECT_ONE_SHOT)

static func _buttons(g) -> void:
	g._pick("控制台 · 选择按钮",["红色按钮","蓝色按钮"],func(i):
		g._flags().k_button="blue" if i==1 else "red"
		var line: String="你按下了停止键，可是库瑟洛斯奇偷偷启动了遥控器！" if i==1 else "你按下的正是启动键，地下传来一阵轰鸣。"
		_resume(g,[line,"石香镇中央的列石打开了。最终兵器像一朵巨花，从地底缓缓升起。"],"库瑟洛斯奇"))

static func prompt(g,act: Dictionary) -> bool:
	var flags: Dictionary=g._flags()
	if act.has("kalos_starter"):
		if int(flags.get("k_starter",0)) in STARTERS:return false
		if _room(g):_pick_starter(g)
	elif act.has("kalos_kanto_gift"):
		if flags.get("ks_kanto_gift",false):return false
		if _room(g):load("res://core/kalos_side.gd").kanto_gift(g,Callable(g,"_story_step"))
	elif act.has("kalos_fossil"):
		if flags.has("k_chosen_fossil"):return false
		var names:=["颚之化石","鳍之化石"]
		g._pick("从化石中选择一块",names,func(i):
			g._give_item(names[i],1,"key")
			flags.k_chosen_fossil=names[i]
			g._persist()
			_resume(g,["带化石回古香镇的化石研究所，就能尝试复活它。"],"化石研究员"),func():Hoenn.abort_event(g))
	elif act.has("kalos_reclaim"):
		_lucario(g,func():
			if flags.get("k_lucario_received",false):g._story_step()
			else:Hoenn.abort_event(g))
	elif act.has("kalos_lucario"):
		if flags.get("k_lucario_received",false):return false
		_lucario(g,Callable(g,"_story_step"))
	elif act.has("kalos_require_item"):
		if g._bag_count(act.kalos_require_item)>0:return false
		Hoenn.abort_event(g)
		g._dialog(["需要带来%s。"%act.kalos_require_item])
	elif act.has("kalos_catch_demo"):
		Hoenn.catch_demonstration(g,659,3,[33],661,5,[33],["莎莉娜派出小箭雀，拦在野生掘掘兔的前面。","小箭雀，用撞击！等对方的体力降下去……","莎莉娜投出了精灵球。成功收服了掘掘兔！"])
	elif act.has("kalos_scene"):preload("res://core/kalos_scenes.gd").play(g,act.kalos_scene)
	elif act.has("kalos_button_choice"):_buttons(g)
	elif act.has("kalos_legend"):
		if flags.get("k_legend_caught",0):
			if not flags.has("k_legend_pc"):return false
			_legend_after_capture(g)
		elif _room(g):_legend(g)
	elif act.has("kalos_final_shot"):
		var wish: String="最后的光，要让你们与我一同面对永生。永远记得这一刻！" if flags.get("k_version","x")=="x" else "最后的光，将夺去这里所有人的生命。你们还能阻止吗？"
		g._dialog([wish,"残存的能量冲向天空，又落回基地。莎莉娜和莎娜拉着你穿过通道，出口在身后坍塌。"],"弗拉达利").closed.connect(func():
			flags.k_last_lysandre=true
			g._do_warp({"region":"kalos","map":"kalos_geosenge","at":g.get_node("/root/Data").load_map("kalos","kalos_geosenge").spawn})
			g._story_step(),CONNECT_ONE_SHOT)
	else:return false
	return true

static func action(g,act: Dictionary) -> void:
	if act.has("kalos_key") and g._bag_count(act.kalos_key)==0:g._give_item(act.kalos_key,1,"key")
	if act.has("kalos_take") and g._bag_count(act.kalos_take)>0:g._consume_item(act.kalos_take)
	if act.has("kalos_held") and act.kalos_held=="KINGS_ROCK":g._give_bag_item("王者之证","held","KINGS_ROCK")
	if act.has("kalos_badge"):g._grant_badge(act.kalos_badge)
	if act.has("kalos_hall") or act.has("kalos_repeat_hall"):
		g.johto_league.register_team(g.save_data,"kalos")
		g._flags().k_hall_entries=int(g._flags().get("k_hall_entries",0))+1
		if act.has("kalos_repeat_hall"):_clear_league(g._flags(),true)
	if act.has("heal") and g.cur_story.get("id","")=="k_first_battle":
		var mon:=partner(g.save_data)
		if not mon.is_empty():
			mon.hp=mon.max_hp
			mon.hp_text="%d/%d"%[int(mon.hp),int(mon.max_hp)]
			mon.erase("status")
			mon.pp=mon.moves.map(func(id):return int(g.get_node("/root/Data").move_of(int(id)).get("pp",1)))
	if act.has("kalos_warp"):
		var target: Dictionary=g.get_node("/root/Data").load_map("kalos",str(act.kalos_warp))
		if not target.is_empty():g._do_warp({"region":"kalos","map":target.id,"at":target.spawn,"facing":"down"})

static func use(g,name: String) -> bool:
	if g.world.map_data.get("region","")!="kalos":return false
	match name:
		"卡洛斯图鉴":g._open_dex()
		"城镇地图":g._open_world_atlas(false)
		"全息影像通讯器":
			var flags: Dictionary=g._flags()
			for e in data().events:
				if active(e,flags):
					var map: Dictionary=g.get_node("/root/Data").load_map("kalos",e.map)
					g._dialog(["%s · %s在等你。"%[map.get("name","卡洛斯"),e.who]],name)
					return true
			g._dialog(["布拉塔诺博士：你的旅行还会继续。下次见面，再让我看看你遇到的伙伴。"],name)
		"探险心得":g._dialog(["精灵球用来捕捉野生宝可梦。训练家的伙伴不能捕捉。","中心的电脑可以寄存或接回队员。途中遇到的伙伴也会留在图鉴中。"],name)
		"博士的信":g._dialog(["信封上写着妈妈的名字，请回朝香镇自己家一楼交给她。"],name)
		"宝可梦之笛":g._dialog(["笛声能唤醒七号道路桥上的卡比兽。走到空手道王身边，把笛子交给他。"],name)
		"发电厂通行证":g._dialog(["十三号道路通往卡洛斯发电厂的门会识别这张证件。"],name)
		"电梯钥匙":g._dialog(["弗拉达利研究所的电梯可以前往地下二层与三层。"],name)
		"超级环":g._dialog(["让能够超级进化的队员携带对应的进化石。对战中选择招式前，触碰超级进化按钮。每位训练家一场限一次。"],name)
		"卡洛斯勋章":g._dialog(["在密阿雷的庆典上，表彰小悠与伙伴守护卡洛斯的勋章。"],name)
		"轮滑鞋":preload("res://core/kalos_side_city.gd").skates(g)
		_:return false
	return true
