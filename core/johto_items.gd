extends RefCounted
## Crystal optional encounters and field gifts. Coordinates refer to the playable map grid.
const BADGES := {"FLASH":"飞翼徽章","CUT":"昆虫徽章","STRENGTH":"标准徽章","SURF":"魅影徽章","FLY":"打击徽章","WHIRLPOOL":"冰川徽章","WATERFALL":"升龙徽章"}
const QUEST_HELD := {"CHARCOAL":["j_charcoal","木炭"],"EXP_SHARE":["j_exp_share","学习装置"],"EVERSTONE":["j_everstone","不变之石"]}
const RODS := ["破旧钓竿","好钓竿","厉害钓竿"]
const HM_WHIRL := "城都秘传学习器 06"
const QUIZ := ["有些宝可梦只有早晨才会出现，对吗？","在城都商店买不到普通树果，对吗？","城都的秘传学习器 01 是闪光，对吗？","桔梗道馆馆主阿速擅长鸟宝可梦，对吗？","满金游戏厅的转轮上有小火龙吗？"]
const ANSWERS := [0,0,1,0,1]
const GIFTS := {
	"johto_players_house_1f":[[3,2],"妈妈","j_gear","宝可装置"],
	"johto_cherrygrove_city":[[16,3],"导游爷爷","j_map_card","地图卡"],
	"johto_route_36":[[22,4],"碎岩大叔","j_rock_smash","城都招式学习器 08"],
	"johto_route_32_pokecenter_1f":[[0,2],"钓鱼人","j_old_rod","破旧钓竿"],
	"johto_olivine_good_rod_house":[[1,1],"钓鱼人","j_good_rod","好钓竿"],
	"johto_route_12_super_rod_house":[[2,1],"钓鱼人","j_super_rod","厉害钓竿"],
	"johto_goldenrod_bike_shop":[[3,1],"自行车店老板","j_bicycle","自行车"],
	"johto_ecruteak_itemfinder_house":[[1,1],"寻宝人","j_finder","探宝器"],
	"johto_olivine_cafe":[[2,1],"水手","j_strength","秘传学习器 04"],
	"johto_cianwood_city":[[5,23],"阿四的妻子","j_fly","秘传学习器 02"],
	"johto_pewter_city":[[14,8],"老人","j_silver_wing","银色之羽"],
	"johto_radio_tower_1f":[[6,3],"问答主持人","j_radio_card","收音机卡"],
	"johto_goldenrod_underground":[[3,12],"道具球","j_coin_case","代币盒"],
	"johto_ice_path_1f":[[15,3],"道具球","j_waterfall","秘传学习器 07"],
	"johto_radio_tower_2f":[[7,2],"小葵","j_blue_card","蓝卡"],
}
const SPECIAL := {
	"johto_tin_tower_1f":[[[4,4],"水君","suicune",245,40],[[3,4],"雷公","raikou",243,40],[[5,3],"炎帝","entei",244,40],[[4,0],"守塔长老","rainbow",0,0]],
	"johto_tin_tower_roof":[[[4,2],"凤王","ho_oh",250,60]],
	"johto_whirl_island_lugia_chamber":[[[1,5],"洛奇亚","lugia",249,60]],
	"johto_route_36":[[[10,3],"水君","suicune36",245,40]],
	"johto_route_42":[[[12,7],"水君","suicune42",245,40]],
}
const TIP := {
	"神奇的蛋":"把宝可梦爷爷托付的蛋交给若叶镇研究所的空木博士。",
	"秘传药":"把药带上浅葱灯塔顶层，交给照料电龙的阿蜜。",
	"红色鳞片":"回 30 号道路找宝可梦爷爷，可以换取学习装置。",
	"地下钥匙":"前往满金地下通道的上锁入口。",
	"钥匙卡（广播塔）":"到满金广播塔，用卡开启被火箭队封锁的门。",
	"透明铃铛":"烧焦塔的三只宝可梦散去后，带着铃铛进入圆朱市的铃铛塔。",
	"GS球":"满金宝可梦中心托付的神秘精灵球。拿给桧皮镇的钢铁检查；等他归还后，再到桐树林的小祠。",
	"银色之羽":"带着羽毛前往漩涡列岛最深处，洛奇亚会现身。",
	"虹色之羽":"铃铛塔的楼梯已经开放，登顶寻找凤王吧。",
}
const PASSWORDS := ["树果","鲤鱼王","月亮球","菊草叶","收音机","肯泰罗"]
static var water: Dictionary

static func tables() -> Dictionary:
	if water.is_empty():
		water = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/items_water.json"))
	return water

static func fish_pool(room: String, rod: String, night: bool) -> Array:
	var data := tables()
	var group: String = data.maps.get(room.trim_prefix("johto_"),"")
	if group.is_empty(): return []
	var index := RODS.find(rod) if rod != "钓竿" else 1
	if index < 0: return []
	var pool: Array = []
	for slot in data.pools[data.groups[group][index]]:
		var i := 3 if night else 1
		pool.append({"weight":slot[0],"species":slot[i],"min":slot[i+1],"max":slot[i+1]})
	return pool

static func visible(role: String, flags: Dictionary) -> bool:
	match role:
		"suicune","raikou","entei":
			var captured: bool = (role=="raikou" and flags.get("j_roam_caught_243",false)) or (role=="entei" and flags.get("j_roam_caught_244",false))
			return not captured and flags.get("j_radio_free",false) and flags.get("j_beasts",false) and not flags.get("j_suicune",false)
		"rainbow": return flags.get("j_rainbow",false) or (flags.get("johto_champion",false) and flags.get("j_three_beasts",false))
		"suicune42": return flags.get("j_eusine_battle",false) and not flags.get("j_suicune42",false)
		"suicune36": return flags.get("j_suicune42",false) and not flags.get("j_suicune36",false)
		"lugia": return flags.get("j_silver_wing",false) and not flags.get("j_lugia",false)
		"ho_oh": return flags.get("j_rainbow",false) and not flags.get("j_ho_oh",false)
	return true

static func same_tile(a: Array, b: Array) -> bool:
	return int(a[0])==int(b[0]) and int(a[1])==int(b[1])

static func roster(map: Dictionary, flags: Dictionary, rows: Array) -> Array:
	var mid: String = map.get("id","")
	rows=preload("res://core/johto_apricorns.gd").roster(mid,rows)
	if flags.get("j_gs_ready",false) and not flags.get("j_gs_return",false):
		if mid=="johto_kurts_house": rows=rows.filter(func(n):return n.get("role","")!="j_kurt_back")
		if mid=="johto_azalea_town":
			rows=rows.duplicate()
			rows.append({"at":[3,2],"name":"钢铁","role":"j_gs_kurt","field_art":"cr_kurt"})
	var gift: Array = GIFTS.get(mid,[])
	var special: Array = SPECIAL.get(mid,[])
	if mid=="johto_guide_gents_house":
		return rows if flags.get("j_map_card",false) else rows.filter(func(n): return n.name!="老爷爷")
	if mid=="johto_goldenrod_game_corner" or mid=="johto_radio_tower_2f":
		rows=rows.duplicate(true)
		for row in rows:
			if mid=="johto_radio_tower_2f" and same_tile(row.at,[6,3]):
				row["johto_service"]="points"
				row["name"]="积分兑奖员"
			if mid=="johto_goldenrod_game_corner":
				if same_tile(row.at,[1,1]): row.merge({"johto_service":"coins","name":"代币柜台"},true)
				if same_tile(row.at,[8,1]): row.merge({"johto_service":"prizes","name":"奖品柜台"},true)
	if gift.is_empty() and special.is_empty(): return rows
	var out := []
	var added := false
	var pos: Array = gift[0] if not gift.is_empty() else []
	if mid=="johto_players_house_1f" and flags.get("j_gear",false):
		var h := int(Time.get_time_dict_from_system().hour)
		pos = [0,1] if h>=4 and h<10 else ([3,2] if h>=10 and h<18 else [0,2])
	for npc in rows:
		if mid=="johto_tin_tower_1f":
			var key := "%d,%d" % npc.at
			var rainbow := visible("rainbow",flags)
			if key=="4,1" and not flags.get("j_ho_oh",false): continue
			if key in ["2,4","5,5","7,3"] and (rainbow or not flags.get("j_suicune",false)): continue
			if key in ["2,1","4,0","7,1"] and not rainbow: continue
		if mid=="johto_players_house_1f":
			if npc.name=="妈妈": continue
			if npc.name=="宝可梦迷" and not flags.get("j_gear",false): continue
		if not gift.is_empty() and same_tile(npc.at,pos):
			added = true
			if (gift[1]=="道具球" or gift[2]=="j_map_card") and flags.get(gift[2],false): continue
			var row: Dictionary = npc.duplicate()
			row.merge({"name":gift[1],"johto_gift":true},true)
			if gift[1]=="道具球": row["field_art"]="fr_item_ball"
			out.append(row)
			continue
		var original: Dictionary = npc
		var matched := false
		for entry in special:
			if not same_tile(entry[0],npc.at): continue
			matched = true
			if visible(entry[2],flags):
				var row: Dictionary = npc.duplicate()
				row.merge({"name":entry[1],"johto_special":entry[2]},true)
				if entry[3]>0: row["field_art"]="crystal_"+str(entry[2]).trim_suffix("36").trim_suffix("42")
				out.append(row)
			break
		if not matched: out.append(original)
	if not added and not gift.is_empty() and not (gift[1]=="道具球" and flags.get(gift[2],false)):
		out.append({"name":gift[1],"at":pos,"gfx":"mom" if gift[1]=="妈妈" else "sailor","johto_gift":true})
	return out

static func grant(g, flag: String, item: String, who: String, lines: Array = []) -> void:
	if g._flags().get(flag,false): return
	if g._bag_count(item)<=0:
		g._give_item(item,1,"tm" if item.contains("学习器") else "key")
	g._flags()[flag] = true
	g.world.refresh_story_actors(g._flags())
	g._persist()
	lines=lines.duplicate()
	lines.append("获得了%s！" % item)
	g._dialog(lines,who)

static func quiz(g, index: int) -> void:
	if index==QUIZ.size():
		grant(g,"j_radio_card","收音机卡","问答主持人",["全对！把这张卡插进宝可装置就可以收听节目。"])
		return
	g._pick(QUIZ[index],["对","不对"],func(reply: int):
		if reply==ANSWERS[index]: quiz(g,index+1)
		else: g._dialog(["答错了。要不要从第一题再试一次？"],"问答主持人"))

static func has_partner(g, species_id: int, box_too: bool = false) -> bool:
	var party: Array = g.save_data.get("party",[])
	if party.any(func(m): return m is Dictionary and int(m.get("species_id",0))==species_id): return true
	if not box_too: return false
	for box in g.save_data.get("boxes",[]):
		if box is Dictionary and box.get("mons",[]).any(func(m): return m is Dictionary and int(m.get("species_id",0))==species_id):
			return true
	var stored: Array = g.save_data.get("box",[])
	return stored.any(func(m): return m is Dictionary and int(m.get("species_id",0))==species_id)

static func legendary(g, role: String, sid: int, level: int):
	g._start_wild_battle(sid,level,"",func(outcome):
		if outcome=="b" and g._party_fainted():
			g._blackout()
		elif outcome in ["caught","a","fled"]:
			g._flags()["j_"+role]=true
			if role=="suicune":
				g._flags().j_suicune36=true
				g._flags().j_suicune42=true
			sync_beasts(g)
			g.world.refresh_story_actors(g._flags())
			g._persist())

static func sync_beasts(g):
	if [243,244,245].all(func(s):return has_partner(g,s,true)):
		g._flags().j_three_beasts=true

static func enter(g):
	var gs_day: String=g.save_data.get("j_gs_date","")
	if not gs_day.is_empty() and gs_day!=Time.get_date_string_from_system() and not g._flags().get("j_gs_ready",false):
		g._flags().j_gs_ready=true
		g.world.refresh_story_actors(g._flags())
		g._persist()
	if g.world.map_data.id=="johto_tin_tower_1f":
		sync_beasts(g)
		g.world.refresh_story_actors(g._flags())
		if visible("suicune",g._flags()) and g._has_party(): legendary(g,"suicune",245,40)

static func talk(g, npc: Dictionary) -> bool:
	var map: String = g.world.map_data.id
	if npc.get("role","")=="j_gs_kurt":
		grant(g,"j_gs_return","GS球","钢铁",["球发出了奇怪的光。桐树林也躁动起来……把球带去那座小祠吧。"])
		return true
	if npc.get("role","")=="j_kurt_back" and g._flags().get("j_gs_received",false) and not g._flags().get("j_gs_return",false):
		if g._bag_count("GS球")>0:
			g._consume_item("GS球")
			g.save_data.j_gs_date=Time.get_date_string_from_system()
			g._persist()
			g._dialog(["这是一颗从来没见过的球。放我这儿研究一天吧。"],"钢铁")
		else: g._dialog(["还在研究。明天再来找我。"],"钢铁")
		return true
	if preload("res://core/johto_apricorns.gd").talk(g,npc): return true
	if npc.has("johto_service"):
		if npc.johto_service=="points": redeem_points(g)
		else: coins(g,npc.johto_service=="prizes")
		return true
	if map=="johto_mr_pokemons_house" and same_tile(npc.at,[1,2]) and g._bag_count("红色鳞片")>0 and not g._flags().get("j_exp_share",false):
		g._pick("把红色鳞片交换给宝可梦爷爷吗？",["交换","先留着"],func(i):
			if i==0:
				g._consume_item("红色鳞片")
				grant(g,QUEST_HELD.EXP_SHARE[0],QUEST_HELD.EXP_SHARE[1],"宝可梦爷爷"))
		return true
	if map=="johto_elms_lab" and npc.name=="空木博士" and g._flags().get("j_togepi_hatched",false) and not g._flags().get("j_everstone",false) and has_partner(g,175):
		grant(g,QUEST_HELD.EVERSTONE[0],QUEST_HELD.EVERSTONE[1],npc.name,["这就是那颗蛋里孵出来的宝可梦！谢谢你带它回来。"])
		return true
	if npc.has("johto_special"):
		var role: String = npc.johto_special
		match role:
			"raikou","entei","suicune": legendary(g,"suicune",245,40)
			"lugia": legendary(g,role,249,60)
			"ho_oh": legendary(g,role,250,60)
			"suicune42","suicune36": sight(g,role)
			"rainbow":
				if g._flags().get("j_rainbow",false):
					g._dialog(["通往塔顶的楼梯就在我身旁。"],npc.name)
				elif g._flags().get("johto_champion",false) and [243,244,245].all(func(s): return has_partner(g,s,true)):
					grant(g,"j_rainbow","虹色之羽",npc.name,["你带回了雷公、炎帝和水君。这支羽毛属于你。"])
				else: g._dialog(["成为联盟冠军，亲自收服雷公、炎帝和水君，再来见我。"],npc.name)
		return true
	if not npc.get("johto_gift",false): return false
	var gift: Array = GIFTS[map]
	var flag: String = gift[2]
	var item: String = gift[3]
	if g._flags().get(flag,false):
		if flag=="j_blue_card": buena(g)
		elif flag=="j_gear": g._dialog(["路上累了就回来看看。记得用宝可装置确认时间和地图。"],npc.name)
		else: g._dialog(["%s已经交给你了，好好使用吧。" % item],npc.name)
		return true
	match flag:
		"j_rock_smash":
			if not g._flags().get("j_tree_clear",false):
				g._dialog(["听说那棵树一碰到水就会动。"],npc.name)
				return true
		"j_fly":
			if "打击徽章" not in g.save_data.get("badges",[]):
				g._dialog(["我丈夫在里面练拳。赢了阿四，再来找我。"],npc.name)
				return true
		"j_radio_card":
			g._pick("参加五道题的收音机问答吗？",["参加","下次再来"],func(i):
				if i==0: quiz(g,0))
			return true
		"j_map_card":
			g._pick("让我带你认识吉花市吧。",["好","下次再来"],func(i):
				if i==0: grant(g,flag,item,npc.name,["红屋顶的宝可梦中心可以治疗伙伴。北边是30号道路，向东则返回若叶镇。","把地图卡装进宝可装置，就能知道自己到了哪里。"]))
			return true
	grant(g,flag,item,npc.name,["修好的宝可装置送回来了。出门前带上吧。"] if flag=="j_gear" else [])
	return true

static func sight(g, role: String):
	if g._flags().get("j_"+role,false): return
	g._flags()["j_"+role]=true
	g.world.refresh_story_actors(g._flags())
	g._persist()
	g._dialog(["水君踏着风跃走了。" if role=="suicune36" else "水君穿过果树林，朝西边跑去了。"],"水君")

static func field_step(g):
	var map: String = g.world.map_data.id
	var pos: Vector2i = g.world.player_pos
	if map=="johto_route_42" and pos in [Vector2i(12,6),Vector2i(13,7),Vector2i(12,8)] and visible("suicune42",g._flags()): sight(g,"suicune42")
	elif map=="johto_route_36" and pos in [Vector2i(10,4),Vector2i(11,3)] and visible("suicune36",g._flags()): sight(g,"suicune36")

static func tick_egg(g):
	if g._flags().get("j_togepi_hatched",false) or g._bag_count("波克比的蛋")==0: return
	var steps := int(g.save_data.get("j_togepi_steps",2560))-1
	g.save_data["j_togepi_steps"]=steps
	if steps>0: return
	g._consume_item("波克比的蛋")
	var target: String = g._add_to_team(175,5)
	g._flags().j_togepi_hatched=true
	g._persist()
	g._dialog(["蛋壳裂开了……波克比孵出来了！","已经把它送去电脑寄存。" if target=="box" else "波克比加入了队伍。"])

static func center_departure(g, dest: Dictionary) -> bool:
	if g.world.map_data.get("id","")!="johto_goldenrod_pokecenter_1f" or dest.get("map","")!="johto_goldenrod_city": return false
	if not g._flags().get("johto_champion",false) or g._flags().get("j_gs_received",false): return false
	grant(g,"j_gs_received","GS球","接待员",["请等一等！研究员托我把这颗特别的球交给你。桧皮镇的钢铁也许认识它。"])
	return true

static func shrine(g, obj: Dictionary) -> bool:
	if obj.get("source_script","")!="IlexForestShrineScript" or not g._flags().get("j_gs_return",false) or g._bag_count("GS球")==0: return false
	g._pick("把发光的GS球放在小祠里吗？",["放上去","再等等"],func(i):
		if i!=0: return
		g._consume_item("GS球")
		g._flags().j_gs_offered=true
		g._persist()
		legendary(g,"celebi",251,30))
	return true

static func passage(g, dest: Dictionary) -> String:
	if dest.get("region","")!="johto": return ""
	if dest.get("map","")=="johto_tin_tower_2f" and g.world.map_data.id=="johto_tin_tower_1f" and not g._flags().get("j_rainbow",false):
		return "通往铃铛塔二层的楼梯尚未显现。"
	if dest.get("map","")=="johto_tin_tower_1f" and g.world.map_data.id!="johto_tin_tower_2f" and g._bag_count("透明铃铛")==0 and not g._flags().get("j_radio_free",false):
		return "守塔人请你先取得透明铃铛。"
	return ""

static func roamer(g, night_grass: bool) -> int:
	if not night_grass or not g._flags().get("j_beasts",false): return 0
	var map: String = g.world.map_data.id
	var area := map.trim_prefix("johto_route_")
	if not tables().roaming.has(area): return 0
	var roam: Dictionary = g.save_data.get("j_roam",{"243":42,"244":37})
	if str(g.save_data.get("j_roam_last",""))!=map:
		for id in roam:
			var links: Array = tables().roaming.get(str(int(roam[id])),[])
			if not links.is_empty(): roam[id]=links[g.rng.randi_range(0,links.size()-1)]
		g.save_data.j_roam=roam
		g.save_data.j_roam_last=map
	for id in roam:
		if str(int(roam[id]))==area and not g._flags().get("j_roam_caught_"+id,false) and g.rng.randf()<0.25:
			return int(id)
	return 0

static func use(g,item: String) -> bool:
	if preload("res://core/johto_apricorns.gd").BALLS.has(item):
		g._dialog(["把%s带给桧皮镇的钢铁，可以制成%s。" % [item,preload("res://core/johto_apricorns.gd").BALLS[item]]])
		return true
	match item:
		"杰尼龟喷壶":
			if g.world.map_data.id=="johto_route_36":
				var row: Dictionary = g.world._npc_at(g.world.player_pos+g.world._dir_vec())
				if row.get("role","")=="j_tree":
					if g._bag_ui!=null: g._bag_ui.handle_back()
					g._story_fire("talk",{"map":"johto_route_36","actor":"j_tree"})
					return true
			g._dialog(["面对36号道路上挡路的怪树，可以用喷壶浇水。"])
		"波克比的蛋": g._dialog(["还能听到蛋里的动静。再走约%d步就能孵化。" % int(g.save_data.get("j_togepi_steps",2560))])
		"宝可装置": gear(g)
		"地图卡": g._open_world_atlas(false,g._bag_ui)
		"收音机卡": radio(g)
		"探宝器": finder(g)
		"自行车": g._toggle_bike()
		"代币盒": g._dialog(["盒中有%d枚游戏代币。" % int(g.save_data.get("j_coins",0))])
		"蓝卡": g._dialog(["卡中有%d点小葵节目的积分。" % int(g.save_data.get("j_blue_points",0))])
		_:
			if not TIP.has(item): return false
			g._dialog([TIP[item]])
	return true

static func gear(g):
	var labels := ["时钟","电话"]
	if g._bag_count("地图卡")>0: labels.append("地区地图")
	if g._bag_count("收音机卡")>0 or g._bag_count("收音机扩充卡")>0: labels.append("收音机")
	labels.append("返回")
	g._pick("宝可装置",labels,func(i):
		match labels[i]:
			"时钟":
				var clock := Time.get_time_dict_from_system()
				g._dialog(["%02d:%02d　%s" % [int(clock.hour),int(clock.minute),g.world.area_name()]],"时钟")
			"电话":
				var contacts := ["妈妈"]
				if g._flags().get("johto_elm_told",false): contacts.append("空木博士")
				g._pick("电话簿",contacts,func(n):
					var line := "路上累了就回若叶镇休息。看到可爱的宝可梦，也记得告诉我。"
					if contacts[n]=="空木博士":
						line = "从蛋里孵出了宝可梦吗？带回来让我看看吧。" if g._flags().get("j_egg_aide",false) else "宝可梦爷爷住在吉花市以北的30号道路。"
					g._dialog([line],contacts[n]))
			"地区地图": g._open_world_atlas(false,g._bag_ui)
			"收音机": radio(g)
	)

static func radio(g):
	var labels := ["城都电台","小葵的口令"]
	if g._bag_count("收音机扩充卡")>0: labels.append("宝可梦之笛")
	labels.append("关闭")
	g._pick("选择频段",labels,func(i):
		match labels[i]:
			"城都电台": g._dialog(["广播塔传来了火箭队的占领宣言……" if g._flags().get("j_radio_takeover",false) and not g._flags().get("j_radio_free",false) else "这里是满金广播塔，正在为你播报城都地区的宝可梦新闻。"],"城都电台")
			"小葵的口令": g._dialog(["今晚的口令是「%s」。来广播塔二楼告诉我吧。" % password() if int(Time.get_time_dict_from_system().hour)>=18 else "节目在每天18点到午夜播出。"],"小葵")
			"宝可梦之笛": preload("res://core/johto_postgame.gd").radio(g)
	)

static func password() -> String:
	return PASSWORDS[absi(Time.get_date_string_from_system().hash())%PASSWORDS.size()]

static func buena(g):
	if int(Time.get_time_dict_from_system().hour)<18:
		g._dialog(["晚上六点开播，记得听我的节目。"],"小葵")
		return
	var today := Time.get_date_string_from_system()
	if g.save_data.get("j_blue_date","")==today:
		g._dialog(["今天的积分已经记在卡上啦。"],"小葵")
		return
	g._pick("今晚的口令是什么？",PASSWORDS,func(i):
		if PASSWORDS[i]!=password():
			g._dialog(["答错啦，调到我的频道再听一次。"],"小葵")
			return
		g.save_data.j_blue_points=mini(30,int(g.save_data.get("j_blue_points",0))+1)
		g.save_data.j_blue_date=today
		g._persist()
		g._dialog(["答对了！蓝卡增加了一点积分。"],"小葵"))

static func finder(g):
	var nearest: Dictionary = {}
	var distance := 2147483647
	for row in g.world.objects:
		if row.get("kind","")!="hidden" or g.world.taken.get(g.world._object_key(row),false) or g.world.taken.get(row.get("flag",""),false): continue
		var tile := Vector2i(row.at[0],row.at[1])
		var delta: Vector2i = tile-g.world.player_pos
		var steps := absi(delta.x)+absi(delta.y)
		if steps<distance:
			distance=steps
			nearest=row
	if distance>8:
		g._dialog(["附近没有检测到隐藏道具。"],"探宝器")
		return
	var d := Vector2i(nearest.at[0],nearest.at[1])-Vector2i(g.world.player_pos)
	var dir := (("北" if d.y<0 else "南") if d.y else "")+(("西" if d.x<0 else "东") if d.x else "")
	g._dialog(["脚下就有反应！" if distance==0 else "%s方有反应。距离约%d格。" % [dir,distance]],"探宝器")

static func coins(g, prizes: bool):
	if g._bag_count("代币盒")==0:
		g._dialog(["领到代币盒再来吧。地下通道里有人丢了一个。"],"柜台")
		return
	var balance := int(g.save_data.get("j_coins",0))
	if not prizes:
		g._pick("代币盒　%d / 9999" % balance,["50枚　¥1000","500枚　¥10000","返回"],func(i):
			if i<0 or i>1: return
			var qty := 50 if i==0 else 500
			var cost := qty*20
			if int(g.save_data.get("money",0))<cost or balance+qty>9999:
				g._dialog(["金钱不足，或盒中空间不足。"],"代币柜台")
				return
			g.save_data.money=int(g.save_data.money)-cost
			g.save_data.j_coins=balance+qty
			g._persist()
			g._dialog(["收好这%d枚代币。" % qty],"代币柜台"))
		return
	var goods := [["凯西",100,63,5],["卡拉卡拉",800,104,15],["果然翁",1500,202,15],["招式学习器 25",5500,0,0],["招式学习器 14",5500,0,0],["招式学习器 38",5500,0,0]]
	var labels: Array = goods.map(func(row): return "%s　%d枚" % [row[0],row[1]])
	g._pick("可用代币　%d" % balance,labels+["返回"],func(i):
		if i<0 or i>=goods.size(): return
		var row: Array = goods[i]
		if balance<int(row[1]):
			g._dialog(["代币还不够。"],"奖品柜台")
			return
		if int(row[2])>0: g._add_to_team(row[2],row[3])
		else: g._give_item(row[0],1,"tm")
		g.save_data.j_coins=balance-int(row[1])
		g._persist()
		g._dialog(["收好你的%s！" % row[0]],"奖品柜台"))

static func redeem_points(g):
	var prizes := [["高级球",2,"ball"],["全复药",2,"heal"],["金珠",3,"other"],["神奇糖果",3,"candy"],["攻击增强剂",5,"other"],["防御增强剂",5,"other"],["速度增强剂",5,"other"],["特攻增强剂",5,"other"],["HP 增强剂",5,"other"]]
	var balance := int(g.save_data.get("j_blue_points",0))
	var options: Array = prizes.map(func(r): return "%s　%d点" % [r[0],r[1]])
	g._pick("蓝卡　%d点" % balance,options+["返回"],func(i):
		if i<0 or i>=prizes.size(): return
		var reward: Array=prizes[i]
		if balance<int(reward[1]):
			g._dialog(["积分还不够，来小葵的节目答题吧。"])
			return
		g.save_data.j_blue_points=balance-int(reward[1])
		g._give_item(reward[0],1,reward[2])
		g._persist()
		g._dialog(["兑换了%s。" % reward[0]]))
