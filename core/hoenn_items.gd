extends RefCounted
## Emerald field permissions are local to the journey. The bag and party stay shared.

const QUEST_HELD := {"SHELL_BELL":["ShoalCave_ShellBellExpert","贝壳之铃"],"SOUL_DEW":["SouthernIsland_Interior_EventScript_TryLatiEncounter","心之水滴"]}
const Legends := preload("res://core/emerald_legends.gd")
const Side := preload("res://core/hoenn_side.gd")

const MACHINES := {
	"CUT":[1,1,"岩石徽章"], "FLY":[2,6,"白羽徽章"], "SURF":[3,5,"天秤徽章"],
	"STRENGTH":[4,4,"烈焰徽章"], "FLASH":[5,2,"拳击徽章"], "ROCK_SMASH":[6,3,"电力徽章"],
	"WATERFALL":[7,8,"雨滴徽章"], "DIVE":[8,7,"心灵徽章"]}
const NAMES := {
	"ITEM_RUNNING_SHOES":"跑步鞋",
	"ITEM_DEVON_GOODS":"得文的物品","ITEM_LETTER":"给大吾的信","ITEM_METEORITE":"陨石",
	"ITEM_GO_GOGGLES":"防沙护目镜","ITEM_DEVON_SCOPE":"得文侦测镜","ITEM_MAGMA_EMBLEM":"熔岩标志",
	"ITEM_POKENAV":"宝可导航","ITEM_SS_TICKET":"丰缘船票","ITEM_ITEMFINDER":"探宝器",
	"ITEM_OLD_ROD":"破旧钓竿","ITEM_GOOD_ROD":"好钓竿","ITEM_SUPER_ROD":"厉害钓竿",
	"ITEM_MACH_BIKE":"音速自行车","ITEM_ACRO_BIKE":"越野自行车","ITEM_WAILMER_PAIL":"吼吼鲸喷壶",
	"ITEM_SOOT_SACK":"集灰袋","ITEM_BASEMENT_KEY":"地下钥匙","ITEM_POKEBLOCK_CASE":"宝可方块盒",
	"ITEM_COIN_CASE":"代币盒","ITEM_HARBOR_MAIL":"港口邮件","ITEM_STORAGE_KEY":"仓库钥匙",
	"ITEM_ROOM_1_KEY":"1号房钥匙","ITEM_ROOM_2_KEY":"2号房钥匙","ITEM_ROOM_4_KEY":"4号房钥匙",
	"ITEM_ROOM_6_KEY":"6号房钥匙","ITEM_SCANNER":"探测器","ITEM_ROOT_FOSSIL":"根状化石",
	"ITEM_CLAW_FOSSIL":"爪子化石"}
const GIFTS := {
	"RustboroCity_CuttersHouse_EventScript_Cutter":"ITEM_HM_CUT",
	"GraniteCave_1F_EventScript_Hiker":"ITEM_HM_FLASH",
	"MauvilleCity_House1_EventScript_RockSmashDude":"ITEM_HM_ROCK_SMASH",
	"DewfordTown_EventScript_OldRodFisherman":"ITEM_OLD_ROD",
	"Route118_EventScript_GoodRodFisherman":"ITEM_GOOD_ROD",
	"MossdeepCity_House3_EventScript_SuperRodFisherman":"ITEM_SUPER_ROD",
	"Route104_PrettyPetalFlowerShop_EventScript_WailmerPailGirl":"ITEM_WAILMER_PAIL",
	"LilycoveCity_ContestLobby_EventScript_ContestReceptionist":"ITEM_POKEBLOCK_CASE"}
const HINTS := {
	"ITEM_RUNNING_SHOES":"在允许奔跑的地图上按住 B 并移动。",
	"ITEM_LETTER":"把信送给石之洞窟深处的大吾。","ITEM_DEVON_GOODS":"把船用零件交给凯那市的馆长。",
	"ITEM_METEORITE":"秋叶镇的索蓝斯博士正在找这块陨石。","ITEM_GO_GOGGLES":"进入111号道路的沙漠时会自动戴上。",
	"ITEM_MAGMA_EMBLEM":"去凹凸山道寻找岩壁里的熔岩队基地。","ITEM_DEVON_SCOPE":"站在挡路的透明宝可梦前按 A 照出它。",
	"ITEM_SS_TICKET":"从凯那或水静的港口向服务员出示船票。","ITEM_BASEMENT_KEY":"打开新紫堇的地下入口，在里面停止发电机。",
	"ITEM_STORAGE_KEY":"打开弃船地下走廊的仓库。","ITEM_SCANNER":"拿给凯那港口的馆长，换取进化物品。",
	"ITEM_ROOT_FOSSIL":"把化石交给得文公司二楼的研究员复活。","ITEM_CLAW_FOSSIL":"把化石交给得文公司二楼的研究员复活。"}
static var tables: Dictionary

static func data() -> Dictionary:
	if tables.is_empty():
		tables = JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_field_items.json"))
	return tables

static func name_for(id: String) -> String:
	if id.begins_with("ITEM_HM_"):
		var machine: Array = MACHINES.get(id.trim_prefix("ITEM_HM_"),[])
		if not machine.is_empty(): return "秘传学习器 %02d" % int(machine[0])
	return str(NAMES.get(id,""))

static func flag_for(id: String) -> String:
	return "h_item_"+id.trim_prefix("ITEM_").to_lower()

static func received(flags: Dictionary, id: String) -> bool:
	return bool(flags.get(flag_for(id),false))

static func grant(g, id: String) -> bool:
	var name_text := name_for(id)
	if name_text.is_empty() or received(g._flags(),id): return false
	g._flags()[flag_for(id)] = true
	if g._bag_count(name_text)==0: g._give_item(name_text,1,"tm" if id.begins_with("ITEM_HM_") else "key")
	return true

static func take(g, id: String) -> void:
	if received(g._flags(),id) and g._bag_count(name_for(id))>0: g._consume_item(name_for(id))

static func permission(flags: Dictionary, key: String) -> String:
	if not MACHINES.has(key): return "丰缘地区对应的秘传资格"
	var row: Array = MACHINES[key]
	if not flags.get("h_badge_%d" % row[1],false): return str(row[2])
	if not received(flags,"ITEM_HM_"+key): return "丰缘的"+name_for("ITEM_HM_"+key)
	return ""

static func gift(g, id: String, who: String) -> void:
	if grant(g,id):
		g.snd.play_sfx("item")
		g._persist()
		var dlg = g._dialog(["获得了「%s」！" % name_for(id)],who)
		if id.begins_with("ITEM_HM_"):
			dlg.closed.connect(func(): g._offer_tm_teach(name_for(id)),CONNECT_ONE_SHOT)
	else:
		g._dialog([str(HINTS.get(id,"你已经拿到了「%s」。" % name_for(id)))],who)

static func behavior(map: Dictionary, pos: Vector2i) -> int:
	return preload("res://core/hoenn_field.gd").behavior(map,pos)

static func underwater(map: Dictionary) -> bool:
	return str(map.get("source_id","")).begins_with("MAP_UNDERWATER_") or str(map.get("source_id","")).begins_with("MAP_ABANDONED_SHIP_UNDERWATER")

static func dive(g) -> bool:
	if Legends.dive(g):return true
	var map: Dictionary = g.world.map_data
	var dest: Dictionary = map.get("dive_connection",{})
	var pos: Vector2i = g.world.player_pos
	dest=map.get("dive_at",{}).get("%d,%d"%[pos.x,pos.y],dest)
	if dest.is_empty(): return false
	var tile := behavior(map,pos)
	var emerging := underwater(map)
	if emerging and tile in [0x19,0x2a]: return false
	if not emerging and (not g.world.surfing or tile not in [0x11,0x12,0x14]): return false
	if not g._party_can_move("DIVE"):
		g._dialog([g._field_move_hint("DIVE","潜水")])
		return true
	var target := dest.duplicate(true)
	target.at = dest.get("at",[pos.x,pos.y])
	target.hoenn_native=true
	g._pick("水面上透着光。要浮上去吗？" if emerging else "这里的海水很深。要潜水吗？", ["上浮" if emerging else "下潜","返回"], func(i):
		if i != 0: return
		g._do_warp(target)
		if g.world.map_data.id == target.map:
			g.world.diving = not emerging
			g.world.surfing = emerging
			g.world._sync_player()
			g._persist())
	return true

static func can_enter(w, pos: Vector2i, dir: Vector2i) -> bool:
	var source: String = w.map_data.get("source_id","")
	if source == "MAP_ROUTE111" and not received(w.taken,"ITEM_GO_GOGGLES"):
		if data().sand_gates.any(func(at):return Vector2i(at[0],at[1])==pos) or behavior(w.map_data,pos)==6: return false
	var tile := behavior(w.map_data,pos)
	if tile == 0xd0 and dir==Vector2i.UP: return w.bike and w.taken.get("h_bike","")=="ITEM_MACH_BIKE"
	if tile in [0xd1,0xd3,0xd4,0xd5,0xd6]: return w.bike and w.taken.get("h_bike","")=="ITEM_ACRO_BIKE"
	return true

static func talk(g, npc: Dictionary) -> bool:
	if not g.world.map_data.has("emerald_original"): return false
	if preload("res://core/emerald_cycling.gd").interact(g,npc):return true
	if preload("res://core/emerald_lilycove_lady.gd").talk(g,npc):return true
	if preload("res://core/emerald_fan_club.gd").interact(g,npc):return true
	var script := str(npc.get("source_script",""))
	if preload("res://core/hoenn_match_call.gd").talk(g,npc):return true
	if preload("res://core/hoenn_daily.gd").talk(g,script):return true
	if preload("res://core/hoenn_move_services.gd").talk(g,script):return true
	if load("res://core/hoenn_reporters.gd").talk(g,npc):return true
	if preload("res://core/hoenn_safari.gd").talk(g,npc):return true
	if preload("res://core/hoenn_hill.gd").talk(g,npc):return true
	if preload("res://core/hoenn_base.gd").talk(g,npc):return true
	if Legends.talk(g,npc):return true
	if Side.talk(g,npc): return true
	var who := str(npc.get("name",""))
	if script=="SlateportCity_EventScript_BerryPowderClerk":
		preload("res://core/berry_powder.gd").vendor(g)
		return true
	if script=="Common_EventScript_WirelessClubAttendant":
		preload("res://core/berry_powder.gd").club(g)
		return true
	if preload("res://core/frontier_challenge.gd").talk(g,npc):return true
	if preload("res://core/contest_hall.gd").talk(g,script):return true
	if script.begins_with("NewMauville_Inside_EventScript_Voltorb"):
		g._start_wild_battle(100,25,"",func(result):
			if result in ["a","caught","fled"]:
				g._flags()["h_caught_"+script]=true
				g.world.refresh_story_actors(g._flags())
				g._persist())
		return true
	if script in ["MirageTower_4F_EventScript_RootFossil","MirageTower_4F_EventScript_ClawFossil","DesertUnderpass_EventScript_Fossil"]:
		pick_fossil(g,script)
		return true
	if script=="RustboroCity_DevonCorp_2F_EventScript_FossilScientist":
		scientist(g)
		return true
	if script.ends_with("_FerryAttendant") or script=="BattleFrontier_OutsideWest_EventScript_FerrySailor":
		ferry(g)
		return true
	if script=="RustboroCity_DevonCorp_3F_EventScript_MrStone" and g._flags().get("h_letter",false) and not g._flags().get("h_exp_share",false):
		g._give_bag_item("学习装置","held","EXP_SHARE")
		g._flags().h_exp_share=true
		g._persist()
		g._dialog(["谢谢你把信送给大吾。请收下这个学习装置，让伙伴携带吧。"],"得文社长")
		return true
	if script=="SSTidalCorridor_EventScript_ExitSailor":
		ferry(g,true)
		return true
	if script=="SlateportCity_Harbor_EventScript_CaptStern" and g._flags().get("h_badge_7",false) and received(g._flags(),"ITEM_SCANNER") and g._bag_count(name_for("ITEM_SCANNER"))>0:
		g._pick("可以把探测器让给我吗？选一样礼物吧。",["深海之牙","深海鳞片","返回"],func(i):
			if i not in [0,1]: return
			take(g,"ITEM_SCANNER")
			g._give_bag_item(["深海之牙","深海鳞片"][i],"evo")
			g._persist()
			g._dialog(["谢谢你的探测器！"],"馆长"))
		return true
	if (script.begins_with("Route119_EventScript_Kecleon") or script.begins_with("Route120_EventScript_Kecleon")) and not g._flags().get("h_caught_"+script,false):
		if not received(g._flags(),"ITEM_DEVON_SCOPE"):
			g._dialog(["前面好像有什么看不见的东西。"])
		else:
			g._pick("用得文侦测镜照一照吗？",["使用","离开"],func(i):
				if i!=0: return
				g._start_wild_battle(352,30,"",func(result):
					if result in ["a","caught","fled"]:
						g._flags()["h_caught_"+script]=true
						g.world.refresh_story_actors(g._flags())
						g._persist()))
		return true
	if script=="MauvilleCity_House2_EventScript_Woman":
		if received(g._flags(),"ITEM_COIN_CASE"): gift(g,"ITEM_COIN_CASE",who)
		elif g._bag_count(name_for("ITEM_HARBOR_MAIL"))<1: g._dialog(["我想用代币盒交换凯那市出售的港口邮件。"],who)
		else:
			g._pick("要用港口邮件交换代币盒吗？",["交换","离开"],func(i):
				if i==0:
					g._consume_item(name_for("ITEM_HARBOR_MAIL"))
					gift(g,"ITEM_COIN_CASE",who))
		return true
	if script in ["MauvilleCity_GameCorner_EventScript_CoinsClerk","MauvilleCity_GameCorner_EventScript_PrizeCornerTMs"]:
		coins(g,script.ends_with("CoinsClerk"))
		return true
	if script=="LilycoveCity_ContestLobby_EventScript_BlendMaster":
		pokeblock(g,true,1)
		return true
	if script.begins_with("BerryBlender_EventScript_Blender"):
		pokeblock(g,true,0 if script.ends_with("Link") else (3 if "Blender3" in script else (2 if "Blender2" in script else 1)))
		return true
	if script=="BattleFrontier_OutsideEast_EventScript_Sudowoodo": return water_tree(g)
	if GIFTS.has(script):
		gift(g,GIFTS[script],who)
		return true
	match script:
		"RusturfTunnel_EventScript_WandasBoyfriend":
			if g._flags().get("h_rusturf_open",false): gift(g,"ITEM_HM_STRENGTH",who)
			else: g._dialog(["这两块岩石把隧道堵住了。谁能帮我打碎它们？"],who)
		"MauvilleCity_BikeShop_EventScript_Rydel":
			g._pick("要骑哪一种？随时可以回来换另一种。",["音速自行车","越野自行车","返回"],func(i):
				if i not in [0,1]: return
				var selected: String = ["ITEM_MACH_BIKE","ITEM_ACRO_BIKE"][i]
				var old: String = g._flags().get("h_bike","")
				if old != selected:
					if not old.is_empty(): take(g,old)
					g._flags().erase(flag_for(selected))
					grant(g,selected)
					g._flags().h_bike = selected
					g.world.bike = false
					g._persist()
				g._dialog(["你的%s已经准备好了。" % name_for(selected)],"风野"))
		"MauvilleCity_EventScript_Wattson":
			if not g._flags().get("h_badge_5",false): return false
			if g._flags().get("h_generator_off",false):
				if not g._flags().get("h_generator_reward",false):
					g._flags().h_generator_reward=true
					g._give_item("招式学习器 24",1,"tm")
					g._persist()
				g._dialog(["辛苦了！十万伏特的招式学习器归你。"],who)
			else: gift(g,"ITEM_BASEMENT_KEY",who)
		"Route113_GlassWorkshop_EventScript_GlassWorker":
			if not received(g._flags(),"ITEM_SOOT_SACK"): gift(g,"ITEM_SOOT_SACK",who)
			else: make_flute(g)
		_: return false
	return true

static func object_action(g, o: Dictionary) -> bool:
	if not g.world.map_data.has("emerald_original"): return false
	if preload("res://core/emerald_cycling.gd").interact(g,o):return true
	if preload("res://core/emerald_fan_club.gd").field(g,o):return true
	var script := str(o.get("source_script",""))
	if script.contains("PokeblockFeeder") and preload("res://core/hoenn_safari.gd").feeder(g,o.at):return true
	if script=="TrainerHill_Entrance_EventScript_Records":
		preload("res://core/hoenn_hill.gd").records(g)
		return true
	if preload("res://core/hoenn_base.gd").action(g,o):return true
	if preload("res://core/hoenn_daily.gd").television(g,str(o.get("source_script",""))):return true
	if Legends.object_action(g,o):return true
	if Side.object_action(g,o): return true
	if preload("res://core/contest_hall.gd").object_action(g,script):return true
	var id := str(o.get("item",""))
	if id in ["ITEM_STORAGE_KEY","ITEM_ROOM_1_KEY","ITEM_ROOM_2_KEY","ITEM_ROOM_4_KEY","ITEM_ROOM_6_KEY","ITEM_SCANNER"]:
		g.world.mark_taken(o)
		gift(g,id,"")
		return true
	if script.get_slice("_EventScript_",1) in SHIP_DOORS:
		var key: String = SHIP_DOORS[script.get_slice("_EventScript_",1)]
		g._dialog(["门锁已打开。"] if open_lock(g,key) else ["上了锁。需要%s。" % name_for(key)])
		return true
	if script.ends_with("BerryBlenderSpeedRecords"):
		var records: Dictionary=g._flags().get("h_blender_rpm",{})
		g._dialog([ "双人　%.1f RPM"%records.get("2",0), "三人　%.1f RPM"%records.get("3",0), "四人　%.1f RPM"%records.get("4",0)],"混合机最高转速")
		return true
	if script.begins_with("BerryBlender_EventScript_BerryBlender"):
		pokeblock(g,true,0 if script.ends_with("Link") else (3 if "Blender3" in script else (2 if "Blender2" in script else 1)))
		return true
	if g.world.map_data.source_id=="MAP_RUSTURF_TUNNEL" and o.get("kind")=="rock" and Vector2i(o.at[0],o.at[1]) in [Vector2i(24,4),Vector2i(24,5)]:
		if not g._party_can_move("ROCK_SMASH"):
			g._dialog([g._field_move_hint("ROCK_SMASH","碎岩")])
		else:
			for rock in g.world.objects:
				if Vector2i(rock.at[0],rock.at[1]) in [Vector2i(24,4),Vector2i(24,5)]: g.world.mark_taken(rock)
			g._flags().h_rusturf_open=true
			gift(g,"ITEM_HM_STRENGTH","隧道中的青年")
		return true
	if script.ends_with("_Generator") and g.world.map_data.source_id=="MAP_NEW_MAUVILLE_INSIDE":
		g._dialog(["发电机已经安静下来了。"] if g._flags().get("h_generator_off",false) else ["发电机正散发着热量。"])
		return true
	return false

static func use(g, nm: String) -> bool:
	if preload("res://core/emerald_lilycove_lady.gd").use(g,nm):return true
	if not g.world.map_data.has("emerald_original"): return false
	if nm in ["音速自行车","越野自行车"]:
		if nm==name_for(g._flags().get("h_bike","")): g._toggle_bike()
		return true
	if nm=="宝可方块盒":
		pokeblock(g,false)
		return true
	if nm=="代币盒":
		g._show_toast("盒内有 %d 枚代币。" % int(g._flags().get("h_coins",0)))
		return true
	if nm in ["黑色玻璃哨","白色玻璃哨"]:
		g._flags().h_encounter_flute=nm
		g._show_toast("野生宝可梦更容易出现了。" if nm=="白色玻璃哨" else "野生宝可梦变少了。")
		return true
	if FLUTES.has(nm):
		g._show_toast("在战斗背包中使用，解除睡眠、混乱或着迷。")
		return true
	if nm=="宝可导航":
		preload("res://core/hoenn_match_call.gd").menu(g)
		return true
	if nm=="探宝器":
		var nearest := Vector2i(-1,-1)
		var distance := 9999
		for o in g.world.objects:
			if o.get("kind","")!="hidden": continue
			var pos := Vector2i(o.at[0],o.at[1])
			if g.world.object_at(pos).is_empty(): continue
			var delta: Vector2i = pos-g.world.player_pos
			if absi(delta.x)>7 or absi(delta.y)>5: continue
			if delta.length_squared()<distance:
				distance=delta.length_squared()
				nearest=delta
		if distance==9999: g._show_toast("附近没有反应。")
		elif distance==0: g._show_toast("就在脚下！按 A 调查。")
		else:
			var direction := ("东" if nearest.x>0 else "西") if absi(nearest.x)>absi(nearest.y) else ("南" if nearest.y>0 else "北")
			g._show_toast("探宝器有反应！方向是"+direction+"。")
		return true
	if nm=="集灰袋":
		g._show_toast("已收集 %d 步火山灰。" % int(g._flags().get("h_ash",0)))
		return true
	if nm=="吼吼鲸喷壶":
		if water_tree(g): return true
		var o: Dictionary = g.world.object_at(g.world.player_pos+g.world._dir_vec())
		if o.get("kind","") in ["berry_tree","soil"]: g._berry_interact(o,o.kind=="berry_tree")
		else: g._show_toast("站到种着树果的土壤旁边浇水。")
		return true
	for id in HINTS:
		if name_for(id)==nm:
			g._show_toast(HINTS[id])
			return true
	return false

const FLUTES := {"蓝色玻璃哨":250,"黄色玻璃哨":500,"红色玻璃哨":500,"白色玻璃哨":1000,"黑色玻璃哨":1000,"漂亮椅子":6000,"漂亮桌子":8000}
static func make_flute(g) -> void:
	var names := FLUTES.keys()
	var labels := []
	for n in names: labels.append("%s · %d 步" % [n,FLUTES[n]])
	g._pick("要用火山灰烧制什么？现有 %d 步。" % int(g._flags().get("h_ash",0)),labels+["返回"],func(i):
		if i<0 or i>=names.size(): return
		var n: String = names[i]
		var amount: int = g._flags().get("h_ash",0)
		if amount<FLUTES[n]:
			g._show_toast("还需要 %d 步火山灰。" % (FLUTES[n]-amount))
			return
		g._flags().h_ash=amount-int(FLUTES[n])
		if n in ["漂亮椅子","漂亮桌子"]:preload("res://core/hoenn_base.gd").add_decoration(g,"PRETTY_CHAIR" if n=="漂亮椅子" else "PRETTY_DESK")
		else:g._give_item(n,1,"key")
		g._persist()
		g._dialog(["烧制好了「%s」。" % n],"玻璃工匠"))

static func field_step(g) -> void:
	if not g.world.map_data.has("emerald_original"): return
	if g.world.map_data.get("mechanisms",{}).has("base"):
		var exit_at: Array=g.world.map_data.mechanisms.base.exit
		if g.world.player_pos==Vector2i(exit_at[0],exit_at[1]) and preload("res://core/hoenn_base.gd").leave(g):return
	if preload("res://core/hoenn_safari.gd").step(g):return
	if preload("res://core/hoenn_hill.gd").step(g):return
	Legends.step(g)
	if Side.step(g):return
	var point: Vector2i=g.world.player_pos
	var switches: Dictionary=g.world.map_data.get("mechanisms",{}).get("power_switches",{})
	if switches.get("%d,%d"%[point.x,point.y],"")=="Red" and received(g._flags(),"ITEM_BASEMENT_KEY") and not g._flags().get("h_generator_off",false):
		g._flags().h_generator_off=true
		g.world._rebuild()
		g._persist()
		g._dialog(["踩下红色开关，发电机停了下来。回紫堇市告诉铁旋吧。"])
	if received(g._flags(),"ITEM_SOOT_SACK") and behavior(g.world.map_data,g.world.player_pos)==0x24:
		var cleared: Dictionary = g.world.get_meta("h_ash_grass",{})
		if not cleared.has(g.world.player_pos):
			cleared[g.world.player_pos]=true
			g.world.set_meta("h_ash_grass",cleared)
			g._flags().h_ash=mini(9999,int(g._flags().get("h_ash",0))+1)

static func passage(g, target: Dictionary) -> String:
	if not g.world.map_data.has("emerald_original"): return ""
	var source: String = g.world.map_data.source_id
	var mid: String = target.get("map","")
	if g.world.map_data.id=="em_trainer_hill_entrance" and mid=="em_trainer_hill_1f" and not g._flags().has("h_hill"):return "请先在一楼的接待处报名。"
	if g.world.map_data.id=="em_trainer_hill_entrance" and mid=="hoenn_111":g._flags().erase("h_hill")
	var safari_gate:=preload("res://core/hoenn_safari.gd").passage(g,target)
	if safari_gate!="":return safari_gate
	var legendary_gate:=Legends.passage(g,str(g.world.map_data.id),target)
	if legendary_gate!="":return legendary_gate
	var side_gate := Side.passage(g,mid)
	if not side_gate.is_empty(): return side_gate
	var key := ""
	if source=="MAP_ABANDONED_SHIP_HIDDEN_FLOOR_CORRIDORS" and mid=="em_abandoned_ship_hidden_floor_rooms":
		key=SHIP_ROOMS.get("%d,%d" % [target.at[0],target.at[1]],"")
	if source=="MAP_ABANDONED_SHIP_CORRIDORS_B1F" and mid=="em_abandoned_ship_room_b1f": key="ITEM_STORAGE_KEY"
	if not key.is_empty() and not open_lock(g,key): return "门锁住了。需要%s。" % name_for(key)
	if mid=="em_safari_zone_south" and source=="MAP_ROUTE121_SAFARI_ZONE_ENTRANCE" and not received(g._flags(),"ITEM_POKEBLOCK_CASE"):
		return "进入狩猎地带前，请先去水静市领取宝可方块盒。"
	if mid=="em_desert_underpass" and not g._flags().get("h_champion",false): return "隧道还在挖掘中。"
	if mid=="em_mirage_tower_1f" and source=="MAP_ROUTE111":
		if g._flags().has("h_tower_fossil"): return "幻影之塔已经沉入了沙中。"
		if not received(g._flags(),"ITEM_GO_GOGGLES"): return "风沙太大，需要防沙护目镜。"
	if target.get("map")=="em_new_mauville_inside" and not received(g._flags(),"ITEM_BASEMENT_KEY"):
		return "通往新紫堇地下的门锁住了，需要铁旋的地下钥匙。"
	return ""

static func actor_visibility(row: Dictionary, flags: Dictionary, source_id: String) -> int:
	var lady_visibility:=preload("res://core/emerald_lilycove_lady.gd").visible(row,flags)
	if lady_visibility>=0:return lady_visibility
	var master_flag:=str(row.get("source_flag",""))
	if master_flag=="FLAG_HIDE_LILYCOVE_CONTEST_HALL_BLEND_MASTER":return int(preload("res://core/hoenn_daily.gd").blender_active(flags))
	if master_flag=="FLAG_HIDE_LILYCOVE_CONTEST_HALL_BLEND_MASTER_REPLACEMENT":return int(not preload("res://core/hoenn_daily.gd").blender_active(flags))
	var script := str(row.get("source_script",""))
	if script=="DewfordTown_Hall_EventScript_SludgeBombMan":return int(flags.get("h_badge_5",false))
	if script=="FallarborTown_PokemonCenter_1F_EventScript_Lanette":return int(not flags.get("h_lanette_met",false))
	if script=="Route114_LanettesHouse_EventScript_Lanette":return int(flags.get("h_lanette_met",false))
	if row.get("source_flag","")=="FLAG_HIDE_SAFARI_ZONE_SOUTH_CONSTRUCTION_WORKERS":return int(not flags.get("h_champion",false))
	if row.get("source_flag","")=="FLAG_HIDE_SAFARI_ZONE_SOUTH_EAST_EXPANSION":return int(flags.get("h_champion",false))
	if script=="LilycoveCity_DepartmentStoreRooftop_EventScript_SaleWoman":return int(flags.get("h_champion",false) and preload("res://core/hoenn_base.gd").sale_today())
	var reporters:=preload("res://core/hoenn_reporters.gd").visible(row,flags)
	if reporters>=0:return reporters
	var legend_visible:=Legends.visibility(row,flags)
	if legend_visible>=0:return legend_visible
	var side_visible:=Side.actor_visibility(script,flags)
	if side_visible>=0:return side_visible
	if script.begins_with("NewMauville_Inside_EventScript_Voltorb"): return int(not flags.get("h_caught_"+script,false))
	if script=="SlateportCity_Harbor_EventScript_CaptStern" and flags.get("h_sub_stolen",false): return 1
	if script=="SeafloorCavern_Entrance_EventScript_Grunt": return int(not flags.get("h_dive",false))
	if script=="MauvilleCity_EventScript_Wattson": return int(flags.get("h_badge_5",false) and not flags.get("h_generator_reward",false))
	if script in ["RusturfTunnel_EventScript_Wanda","RusturfTunnel_EventScript_WandasBoyfriend"]: return int(not flags.get("h_rusturf_open",false))
	if script.ends_with("_FerryAttendant") and source_id in ["MAP_SLATEPORT_CITY_HARBOR","MAP_LILYCOVE_CITY_HARBOR"]: return int(received(flags,"ITEM_SS_TICKET"))
	if script in ["MirageTower_4F_EventScript_RootFossil","MirageTower_4F_EventScript_ClawFossil"]: return int(not flags.has("h_tower_fossil"))
	if script=="DesertUnderpass_EventScript_Fossil": return int(flags.get("h_champion",false) and flags.has("h_tower_fossil") and not flags.get("h_second_fossil",false))
	if flags.get("h_caught_"+script,false): return 0
	return -1

const SHIP_DOORS := {"Room1Door":"ITEM_ROOM_1_KEY","Room2Door":"ITEM_ROOM_2_KEY","Room4Door":"ITEM_ROOM_4_KEY","Room6Door":"ITEM_ROOM_6_KEY","StorageRoomDoor":"ITEM_STORAGE_KEY"}
const SHIP_ROOMS := {"6,14":"ITEM_ROOM_1_KEY","21,14":"ITEM_ROOM_2_KEY","6,2":"ITEM_ROOM_4_KEY","36,2":"ITEM_ROOM_6_KEY"}

static func open_lock(g, id: String) -> bool:
	var flags: Dictionary = g._flags()
	if flags.get("h_lock_"+id,false): return true
	if not received(flags,id) or g._bag_count(name_for(id))==0: return false
	take(g,id)
	flags["h_lock_"+id]=true
	g.world._rebuild()
	g._persist()
	return true

static func pick_fossil(g, script: String) -> void:
	var flags: Dictionary = g._flags()
	var second := script.begins_with("DesertUnderpass")
	var id := "ITEM_ROOT_FOSSIL" if script.contains("RootFossil") else "ITEM_CLAW_FOSSIL"
	if second:
		if not flags.get("h_champion",false) or not flags.has("h_tower_fossil") or flags.get("h_second_fossil",false): return
		id="ITEM_ROOT_FOSSIL" if flags.h_tower_fossil=="ITEM_CLAW_FOSSIL" else "ITEM_CLAW_FOSSIL"
	elif flags.has("h_tower_fossil"): return
	g._pick("要取下%s吗？" % name_for(id),["取下","离开"],func(i):
		if i!=0: return
		if second: flags.h_second_fossil=true
		else: flags.h_tower_fossil=id
		grant(g,id)
		if not second: g._do_warp({"region":"hoenn","hoenn_native":true,"map":"hoenn_111","at":[19,59],"facing":"down"})
		g.world.refresh_story_actors(flags)
		g._persist()
		g._dialog(["找到了「%s」。" % name_for(id)]+([] if second else ["幻影之塔倒塌了，另一块化石沉入沙中。"])))

static func scientist(g) -> void:
	var flags: Dictionary = g._flags()
	var pending := int(flags.get("h_reviving",0))
	if pending>0:
		if not flags.get("h_fossil_ready",false):
			g._dialog(["复原还需要一点时间。出去走走再来吧。"],"研究员")
			return
		var mon: Dictionary = g.PartyScript.make(pending,20,g.EncounterScript.moves_for(pending,20))
		var place: String = g._store_mon(mon)
		flags.erase("h_reviving")
		flags.erase("h_fossil_ready")
		g._persist()
		g._dialog(["%s复活了！%s" % [mon.name,"已加入队伍。" if place=="party" else "已送到电脑。"]],"研究员")
		return
	var ids := []
	for id in ["ITEM_ROOT_FOSSIL","ITEM_CLAW_FOSSIL"]:
		if received(flags,id) and g._bag_count(name_for(id))>0: ids.append(id)
	if ids.is_empty():
		g._dialog(["如果找到化石，就带来这里。我能让它复活。"],"研究员")
		return
	var options := []
	for id in ids: options.append(name_for(id))
	g._pick("要复活哪块化石？",options+["返回"],func(i):
		if i<0 or i>=ids.size(): return
		take(g,ids[i])
		flags.h_reviving=345 if ids[i]=="ITEM_ROOT_FOSSIL" else 347
		flags.h_fossil_ready=false
		g._persist()
		g._dialog(["已开始复原。出去走走，再回来领宝可梦。"],"研究员"))

static func ferry(g, leaving_ship: bool=false) -> void:
	if not g._flags().get("h_champion",false) or not received(g._flags(),"ITEM_SS_TICKET"):
		g._dialog(["请出示丰缘船票。"],"乘务员")
		return
	if leaving_ship:
		var to: String = g._flags().get("h_ship_destination","")
		if to.is_empty(): return
		g._flags().erase("h_ship_destination")
		g._do_warp({"region":"hoenn","hoenn_native":true,"map":to,"at":[8,11],"facing":"down"})
		g._persist()
		return
	var slateport: bool = g.world.map_data.source_id=="MAP_SLATEPORT_CITY_HARBOR"
	var frontier: bool = g.world.map_data.source_id=="MAP_BATTLE_FRONTIER_OUTSIDE_WEST"
	var options: Array = ["凯那市","水静市"] if frontier else (["水静市","对战开拓区"] if slateport else ["凯那市","对战开拓区"])
	if not frontier and not slateport:
		for island in Legends.ISLANDS:
			if g._bag_count(Legends.ISLANDS[island][0])>0:options.append(island)
	g._pick("欢迎搭乘破浪号。您想去哪里？",options+["返回"],func(i):
		if i<0 or i>=options.size():return
		if options[i] in Legends.ISLANDS:
			var port:Array=Legends.ISLANDS[options[i]]
			Legends.warp(g,port[1],port[2]);return
		if options[i]=="对战开拓区":
			g._do_warp({"region":"hoenn","hoenn_native":true,"map":"em_battle_frontier_outside_west","at":[19,67],"facing":"up"})
		else:
			var dest := "em_slateport_city_harbor" if options[i]=="凯那市" else "em_lilycove_city_harbor"
			if frontier: g._do_warp({"region":"hoenn","hoenn_native":true,"map":dest,"at":[8,11],"facing":"down"})
			else:
				g._flags().h_ship_destination=dest
				g._do_warp({"region":"hoenn","hoenn_native":true,"map":"em_ss_tidal_corridor","at":[1,10],"facing":"up"})
		g._persist())

static func coins(g, buy: bool) -> void:
	if not received(g._flags(),"ITEM_COIN_CASE"):
		g._dialog(["请先准备一个代币盒。"])
		return
	var options := ["50 枚 · ₽1000","500 枚 · ₽10000"] if buy else ["影子分身 · 1500 枚","精神强念 · 3500 枚","冰冻光束 · 4000 枚","十万伏特 · 4000 枚","喷射火焰 · 4000 枚"]
	g._pick("盒内有 %d 枚代币。" % int(g._flags().get("h_coins",0)),options+["返回"],func(i):
		if i<0 or i>=options.size(): return
		var count: int = g._flags().get("h_coins",0)
		if buy:
			var n: int = [50,500][i]
			if g.save_data.get("money",0)<n*20 or count+n>9999:
				g._show_toast("钱不足，或代币盒已满。")
				return
			g.save_data.money-=n*20
			g._flags().h_coins=count+n
		else:
			var cost: int = [1500,3500,4000,4000,4000][i]
			if count<cost:
				g._show_toast("代币不够。")
				return
			g._flags().h_coins=count-cost
			g._give_item("招式学习器 %02d" % [32,29,13,24,35][i],1,"tm")
		g._persist()
		g._show_toast("兑换完成。"))

static func pokeblock(g, blending: bool, partners:=1) -> void:
	if not received(g._flags(),"ITEM_POKEBLOCK_CASE"):
		g._dialog(["先到水静市华丽大赛柜台领一个宝可方块盒。"])
		return
	var flags: Dictionary = g._flags()
	if blending:
		var berries := []
		for item in g.bag_items:
			if item.get("category","")=="berry" and int(item.get("count",0))>0: berries.append(item.name)
		if berries.is_empty():
			g._dialog(["放入一颗树果才能启动混合机。"])
			return
		g._pick("选择要混合的树果",berries+["返回"],func(i):
			if i<0 or i>=berries.size(): return
			var berry: String = berries[i]
			var berry_key:=""
			for entry in g.bag_items:
				if entry.name==berry:berry_key=str(entry.get("berry","")).to_lower()
			if not preload("res://core/emerald_contest.gd").data().berries.has(berry_key):
				g._dialog(["这台混合机需要丰缘可混合的树果。"]);return
			var machine=preload("res://scenes/contest_blender_room.gd").new() if partners==0 else preload("res://scenes/contest_blender.gd").new()
			g.menu_layer.add_child(machine)
			g.panel_open+=1
			g._set_hud_visible(false)
			if partners==0:machine.setup(berry_key)
			else:machine.setup(berry_key,partners,partners==1 and preload("res://core/hoenn_daily.gd").blender_active(flags))
			machine.completed.connect(func(block):
				g.panel_open=maxi(0,g.panel_open-1)
				g._set_hud_visible(g.panel_open==0)
				if block.is_empty():return
				g._consume_item(berry)
				block.name=berry
				flags.get_or_add("h_blocks",[]).append(block)
				var records: Dictionary=flags.get_or_add("h_blender_rpm",{})
				var people:=str(int(block.get("people",partners+1)))
				records[people]=maxf(float(records.get(people,0)),float(block.rpm))
				g._persist()
				g._dialog(["用%s做成了宝可方块，已装进盒里。" % berry])))
		return
	var blocks: Array = flags.get("h_blocks",[])
	if blocks.is_empty():
		g._dialog(["盒子是空的。拿树果去水静市华丽大赛大厅的树果混合机。"])
		return
	var slots := []
	var options := []
	for i in g.save_data.get("party",[]).size():
		var mon: Dictionary = g.save_data.party[i]
		if mon.is_empty(): continue
		slots.append(i)
		options.append(str(mon.name))
	var block=blocks[0]
	var label: String=block.get("name","树果") if block is Dictionary else str(block)
	g._pick("把%s方块喂给谁？" % label,options+["返回"],func(i):
		if i<0 or i>=slots.size(): return
		var mon: Dictionary=g.save_data.party[slots[i]]
		if int(mon.get("sheen",0))>=255:
			g._show_toast("它吃饱了。")
			return
		blocks.pop_front()
		var berry_key:=str(block.get("berry","")) if block is Dictionary else str(block).to_lower()
		if not preload("res://core/emerald_contest.gd").data().berries.has(berry_key):
			for key in g.get_node("/root/Data").berries:
				if g.get_node("/root/Data").berry_name(key)==label:berry_key=key;break
		var berry_data: Dictionary=block if block is Dictionary and block.has("flavor") else preload("res://core/emerald_contest.gd").data().berries.get(berry_key,{"flavor":[10,0,0,0,0],"smooth":20})
		var stats: Array=mon.get_or_add("contest_condition",[0,0,0,0,0])
		for c in 5:stats[c]=mini(255,int(stats[c])+int(berry_data.flavor[c]))
		mon.sheen=mini(255,int(mon.get("sheen",0))+int(berry_data.smooth))
		flags.h_blocks=blocks
		g._persist()
		g._dialog(["%s吃下了宝可方块，光泽提高了。" % mon.name]))

static func leave(g, next_map: Dictionary) -> void:
	if not g.world.map_data.has("emerald_original") or next_map.id==g.world.map_data.id: return
	if g.world.has_meta("h_ash_grass"): g.world.remove_meta("h_ash_grass")
	if g.world.map_data.source_id=="MAP_RUSTBORO_CITY_DEVON_CORP_2F" and g._flags().get("h_reviving",0)>0:
		g._flags().h_fossil_ready=true
	if not next_map.get("allow_cycling",false): g.world.bike=false

static func flute_effect(mon: Dictionary, name_text: String) -> bool:
	var conditions := {"蓝色玻璃哨":"slp","黄色玻璃哨":"cfu","红色玻璃哨":"inf"}
	if not conditions.has(name_text): return false
	var affected: bool = mon.get("status","")==conditions[name_text]
	if affected:
		mon.status=""
		mon.status_turns=0
	if name_text=="红色玻璃哨" and mon.get("attract",false):
		mon.erase("attract")
		affected=true
	return affected

const CRACKED_FLOORS := {
	"MAP_GRANITE_CAVE_B1F":"em_granite_cave_b2f", "MAP_MIRAGE_TOWER_2F":"em_mirage_tower_1f",
	"MAP_MIRAGE_TOWER_3F":"em_mirage_tower_2f", "MAP_SKY_PILLAR_2F":"em_sky_pillar_1f",
	"MAP_SKY_PILLAR_4F":"em_sky_pillar_3f"}

static func fall_through(g) -> bool:
	var map: Dictionary = g.world.map_data
	var src: String = map.get("source_id","")
	if not CRACKED_FLOORS.has(src): return false
	var pos: Vector2i = g.world.player_pos
	if src.begins_with("MAP_SKY_PILLAR_") and not g._flags().get("h_peace",false):
		# The clean 4F layout keeps the cracks above the small middle landing on 3F.
		for change in map.get("mechanisms",{}).get("clean",[]):
			if pos==Vector2i(int(change[0]),int(change[1])): return false
	var tile := behavior(map,pos)
	if tile!=0x66 and (tile!=0xd2 or (g.world.bike and g._flags().get("h_bike","")=="ITEM_MACH_BIKE")): return false
	g._do_warp({"region":"hoenn","hoenn_native":true,"map":CRACKED_FLOORS[src],"at":[pos.x,pos.y],"facing":"down"})
	g._persist()
	g._show_toast("脚下的地板塌了！")
	return true

static func water_tree(g) -> bool:
	var tree: Dictionary = g.world._npc_at(g.world.player_pos+g.world._dir_vec())
	if tree.get("source_script","")!="BattleFrontier_OutsideEast_EventScript_Sudowoodo": return false
	if not received(g._flags(),"ITEM_WAILMER_PAIL"):
		g._dialog(["这棵树好像在微微晃动。"])
		return true
	g._pick("对着这棵奇怪的树使用喷壶吗？",["浇水","离开"],func(i):
		if i!=0: return
		g._start_wild_battle(185,40,"",func(result):
			if result in ["caught","a"]:
				g._flags().h_caught_BattleFrontier_OutsideEast_EventScript_Sudowoodo=true
				g.world.refresh_story_actors(g._flags())
				g._persist()))
	return true
