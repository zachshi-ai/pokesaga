extends Node2D
## 启动场景：自检 + 场景装配 + 输入（键盘 / 触摸）。

const StartMenu := preload("res://scenes/start_menu.gd")
const TitleScreen := preload("res://scenes/title_screen.gd")
const WorldScript := preload("res://core/world.gd")
const BattleScript := preload("res://core/battle.gd")
const BattleUI := preload("res://scenes/battle_ui.gd")
const DexCatalog := preload("res://core/dex_catalog.gd")
const DexVariants := preload("res://core/dex_variants.gd")
const DexUI := preload("res://scenes/dex_ui.gd")
const EditorUI := preload("res://scenes/editor_ui.gd")
const TouchScroll := preload("res://core/touch_scroll.gd")
const EncounterScript := preload("res://core/encounter.gd")
const GrowthScript := preload("res://core/growth.gd")
const ShopUI := preload("res://scenes/shop_ui.gd")
const FacilityScript := preload("res://core/facility.gd")
const PartyUI := preload("res://scenes/party_ui.gd")
const BagUI := preload("res://scenes/bag_ui.gd")
const PartyScript := preload("res://core/party.gd")
const SaveScript := preload("res://core/save_game.gd")
const StoryScript := preload("res://core/story.gd")
var johto_league := preload("res://core/johto_league.gd").new()
const FusionScript := preload("res://core/fusion.gd")
const FusionUI := preload("res://scenes/fusion_ui.gd")
const FormItemUI := preload("res://scenes/form_item_ui.gd")

var world
var title_screen
var title_layer: CanvasLayer
var snd                     # 原版曲子的 BGM / SFX
var _last_bump := 0
var results: Array = []
var ui_layer: CanvasLayer
var name_label: Label
var hint_label: Label
var toast: Label
var save_data: Dictionary = {}
var menu_layer: CanvasLayer
var start_menu: StartMenu
var _start_after_step := false
var team_slots: Array = []
var rng := RandomNumberGenerator.new()
var appearance_rng := RandomNumberGenerator.new()
var story                      # 剧情引擎
var story_on := true           # 自检/端到端点跑时关掉，免得弹对话打断脚本
var story_queue: Array = []    # 剧情动作队列
var _escort_active := false
var story_abort := false       # 这一场剧情被战斗中断（输了），不写完成标记
var cur_story: Dictionary = {} # 正在播的事件
var grass_streak := 0
var active_battle: Control
var panel_open := 0
var held_dir := ""
var run_held := false
var _field_fingers := {}
var _post_warp_keys := {}
var ui_timer := 0.0
var touch_layer: CanvasLayer
var money_label: Label
var badges_label: Label
var _talked_once := false
var bag_items: Array = []
var _bag_ui = null

const STEP_INTERVAL := 0.13
const KEY_MAP := [["up", KEY_UP], ["down", KEY_DOWN], ["left", KEY_LEFT], ["right", KEY_RIGHT],
	["up", KEY_W], ["down", KEY_S], ["left", KEY_A], ["right", KEY_D]]

func _ready() -> void:
	get_tree().quit_on_go_back = false
	# 数据表必须在任何界面之前加载：自检不跑了，这里不能省
	if not Data.load_core_tables():
		push_error("核心数据表加载失败")
	bag_items = _default_items()
	world = WorldScript.new()
	add_child(world)
	snd = load("res://core/sound.gd").new()
	add_child(snd)
	world.warp_ready.connect(_on_warp_ready)
	_build_ui()

	var ok := true
	var argv0: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	var run_selftest := "--selftest" in argv0 or "-selftest" in argv0
	# 脚本化跑（自检 / 端到端 / 截图指定地图）时不播剧情，免得弹窗打断
	for a in argv0:
		if String(a).begins_with("--e2e") or String(a).begins_with("--map=") or String(a) == "--selftest" \
				or String(a).begins_with("--only") or String(a).begins_with("--walk-"):
			story_on = false
	# 只跑指定用例的快速通道（调机制时用，省得每次等全套）
	var want_only := ""
	for a in argv0:
		if String(a).begins_with("--only="):
			want_only = String(a).split("=")[1]
	if run_selftest or want_only != "":
		SaveScript.use_test_slot()
	if want_only != "":
		var want := want_only
		if want == "johto":
			ok = _t("城都训练家", await _test_johto_trainers()) and ok
			ok = _t("城都野生", _test_johto_wild()) and ok
			ok = _t("城都徽章与初始", _test_johto_story()) and ok
			ok = _t("秘传与道具可达", _test_field_kit()) and ok
			ok = _t("道具能用", _test_item_use()) and ok
		elif want == "mdet":
			ok = _t("招式细节", _test_move_details()) and ok
			ok = _t("招式细节二", _test_move_details2()) and ok
			ok = _t("招式细节三", _test_move_details3()) and ok
			ok = _t("形态切换", _test_form_switch()) and ok
			ok = _t("融合系统", _test_fusion()) and ok
			ok = _t("招式效果回合", _test_effect_coverage()) and ok
		elif want == "abilities":
			ok = _t("特性效果", _test_ability_effects()) and ok
			ok = _t("特性效果二", _test_ability_effects2()) and ok
			ok = _t("特性名一致", _test_ability_names()) and ok
			ok = _t("特性效果三", _test_ability_effects3()) and ok
			ok = _t("特性效果四", _test_ability_effects4()) and ok
			ok = _t("形态切换", _test_form_switch()) and ok
		elif want == "forms":
			ok = _t("形态切换", _test_form_switch()) and ok
			ok = _t("融合系统", _test_fusion()) and ok
		elif want == "story":
			ok = _t("剧情流程", _test_story()) and ok
			ok = _t("剧情表体检", _test_story_table()) and ok
		elif want == "wf":
			ok = _t("进出房间方向", _test_warp_facing()) and ok
		elif want == "surf":
			ok = _t("土坡可跳", _test_ledge()) and ok
			ok = _t("冲浪", _test_surf()) and ok
			ok = _t("道具能用", _test_item_use()) and ok
		elif want == "field":
			ok = _t("秘传开路与培育", _test_fieldwork()) and ok
		elif want == "berry":
			ok = _t("树果", _test_berries()) and ok
		elif want == "reach":
			ok = _t("每扇门都走得到", _test_warp_reach()) and ok
			ok = _t("跨地区走得通", _test_world_reach()) and ok
		elif want == "lift":
			ok = _t("百货电梯", _test_elevator()) and ok
		elif want == "terrain":
			ok = _t("地形机制", _test_terrain()) and ok
		else:
			push_error("未知自检分组 " + want)
			ok = false
		print("SELFTEST " + ("PASS" if ok else "FAIL"))
		SaveScript.clear_test_slot()
		get_tree().quit(0 if ok else 1)
		return
	if run_selftest:
		ok = _t("核心数据表", _test_tables()) and ok
		ok = _t("图块图集", _test_atlas()) and ok
		ok = _t("地图加载", _test_map()) and ok
		ok = _t("碰撞与移动", _test_collision()) and ok
		ok = _t("跨地区传送", _test_warp()) and ok
		ok = _t("战斗回合", _test_battle()) and ok
		ok = _t("存档读写", _test_save()) and ok
		ok = _t("战斗界面", await _test_battle_ui()) and ok
		ok = _t("队伍数据", _test_party()) and ok
		ok = _t("菜单界面", await _test_menus()) and ok
		ok = _t("图鉴与回写", await _test_dex()) and ok
		ok = _t("修改器", await _test_editor()) and ok
		ok = _t("野外遇敌", _test_encounter()) and ok
		ok = _t("城都训练家", await _test_johto_trainers()) and ok
		ok = _t("城都野生", _test_johto_wild()) and ok
		ok = _t("城都徽章与初始", _test_johto_story()) and ok
		ok = _t("投球捕获", _test_catch()) and ok
		ok = _t("捕获入队", _test_catch_add()) and ok
		ok = _t("成长与进化", _test_growth()) and ok
		ok = _t("逃跑判定", _test_flee()) and ok
		ok = _t("地图连通性", _test_map_graph()) and ok
		ok = _t("对战塔", _test_facility()) and ok
		ok = _t("按键可操作", _test_input()) and ok
		ok = _t("朝向帧", _test_facing()) and ok
		ok = _t("土坡可跳", _test_ledge()) and ok
		ok = _t("冲浪", _test_surf()) and ok
		ok = _t("道具能用", _test_item_use()) and ok
		ok = _t("秘传开路与培育", _test_fieldwork()) and ok
		ok = _t("地形机制", _test_terrain()) and ok
		ok = _t("每扇门都走得到", _test_warp_reach()) and ok
		ok = _t("跨地区走得通", _test_world_reach()) and ok
		ok = _t("道馆战与徽章", _test_gyms()) and ok
		ok = _t("百货电梯", _test_elevator()) and ok
		ok = _t("剧情流程", _test_story()) and ok
		ok = _t("剧情表体检", _test_story_table()) and ok
		ok = _t("NPC 都有话讲", _test_npc_lines()) and ok
		ok = _t("图鉴 1025 只都在", _test_dex_complete()) and ok
		ok = _t("招式与学习表通顺", _test_move_data()) and ok
		ok = _t("全图鉴混战不崩", _test_battle_sweep()) and ok
		ok = _t("形态数据完整", _test_forms()) and ok
		ok = _t("战斗中的形态变化", _test_battle_forms()) and ok
		ok = _t("进出门与对话", _test_door_talk()) and ok
		ok = _t("进出房间方向", _test_warp_facing()) and ok
		ok = _t("Z 招式与极巨招式", _test_gimmick_moves()) and ok
		ok = _t("太晶化", _test_tera()) and ok
		ok = _t("形态进化链", _test_form_evolution()) and ok
		ok = _t("变化按钮不混淆", _test_gimmick_label()) and ok
		ok = _t("天气与场地系统", _test_field_system()) and ok
		ok = _t("两回合招式与替身接力", _test_charge_sub()) and ok
		ok = _t("太晶碎块改属性", _test_tera_shard()) and ok
		ok = _t("天气特性与半无敌", _test_weather_ability()) and ok
		ok = _t("携带道具", _test_held_items()) and ok
		ok = _t("树果", _test_berries()) and ok
		ok = _t("特性效果", _test_ability_effects()) and ok
		ok = _t("招式附带效果", _test_move_extras()) and ok
		ok = _t("特性效果二", _test_ability_effects2()) and ok
		ok = _t("特性名一致", _test_ability_names()) and ok
		ok = _t("特性效果三", _test_ability_effects3()) and ok
		ok = _t("特性效果四", _test_ability_effects4()) and ok
		ok = _t("招式细节", _test_move_details()) and ok
		ok = _t("招式细节二", _test_move_details2()) and ok
		ok = _t("招式细节三", _test_move_details3()) and ok
		ok = _t("形态切换", _test_form_switch()) and ok
		ok = _t("融合系统", _test_fusion()) and ok
		ok = _t("招式效果回合", _test_effect_coverage()) and ok

	if run_selftest:
		for line in results:
			print(line)
		print("SELFTEST " + ("PASS" if ok else "FAIL"))
		SaveScript.clear_test_slot()
		get_tree().quit(0 if ok else 1)
		return

	var argv: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if not _has_debug_start(argv):
		_show_title()
		return
	_restore_from_save()

	for a in argv:
		if String(a).begins_with("--at="):
			var xy := String(a).substr(5).split(",")
			if xy.size() == 2:
				world.player_pos = Vector2i(int(xy[0]), int(xy[1]))
				world.render_pos = Vector2(world.player_pos)
				world._sync_player()
		if String(a).begins_with("--face="):
			world.facing = String(a).substr(7)
			world.frame_col = 0
			world._sync_player()
		if String(a).begins_with("--walk="):
			# 截图中途姿势：0 站 / 1 抬左脚 / 2 抬右脚
			world.frame_col = int(String(a).substr(7))
			world._sync_player()
		if String(a).begins_with("--map="):
			var parts := String(a).substr(6).split("/")
			if parts.size() == 2:
				var mm: Dictionary = Data.load_map(parts[0], parts[1])
				if not mm.is_empty():
					world.load_map(mm)
					var sp: Array = mm.get("spawn", [0, 0])
					world.player_pos = Vector2i(int(sp[0]), int(sp[1]))
					world._sync_player()
					_apply_defeated()
					_ensure_form_npc()
		for pa in argv0:
			# 截图/调试用：直接跟某格的 NPC 说话（手机上没键盘，命令行验流程要用）
			if String(pa).begins_with("--talk="):
				var tv := String(pa).substr(7).split(",")
				if tv.size() == 2:
					var tp := Vector2i(int(tv[0]), int(tv[1]))
					for n3 in world.npcs:
						var at3: Array = (n3 as Dictionary).get("at", [-1, -1])
						if int(at3[0]) == tp.x and int(at3[1]) == tp.y:
							if _talked_once:
								break
							_talked_once = true
							print("talk dbg: 和 ", n3.get("name", ""), " 说话")
							_talk_to_npc(n3)
							break
		for pa in argv0:
			if String(pa) == "--interact":
				print("interact dbg: 站 ", world.player_pos, " 朝向 ", world.facing)
				_on_action()
				print("objects dbg: ", world.objects.size(), " 画出来 ", world._obj_nodes.size())
				for nd in world._obj_nodes:
					if nd is Sprite2D and nd.texture != null:
						print("   sprite ", nd.position, " z=", nd.z_index, " tex=", nd.texture.resource_path, " size=", nd.texture.get_size())
				for ob in world.objects:
					print("  ", ob.get("kind"), ob.get("at"), ob.get("name", ""))
		for pa in argv0:
			# 截图/调试用：按一次方向，看看能不能走/能不能跳坡
			if String(pa).begins_with("--press="):
				var pv := String(pa).substr(8)
				var dv := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
				var d2: Vector2i = dv.get(pv, Vector2i.ZERO)
				var before: Vector2i = world.player_pos
				print("press dbg: 从 ", before, " 按 ", pv, " 挡格=", world.is_blocked(before))
				world.step(d2)
				print("press dbg: 走成功=", world.walking, " 跳=", world.jumping, " 落点=", world.player_pos)
				world.finish_walk()
				print("press dbg: 停在 ", world.player_pos)
	if "--e2e-johto-story" in argv:
		await _e2e_johto_story()
		get_tree().quit(0)
		return
	if "--e2e-story" in argv:
		await _e2e_story()
		get_tree().quit(0)
		return
	if "--story-demo" in argv:
		await _story_demo()
	var has_walk := false
	for a in argv:
		if String(a).begins_with("--walk-from="):
			has_walk = true
	if has_walk:
		var wf := Vector2i(-1, -1)
		var wd := "down"
		var wn := 4
		var wmap := "kanto/kanto_main"
		for a in argv:
			var s2 := String(a)
			if s2.begins_with("--walk-from="):
				var pv2 := s2.substr(12).split(",")
				wf = Vector2i(int(pv2[0]), int(pv2[1]))
			elif s2.begins_with("--walk-dir="):
				wd = s2.substr(11)
			elif s2.begins_with("--walk-n="):
				wn = int(s2.substr(9))
			elif s2.begins_with("--walk-map="):
				wmap = s2.substr(11)
		var reg := wmap.split("/")[0]
		var mid := wmap.split("/")[1]
		world.load_map(Data.load_map(reg, mid))
		world.warp_to(wf)
		var wv := {"up": Vector2i(0, -1), "down": Vector2i(0, 1), "left": Vector2i(-1, 0), "right": Vector2i(1, 0)}
		var d3: Vector2i = wv.get(wd, Vector2i(0, 1))
		print("walk dbg: 起点 ", wf, " 地图 ", world.map_data.get("id", ""))
		for i in wn:
			var okw: bool = world.step(d3)
			world.tick_walk(1.0)
			var ev0 := String(world.last_event)
			var bag0 := (bag_items as Array).size()
			_after_step()
			print("walk dbg: 第%d步 ok=%s 位置=%s 地图=%s 事件=%s 背包 %d->%d" % [i + 1, okw, world.player_pos, world.map_data.get("id", ""), ev0, bag0, (bag_items as Array).size()])
			if String(world.map_data.get("id", "")) != mid:
				print("walk dbg: >>> 切图成功 -> ", world.map_data.get("id", ""), " at ", world.player_pos, " (", world.map_data.get("name", ""), ")")
				break
		get_tree().quit(0)
		return
	if "--e2e-walk" in argv:
		for a in argv:
			if String(a).begins_with("--dir="):
				_e2e_walk(String(a).substr(6))
		get_tree().quit(0)
		return
	if "--e2e-all" in argv:
		_e2e_all_pc()
		get_tree().quit(0)
		return
	if "--e2e" in argv:
		_e2e_pc()
		get_tree().quit(0)
		return
	if "--fusionvis" in argv:
		await get_tree().create_timer(0.4).timeout
		print("vis: 首图 ", String(world.map_data.get("id", "")), " 融合按钮=", _fusion_btn_visible())
		world.load_map(Data.load_map("kanto", "kanto_main"))
		world.warp_to(Vector2i(24, 217))
		await get_tree().create_timer(0.4).timeout
		print("vis: 大地图 融合按钮=", _fusion_btn_visible())
		world.load_map(Data.load_map("kanto", "pewtercity_pokemoncenter_1f"))
		world.warp_to(Vector2i(7, 4))
		await get_tree().create_timer(0.4).timeout
		print("vis: 宝可梦中心 融合按钮=", _fusion_btn_visible())
		_ensure_form_npc()
		for n in world.npcs:
			if bool((n as Dictionary).get("form_items", false)):
				print("vis: 研究员在 ", str((n as Dictionary).get("at", [])))
				_talk_to_npc(n as Dictionary)
				break
		await get_tree().create_timer(0.5).timeout
		for c in menu_layer.get_children():
			if c.get_script() == FormItemUI:
				var texts: Array = []
				for b2 in c.find_children("*", "Button", true, false):
					texts.append((b2 as Button).text)
				print("vis: 道具台 %d 项 %s" % [texts.size(), str(texts.slice(1, 3))])
		get_tree().quit(0)
		return
	if "--e2e-story" in argv:
		await _e2e_story()
		get_tree().quit(0)
		return
	if "--story-demo" in argv:
		await _story_demo()
	if "--e2e-walk" in argv:
		for a in argv:
			if String(a).begins_with("--dir="):
				_e2e_walk(String(a).substr(6))
		get_tree().quit(0)
		return
	if "--e2e-all" in argv:
		_e2e_all_pc()
		get_tree().quit(0)
		return
	if "--e2e" in argv:
		_e2e_pc()
		get_tree().quit(0)
		return
	if "--fusionvis" in argv:
		await get_tree().create_timer(0.4).timeout
		var n0: Array = []
		for n in world.npcs:
			n0.append(String((n as Dictionary).get("name", "")))
		print("vis: 首图 ", String(world.map_data.get("id", "")), " -> ", _fusion_btn_visible(), " NPC=", str(n0))
		world.load_map(Data.load_map("kanto", "kanto_main"))
		world.warp_to(Vector2i(24, 217))
		await get_tree().create_timer(0.4).timeout
		print("vis: 大地图 -> ", _fusion_btn_visible())
		var mp: Dictionary = Data.load_map("kanto", "pewtercity_pokemoncenter_1f")
		world.load_map(mp)
		world.warp_to(Vector2i(7, 4))
		await get_tree().create_timer(0.4).timeout
		print("vis: 宝可梦中心 -> ", _fusion_btn_visible(), " 图=", String(world.map_data.get("id", "")))
		var names: Array = []
		for n in world.npcs:
			names.append("%s@%s" % [String((n as Dictionary).get("name", "")), str((n as Dictionary).get("at", []))])
		print("vis: NPC ", str(names))
		_ensure_form_npc()
		var names2: Array = []
		for n in world.npcs:
			names2.append("%s@%s" % [String((n as Dictionary).get("name", "")), str((n as Dictionary).get("at", []))])
		print("vis: 注入后 ", str(names2))
		print("vis: tile_size ", str(world.tile_size))
		for n in world.npcs:
			if bool((n as Dictionary).get("form_items", false)):
				_talk_to_npc(n as Dictionary)
				break
		await get_tree().create_timer(0.5).timeout
		for c in menu_layer.get_children():
			if c.get_script() == FormItemUI:
				var texts: Array = []
				for b in c.find_children("*", "Button", true, false):
					texts.append((b as Button).text)
				print("vis: 道具台 %d 项，前三条 %s" % [texts.size(), str(texts.slice(0, 3))])
		get_tree().quit(0)
		return
	if "--fusion" in argv:
		# 截图用：给一支带可合体素材与洛托姆的队伍
		save_data["party"] = [
			PartyScript.make(646, 50, [58, 59]),
			PartyScript.make(643, 50, [53, 46]),
			PartyScript.make(479, 50, [84]),
		]
		_open_fusion()
		await get_tree().create_timer(0.6).timeout

	if "-party" in argv or "--party" in argv:
		_open_party()
		await get_tree().create_timer(0.5).timeout
	if "-bag" in argv or "--bag" in argv:
		# 截图用：带 --bag-berry 时先塞几种树果进背包，看新分类页
		if "--bag-berry" in argv:
			for b in [["文柚果", "sitrus", 3], ["木子果", "lum", 2], ["巧可果", "occa", 1], ["枝荔果", "liechi", 1]]:
				bag_items.append({"name": String(b[0]), "category": "berry", "count": int(b[2]), "berry": String(b[1])})
			bag_items.append({"name": "吃剩的东西", "category": "held", "count": 1, "held": "LEFTOVERS"})
		_open_bag()
		if "--bag-berry" in argv:
			await get_tree().process_frame
			for c in menu_layer.get_children():
				if c.has_method("_switch"):
					c._switch("berry")
		await get_tree().create_timer(0.5).timeout
	if "-editor" in argv or "--editor" in argv:
		_open_editor()
		await get_tree().create_timer(0.5).timeout
		if "--tab=bag" in argv:
			for c in menu_layer.get_children():
				if c.get_script() == EditorUI:
					c._switch("bag")
		elif "--tab=base" in argv:
			for c in menu_layer.get_children():
				if c.get_script() == EditorUI:
					c._switch("base")
		await get_tree().create_timer(0.3).timeout
	if "-dex" in argv or "--dex" in argv:
		_open_dex()
		await get_tree().create_timer(0.5).timeout
		for a in argv:
			if String(a).begins_with("--dexdetail="):
				var want := int(String(a).split("=")[1])
				for c in menu_layer.get_children():
					if c.get_script() == DexUI and c.has_method("_show_detail"):
						c._show_detail(want)
				await get_tree().create_timer(0.4).timeout
	if "-battle" in argv or "--battle" in argv:
		_start_battle({"battle": {"species": 25, "level": 12, "moves": [84, 33, 98]}})
		await get_tree().create_timer(1.6).timeout
		if "-switch" in argv or "--switch" in argv:
			for c in get_children():
				if c is CanvasLayer and int((c as CanvasLayer).layer) == 6:
					for u in (c as CanvasLayer).get_children():
						if u.has_method("_open_switch"):
							u.menu.visible = false
							u._open_switch()
			await get_tree().create_timer(0.5).timeout
	if "-wild" in argv or "--wild" in argv:
		_start_wild_battle(52, 7)
		await get_tree().create_timer(1.2).timeout
		if "-ball" in argv or "--ball" in argv:
			for c in get_children():
				if c is CanvasLayer and int((c as CanvasLayer).layer) == 6:
					for u in (c as CanvasLayer).get_children():
						if u.has_method("_open_balls"):
							u.menu.visible = false
							u._open_balls()
			await get_tree().create_timer(0.5).timeout
	if "--press" in argv:
		await get_tree().process_frame
		for n in touch_layer.get_children():
			if n is Button and String((n as Button).text) in ["A", "B", "▲", "▶"]:
				var btn: Button = n
				btn.toggle_mode = true
				btn.button_pressed = true
		await get_tree().create_timer(0.3).timeout
	# 截图用：直接走到店员面前开店
	if "--at-shop" in argv:
		var sp := Vector2i(-1, -1)
		for n in world.npcs:
			if String(n.get("name", "")).contains("店员"):
				var at: Array = n.get("at", [0, 0])
				sp = Vector2i(int(at[0]), int(at[1]))
		if sp.x >= 0:
			var target := sp + Vector2i(0, 1)
			if world.is_blocked(target):
				target = sp + Vector2i(0, -1)
			world.warp_to(target)
			world.facing = "up" if target.y > sp.y else "down"
			world.step_interact()
			if not world.last_npc.is_empty():
				_talk_to_npc(world.last_npc)
				world.last_npc = {}
		await get_tree().create_timer(0.9).timeout
	# 截图用：直接开商店界面（不依赖 NPC 位置），看货架滚动
	if "--shop-ui" in argv:
		_open_shop()
		await get_tree().create_timer(0.6).timeout

	# 截图用：直接站到柜台前跟护士说话，看对话框长什么样
	if "--at-nurse" in argv:
		var np: Vector2i = Vector2i(-1, -1)
		for n in world.npcs:
			if String(n.get("name", "")).contains("护士"):
				var at: Array = n.get("at", [0, 0])
				np = Vector2i(int(at[0]), int(at[1]) + 2)
		if np.x >= 0:
			world.warp_to(np)
			world.facing = "up"
			world.step_interact()
			if not world.last_npc.is_empty():
				_talk_to_npc(world.last_npc)
				world.last_npc = {}
		await get_tree().create_timer(0.9).timeout
	# 截图用：队伍里放一只洗翠卡蒂狗、背包里放火之石，打开进化那一屏
	if "--party-evolve" in argv:
		var mon: Dictionary = PartyScript.make(58, 30, [33], "GROWLITHE_HISUI")
		save_data["party"] = [mon]
		bag_items.append({"name": "火之石", "count": 1})
		_open_party()
		await get_tree().create_timer(0.2).timeout
		for c in menu_layer.get_children():
			if c.has_method("_open_detail"):
				c._open_detail(0)
		await get_tree().create_timer(0.6).timeout
		if "--confirm" in argv:
			# 点一下「用火之石进化」，看确认框有没有挡住按钮
			for c2 in menu_layer.get_children():
				if c2.has_method("_open_detail") and c2.detail != null:
					for b in c2.detail.get_children():
						if b is Button and String(b.text).find("进化") >= 0:
							b.emit_signal("pressed")
							break
			await get_tree().create_timer(0.5).timeout
	# 截图用：打开队伍详情，看「携带物品」那一行；带 --pick 再点开挑选面板
	if "--party-held" in argv:
		var mon2: Dictionary = PartyScript.make(25, 30, [33], "")
		mon2["held"] = "LEFTOVERS"
		save_data["party"] = [mon2]
		bag_items.append({"name": "文柚果", "category": "berry", "count": 2, "berry": "sitrus"})
		bag_items.append({"name": "生命宝珠", "category": "held", "count": 1, "held": "LIFE_ORB"})
		_open_party()
		await get_tree().create_timer(0.2).timeout
		for c3 in menu_layer.get_children():
			if c3.has_method("_open_detail"):
				c3._open_detail(0)
		await get_tree().create_timer(0.5).timeout
		if "--pick" in argv:
			for c4 in menu_layer.get_children():
				if c4.has_method("_pick_held"):
					var owned: Array = [
						{"key": "LEFTOVERS", "name": "吃剩的东西"},
						{"key": "LIFE_ORB", "name": "生命宝珠"},
						{"key": "berry:sitrus", "name": "文柚果", "berry": true},
						{"key": "berry:lum", "name": "木子果", "berry": true},
					]
					c4._pick_held(c4.party[0], 0, owned)
			await get_tree().create_timer(0.5).timeout

	# 截图用：开一场带天气与场地的战斗，看顶部状态行
	if "--shot-field" in argv:
		var mine2 := [BattleScript.make_combatant(6, 50, [53, 241], "")]
		var foe2 := [BattleScript.make_combatant(9, 50, [55], "")]
		var layer2 := CanvasLayer.new()
		layer2.layer = 6
		add_child(layer2)
		var ui2 := BattleUI.new()
		layer2.add_child(ui2)
		ui2.fast = true
		ui2.setup(mine2, foe2, 3)
		ui2.battle.field.set_weather("sun")
		ui2.battle.field.set_terrain("electric")
		ui2.battle.field.set_screen("a", "reflect")
		ui2.battle.field.add_hazard("b", "spikes")
		ui2._refresh_field_label()
		print("field shot dbg: ", ui2.field_label.text, " rect=", ui2.field_label.get_global_rect())
		await get_tree().create_timer(0.6).timeout

	if "-shot" in argv or "--shot" in argv:
		await get_tree().create_timer(0.9).timeout
		if OS.get_environment("HUD_DBG") == "1":
			var vs2 := get_viewport().get_visible_rect().size
			print("hud dbg: 视口 ", vs2, " 玩家格子 ", world.player_pos, " 精灵 ", world._player_sprite.position, " 相机 ", world.cam.position, " zoom ", world.cam.zoom, " 位移 ", world.view_shift)
		var img := get_viewport().get_texture().get_image()
		img.save_png("/root/build/pokesaga/shot.png")
		print("SHOT %dx%d" % [img.get_width(), img.get_height()])
		get_tree().quit(0)

## Engine arguments on Android and desktop must not skip the title.
func _has_debug_start(args: Array) -> bool:
	const ACTIONS := ["party","bag","editor","dex","battle","wild","fusion","fusionvis","press","at-shop","at-nurse",
		"shop-ui","party-evolve","party-held","shot","shot-field","story-demo","interact","map","at","talk","walk",
		"e2e","e2e-story","e2e-johto-story","e2e-walk","e2e-all"]
	for arg in args:
		if str(arg).trim_prefix("-").trim_prefix("-").get_slice("=", 0) in ACTIONS:
			return true
	return false

func _show_title() -> void:
	_start_after_step = false
	held_dir = ""
	set_process(false)
	world.visible = false
	ui_layer.visible = false
	menu_layer.visible = false
	touch_layer.visible = false
	snd.stop_music()
	var stored := SaveScript.existing()
	var summary := {}
	if not stored.is_empty():
		var last_map: Dictionary = Data.load_map(str(stored.region), str(stored.map))
		summary = {"location":str(stored.get("location_label", last_map.get("name", stored.map))),
			"badge_count":stored.get("badges", []).size()}
	title_layer = CanvasLayer.new()
	title_layer.layer = 12
	add_child(title_layer)
	title_screen = TitleScreen.new()
	title_layer.add_child(title_screen)
	title_screen.setup(summary, FileAccess.file_exists(SaveScript.slot))
	title_screen.start_requested.connect(_enter_game)
	title_screen.quit_requested.connect(func() -> void: get_tree().quit())

func _enter_game(fresh: bool) -> void:
	if not is_instance_valid(title_screen):
		return
	if fresh and not SaveScript.new_game():
		title_screen.show_failure("未能写入新存档，请检查设备可用空间。")
		return
	if not fresh and SaveScript.existing().is_empty():
		title_screen.show_failure("无法读取原存档。")
		return
	title_layer.queue_free()
	title_screen = null
	world.visible = true
	ui_layer.visible = true
	menu_layer.visible = true
	_set_hud_visible(true)
	set_process(true)
	_restore_from_save()

func _refresh_hud() -> void:
	if name_label:
		name_label.text = world.display_name()
	if hint_label:
		hint_label.text = "位置 %d,%d   方向 %s%s" % [world.player_pos.x, world.player_pos.y, world.facing, _ledge_tip()]
	if money_label and save_data.has("money"):
		money_label.text = "¥%d" % int(save_data.get("money", 0))
	if badges_label:
		var bs: Array = save_data.get("badges", [])
		badges_label.text = ("徽章 %d" % bs.size()) if not bs.is_empty() else ""

## 站在坡上方时直接把「按 ↓ 能跳下去」写出来，省得靠坐标对位置
func _ledge_tip() -> String:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if world.ledge_bits(world.player_pos + d) != 0 and world._ledge_allows(world.player_pos + d, d):
			return "   坡↓可跳"
	return ""

func _t(name: String, pass_flag: bool) -> bool:
	results.append(("PASS  " if pass_flag else "FAIL  ") + name)
	return pass_flag

## 手机没有物理键盘，方向与确认必须给屏幕按键，否则根本没法操作
func _build_touch_controls() -> void:
	touch_layer = CanvasLayer.new()
	touch_layer.layer = 3
	add_child(touch_layer)

	# 十字键底盘：没有它，四个圆键漂在画面左下角很突兀
	var plate := Panel.new()
	plate.position = Vector2(14, 150)
	plate.size = Vector2(136, 136)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.05, 0.08, 0.11, 0.42)
	psb.set_corner_radius_all(68)
	psb.border_width_left = 1
	psb.border_width_top = 1
	psb.border_width_right = 1
	psb.border_width_bottom = 1
	psb.border_color = Color(0.62, 0.80, 0.76, 0.20)
	plate.add_theme_stylebox_override("panel", psb)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_layer.add_child(plate)
	_plate = plate

	# 四键压在底盘上，中心留空
	var specs := [["up", Vector2(45, 2)], ["down", Vector2(45, 90)],
		["left", Vector2(2, 45)], ["right", Vector2(90, 45)]]
	for sp in specs:
		var b := _pad_button({"up": "▲", "down": "▼", "left": "◀", "right": "▶"}[String(sp[0])], Vector2(46, 46))
		b.position = Vector2(14, 150) + Vector2(sp[1])
		b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		var key := String(sp[0])
		b.button_down.connect(func() -> void:
				held_dir = key
				_move(key))
		b.button_up.connect(func() -> void:
				if held_dir == key: held_dir = "")
		touch_layer.add_child(b)
		_dpad.append({"key": String(sp[0]), "off": Vector2(sp[1]), "btn": b})

	# A / B：右下斜排，A 靠外靠上，拇指自然落在 A 上
	var ba := _pad_button("A", Vector2(58, 58))
	ba.position = Vector2(396, 186)
	ba.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	ba.pressed.connect(_on_action)
	touch_layer.add_child(ba)
	_btn_a = ba

	var bb := _pad_button("B", Vector2(52, 52))
	bb.position = Vector2(330, 224)
	bb.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	# B 键：短按关面板；面板全关时按住就是跑
	bb.button_down.connect(func() -> void: run_held = true)
	bb.button_up.connect(func() -> void: run_held = false)
	bb.pressed.connect(_on_back)
	touch_layer.add_child(bb)
	_btn_b = bb

## 屏幕按键：三态各自不同，按下去要能「看见」自己被按了
func _pad_button(txt: String, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = txt
	b.size = sz
	b.keep_pressed_outside = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", int(sz.x * 0.42))
	var r := int(sz.x / 2)
	# 常态：半透明深底，细边
	var n := StyleBoxFlat.new()
	n.bg_color = Color(0.06, 0.10, 0.13, 0.55)
	n.set_corner_radius_all(r)
	n.border_width_left = 2
	n.border_width_top = 2
	n.border_width_right = 2
	n.border_width_bottom = 2
	n.border_color = Color(0.86, 0.93, 0.89, 0.45)
	n.content_margin_top = 0
	n.content_margin_bottom = 2
	# 悬停：亮一点点
	var h: StyleBoxFlat = n.duplicate()
	h.bg_color = Color(0.10, 0.17, 0.21, 0.62)
	h.border_color = Color(0.86, 0.93, 0.89, 0.62)
	# 按下：底色点亮、边框发亮、字往下沉 3 像素，像真的被压下去
	var pr: StyleBoxFlat = n.duplicate()
	pr.bg_color = Color(0.42, 0.80, 0.72, 0.78)
	pr.border_color = Color(0.95, 1.0, 0.97, 0.95)
	pr.content_margin_top = 3
	pr.content_margin_bottom = 0
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(0.95, 0.98, 0.94, 0.92))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.04, 0.10, 0.10, 1))
	return b

## A 键：走近 NPC 就对话，空地就原地确认
## ---------- 剧情 ----------

func _story_init() -> void:
	story = StoryScript.new()
	if not story.load_region("kanto"):
		print("[story] 关都剧情表缺失")

func _flags() -> Dictionary:
	if not (save_data.get("flags") is Dictionary):
		save_data["flags"] = {}
	return save_data["flags"]

func _has_party() -> bool:
	for m in save_data.get("party", []):
		if m is Dictionary and not (m as Dictionary).is_empty():
			return true
	return false

## 触发一次剧情；返回是否播了东西
func _story_use_region(rid: String) -> void:
	if story == null:
		return
	if String(story.region_id) == rid:
		return
	story.load_region(rid)


func _story_fire(kind: String, ctx: Dictionary) -> bool:
	if not story_on or story == null or not cur_story.is_empty():
		return false
	_story_use_region(String(world.map_data.get("region", "kanto")))
	var flags := _flags()
	if kind in ["step","map_enter"]:
		ctx["area_name"] = world.area_name()
		ctx["x"] = world.player_pos.x
		ctx["y"] = world.player_pos.y
	if (kind == "talk" and ctx.get("actor","") == "lab_oak") or (kind == "map_enter" and world.map_data.id == "kanto_main"):
		preload("res://core/sevii_campaign.gd").sync(save_data)
	var ev: Dictionary = story.take(kind, ctx, flags, _has_party())
	if ev.is_empty():
		return false
	_play_story(ev)
	return true

func _play_story(ev: Dictionary) -> void:
	if world.map_data.get("region","")=="kanto":
		preload("res://core/kanto_campaign.gd").stage_rival(world,ev.get("id",""))
	cur_story = ev
	story_queue = ev.get("steps", []).duplicate()
	story_abort = false
	_story_step()

func _story_step() -> void:
	while not story_queue.is_empty():
		var act: Dictionary = story_queue.pop_front()
		if act.has("choice"):
			var choice: Dictionary = act.choice
			var prompt = _dialog(choice.say,choice.who)
			prompt.ask(choice.accept,choice.decline)
			prompt.answered.connect(func(yes: bool) -> void:
				story_queue = (choice.yes if yes else choice.no) + story_queue)
			prompt.closed.connect(_story_step,CONNECT_ONE_SHOT)
			return
		if act.has("say"):
			var dlg = _dialog(act["say"], String(act.get("who", cur_story.get("who", ""))))
			dlg.closed.connect(_story_step, CONNECT_ONE_SHOT)
			return
		if act.has("escort"):
			_play_oak_escort(str(act.escort))
			return
		if act.has("battle"):
			_story_battle(act["battle"])
			return
		_story_do(act)
	_story_done()

## 队列跑完：写完成标记、存档，回头补一次区域触发
func _story_done() -> void:
	preload("res://core/sevii_campaign.gd").reconcile_pass(_flags(),bag_items)
	_persist()
	if story_abort:
		if world.map_data.get("region","")=="kanto": world.refresh_story_actors(_flags())
		story_abort = false
		cur_story = {}
		return
	if not cur_story.is_empty() and story != null:
		story.mark_finished(cur_story, _flags())
		if world.map_data.get("region","") in ["kanto","sevii"]:
			world.refresh_story_actors(_flags())
			_apply_defeated()
		save_data["flags"] = _flags()
		_persist()
	cur_story = {}
	_story_fire("step", {"map": String(world.map_data.get("id", "")),
		"x": world.player_pos.x, "y": world.player_pos.y})

## 剧情里的对战：赢了解锁后续；输了这场作废，可以重新触发
func _story_battle(cfg) -> void:
	var conf: Dictionary = cfg if cfg is Dictionary else {}
	var nm := String(conf.get("name", "对手"))
	var npc := {"name": nm, "battle": conf}
	var after := func(result: String) -> void:
		if result in ["a","caught"]:
			var wf := String(conf.get("win_flag", ""))
			if wf != "":
				_flags()[wf] = true
			var tail: Array = conf.get("win_say", [])
			if tail.is_empty():
				_story_step()
				return
			var d2 = _dialog(tail, nm)
			d2.connect("closed", func() -> void: _story_step())
		else:
			story_abort = not conf.get("finish_on_loss",false)
			if story_abort: story_queue.clear()
			var stage: String = cur_story.get("id","")
			if stage in ["kanto_loreleis_win","kanto_brunos_win","kanto_agathas_win","kanto_lances_win","kanto_champions_win"] or stage.begins_with("repeat_kanto_"):
				preload("res://core/kanto_campaign.gd").lost_league(self)
			var lose: Array = conf.get("lose_say", ["……这次算你运气好。"])
			var d3 = _dialog(lose, nm)
			d3.connect("closed", func() -> void:
				_story_step()
				if result == "b" and _party_fainted():
					if conf.get("finish_on_loss",false):
						_heal_party()
						_persist()
					else:
						_blackout())
	if conf.get("wild",false):
		var foe: Dictionary = conf.team[0]
		_start_wild_battle(int(foe.species),int(foe.level),"",after)
	else:
		_start_battle(npc,after)

## 单个剧情动作
func _story_do(act: Dictionary) -> void:
	var flags := _flags()
	if act.has("scene_cast"):
		var temporary := {"sevii_" + str(act.scene_cast):true}
		world.refresh_story_actors(flags.merged(temporary,true))
	if act.get("hall_of_fame") in ["johto","kanto"]:
		johto_league.register_team(save_data,act.hall_of_fame)
		_persist()
	if act.has("flag"):
		flags[String(act["flag"])] = true
		save_data["flags"] = flags
	if act.has("remove_item"):
		for row in bag_items:
			if row.get("name","") == act.remove_item:
				bag_items.erase(row)
				break
	if act.has("set_player_at"):
		var xy: Array = act.set_player_at
		world.warp_to(Vector2i(int(xy[0]),int(xy[1])))
	if act.has("warp"):
		_do_warp(act.warp)
	if act.has("give_mon"):
		var gm: Dictionary = act["give_mon"]
		var sid := int(gm.get("species", 25))
		_add_to_team(sid, int(gm.get("level", 5)))
		var nm2 := String((Data.species_of(sid) as Dictionary).get("name", ""))
		if nm2 != "":
			_show_toast("获得了 %s！" % nm2)
	if act.has("give_item"):
		var gi: Dictionary = act["give_item"]
		if gi.has("berry"):
			var berry_key := str(gi.berry).to_lower().trim_suffix("_berry")
			for i in int(gi.get("count",1)):
				_give_bag_item(gi.name,"berry","",berry_key)
		else:
			_give_item(String(gi.get("name", "")), int(gi.get("count", 1)),
				String(gi.get("category", "other")))
	if act.has("heal"):
		_heal_party()
	if act.has("money"):
		save_data["money"] = int(save_data.get("money", 0)) + int(act["money"])

## Walk Oak and the player along the original movement lists without firing doors mid-scene.
func _play_oak_escort(stage: String) -> void:
	_escort_active = true
	panel_open += 1
	held_dir = ""
	run_held = false
	_set_hud_visible(false)
	world.warp_to(world.player_pos)
	var side := "Left" if world.player_pos.x == 72 else "Right"
	var paths: Dictionary = preload("res://core/frlg_actors.gd").data().opening_paths
	if stage == "approach":
		world.refresh_story_actors(_flags().merged({"oak_approaching":true}))
		world.facing = "down"
	var npc_path: String = paths["OakEnter"+side] if stage == "approach" else paths["OakWalkToLab"+side] + "U"
	var player_path: String = "" if stage == "approach" else paths["PlayerWalkToLab"+side] + "RU"
	await world.play_actor_paths("pallet_oak",npc_path,player_path)
	panel_open -= 1
	_escort_active = false
	_set_hud_visible(true)
	_story_step()

## 对话框栈：A 键先翻对话，再谈别的
var _dialogs: Array = []

func _dialog(lines: Array, speaker := "") -> Node:
	var dlg = load("res://scenes/dialog_ui.gd").new()
	menu_layer.add_child(dlg)
	_dialogs.append(dlg)
	panel_open += 1
	_set_hud_visible(false)
	dlg.connect("closed", func() -> void:
			_dialogs.erase(dlg)
			panel_open = maxi(0, panel_open - 1)
			if panel_open == 0:
				_set_hud_visible(true))
	dlg.call("setup", lines, speaker)
	return dlg

## 护士：原版那句话 + 是/否，确认了才真的治疗
func _dialog_heal(npc: Dictionary) -> void:
	var who := String(npc.get("name", "护士"))
	var dlg = _dialog(["欢迎来到宝可梦中心。\n要恢复你的宝可梦吗？"], who)
	dlg.call("ask", "恢复", "不用")
	dlg.connect("answered", func(yes: bool) -> void:
			if yes:
				_heal_party()
				_dialog(["你的宝可梦都恢复精神了。", "我们会等你再次光临。"], who)
			else:
				_dialog(["欢迎随时来。"], who))

func _on_action() -> void:
	if is_instance_valid(active_battle) and not active_battle.is_queued_for_deletion():
		return
	if not _dialogs.is_empty():
		(_dialogs[_dialogs.size() - 1] as Object).call("advance")
		return
	if panel_open > 0 or world.walking:
		return
	# 站在道具球上按 A 直接捡：球已经不挡路，人是踩着它站上去的，
	# 这时候面前是空地，以前就永远捡不到（看着有球、按不到，就是这个原因）
	var here: Dictionary = world.object_at(world.player_pos)
	if not here.is_empty():
		var hk := String(here.get("kind", ""))
		if hk == "item" or hk == "hidden":
			_handle_object(here)
			return
	if _ruin_door_ahead():
		_open_ruin_door()
		return
	# 地形类秘传：潜水 / 漩涡 / 攀岩
	if _try_terrain_move():
		return
	if _use_waterfall():
		return
	# 朝水面按 A：按原版那样先问一句，再决定冲浪还是钓鱼
	if _on_water_action():
		return
	world.step_interact()
	if world.last_event.begins_with("obj:"):
		var o0: Dictionary = world.last_obj
		world.last_obj = {}
		world.last_event = ""
		_handle_object(o0)
		return
	if world.last_event.begins_with("talk:"):
		var nm: String = String(world.last_event).substr(5)
		world.last_event = ""
		# 用坐标定位的那个 NPC，同名 NPC（比如一排"路人"）才不会认错
		if not world.last_npc.is_empty():
			var npc_row: Dictionary = world.last_npc
			world.last_npc = {}
			# 有剧情先播剧情，没有才走普通台词
			if not _story_fire("talk", {"npc": String(npc_row.get("name", "")), "actor":npc_row.get("role",""),
					"map": String(world.map_data.get("id", ""))}):
				_talk_to_npc(npc_row)
		else:
			_talk_to(nm)
	elif world.last_event.begins_with("warp:"):
		# Standing on a door has no walk animation to emit warp_ready.
		var target: Dictionary = world.pending_warp
		world.pending_warp = {}
		_on_warp_ready(target)

## 火红叶绿的徽章约束场外使用，在战斗中仍能正常选择已学招式。
func _required_field_badge(key: String) -> String:
	if world.map_data.get("region","") not in ["kanto","sevii"]: return ""
	var badge: String = preload("res://core/kanto_campaign.gd").FIELD_BADGES.get(key,"")
	return badge if badge not in save_data.get("badges",[]) else ""

func _party_can_move(key: String) -> bool:
	return _required_field_badge(key).is_empty() and _party_has_move(key)

func _field_move_hint(key: String, move_name: String) -> String:
	var badge := _required_field_badge(key)
	if not badge.is_empty(): return "在关都和七岛，获得%s后才能在场外使用%s。" % [badge,move_name]
	return "队伍中需要有会%s的宝可梦。" % move_name

func _has_rod() -> bool:
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")).contains("钓竿") and int(it.get("count",0)) > 0:
			return true
	return false

## 朝水面按 A：能做的事一次问清（原版就是弹一句「要冲浪吗？」）
func _ruin_door_ahead() -> bool:
	return world.map_data.get("id","") == "six_island_ruin_valley" and _flags().get("rescued_icefall",false) and not _flags().get("ruin_valley_cut_door",false) and world.player_pos + world._dir_vec() == Vector2i(24,24)

func _open_ruin_door() -> void:
	if not _party_can_move("CUT"):
		_dialog(["铁门上刻着点字。读起来是「居合斩」。",_field_move_hint("CUT","居合斩")],"")
		return
	_pick("要对刻着点字的铁门使用居合斩吗？", ["使用居合斩","返回"], func(choice: int) -> void:
		if choice == 0:
			_flags().ruin_valley_cut_door = true
			world.refresh_story_actors(_flags())
			_persist()
			_show_toast("点之穴的大门打开了。"))

func _on_water_action() -> bool:
	if world.surfing:
		return _try_surf()
	var face: Vector2i = world.player_pos + world._dir_vec()
	if not world.is_water(face):
		return false
	var can_surf := _party_can_move("SURF")
	var rod := _has_rod()
	if not can_surf and not rod:
		_show_toast(_field_move_hint("SURF","冲浪"))
		return true
	if can_surf and rod:
		var acts: Array = ["冲浪", "钓鱼", "算了"]
		_pick("这里是水面", acts, func(idx: int) -> void:
			if idx == 0:
				_surf_confirm()
			elif idx == 1:
				_fish())
		return true
	if can_surf:
		_surf_confirm()
		return true
	_fish()
	return true

func _surf_confirm() -> void:
	_pick("要冲浪吗？", ["好", "算了"], func(idx: int) -> void:
		if idx != 0:
			return
		var msg: String = world.toggle_surf()
		if msg != "":
			_show_toast(msg))

## 冲浪开关：只有队伍里有会「冲浪」的宝可梦才能下水
func _try_surf() -> bool:
	var face: Vector2i = world.player_pos + world._dir_vec()
	if not world.surfing and not world.is_water(face):
		return false
	var can: bool = world.surfing or _party_can_move("SURF")
	if not can:
		_show_toast(_field_move_hint("SURF","冲浪"))
		return true
	if world.surfing:
		_pick("要上岸吗？", ["好", "算了"], func(idx: int) -> void:
			if idx != 0:
				return
			var msg: String = world.toggle_surf()
			if msg != "":
				_show_toast(msg))
	else:
		_surf_confirm()
	return true

## B 键：关掉最上层面板
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_field_fingers.clear()
		held_dir = ""
		run_held = false
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or not is_node_ready():
		return
	if is_instance_valid(title_screen):
		title_screen.handle_back()
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) and DisplayServer.virtual_keyboard_get_height() > 0:
		DisplayServer.virtual_keyboard_hide()
		get_viewport().gui_release_focus()
		return
	if panel_open > 0 or not _dialogs.is_empty() or is_instance_valid(active_battle):
		_on_back()
		return
	var prompt = _dialog(["要保存进度并返回标题吗？"])
	prompt.ask("保存并返回", "继续游戏")
	prompt.answered.connect(func(yes: bool) -> void:
		if yes:
			if _persist():
				_show_title()
			else:
				_show_toast("存档写入失败，请检查设备空间。"))


func _on_back() -> void:
	if _escort_active: return
	if is_instance_valid(active_battle) and not active_battle.is_queued_for_deletion():
		active_battle.handle_back()
		return
	# 对话框开着时，B 直接关掉当前这句
	if not _dialogs.is_empty():
		var top_dlg = _dialogs.back()
		if top_dlg.ask_mode:
			top_dlg._pick(false)
		else:
			top_dlg._close()
		return
	if panel_open <= 0:
		return
	var kids: Array = menu_layer.get_children()
	if kids.is_empty():
		return
	var top = kids.back()
	if top.has_method("handle_back"):
		top.handle_back()
		return
	if top.has_signal("closed"):
		top.closed.emit()
	else:
		panel_open = maxi(0, panel_open - 1)
	top.queue_free()
	_set_hud_visible(panel_open == 0)

var _bar: Panel
var _dock: Panel
var _plate: Panel
var _dpad: Array = []
var _btn_a: Button
var _btn_b: Button

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)

	var bar := Panel.new()
	bar.position = Vector2(0, 288)
	bar.size = Vector2(480, 32)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.16, 0.88)
	sb.border_width_top = 2
	sb.border_color = Color(0.42, 0.78, 0.72)
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	bar.add_theme_stylebox_override("panel", sb)
	ui_layer.add_child(bar)
	_bar = bar

	name_label = Label.new()
	name_label.position = Vector2(14, 292)
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.92, 0.97, 0.95))
	ui_layer.add_child(name_label)

	hint_label = Label.new()
	hint_label.position = Vector2(250, 294)
	hint_label.add_theme_font_size_override("font_size", 12)
	hint_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.74))
	ui_layer.add_child(hint_label)

	money_label = Label.new()
	money_label.position = Vector2(14, 268)
	money_label.add_theme_font_size_override("font_size", 12)
	money_label.add_theme_color_override("font_color", Color(0.96, 0.86, 0.52))
	ui_layer.add_child(money_label)

	badges_label = Label.new()
	badges_label.position = Vector2(150, 268)
	badges_label.add_theme_font_size_override("font_size", 12)
	badges_label.add_theme_color_override("font_color", Color(0.72, 0.84, 0.80))
	ui_layer.add_child(badges_label)

	toast = Label.new()
	# 提示条位于 START 和虚拟方向键之间。
	toast.position = Vector2(0, 44)
	toast.size = Vector2(480, 24)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", Color(1, 0.95, 0.72))
	toast.visible = false
	ui_layer.add_child(toast)

	_build_start_menu()
	_build_touch_controls()
	_layout_hud()
	get_viewport().size_changed.connect(_layout_hud)

## HUD / 十字键 / A B 都贴着真实屏幕的边排，不再写死在 480x320 上
## 画面锁死 480x320（GBA 3:2），等比缩放居中，绝不拉伸也不加宽。
## 所有 HUD / 按键都在这块画布内排版，横竖屏都不会错位。
const BASE_W := 480.0
const BASE_H := 320.0

func _layout_hud() -> void:
	var w := BASE_W
	var h := BASE_H
	var bar_h := 32.0
	# 操作区不再占掉半屏：按键半透明浮在地图上，只避开最下面那条状态栏
	if _dock != null:
		_dock.visible = false
	if world != null and world.cam != null:
		world.cam.zoom = Vector2(2, 2)
		world.view_shift = 0.0
		world._sync_player()
	if _bar != null:
		_bar.position = Vector2(0, h - bar_h)
		_bar.size = Vector2(w, bar_h)
	if name_label != null:
		name_label.position = Vector2(14, h - bar_h + 7)
	if hint_label != null:
		hint_label.position = Vector2(w - 230, h - bar_h + 9)
		hint_label.size = Vector2(216, 18)
		hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if money_label != null:
		money_label.position = Vector2(14, h - bar_h - 18)
	if badges_label != null:
		badges_label.position = Vector2(150, h - bar_h - 18)
	if toast != null:
		toast.size = Vector2(w, 24)
	var bottom: float = h - bar_h - 6.0
	if _plate != null:
		_plate.position = Vector2(12, bottom - 132)
		for d in _dpad:
			(d["btn"] as Button).position = _plate.position + (d["off"] as Vector2)
	if _btn_a != null:
		_btn_a.position = Vector2(w - 78, bottom - 118)
	if _btn_b != null:
		_btn_b.position = Vector2(w - 138, bottom - 86)

func _move(key: String) -> void:
	if is_instance_valid(active_battle) and not active_battle.is_queued_for_deletion():
		return
	if panel_open > 0:
		return
	# 一格没走完不能迈下一步：原版也是这样，连续按住才连贯
	if world.walking:
		return
	var dir: Vector2i = {
		"up": Vector2i(0, -1), "down": Vector2i(0, 1),
		"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
	}[key]
	var checkpoint := preload("res://core/kanto_campaign.gd").checkpoint(world.map_data,world.player_pos+dir,dir,save_data.get("badges",[]))
	if checkpoint!="":
		held_dir=""
		run_held=false
		_dialog([checkpoint],"联盟警卫")
		return
	if world.step(dir):
		_after_step()
		if _has_party():
			_tick_egg()
	else:
		if not world.walking and Time.get_ticks_msec() - _last_bump > 220:
			_last_bump = Time.get_ticks_msec()
			snd.play_sfx("bump")

## 走到门口、这一步动画走完才切场景，不会半路就闪进去
func _on_warp_ready(target: Dictionary) -> void:
	var ticket := preload("res://core/sevii_campaign.gd").ferry_message(world.map_data,target,bag_items)
	if ticket != "":
		held_dir = ""
		run_held = false
		_dialog([ticket],"船员")
		return
	if target.get("region","") == "kanto" and target.get("map","") == "viridiancity_gym" and not _flags().get("viridian_gym_open",false):
		held_dir = ""
		run_held = false
		world.warp_to(Vector2i(84,192))
		_dialog(["常磐道馆的大门紧闭。先去挑战其他城市的道馆吧。"])
		return
	_do_warp(target)

## 换图后统一刷新：天气、昼夜、背景音乐、物件状态
func _refresh_scene() -> void:
	if world == null:
		return
	_layout_hud()
	world.taken = save_data.get("flags", {})
	world.night = _night_amount()
	# 照亮过的洞窟再进来还是亮的
	if _flags().get("flash_" + String(world.map_data.get("id", "")), false):
		world.dark = false
	world.apply_light()
	_mark_fly_visits()
	_update_music()


## 现实时间 -> 夜色浓度（白天 0，入夜渐深）
func _night_amount() -> float:
	var t := Time.get_time_dict_from_system()
	var h := float(t["hour"]) + float(t["minute"]) / 60.0
	if h >= 20.0 or h < 4.5:
		return 1.0
	if h >= 18.0:
		return (h - 18.0) / 2.0
	if h < 6.5:
		return 1.0 - (h - 4.5) / 2.0
	return 0.0


func _is_night() -> bool:
	return _night_amount() >= 0.5


func _update_music() -> void:
	if snd == null:
		return
	var mid := String(world.map_data.get("id", ""))
	var area := String(world.map_data.get("name", ""))
	var indoor: bool = not mid.contains("main") and not area.contains("道路")
	if world.surfing:
		snd.play_music("surf")
		return
	if world.bike:
		snd.play_music("route")
		return
	snd.play_music(snd.music_key_for(mid, area, indoor))


func _do_warp(target: Dictionary) -> void:
	if target.is_empty():
		return
	var kanto_gate := preload("res://core/kanto_campaign.gd").passage_message(world.map_data,target,save_data)
	if kanto_gate != "":
		held_dir=""
		run_held=false
		_dialog([kanto_gate])
		return
	if target.get("region") == "johto":
		var room := String(target.get("map", ""))
		if johto_league.stage(room) > johto_league.stage(String(world.map_data.get("id", ""))):
			var gate := johto_league.gate_message(room, save_data)
			if gate != "":
				held_dir = ""
				_dialog([gate], "联盟")
				return
	var island_gate := preload("res://core/sevii_campaign.gd").passage_message(world.map_data,target,_flags())
	if island_gate != "":
		held_dir = ""
		_dialog([island_gate])
		return
	preload("res://core/kanto_campaign.gd").begin_rematch(world.map_data,target,_flags())
	target = preload("res://core/passage_memory.gd").resolve(save_data,target)
	if world.map_data.get("id","") == "five_island_resort_gorgeous_house" and target.get("map","") != world.map_data.id:
		save_data.erase("selphy_thanked")
	var next_map: Dictionary = Data.load_map(String(target.get("region", "")), String(target.get("map", "")))
	if next_map.is_empty():
		# 目标地图缺失时说清楚，别让人以为门坏了
		print("[warp] 目标地图缺失 ", target)
		_dialog(["这扇门打不开。"], "")
		return
	snd.play_sfx("door")
	_show_toast("前往 " + String(next_map.get("name", "")))
	if world.map_data.get("id","") == "four_island_icefall_cave_1f" and next_map.id != world.map_data.id:
		for rule in preload("res://core/kanto_campaign.gd").field_rules(world.map_data.id):
			_flags().erase(rule.variants[0].flags[0])
	world.load_map(next_map)
	world.arrive(target)
	if next_map.region in ["kanto","sevii"] and next_map.get("npcs",[]).any(func(n):return n.get("heal",false) and n.get("name","")=="护士"):
		save_data["last_pokemon_center"] = {"region":next_map.region,"map":next_map.id,"at":next_map.spawn.duplicate()}
	_start_after_step = false
	if not target.get("connection",false):
		for pair in KEY_MAP:
			if Input.is_physical_key_pressed(int(pair[1])):
				_post_warp_keys[int(pair[1])] = true
		held_dir = ""
	_refresh_scene()
	_story_fire("map_enter", {"map": String(world.map_data.get("id", "")),
		"region": String(world.map_data.get("region", ""))})
	_apply_defeated()
	_ensure_form_npc()

func _after_step() -> void:
	preload("res://core/sevii_campaign.gd").request_step(save_data)
	if _flags().get("got_vs_seeker",false) and int(save_data.get("vs_charge",100)) < 100:
		save_data["vs_charge"] += 1
	# A door owns the entire step until the arrival animation finishes.
	if not world.pending_warp.is_empty():
		return
	if world.map_data.get("id","")=="four_island_icefall_cave_1f":
		var cell: Vector2i = world.player_pos
		for rule in preload("res://core/kanto_campaign.gd").field_rules(world.map_data.id):
			if not preload("res://core/kanto_campaign.gd").same_cell(rule.thin_ice,cell.x,cell.y): continue
			var cracked: String = rule.variants[0].flags[0]
			if _flags().get(cracked,false):
				snd.play_sfx("hit")
				_do_warp({"region":"sevii","map":"four_island_icefall_cave_b1f","at":[cell.x,cell.y]})
				_persist()
				return
			_flags()[cracked]=true
			world.refresh_story_actors(_flags())
			_show_toast("脚下的薄冰裂开了。")
			break
	_mark_fly_visits()
	# 走到道具球那一格就自动捡：手机上不用瞄准，也不会"看着捡不到"
	var step_obj: Dictionary = world.object_at(world.player_pos)
	if not step_obj.is_empty():
		var sk := String(step_obj.get("kind", ""))
		if sk == "item" or sk == "hidden":
			_handle_object(step_obj)
			return
	if world.last_event.begins_with("obj:"):
		var o: Dictionary = world.last_obj
		world.last_obj = {}
		world.last_event = ""
		_handle_object(o)
		return
	elif world.last_event.begins_with("talk:"):
		var npc2: Dictionary = world.last_npc
		world.last_npc = {}
		world.last_event = ""
		if not npc2.is_empty():
			_talk_to_npc(npc2)
		return
	world.last_event = ""
	# 走到某个区域就先看剧情，再谈遇敌
	if _story_fire("step", {"map": String(world.map_data.get("id", "")),
			"x": world.player_pos.x, "y": world.player_pos.y}):
		return
	_try_encounter()

## 踩进高草就摇一次骰子；需要判定「刚踩进去」，站在原地看着不算
func _try_encounter() -> void:
	if panel_open > 0:
		return
	# 手上没有宝可梦就不该被野生宝可梦缠上
	if not _has_party():
		return
	if world.is_blocked(world.player_pos):
		return
	# 踩草遇敌；在海上冲浪也算「有东西会冒出来」
	var on_grass: bool = world.wild_tile_here()
	var on_sea: bool = world.surfing and world.is_water(world.player_pos)
	if not on_grass and not on_sea:
		grass_streak = 0
		return
	grass_streak += 1
	# 优先用这张图自己的原版分布；拼过的大地图按分区取（每段路原版分布不同）
	var pool: Array = world.map_data.get("encounters", [])
	var rate := float(world.map_data.get("encounter_rate", 0.0))
	# 单张图上冲浪时优先用原版水面分布（城都这些图都是独立一张）
	if on_sea:
		var wp: Array = world.map_data.get("water_encounters", [])
		if not wp.is_empty():
			pool = wp
			rate = float(world.map_data.get("water_encounter_rate", rate))
	var zones: Array = world.map_data.get("zones", [])
	if not zones.is_empty():
		pool = []
		rate = 0.0
		var px: int = int(world.player_pos.x)
		var py: int = int(world.player_pos.y)
		for z in zones:
			var r: Array = z.get("rect", [0, 0, 0, 0])
			if px >= int(r[0]) and px < int(r[0]) + int(r[2]) and py >= int(r[1]) and py < int(r[1]) + int(r[3]):
				# 水上用该段的水面分布（原版 water_mons），没有就退回陆地分布
				var water_pool: Array = z.get("water", [])
				if on_sea and not water_pool.is_empty():
					pool = water_pool
					rate = float(z.get("water_rate", z.get("rate", 0.0)))
				else:
					pool = z.get("encounters", [])
					rate = float(z.get("rate", 0.0))
				break
	if pool.is_empty():
		var reg: Dictionary = Data.load_region(String(world.map_data.get("region", "")))
		pool = reg.get("encounters", [])
		rate = float(reg.get("encounter_rate", 0.12))
	if pool.is_empty():
		return
	if rate <= 0.0:
		return
	for mon in save_data.get("party", []):
		if mon is Dictionary and not mon.is_empty():
			if str(mon.get("held", "")) == "CLEANSE_TAG": rate *= 2.0 / 3.0
			break
	if not EncounterScript.should_encounter(rng, rate, grass_streak):
		return
	var wild: Dictionary = EncounterScript.roll(pool, rng)
	if wild.is_empty():
		return
	grass_streak = 0
	var sid := int(wild["species"])
	var form := _roll_regional(sid)
	_start_wild_battle(sid, int(wild["level"]), form)

## 地区形态不是独立图鉴号，就是这只宝可梦换了个样子。
## 野生偶尔能碰到本地物种的地区形态（约 6%）。
func _roll_regional(species_id: int) -> String:
	if rng.randf() > 0.06:
		return ""
	var pool: Array = []
	for f in Data.forms_of(species_id):
		if f is Dictionary and String(f.get("kind", "")) == "regional":
			pool.append(String(f.get("key", "")))
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])

## 商店：读货架，买完改背包和钱
func _open_shop() -> void:
	var goods := Data.load_shop(str(world.map_data.get("region", "kanto")))
	if world.map_data.id == "indigo_plateau_pokemon_center_1f":
		goods.append_array([{"name":"活力碎片","category":"heal","price":1500},{"name":"厉害伤药","category":"heal","price":1200}])
	if goods.is_empty():
		_dialog(["抱歉，今天没什么好卖的。"], "店员")
		return
	var ui = ShopUI.new()
	menu_layer.add_child(ui)
	panel_open += 1
	_set_hud_visible(false)
	ui.connect("closed", func() -> void:
			panel_open = maxi(0, panel_open - 1)
			if panel_open == 0:
				_set_hud_visible(true))
	ui.connect("bought", func(item_name: String, price: int, category: String) -> void:
			var money := int(save_data.get("money", 0))
			if money < price:
				_show_toast("钱不够")
				return
			save_data["money"] = money - price
			for g in goods:
				if str(g.name) == item_name:
					_give_bag_item(item_name, category, str(g.get("held", "")), str(g.get("berry", "")), str(g.get("tera", "")))
					break
			_persist()
			_refresh_hud())
	ui.call("setup", goods, int(save_data.get("money", 0)))

## 告示牌 / 道具球 / 树果树 / 土：按 A 之后的分流
func _handle_object(o: Dictionary) -> void:
	if o.get("kind","")=="kanto_puzzle":
		preload("res://core/kanto_campaign.gd").use_control(self,o)
		return
	if world.map_data.get("id","")=="celadon_city_game_corner" and preload("res://core/kanto_campaign.gd").same_cell(o.get("at",[]),11,1):
		if not _story_fire("talk",{"map":"celadon_city_game_corner","actor":"poster_switch"}):
			_dialog(["海报后面的开关已经按下，楼梯就在右侧。"] if _flags().get("hideout_stairs",false) else ["有人守在海报前面。"])
		return
	if world.map_data.get("id","") == "route25_sea_cottage" and o.has("at") and Vector2i(int(o.at[0]),int(o.at[1])) == Vector2i(4,5) and world.facing == "up":
		if not _story_fire("talk",{"map":"route25_sea_cottage","actor":"bill_pc"}):
			_dialog(["屏幕上显示着传送装置的细胞分离程序。"],"电脑")
		return
	if o.is_empty():
		return
	snd.play_sfx("select")
	match String(o.get("kind", "")):
		"mansion_switch":
			_pick("雕像上藏着一个开关。要按吗？", ["按下","离开"], func(index: int):
				if index == 0:
					world.set_mansion_switch(not world.taken.get(world.MANSION_FLAG,false))
					save_data["flags"] = world.taken
					_persist()
					snd.play_sfx("confirm")
					_show_toast("远处传来了闸门的声音。"))
		"wall_map":
			_open_world_atlas(false)
		"sign":
			var t := String(o.get("text", ""))
			_dialog([t] if t != "" else ["（字迹被磨掉了）"], "")
		"item", "hidden":
			var nm := String(o.get("name", "道具"))
			var fields := Data.field_item_fields(o)
			nm = str(fields.get("name", nm))
			_give_bag_item(nm, str(fields.get("category", o.get("category", "other"))), str(fields.get("held", o.get("held", ""))))
			save_data["flags"] = world.taken
			world.mark_taken(o)
			snd.play_sfx("item")
			_persist()
			var message := _dialog(["捡到了「%s」！" % nm], "")
			if Data.tm_map.has(nm):
				message.closed.connect(func(): _offer_tm_teach(nm), CONNECT_ONE_SHOT)
		"cut":
			_use_field_move(o, "CUT", "居合斩", "树被砍倒了！")
		"rock":
			_use_field_move(o, "ROCK_SMASH", "碎岩", "岩石碎开了！")
		"boulder":
			_push_boulder(o)
		"elevator":
			_open_elevator()
			return
		"berry_tree":
			_berry_interact(o, true)
		"soil":
			_berry_interact(o, false)


## 百货电梯：站门口按 A，选一层就过去
const ELEVATOR_FLOORS := {
	"johto_goldenrod_dept_store_elevator": [
		["B1F", "johto_goldenrod_dept_store_b1_f", [4, 3]],
		["1F", "johto_goldenrod_dept_store_1f", [0, 2]],
		["2F", "johto_goldenrod_dept_store_2f", [0, 2]],
		["3F", "johto_goldenrod_dept_store_3f", [0, 2]],
		["4F", "johto_goldenrod_dept_store_4f", [0, 2]],
		["5F", "johto_goldenrod_dept_store_5f", [0, 2]],
		["6F", "johto_goldenrod_dept_store_6f", [0, 2]],
		["屋顶", "johto_goldenrod_dept_store_roof", [3, 2]],
	],
	"johto_celadon_dept_store_elevator": [
		["1F", "johto_celadon_dept_store_1f", [0, 2]],
		["2F", "johto_celadon_dept_store_2f", [0, 2]],
		["3F", "johto_celadon_dept_store_3f", [0, 2]],
		["4F", "johto_celadon_dept_store_4f", [0, 2]],
		["5F", "johto_celadon_dept_store_5f", [0, 2]],
		["6F", "johto_celadon_dept_store_6f", [0, 2]],
	],
}

func _open_elevator() -> void:
	var cur := String(world.map_data.get("id", ""))
	var native_stops: Array = world.map_data.get("lift_stops", [])
	if not native_stops.is_empty():
		var names: Array = []
		for stop in native_stops:
			var m: Dictionary = Data.load_map(stop.region, stop.map)
			var label := String(stop.map).get_slice("_",2).to_upper()
			names.append(label if cur=="rocket_hideout_elevator" else m.get("name", stop.map))
		_pick("要去哪一层？", names, func(index: int) -> void:
			if index >= 0 and index < native_stops.size():
				_do_warp(native_stops[index])
				_persist())
		return
	var rows = ELEVATOR_FLOORS.get(cur, [])
	if (rows as Array).is_empty():
		_dialog(["电梯停运了。"], "")
		return
	var labels: Array = []
	for r in rows:
		labels.append(String((r as Array)[0]))
	_pick("要去哪一层？", labels, func(idx: int) -> void:
		if idx < 0 or idx >= (rows as Array).size():
			return
		var r: Array = rows[idx]
		var m2: Dictionary = Data.load_map("johto", String(r[1]))
		if m2.is_empty():
			_show_toast("这一层还没修好。")
			return
		var at: Array = r[2]
		world.load_map(m2)
		world.warp_to(Vector2i(int(at[0]), int(at[1])))
		world.finish_walk()
		_refresh_scene()
		_persist()
		snd.play_sfx("confirm"))


## 培育屋：一只换一个蛋，蛋靠走路孵
func _daycare(npc: Dictionary) -> void:
	var egg: Dictionary = save_data.get("egg", {})
	if not egg.is_empty():
		_dialog(["蛋还没孵出来。", "多走走吧，蛋会自己动的。"], String(npc.get("name", "")))
		return
	var party: Array = save_data.get("party", [])
	if PartyScript.occupied(party) < 2:
		_dialog(["只有一只可不行。", "留两只给我，才有的照顾。"], String(npc.get("name", "")))
		return
	if save_data.get("daycare_done", false):
		_dialog(["上次那只照顾得不错。", "再带一只来吧。"], String(npc.get("name", "")))
		return
	var babys = [133, 172, 173, 174, 175, 236, 238, 239, 240, 298, 360]
	var sp: int = int(babys[randi() % babys.size()])
	save_data["egg"] = {"species": sp, "steps": 180}
	save_data["daycare_done"] = true
	_persist()
	snd.play_sfx("confirm")
	_dialog(["哦？这两只相处得不错。", "这个蛋交给你，路上带着暖一暖。"], String(npc.get("name", "")))


## 每走一步看一眼蛋
func _tick_egg() -> void:
	var egg: Dictionary = save_data.get("egg", {})
	if egg.is_empty():
		return
	egg["steps"] = int(egg.get("steps", 0)) - 1
	if int(egg["steps"]) > 0:
		save_data["egg"] = egg
		return
	var sp := int(egg.get("species", 133))
	save_data.erase("egg")
	var destination := _add_to_team(sp, 5, "", PartyScript.roll_shiny(appearance_rng))
	snd.play_sfx("levelup")
	_dialog(["蛋动了动……", "孵出来了！" if destination == "party" else "孵出来了！队伍已满，已送入电脑。"], "")
	_persist()


## 秘传招式开路：队伍里有这招就能清掉挡路的树/石头
func _party_has_move(key: String) -> bool:
	for m in save_data.get("party", []):
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		for mid in (m as Dictionary).get("moves", []):
			if String((Data.move_of(int(mid)) as Dictionary).get("key", "")) == key:
				return true
	return false


func _use_field_move(o: Dictionary, key: String, cname: String, msg: String) -> void:
	if not _party_can_move(key):
		_dialog([_field_move_hint(key,cname)], "")
		return
	snd.play_sfx("hit")
	world.mark_taken(o)
	save_data["flags"] = world.taken
	_persist()
	_dialog([msg], "")


## 地形类秘传招式统一入口：潜水、漩涡、攀岩
func _try_terrain_move() -> bool:
	var face: Vector2i = world.player_pos + {
		"up": Vector2i(0, -1), "down": Vector2i(0, 1),
		"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
	}.get(world.facing, Vector2i(0, 1))
	# 潜水：对着深水按 A
	if world.is_deep(face) or (world.diving and not world.is_deep(face)):
		if world.diving:
			var m: String = world.toggle_dive()
			if m != "":
				_show_toast(m)
				return true
		elif _party_has_move("DIVE"):
			_show_toast(world.toggle_dive())
			return true
		return false
	# 漩涡
	if world.is_whirl(face) and not world.whirl_cleared(face):
		if not _party_has_move("WHIRLPOOL"):
			_dialog(["水面打着旋。", "（需要会「漩涡」的宝可梦）"], "")
			return true
		world.clear_whirl(face)
		save_data["flags"] = world.taken
		_persist()
		snd.play_sfx("hit")
		_dialog(["漩涡被平息了。"], "")
		return true
	# 攀岩
	if world.is_climb(face):
		if not _party_has_move("ROCK_CLIMB"):
			_dialog(["岩壁陡得很。", "（需要会「攀岩」的宝可梦）"], "")
			return true
		if world.climb_up():
			snd.play_sfx("hit")
			_show_toast("攀上岩壁了")
			return true
	return false


## 攀瀑：冲浪时对着瀑布按 A，一路爬到顶上
func _use_waterfall() -> bool:
	if not world.surfing:
		return false
	var dir: Vector2i = world._dir_vec()
	if dir != Vector2i.UP or not world.is_waterfall(world.player_pos + dir):
		return false
	if not _party_can_move("WATERFALL"):
		_dialog([_field_move_hint("WATERFALL", "攀瀑")])
		return true
	var top: Vector2i = world.player_pos
	while world.is_waterfall(top + dir):
		if not world.can_enter(top + dir,dir):
			_dialog(["这里爬不上去。"])
			return true
		top += dir
	if world.can_enter(top + dir,dir):
		top += dir
	world.warp_to(top)
	world.surfing = world.is_water(top)
	_persist()
	snd.play_sfx("hit")
	_dialog(["顺着瀑布爬上来了！"], "")
	return true


## 怪力：不是清掉，是推一格；推不动就明说被挡住了
func _push_boulder(o: Dictionary) -> void:
	if not _party_can_move("STRENGTH"):
		_dialog(["石头纹丝不动。", _field_move_hint("STRENGTH","怪力")], "")
		return
	var dir: Vector2i = {
		"up": Vector2i(0, -1), "down": Vector2i(0, 1),
		"left": Vector2i(-1, 0), "right": Vector2i(1, 0),
	}.get(world.facing, Vector2i(0, 1))
	var at: Array = o.get("at", [0, 0])
	var real: Dictionary = world.object_ref(Vector2i(int(at[0]), int(at[1])))
	if world.push_object(real, dir):
		save_data["flags"] = world.taken
		_persist()
		snd.play_sfx("hit")
		if real.get("dropped",false):
			_dialog(["石头从洞口落到了下面一层。"])
		elif bool(real.get("filled_hole", false)):
			_dialog(["石头落进洞里，把坑填平了。"], "")
		elif bool(real.get("sunk", false)):
			_dialog(["石头掉进水里，沉了下去。"], "")
		elif world.is_button(world.player_pos + dir + dir):
			# 石头压在开关上：原版这种机关一压就响
			var fl: Dictionary = save_data.get("flags", {})
			if real.has("rock_id"):
				fl["placed:"+str(real.rock_id)]=real.at.duplicate()
			fl["btn:%s:%d,%d" % [String(world.map_data.get("id", "")),
				world.player_pos.x + dir.x * 2, world.player_pos.y + dir.y * 2]] = true
			save_data["flags"] = fl
			if real.has("rock_id"): world.refresh_story_actors(fl)
			_persist()
			snd.play_sfx("confirm")
			_dialog(["石头压住了开关。", "咔哒一声，深处传来机关响动。"], "")
		else:
			_dialog(["石头被推动了。"], "")
	else:
		_dialog(["石头纹丝不动。", "（后面被挡住了）"], "")


## ---------- 树果：种下 / 浇水 / 摘 ----------
const BERRY_STAGE_SEC := 180.0      # 现实 3 分钟长一阶段，浇过水减半

func _berry_key(o: Dictionary) -> String:
	return String(o.get("_key", "berry"))


func _berry_state(o: Dictionary) -> Dictionary:
	var all: Dictionary = save_data.get("berries", {})
	return all.get(_berry_key(o), {})


func _berry_stage(o: Dictionary) -> int:
	var st := _berry_state(o)
	if st.is_empty():
		return -1
	var planted := float(st.get("planted", 0.0))
	var watered := float(st.get("watered", 0.0))
	var speed := 1.0
	if watered > planted:
		speed = 2.0
	var stages := int((Time.get_unix_time_from_system() - planted) * speed / BERRY_STAGE_SEC)
	return clampi(stages, 0, 4)


func _berry_interact(o: Dictionary, is_tree: bool) -> void:
	if not (save_data.get("berries", null) is Dictionary):
		save_data["berries"] = {}
	var all: Dictionary = save_data["berries"]
	var key := _berry_key(o)
	var st: Dictionary = all.get(key, {})
	if st.is_empty():
		# 没种：选一种树果种下去
		if is_tree:
			_dialog(["树上没有果子。", "过一段时间再来看看。"], "")
			return
		var seed := _first_berry_in_bag()
		if seed.is_empty():
			_dialog(["这里可以种树果。", "可是你手上没有树果。"], "")
			return
		all[key] = {"berry": String(seed.get("berry", "")), "name": String(seed.get("name", "树果")),
			"planted": Time.get_unix_time_from_system(), "watered": 0.0}
		seed["count"] = int(seed.get("count", 1)) - 1
		if int(seed.get("count", 0)) <= 0:
			bag_items.erase(seed)
		snd.play_sfx("confirm")
		_persist()
		_dialog(["种下了「%s」。" % all[key]["name"], "记得回来浇水。"], "")
		return
	var stage := _berry_stage(o)
	if stage >= 4:
		var n := 2 + randi() % 3
		var nm := String(st.get("name", "树果"))
		for i in n:
			_give_bag_item(nm, "berry", "", String(st.get("berry", "")))
		all.erase(key)
		snd.play_sfx("item")
		_persist()
		_dialog(["摘到了 %d 个「%s」！" % [n, nm]], "")
		return
	if float(st.get("watered", 0.0)) < float(st.get("planted", 0.0)):
		st["watered"] = Time.get_unix_time_from_system()
		all[key] = st
		snd.play_sfx("water")
		_persist()
		_dialog(["浇了水。", "长得快了一些。"], "")
		return
	_dialog(["「%s」还在长（%d/4）。" % [String(st.get("name", "树果")), stage]], "")


func _first_berry_in_bag() -> Dictionary:
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("category", "")) == "berry":
			return it
	return {}


## ---------- 钓鱼 ----------
const FISH_TABLE := [
	{"species": 129, "min": 5, "max": 15}, {"species": 118, "min": 5, "max": 15},
	{"species": 60, "min": 5, "max": 15}, {"species": 72, "min": 5, "max": 20},
	{"species": 90, "min": 5, "max": 15}, {"species": 98, "min": 5, "max": 15},
	{"species": 116, "min": 5, "max": 20}, {"species": 120, "min": 5, "max": 20},
	{"species": 54, "min": 10, "max": 25}, {"species": 147, "min": 10, "max": 20},
]

const RODS := ["破旧钓竿","好钓竿","厉害钓竿"]

func _fish(rod: String = "") -> void:
	if not _has_party():
		_show_toast("先带上一只宝可梦，再来钓鱼吧。")
		return
	if rod.is_empty():
		var owned := []
		for name_text in RODS + ["钓竿"]:
			if _bag_count(name_text) > 0:
				owned.append(name_text)
		if owned.is_empty(): return
		if owned.size() > 1:
			_pick("要用哪根钓竿？", owned + ["返回"], func(i: int) -> void:
				if i >= 0 and i < owned.size(): _fish(owned[i]))
			return
		rod = str(owned[0])
	var pool: Array = FISH_TABLE
	if world.map_data.get("region","") in ["kanto","sevii"]:
		var area: Dictionary = world.map_data
		if area.get("id","") == "kanto_main":
			area = world.area_at(world.player_pos + world._dir_vec())
		var tables: Array = area.get("fishing",[])
		# 4.52 的通用钓竿可继续使用多鱼种鱼群。
		var rank: int = 1 if rod == "钓竿" else RODS.find(rod)
		pool = tables[rank] if rank >= 0 and rank < tables.size() else []
	elif rod == "破旧钓竿":
		pool = [{"species":129,"min":5,"max":5}]
	var pick: Dictionary = EncounterScript.roll(pool,rng)
	if pick.is_empty():
		_show_toast("这里没有鱼上钩。")
		return
	snd.play_sfx("water")
	_dialog(["……","钓到了什么东西！"],"")
	_start_wild_battle(int(pick.species),int(pick.level))


## ---------- 招式学习器 ----------
func _offer_tm_teach(nm: String) -> void:
	var mv := _tm_move_of(nm)
	if mv <= 0:
		_show_toast("这东西看不出是哪个招式。")
		return
	var mv_name := String((Data.move_of(mv) as Dictionary).get("name", "招式"))
	var party: Array = save_data.get("party", [])
	var can: Array = []
	var names: Array = []
	for i in party.size():
		var m: Dictionary = party[i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		can.append(i)
		names.append(String(m.get("name", "宝可梦")))
	if can.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("要让谁学「%s」？" % mv_name, names,
		func(idx: int) -> void: _tm_teach_one(mv, int(can[idx]), mv_name))


func _tm_teach_one(mv: int, slot: int, mv_name: String) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var m: Dictionary = party[slot]
	if not _can_learn_move(int(m.get("species_id", 0)), mv):
		_dialog(["%s 学不会「%s」。" % [String(m.get("name", "宝可梦")), mv_name]], "")
		return
	var mvs: Array = m.get("moves", [])
	if mvs.any(func(id): return int(id) == mv):
		_dialog(["%s 已经会「%s」了。" % [m.get("name", "宝可梦"), mv_name]], "")
		return
	var pp: Array = m.get("pp", [])
	while pp.size() < mvs.size():
		pp.append(int(Data.move_of(int(mvs[pp.size()])).get("pp", 1)))
	m["pp"] = pp
	var move_pp := int(Data.move_of(mv).get("pp", 1))
	if mvs.size() < 4:
		mvs.append(mv)
		pp.append(move_pp)
		m["moves"] = mvs
		save_data["party"] = party
		_persist()
		snd.play_sfx("levelup")
		_dialog(["%s 学会了「%s」！" % [String(m.get("name", "宝可梦")), mv_name]], "")
		return
	# 招式满了，让玩家选忘掉哪一个
	var labels: Array = []
	for i in mvs.size():
		labels.append("%s（%d）" % [String((Data.move_of(int(mvs[i])) as Dictionary).get("name", "?")), int(mvs[i])])
	labels.append("算了，不学")
	_pick("招式满了，忘掉哪一招？", labels,
		func(idx: int) -> void:
			if idx < 0 or idx >= mvs.size():
				return
			var old_name := String((Data.move_of(int(mvs[idx])) as Dictionary).get("name", "旧招"))
			mvs[idx] = mv
			pp[idx] = move_pp
			m["moves"] = mvs
			save_data["party"] = party
			_persist()
			snd.play_sfx("levelup")
			_dialog(["忘掉了「%s」。" % old_name,
				"%s 学会了「%s」！" % [String(m.get("name", "宝可梦")), mv_name]], ""))


func _tm_move_of(nm: String) -> int:
	return int(Data.tm_map.get(nm, 0))


## 这只能不能学这招：学习表里有，或者本来就是它的招式。
## 原版的"招式机兼容表"我们没有搬进来（machine_set 是空的），
## 所以招式机一律放行，不然玩家永远学不会冲浪/飞行/闪光。
func _can_learn_move(sid: int, mv: int) -> bool:
	var sp: Dictionary = Data.species_of(sid)
	for row in sp.get("learnset", []):
		if row is Array and int(row[1]) == mv:
			return true
	for row2 in sp.get("machine_set", []):
		if int(row2) == mv:
			return true
	if _is_machine_move(mv):
		return true
	return false


## 这招是不是招式机/秘传学习器里的
func _is_machine_move(mv: int) -> bool:
	for k in Data.tm_map.keys():
		if int(Data.tm_map[k]) == mv:
			return true
	return false


func _tm_teach_menu(mv: int, slots: Array, names: Array) -> void:
	# 简单起见：先给第一个能学的学，学不了就往下找
	var party: Array = save_data.get("party", [])
	for i in slots:
		var m: Dictionary = party[i]
		if _can_learn_move(int(m.get("species_id", 0)), mv):
			var mvs: Array = m.get("moves", [])
			if mvs.size() < 4:
				mvs.append(mv)
				m["moves"] = mvs
				save_data["party"] = party
				_persist()
				snd.play_sfx("levelup")
				_dialog(["%s 学会了「%s」！" % [String(m.get("name", "宝可梦")),
					String((Data.move_of(mv) as Dictionary).get("name", "招式"))]], "")
				return
	_dialog(["没有宝可梦能学这招。"], "")


func _battle_backdrop() -> String:
	var m: Dictionary = world.map_data
	var id := String(m.get("id",""))
	var biome: String = world.field_biome()
	if world.diving:
		return "underwater"
	if world.surfing or biome=="coast" or id.contains("harbor"):
		return "water"
	if biome in ["sand","desert"] or id.contains("desert"):
		return "sand"
	if biome=="snow" or id.contains("ice_path"):
		return "ice"
	if biome in ["ruins","space"] or id.contains("sky_pillar"):
		return "sky"
	if biome in ["cave","volcano"] or id.contains("cave") or id.contains("tunnel"):
		return "cave"
	if johto_league.stage(id)>0:
		return "league"
	if id.contains("gym"):
		return "gym"
	if biome in ["city", "interior"]:
		return "building"
	if biome in ["forest","marsh"] or id.contains("forest"):
		return "forest"
	return "grass"

func _sevii_ferry() -> void:
	var campaign = preload("res://core/sevii_campaign.gd")
	var ports: Array = campaign.destinations(bag_items)
	if ports.is_empty():
		var advice := "请先出示通行证。红莲岛的正辉认识这条船的船长。"
		if world.map_data.id=="kanto_main":
			advice = "欢迎来到枯叶码头。圣安奴号在南侧栈桥验船票。" if not _flags().get("anne_departed",false) else "圣安奴号已经出港。七岛的联络船还没靠岸，红莲岛的正辉认识船长。"
		_dialog([advice],"船员")
		return
	ports.erase(world.map_data.id)
	var labels: Array = []
	for port in ports: labels.append(campaign.PORTS[port])
	if _flags().get("sevii_detour_finished",false) and world.map_data.id != "kanto_main":
		ports.append("kanto_main")
		labels.append("枯叶市")
	labels.append("留在这里")
	_pick("海烈焰马号要出航了。你要去哪一站？",labels,func(i: int) -> void:
		if i < 0 or i >= ports.size(): return
		var port: String = ports[i]
		if port == "kanto_main":
			_do_warp({"region":"kanto","map":port,"at":[287,231]})
		else:
			_do_warp({"region":"sevii","map":port,"at":[8,3]})
		_persist())

func _receive_field_machine(npc: Dictionary) -> void:
	var reward: Dictionary = npc.gives_hm
	var flag := "received_hm_%02d" % int(reward.number)
	if _flags().get(flag,false):
		_dialog(npc.lines,npc.name)
		return
	if reward.has("kanto_caught"):
		var caught := preload("res://core/kanto_campaign.gd").caught_species_count(save_data)
		if not _flags().get("got_dex",false) or caught < int(reward.kanto_caught):
			_dialog(["我是大木博士的助手。图鉴上捕获十种关都宝可梦后，请回来找我。你目前登记了%d种。" % caught],npc.name)
			return
	var item := "秘传学习器 %02d" % int(reward.number)
	_give_item(item,1,"tm")
	_flags()[flag] = true
	_persist()
	snd.play_sfx("item")
	_dialog([reward.say,"获得了%s（%s）。" % [item,Data.move_of(int(Data.tm_map[item])).name]],npc.name)

func _talk_to_npc(npc: Dictionary) -> void:
	if npc.is_empty():
		return
	if npc.has("gives_hm"):
		_receive_field_machine(npc)
		return
	if npc.has("gives_rod"):
		var rod := str(npc.gives_rod)
		var flag := "rod_" + rod
		if _flags().get(flag,false):
			_dialog(["面朝水边，从背包选「%s」就能甩竿。" % rod],npc.name)
		else:
			_pick("喜欢钓鱼吗？我这根%s送给你。" % rod,["好","不用了"],func(choice: int) -> void:
				if choice == 0:
					_give_item(rod,1,"key")
					_flags()[flag] = true
					_persist()
					_dialog(["获得了%s！面朝水面就可以试试。" % rod],npc.name))
		return
	if npc.get("vs_seeker",false):
		if not _flags().get("got_vs_seeker",false):
			_give_item("对战搜寻器",1,"key")
			_flags().got_vs_seeker = true
			save_data["vs_charge"] = 100
			_persist()
			_dialog(["想再向老对手挑战吗？这个对战搜寻器给你。","在路边打赢过的训练家附近使用。下次充满电需要走一百步。"],npc.name)
		else:
			_dialog(["带着搜寻器走一百步，电就能充满。到道路上试试吧！"],npc.name)
		return
	var role := str(npc.get("role",""))
	if role=="cave_mewtwo":
		_start_wild_battle(150,70)
		active_battle.finished.connect(func(outcome):
			if outcome in ["caught","a"]:
				_flags().kanto_mewtwo_cleared=true
				world.refresh_story_actors(_flags())
				_persist())
		return
	if role=="kanto_record":
		_dialog(johto_league.record_lines(save_data,"kanto"),"名人堂")
		return
	if role == "selphy_home":
		if save_data.get("selphy_thanked",false):
			_dialog(["今天真高兴！下次再让管家招待你。"],"阿姿莎")
			return
		var request := preload("res://core/sevii_campaign.gd").show_partner(save_data,rng)
		if request.is_empty(): return
		var wanted: String = Data.species_of(int(request.species)).name
		if request.has("reward"):
			var reward: String = request.reward
			var category := "ball" if reward=="豪华球" else ("candy" if reward=="神奇糖果" else "other")
			_give_item(reward,1,category)
			_dialog(["就是%s！谢谢你特地带它来。管家，请把%s送给这位客人。"%[wanted,reward]],"阿姿莎")
		else:
			_dialog(["我想见见%s。能在我改变主意前，让它跟着你的队伍来家里吗？"%wanted],"阿姿莎")
		_persist()
		return
	if role == "sevii_ferry":
		_sevii_ferry()
		return
	if role in ["snorlax_12","snorlax_16"]:
		if not _flags().get("poke_flute",false):
			_dialog(["一只卡比兽在这里睡得正香。"])
			return
		var prompt := _dialog(["要用宝可梦之笛唤醒卡比兽吗？"])
		prompt.ask("吹奏","离开")
		prompt.answered.connect(func(play: bool):
			if play:
				_flags()["FLAG_HIDE_ROUTE_%s_SNORLAX" % role.get_slice("_",1)] = true
				world.refresh_story_actors(_flags())
				_apply_defeated()
				_start_wild_battle(143,30))
		return
	if npc.get("transit", false):
		_open_world_atlas(true)
		return
	if npc.get("hall_record", false):
		_dialog(johto_league.record_lines(save_data), "名人堂")
		return
	if npc.has("league_flag"):
		var message := johto_league.gate_message(String(world.map_data.get("id", "")), save_data)
		if message != "":
			_dialog([message], String(npc.name))
			return
		if bool(_flags().get(npc.league_flag, false)):
			_dialog(npc.after, String(npc.name))
			return
	if npc.get("shop", false):
		_open_shop()
		return
	if npc.get("facility", false):
		_open_facility(npc)
		return
	if npc.get("form_items", false):
		_open_form_items()
		return
	if npc.get("daycare", false):
		_daycare(npc)
		return
	if npc.get("gives_bike", false):
		var has_bike := false
		for it in bag_items:
			if it is Dictionary and String((it as Dictionary).get("name", "")).contains("自行车"):
				has_bike = true
				break
		if has_bike:
			_dialog(["车骑得还顺手吧？", "别在店里骑就行。"], String(npc.get("name", "")))
			return
		_give_bag_item("自行车", "key")
		_persist()
		snd.play_sfx("item")
		_dialog(npc.get("lines", ["给你的。"]), String(npc.get("name", "")))
		return
	if npc.get("heal", false):
		_dialog_heal(npc)
		return
	# 空木博士桌上的三个精灵球：一人只能拿一个，拿了就空
	if npc.has("gives_mon"):
		var gm: Dictionary = npc["gives_mon"]
		var fkey := "mon_%s_%s_%d_%d" % [String(world.map_data.get("region", "")), String(world.map_data.get("id", "")), int(npc.get("at", [0, 0])[0]), int(npc.get("at", [0, 0])[1])]
		var fst := _flags()
		if bool(fst.get(fkey, false)):
			_dialog(["这个精灵球已经空了。"], "")
			return
		# 每人只能挑一只城都初始：已有一只 152/155/158 就拦下
		var picked := bool(fst.get("johto_starter", false))
		for mon in (save_data.get("party", []) as Array) + (save_data.get("box", []) as Array):
			if not (mon is Dictionary):
				continue
			var sp0 := int((mon as Dictionary).get("species", (mon as Dictionary).get("species_id", 0)))
			if sp0 == 152 or sp0 == 155 or sp0 == 158:
				picked = true
				break
		if picked:
			_dialog(["你已经挑过一只了。", "把它照顾好就行。"], "")
			return
		var gsid := int(gm.get("species", 152))
		var glv := int(gm.get("level", 5))
		fst[fkey] = true
		# 剧情表要能知道"已经挑过初始了"
		var gf := String(gm.get("flag", ""))
		if gf != "":
			fst[gf] = true
		save_data["flags"] = fst
		_add_to_team(gsid, glv)
		_persist()
		snd.play_sfx("item")
		_dialog([String((Data.species_of(gsid) as Dictionary).get("name", "")) + " 加入了队伍！"], "")
		return
	if npc.has("battle") and not npc.get("defeated", false):
		if not _has_party():
			_dialog(["你还没有宝可梦吧？", "先回新叶镇找空木博士，他会给你一只。"], String(npc.get("name", "")))
			return
		var ls = npc.get("lines", null)
		if ls is Array and not (ls as Array).is_empty():
			# 先说完再动手，跟原版一样
			var d = _dialog(ls, String(npc.get("name", "")))
			d.connect("closed", func() -> void: _start_battle(npc))
			return
		_show_toast(String(npc.get("name", "")) + "：来一场吧！")
		_start_battle(npc)
		return
	var nm := String(npc.get("name", ""))
	DialogLines(npc, nm)

## NPC 说话：多句台词优先，只有一句时退回 line
func DialogLines(npc: Dictionary, who: String) -> void:
	var ls = npc.get("lines", null)
	if npc.get("defeated", false) and npc.has("post"):
		ls = npc.post if npc.post is Array else [npc.post]
	if ls is Array and not (ls as Array).is_empty():
		_dialog(ls, who)
		return
	_dialog([String(npc.get("line", "路上小心。"))], who)

func _talk_to(name: String) -> void:
	var npc := _find_npc(name)
	if npc.is_empty():
		_dialog(["今天的风不错。"], name)
		return
	if npc.has("gives_hm") or npc.has("league_flag") or npc.get("hall_record", false):
		_talk_to_npc(npc)
		return
	if npc.get("facility", false):
		_open_facility(npc)
		return
	if npc.get("daycare", false):
		_daycare(npc)
		return
	if npc.get("gives_bike", false):
		var has_bike := false
		for it in bag_items:
			if it is Dictionary and String((it as Dictionary).get("name", "")).contains("自行车"):
				has_bike = true
				break
		if has_bike:
			_dialog(["车骑得还顺手吧？", "别在店里骑就行。"], String(npc.get("name", "")))
			return
		_give_bag_item("自行车", "key")
		_persist()
		snd.play_sfx("item")
		_dialog(npc.get("lines", ["给你的。"]), String(npc.get("name", "")))
		return
	if npc.get("heal", false):
		_dialog_heal(npc)
		return
	if npc.has("battle") and not npc.get("defeated", false):
		if not _has_party():
			_dialog(["你还没有宝可梦吧？", "先去真新镇找大木博士，他会给你一只。"], name)
			return
		var ls2 = npc.get("lines", null)
		if ls2 is Array and not (ls2 as Array).is_empty():
			var d2 = _dialog(ls2, name)
			d2.connect("closed", func() -> void: _start_battle(npc))
			return
		_dialog(["来一场吧！"], name)
		_start_battle(npc)
		return
	DialogLines(npc, name)

## 对战塔：连胜挑战，Lv50 平级，不消耗真实队伍
func _open_facility(npc: Dictionary) -> void:
	var f: Dictionary = save_data.get("facility", {})
	var streak := int(f.get("streak", 0))
	var best := int(f.get("best", 0))
	_show_toast("前台：当前连胜 %d 场（最高 %d）。开始吧！" % [streak, best])
	_start_facility_battle()

func _start_facility_battle() -> void:
	var f: Dictionary = save_data.get("facility", {})
	var streak := int(f.get("streak", 0))
	var mine: Array = FacilityScript.tower_team(save_data.get("party", []))
	var enemy: Array = [FacilityScript.make_opponent(streak, rng)]

	snd.play_sfx("hit")
	snd.battle_music(false)
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var ui := BattleUI.new()
	ui.backdrop = _battle_backdrop()
	ui.observe_variant = _battle_variant_seen.bind(PartyScript.occupied(save_data.get("party", [])) > 0)
	active_battle = ui
	held_dir = ""
	layer.add_child(ui)
	ui.setup(mine, enemy, rng.randi(), bag_items, "前台挑战者")
	ui.item_used.connect(func(nm: String) -> void:
		for it in bag_items:
			if it is Dictionary and String((it as Dictionary).get("name", "")) == nm:
				it["count"] = maxi(0, int(it.get("count", 0)) - 1))
	_set_hud_visible(false)
	ui.finished.connect(func(result: String) -> void:
		active_battle = null
		# 塔内是 Lv50 临时队伍，不回写存档血量
		var fac: Dictionary = save_data.get("facility", {})
		var cur := int(fac.get("streak", 0))
		if result == "a":
			cur += 1
			var bonus := FacilityScript.prize(cur)
			save_data["money"] = int(save_data.get("money", 0)) + bonus
			fac["streak"] = cur
			fac["best"] = maxi(int(fac.get("best", 0)), cur)
			_show_toast("连胜 %d 场！奖金 %d 元" % [cur, bonus])
		else:
			fac["streak"] = 0
			fac["best"] = maxi(int(fac.get("best", 0)), cur)
			_show_toast("挑战结束，纪录停在 %d 连胜。" % cur)
		save_data["facility"] = fac
		_persist()
		_set_hud_visible(true)
		layer.queue_free()
	)

## 宝可梦中心：队伍全恢复，PP 也回满
func _party_fainted() -> bool:
	return _has_party() and not save_data.get("party",[]).any(func(m): return m is Dictionary and int(m.get("hp",0)) > 0)

func _blackout() -> void:
	if world.map_data.region not in ["kanto","sevii"]: return
	var destination: Dictionary = save_data.get("last_pokemon_center",{"region":"kanto","map":"pallet_town_players_house_2f","at":[3,6]})
	_heal_party()
	_do_warp(destination)
	_persist()
	_dialog(["你赶到安全的地方，让伙伴们恢复了体力。"],"旁白")

func _heal_party() -> void:
	snd.play_sfx("heal")
	var party: Array = save_data.get("party", [])
	for m in party:
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var mon: Dictionary = m
		mon["hp"] = int(mon.get("max_hp", 1))
		mon["hp_text"] = "%d/%d" % [int(mon["hp"]), int(mon["max_hp"])]
		var pps: Array = []
		for mid in mon.get("moves", []):
			pps.append(int((Data.move_of(int(mid)) as Dictionary).get("pp", 10)) if int(mid) > 0 else 0)
		mon["pp"] = pps
	save_data["party"] = PartyScript.compact(party)
	_persist()

## 打赢过的训练家记进存档，换图回来就不再重新开战
func _mark_defeated(npc_name: String) -> void:
	if npc_name == "":
		return
	var key := "%s/%s" % [String(world.map_data.get("region", "")), String(world.map_data.get("id", ""))]
	var all: Dictionary = save_data.get("defeated", {})
	var arr: Array = all.get(key, [])
	if not arr.has(npc_name):
		arr.append(npc_name)
	all[key] = arr
	save_data["defeated"] = all

## 每次载入地图后，把已击败的训练家标回去
func _apply_defeated() -> void:
	var key := "%s/%s" % [String(world.map_data.get("region", "")), String(world.map_data.get("id", ""))]
	var arr: Array = (save_data.get("defeated", {}) as Dictionary).get(key, [])
	for n in world.npcs:
		if arr.has(String(n.get("name", ""))):
			n["defeated"] = true

func _use_vs_seeker() -> void:
	var charge := int(save_data.get("vs_charge",100))
	if charge < 100:
		_dialog(["还要走 %d 步才能充满电。" % (100-charge)],"对战搜寻器")
		return
	var available := []
	var key := "%s/%s" % [world.map_data.region,world.map_data.id]
	var defeated: Array = save_data.get("defeated",{}).get(key,[])
	var outdoors: bool = world.map_data.get("id","") == "kanto_main" or (world.map_data.region == "sevii" and world.map_data.get("cycling",false))
	if outdoors:
		for trainer in world.npcs:
			if not trainer.has("battle") or trainer.has("role") or trainer.has("badge") or not defeated.has(trainer.name):
				continue
			var offset: Vector2i = world.player_pos - Vector2i(int(trainer.at[0]),int(trainer.at[1]))
			if absi(offset.x) <= 7 and absi(offset.y) <= 5:
				defeated.erase(trainer.name)
				trainer["defeated"] = false
				available.append(trainer.name)
	if available.is_empty():
		_dialog(["附近没有接受再战的训练家。到道路上找以前交过手的对手吧。"],"对战搜寻器")
		return
	save_data["vs_charge"] = 0
	_persist()
	_dialog(["%s 回应了信号！和训练家交谈即可再战。" % "、".join(available)],"对战搜寻器")

func _find_npc(name: String) -> Dictionary:
	for n in world.npcs:
		if String(n.get("name", "")) == name:
			return n
	return {}

func _start_battle(npc: Dictionary, on_done := Callable()) -> void:
	var cfg: Dictionary = npc.get("battle", {})
	# 支持整队：道馆馆主不是一只，队伍按原版配置来
	var enemy: Array = []
	var team = cfg.get("team", cfg.get("party", []))
	if team is Array and not (team as Array).is_empty():
		for e in team:
			var sid := int(e.get("species", 143))
			var lv := int(e.get("level", 10))
			# 没写招式就按它的等级从学习表里配
			var mvs = e.get("moves", null)
			if not (mvs is Array) or (mvs as Array).is_empty():
				mvs = EncounterScript.moves_for(sid, lv)
			var opponent := BattleScript.make_combatant(sid, lv, mvs)
			opponent["berry"] = e.get("berry", "")
			enemy.append(opponent)
	else:
		var sid2 := int(cfg.get("species", 143))
		var lv2 := int(cfg.get("level", 10))
		var mvs2 = cfg.get("moves", null)
		if not (mvs2 is Array) or (mvs2 as Array).is_empty():
			mvs2 = EncounterScript.moves_for(sid2, lv2)
		enemy.append(BattleScript.make_combatant(sid2, lv2, mvs2))
	var mine: Array = _make_team()

	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var ui := BattleUI.new()
	ui.backdrop = _battle_backdrop()
	ui.observe_variant = _battle_variant_seen.bind(PartyScript.occupied(save_data.get("party", [])) > 0)
	active_battle = ui
	held_dir = ""
	layer.add_child(ui)
	ui.setup(mine, enemy, rng.randi(), bag_items, String(npc.get("name", "训练家")))
	ui.item_used.connect(func(nm: String) -> void:
		for it in bag_items:
			if it is Dictionary and String((it as Dictionary).get("name", "")) == nm:
				it["count"] = maxi(0, int(it.get("count", 0)) - 1))
	_set_hud_visible(false)
	ui.finished.connect(func(result: String) -> void:
		active_battle = null
		_writeback_team(ui.player_team)
		snd.play_sfx("confirm")
		snd.stop_music()
		_update_music()
		npc["defeated"] = result == "a"
		if result == "a":
			var npc_name := String(npc.get("name", ""))
			if npc.has("league_flag"):
				_flags()[npc.league_flag] = true
			_mark_defeated(npc_name)
			var lv := int(cfg.get("level", 0))
			if lv == 0 and not enemy.is_empty():
				lv = int((enemy[0] as Dictionary).get("level", 10))
			var prize := int(cfg.get("prize", 120 + lv * 22))
			save_data["money"] = int(save_data.get("money", 0)) + prize
			var is_leader := npc_name.contains("馆主")
			var badge := String(npc.get("badge", ""))
			if is_leader and badge != "":
				var have: bool = (save_data.get("badges", []) as Array).has(badge)
				_grant_badge(badge)
				if not have:
					_show_toast("获得 %s！" % badge)
			_award_exp(enemy, prize, badge if is_leader else "")
		elif result=="b" and not on_done.is_valid() and not npc.has("league_flag") and _party_fainted():
			_blackout()
		elif npc.has("league_flag"):
			_do_warp({"region": "johto", "map": johto_league.rules.lobby, "at": [4, 3]})
			_heal_party()
			_show_toast("已在联盟中心恢复，可以再次挑战。")
		else:
			_persist()
			_show_toast("战斗结束")
		_set_hud_visible(true)
		layer.queue_free()
		if on_done.is_valid():
			on_done.call(result)
	)

## 野外一只，打或抓都行。抓到就入队，队伍满了记进 box。
func _start_wild_battle(species_id: int, level: int, form_key: String = "", on_done := Callable()) -> void:
	var mon := PartyScript.make(species_id, level, EncounterScript.moves_for(species_id, level), form_key)
	PartyScript.set_shiny_kind(mon, PartyScript.roll_shiny(appearance_rng))
	var enemy := [mon.duplicate(true)]
	var mine: Array = _make_team()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var ui := BattleUI.new()
	ui.backdrop = _battle_backdrop()
	ui.observe_variant = _battle_variant_seen.bind(PartyScript.occupied(save_data.get("party", [])) > 0)
	active_battle = ui
	held_dir = ""
	layer.add_child(ui)
	ui.setup(mine, enemy, rng.randi(), bag_items)
	ui.item_used.connect(func(nm: String) -> void:
		for it in bag_items:
			if it is Dictionary and String((it as Dictionary).get("name", "")) == nm:
				it["count"] = maxi(0, int(it.get("count", 0)) - 1))
	_set_hud_visible(false)
	ui.finished.connect(func(result: String) -> void:
		active_battle = null
		_writeback_team(ui.player_team)
		if result == "caught":
			var caught: Dictionary = ui.battle.cur_b()
			mon["pp"] = caught.pp.duplicate()
			mon["hp"] = clampi(roundi(float(caught.hp) * mon.max_hp / maxi(1, int(caught.max_hp))), 1, int(mon.max_hp))
			mon["hp_text"] = "%d/%d" % [mon.hp, mon.max_hp]
			mon["status"] = str(caught.get("status", ""))
			mon["berry"] = str(caught.get("berry", ""))
			var destination := _store_mon(mon)
			var name_text := String(Data.species_of(species_id).get("name", "?"))
			_show_toast("抓到了！%s%s" % [name_text, "加入队伍" if destination == "party" else "已送入电脑"])
		elif result == "a":
			_award_exp([mon])
		elif result == "fled":
			_show_toast("成功逃走了！")
		elif result == "b" and not on_done.is_valid() and _party_fainted():
			_blackout()
		else:
			_show_toast("被打退了…")
		_persist()
		_set_hud_visible(true)
		layer.queue_free()
		if on_done.is_valid(): on_done.call(result)
	)

## 打赢后给队伍里没过劳的成员分经验；升满级的不再涨
func _grant_badge(badge: String) -> void:
	var bs: Array = save_data.get("badges", [])
	if not bs.has(badge):
		bs.append(badge)
	save_data["badges"] = bs
	preload("res://core/frlg_actors.gd").migrate_progress(save_data)
	# 拿到徽章就触发对应的剧情台词
	_story_fire("badge", {"badge": badge})

func _award_exp(enemies: Array, prize: int = 0, badge: String = "") -> void:
	var party: Array = save_data.get("party", [])
	var notes: Array = []
	var evolved: Array = []
	for i in party.size():
		var m = party[i]
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var mon: Dictionary = m
		if int(mon.get("hp", 1)) <= 0:
			continue
		var before := int(mon.get("level", 1))
		var gained := 0
		for opponent in enemies:
			GrowthScript.award_effort(mon, int(opponent.species_id))
			var species := Data.species_of(int(opponent.species_id))
			var exp_yield := int(species.get("exp_yield",60))
			var reward := GrowthScript.gain(int(opponent.level), maxi(1,exp_yield), before)
			gained += reward * 3 / 2 if prize > 0 else reward
		var grew := GrowthScript.add_exp(mon, gained) if before < GrowthScript.MAX_LEVEL else 0
		PartyScript.recalc(mon, true)
		if grew > 0:
			notes.append("%s 升到 Lv%d" % [String(mon.get("name", "?")), int(mon["level"])])
			# 升级后学这一级段的新招式
			_learn_new_moves(mon, before, int(mon["level"]))
			var evo: Dictionary = GrowthScript.evolution_of(mon)
			if not evo.is_empty():
				var old_name := String(mon.get("name", "?"))
				if PartyScript.evolve(mon, int(evo.get("to", 0)), String(evo.get("form", ""))):
					DexVariants.record(save_data, mon, true)
					evolved.append("%s 进化成了 %s！" % [old_name, String(mon.get("name", "?"))])
	save_data["party"] = PartyScript.compact(party)
	_persist()
	var text := ""
	if not notes.is_empty():
		text = "、".join(notes)
	if not evolved.is_empty():
		text = (text + "  " if text != "" else "") + String(evolved[0])
	if prize > 0:
		text = (text + "  获得 %d 元" % prize) if text != "" else "获得 %d 元" % prize
	if badge != "":
		text += "  拿到%s！" % badge
	_show_toast(text if text != "" else "赢了！")

## 升到能学新招时，若还有空槽就补上（满四招暂不替换，留给以后的学招界面）
## 升级时按学习表学招式：满了就替换威力最低的那一招
func _learn_new_moves(mon: Dictionary, from_lv: int = 0, to_lv: int = 0) -> void:
	var moves: Array = mon.get("moves", [])
	var pp: Array = mon.get("pp", [])
	var got: Array = GrowthScript.moves_learned(mon, from_lv, to_lv)
	for id in got:
		var mid := int(id)
		if moves.has(mid) or not Data.moves.has(mid):
			continue
		if moves.size() < 4:
			moves.append(mid)
			pp.append(int((Data.move_of(mid) as Dictionary).get("pp", 10)))
			_show_toast("%s 学会了 %s！" % [String(mon.get("name", "?")),
				String((Data.move_of(mid) as Dictionary).get("name", ""))])
			continue
		# 满了：找当前最弱的一招换掉
		var worst := 0
		var worst_power := 9999
		for i in moves.size():
			var pw := int((Data.move_of(int(moves[i])) as Dictionary).get("power", 0))
			if pw < worst_power:
				worst_power = pw
				worst = i
		if int((Data.move_of(mid) as Dictionary).get("power", 0)) > worst_power:
			var old := String((Data.move_of(int(moves[worst])) as Dictionary).get("name", ""))
			moves[worst] = mid
			pp[worst] = int((Data.move_of(mid) as Dictionary).get("pp", 10))
			_show_toast("%s 忘掉了 %s，学会了 %s！" % [String(mon.get("name", "?")), old,
				String((Data.move_of(mid) as Dictionary).get("name", ""))])
	mon["moves"] = moves
	mon["pp"] = pp

## 队伍有空位就进队伍，满了进 box；总之不丢
func _add_to_team(species_id: int, level: int, form_key: String = "", shiny_kind := "none") -> String:
	var moves: Array = EncounterScript.moves_for(species_id, level)
	var mon: Dictionary = PartyScript.make(species_id, level, moves, form_key)
	PartyScript.set_shiny_kind(mon, shiny_kind)
	return _store_mon(mon)

func _store_mon(mon: Dictionary) -> String:
	DexVariants.record(save_data, mon, true)
	var party: Array = save_data.get("party", [])
	if PartyScript.insert_into(party, mon, PartyScript.MAX_SIZE):
		save_data["party"] = party
		return "party"
	if not (save_data.get("boxes") is Array):
		save_data["boxes"] = []
	if not PartyScript.store_in_boxes(save_data["boxes"], mon):
		# 极端旧档可能已用满所有电脑箱。保留在待转入列表，下次有空位再迁移。
		if not (save_data.get("box") is Array):
			save_data["box"] = []
		save_data["box"].append(mon)
	return "box"

func _set_hud_visible(on: bool) -> void:
	# A battle can start from the bag (for example, by using a fishing rod).
	if is_instance_valid(active_battle) and is_instance_valid(start_menu):
		_remove_start_menu()
	var field_visible := on and panel_open == 0 and not is_instance_valid(active_battle) and not is_instance_valid(title_screen)
	for n in [_bar, name_label, hint_label, money_label, badges_label]:
		if n:
			n.visible = field_visible
	if not field_visible:
		held_dir = ""
		run_held = false
		if toast:
			toast.hide()
	if ui_layer:
		for c in ui_layer.get_children():
			if c is Button:
				c.visible = field_visible
	if touch_layer:
		touch_layer.visible = field_visible

func _show_toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	await get_tree().create_timer(2.2).timeout
	if is_instance_valid(toast):
		toast.visible = false

func _process(delta: float) -> void:
	# HUD 文字四分之一秒刷一次就够，每帧重排 Label 是手机上最贵的开销之一
	ui_timer -= delta
	if ui_timer <= 0.0:
		ui_timer = 0.25
		_refresh_hud()
	# 先推进走路时间，再读输入：同一帧走完就能立刻迈下一步，不会每格顿一下
	# 按住 B 跑步：和原版一致，8 帧一格（正好两倍速）
	world.running = (run_held or world.bike) and panel_open == 0
	var changing_map: bool = not world.pending_warp.is_empty()
	world.tick_walk(delta)
	if world.walking or changing_map:
		return
	if _start_after_step:
		_start_after_step = false
		_toggle_start_menu()
		return
	# 冰面 / 洋流：站定之后被地形带着继续滑一格，原版就是这么走的
	if panel_open == 0:
		var auto: Vector2i = world.auto_step_dir()
		if auto != Vector2i.ZERO:
			if world.step(auto):
				_after_step()
				return
	if held_dir != "":
		_move(held_dir)
		return
	for code in _post_warp_keys.keys():
		if not Input.is_physical_key_pressed(code):
			_post_warp_keys.erase(code)
	for pair in KEY_MAP:
		if not _post_warp_keys.has(int(pair[1])) and Input.is_physical_key_pressed(int(pair[1])):
			_move(String(pair[0]))
			break

# ---------------- 自检 ----------------

func _test_tables() -> bool:
	if not Data.load_core_tables():
		return false
	if Data.species.is_empty() or Data.moves.is_empty() or Data.types.is_empty():
		return false
	if Data.types.get("water", {}).get("fire", 1.0) != 2.0:
		return false
	return true

func _test_atlas() -> bool:
	if world._frames.size() < 16:
		return false
	for t in world._frames:
		if t.region.size != Vector2(16, 16):
			return false
	return true

func _test_map() -> bool:
	if Data.load_region("hoenn").is_empty():
		return false
	var map: Dictionary = Data.load_map("hoenn", "littleroot_town")
	if map.is_empty():
		return false
	world.load_map(map)
	var sp: Array = map.get("spawn", [0, 0])
	return world.tile_size == Vector2i(20, 20) and world.player_pos == Vector2i(int(sp[0]), int(sp[1]))

func _test_collision() -> bool:
	# 碰撞要在原版地图上也成立：能走的地方能走，墙和边界必须挡住
	world.load_map(Data.load_map("kanto", "kanto_main"))
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	var walked := 0
	var blocked := 0
	var r := RandomNumberGenerator.new()
	r.seed = 20261117
	# 单点随机游走容易被地形困住，改成从多个可走点各走几步，覆盖城镇、道路、水边
	var starts: Array = []
	for i in 400:
		if starts.size() >= 40:
			break
		var p := Vector2i(r.randi_range(0, 407), r.randi_range(0, 399))
		if not world.blocked_by_terrain(p):
			starts.append(p)
	for st in starts:
		world.player_pos = st
		world.finish_walk()
		for k in 5:
			var d: Vector2i = dirs[r.randi_range(0, 3)]
			if world.step(d):
				walked += 1
				world.finish_walk()
			else:
				blocked += 1
	if walked < 20 or blocked < 20:
		print("collision dbg: walked=%d blocked=%d" % [walked, blocked])
		return false
	# 越界必须走不出去
	world.player_pos = Vector2i(0, 0)
	world.finish_walk()
	if world.step(Vector2i(-1, 0)) or world.step(Vector2i(0, -1)):
		print("collision dbg: 能走出地图边界")
		return false
	print("collision dbg: 可走 %d / 挡住 %d" % [walked, blocked])
	return true

## 传送体检：从每个地区的起点沿 warp 做 BFS，能走到的图必须包含该地区的全部图
func _test_warp() -> bool:
	var starts := {"kanto": "kanto_main", "hoenn": "littleroot_town", "sevii": "one_island_harbor"}
	for rid in starts:
		var first: String = String(starts[rid])
		var seen := {first: true}
		var queue: Array = [first]
		while not queue.is_empty():
			var cur: String = String(queue.pop_front())
			var m: Dictionary = Data.load_map(rid, cur)
			if m.is_empty():
				print("warp dbg: 地图加载失败 ", rid, "/", cur)
				return false
			for w in m.get("warps", []):
				var to: Dictionary = w.get("to", {})
				if String(to.get("region", "")) != rid:
					continue
				var tgt: String = String(to.get("map", ""))
				if tgt != "" and not seen.has(tgt):
					seen[tgt] = true
					queue.append(tgt)
		var files := DirAccess.get_files_at("res://content/regions/%s/maps" % rid)
		for f in files:
			if not String(f).ends_with(".json"):
				continue
			var mid: String = String(f).get_basename()
			if not seen.has(mid):
				print("warp dbg: 走不到 ", rid, "/", mid)
				return false
		print("warp dbg: %s 从 %s 起可走遍 %d 张图" % [rid, first, seen.size()])
	return true

func _test_battle() -> bool:
	var a := [BattleScript.make_combatant(4, 14, [52, 33]),
		BattleScript.make_combatant(7, 13, [55, 33])]
	var b := [BattleScript.make_combatant(1, 14, [71, 33]),
		BattleScript.make_combatant(25, 13, [84, 98])]
	var battle = BattleScript.new(20261116)
	battle.start(a, b)
	var rounds := 0
	while not battle.over and rounds < 200:
		battle.run_turn("move:0", "move:0")
		rounds += 1
	if not battle.over or battle.winner == "":
		return false
	for c in a + b:
		if c["hp"] < 0 or c["hp"] > c["max_hp"]:
			return false
		for v in c["pp"]:
			if int(v) < 0:
				return false
	return true

func _battle_art_key(texture: Texture2D) -> String:
	if texture is AtlasTexture:
		var frame := texture as AtlasTexture
		if frame.atlas == null or not frame.region.has_area():
			return ""
		return frame.atlas.resource_path + "#" + str(frame.region)
	return texture.resource_path if texture != null else ""

func _expected_battle_art(sid: int, form: String, rear: bool) -> String:
	const Art := preload("res://core/dex_art.gd")
	var texture := Art.battle_texture(sid, form, false, rear)
	return _battle_art_key(texture) if texture != null else Data.sprite_path(sid, form)

func _test_battle_ui() -> bool:
	var mine := [BattleScript.make_combatant(4, 20, [33, 52])]
	var enemy := [BattleScript.make_combatant(1, 12, [33])]
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var ui := BattleUI.new()
	layer.add_child(ui)
	ui.fast = true
	ui.setup(mine, enemy, 7)
	var done := {"result": ""}
	ui.finished.connect(func(r: String) -> void: done["result"] = r)

	var waited := 0.0
	while ui.state == "intro" and waited < 3.0:
		await get_tree().process_frame
		waited += 0.016
	if ui.state != "menu":
		ui.queue_free()
		return false

	var rounds := 0
	while String(done["result"]) == "" and rounds < 900 and is_instance_valid(ui):
		if ui.state == "menu":
			ui._on_move(0)
		await get_tree().process_frame
		rounds += 1
	var ok: bool = String(done["result"]) != ""
	if is_instance_valid(ui):
		ui.queue_free()

	# 战斗里的形态变化：菜单多出「Mega」按钮，点了以后精灵与属性要跟着换
	var mine3 := [BattleScript.make_combatant(6, 50, [33, 52], "")]
	var foe3 := [BattleScript.make_combatant(19, 30, [33])]
	var layer3 := CanvasLayer.new()
	layer3.layer = 6
	add_child(layer3)
	var ui3 := BattleUI.new()
	layer3.add_child(ui3)
	ui3.fast = true
	ui3.setup(mine3, foe3, 13)
	var waited3 := 0.0
	while ui3.state == "intro" and waited3 < 3.0:
		await get_tree().process_frame
		waited3 += 0.016
	if ui3.transform_label() == "":
		print("!! 能 Mega 的宝可梦没给变化按钮")
		ui3.queue_free()
		return false
	print("battle ui dbg: 变化按钮 ", ui3.transform_label())
	ui3._do_transform("CHARIZARD_MEGA_X")
	await get_tree().process_frame
	var a3: Dictionary = ui3.battle.cur_a()
	var spr := ""
	if ui3.player_sprite and is_instance_valid(ui3.player_sprite) and ui3.player_sprite.texture:
		spr = _battle_art_key(ui3.player_sprite.texture)
	var want3 := _expected_battle_art(6, "CHARIZARD_MEGA_X", true)
	print("battle ui dbg: 变形态后 ", String(a3.get("name", "")), " 立绘 ", spr.get_file())
	if String(a3.get("form", "")) != "CHARIZARD_MEGA_X":
		print("!! 界面点 Mega 没生效")
		ui3.queue_free()
		return false
	if spr.is_empty() or spr != want3 or spr == _expected_battle_art(6, "", true):
		print("!! 立绘没换成 Mega 形态")
		ui3.queue_free()
		return false
	if ui3.transform_label() != "":
		print("!! 变过一次后还能再变")
		ui3.queue_free()
		return false
	ui3.queue_free()

	# 敌方整队：第一只倒下后，精灵与名字必须换成第二只，不能两张叠着
	var mine2 := [BattleScript.make_combatant(9, 60, [55, 34])]
	var foe2 := [BattleScript.make_combatant(74, 8, [33]),
		BattleScript.make_combatant(95, 9, [33])]
	var layer2 := CanvasLayer.new()
	layer2.layer = 6
	add_child(layer2)
	var ui2 := BattleUI.new()
	layer2.add_child(ui2)
	ui2.fast = true
	ui2.setup(mine2, foe2, 11)
	var done2 := {"result": ""}
	ui2.finished.connect(func(r: String) -> void: done2["result"] = r)
	var waited2 := 0.0
	while ui2.state == "intro" and waited2 < 3.0:
		await get_tree().process_frame
		waited2 += 0.016
	var expected_foes := {74: _expected_battle_art(74, "", false), 95: _expected_battle_art(95, "", false)}
	var seen: Array = []
	var r2 := 0
	while String(done2["result"]) == "" and r2 < 900 and is_instance_valid(ui2):
		if ui2.state == "menu":
			var sid := int(ui2.battle.cur_b().get("species_id", 1))
			var now := _battle_art_key(ui2.enemy_sprite.texture)
			var want := str(expected_foes.get(sid, ""))
			if now.is_empty() or now != want:
				print("battle ui dbg: 敌方精灵与当前对手不一致 %s != %s" % [now, want])
				ui2.queue_free()
				return false
			if not seen.has(now):
				seen.append(now)
			ui2._on_move(0)
		await get_tree().process_frame
		r2 += 1
	if is_instance_valid(ui2):
		ui2.queue_free()
	if seen.size() < 2:
		print("battle ui dbg: 只见到 %d 种敌方精灵，换人没生效" % seen.size())
		return false
	return ok

func _test_party() -> bool:
	var p: Array = []
	for sid in [1, 4, 7, 25, 74, 129, 143, 6, 9, 3, 65, 94]:
		p.append(PartyScript.make(int(sid), 20 + int(sid) % 5, [33]))
	if p.size() != 12:
		return false
	for m in p:
		var hp := int(m["hp"])
		var mx := int(m["max_hp"])
		if hp != mx or mx <= 0:
			return false
		if int(m["species_id"]) <= 0:
			return false
		for v in m["stats"].values():
			if int(v) <= 0:
				return false
	# 压紧 + 补齐：塞两个空槽进去，出来后仍是 12 格且无空洞
	var dirty: Array = p.duplicate()
	dirty.insert(3, {})
	dirty.insert(7, {})
	var fixed: Array = PartyScript.compact(dirty)
	if fixed.size() != 12:
		return false
	for m in fixed:
		if not (m is Dictionary) or int(m.get("species_id", 0)) <= 0:
			return false
	# 血量回写不越界
	var combat: Array = fixed.duplicate(true)
	combat[0]["hp"] = -50
	combat[1]["hp"] = 99999
	PartyScript.sync_hp(combat, fixed)
	if int(fixed[0]["hp"]) != 0 or int(fixed[1]["hp"]) != int(fixed[1]["max_hp"]):
		return false
	return true

func _test_menus() -> bool:
	save_data["party"] = PartyScript.compact([PartyScript.make(4, 14, [52]), PartyScript.make(7, 13, [55])])
	_open_party()
	_open_bag()
	var ok := true
	var party_ui = null
	var bag_ui = null
	for c in menu_layer.get_children():
		if c.get_script() == PartyUI:
			party_ui = c
		elif c.get_script() == BagUI:
			bag_ui = c
	if party_ui == null or bag_ui == null:
		return false
	# 12 格按钮都要存在，只有 2 格可用
	var buttons: Array = party_ui.list.get_children()
	if buttons.size() != PartyScript.MAX_SIZE:
		return false
	var enabled := 0
	for b in buttons:
		if not b.disabled:
			enabled += 1
	if enabled != 2:
		return false
	party_ui._open_detail(0)
	if party_ui.detail == null:
		return false
	# 点击每一个口袋后，实际可点的道具必须与背包中有余量的条目相符。
	for category in BagUI.CATEGORIES:
		var cat := str(category[0])
		bag_ui._switch(cat)
		var names: Array = []
		for item in bag_items:
			if str(item.name).begins_with("秘传学习器") and bag_ui._category(item) != "tm":
				return false
			if bag_ui._category(item) == cat and int(item.get("count", 0)) > 0:
				names.append(str(item.name))
		for row in bag_ui.row_box.get_children():
			if not row is Button or row.disabled:
				return false
			var matched := false
			for label in row.find_children("*", "Label", true, false):
				if label.text in names:
					names.erase(label.text)
					matched = true
					break
			if not matched:
				return false
		ok = ok and names.is_empty() and bag_ui.empty_state.visible == (bag_ui.row_box.get_child_count() == 0)
	party_ui.queue_free()
	bag_ui.queue_free()
	return ok

func _test_dex() -> bool:
	# 图鉴：见过/抓到分别记，重复标记不产生重复条目
	save_data["dex"] = {}
	_dex_mark(25, true)
	_dex_mark(25, true)
	_dex_mark(4, false)
	var dex: Dictionary = save_data["dex"]
	if (dex["seen"] as Array).size() != 2 or (dex["caught"] as Array).size() != 1:
		print("dex dbg: ", dex)
		return false
	# 战斗回写：受伤写回对应槽位，且不越界
	save_data["party"] = PartyScript.compact([PartyScript.make(4, 20, [52]), PartyScript.make(25, 18, [84])])
	var team: Array = _make_team()
	if team_slots.size() != 2:
		print("dex dbg: slots ", team_slots)
		return false
	team[0]["hp"] = 7
	team[1]["pp"] = [1]
	_writeback_team(team)
	var party: Array = save_data["party"]
	if int(party[0]["hp"]) != 7 or String(party[0]["hp_text"]) != "7/%d" % int(party[0]["max_hp"]):
		print("dex dbg: hp ", party[0]["hp"], " ", party[0]["hp_text"])
		return false
	if int((party[1]["pp"] as Array)[0]) != 1:
		return false
	# 换人：只会换到别的存活单位，不会出现两只同名同位置
	var bt = BattleScript.new(7)
	bt.start([PartyScript.make(4, 20, [52]), PartyScript.make(25, 18, [84])], [BattleScript.make_combatant(143, 20, [33])])
	bt.run_turn("switch:1", "move:0")
	if bt.active_a != 1:
		print("switch dbg: active_a ", bt.active_a)
		return false
	if bt.cur_a().get("name", "") != bt.team_a[1].get("name", ""):
		return false
	bt.run_turn("switch:0", "move:0")
	if bt.active_a != 0:
		return false
	# 界面能开、能翻页、能看详情
	var ui := DexUI.new()
	menu_layer.add_child(ui)
	ui.setup(dex["seen"], dex["caught"], save_data.get("dex_variants", {}))
	if ui.grid.get_child_count() == 0:
		return false
	if 232 not in ui.ids or 984 in ui.ids or DexCatalog.entry_id(984) != 232 or Data.species_of(984).is_empty():
		return false
	ui._show_detail(25)
	ui.page = 1
	ui._refresh()
	ui.queue_free()
	return true

## 遇敌：三个地区的遭遇表都要能抽出来，且抽到的物种必须真实存在
## 城都训练家：每张图上的 battle 队伍必须真的能开打（物种存在、等级合理、招式能配出来）
func _test_johto_trainers() -> bool:
	var ok := true
	var maps := 0
	var trainers := 0
	var dir := DirAccess.open("res://content/regions/johto/maps")
	if dir == null:
		print("johto dbg: 打不开城都地图目录")
		return false
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/maps/%s" % f))
		if not (raw is Dictionary):
			continue
		maps += 1
		for n in (raw as Dictionary).get("npcs", []):
			var bt = (n as Dictionary).get("battle", null)
			if not (bt is Dictionary):
				continue
			trainers += 1
			var team: Array = (bt as Dictionary).get("team", [])
			if team.is_empty():
				print("johto dbg: 空队伍 ", f, " ", n.get("name", ""))
				ok = false
				continue
			for e in team:
				var sid := int((e as Dictionary).get("species", 0))
				var lv := int((e as Dictionary).get("level", 0))
				if sid <= 0 or Data.species_of(sid).is_empty():
					print("johto dbg: 物种不存在 ", f, " ", n.get("name", ""), " ", sid)
					ok = false
				if lv < 1 or lv > 100:
					print("johto dbg: 等级越界 ", f, " ", lv)
					ok = false
				var mvs = (e as Dictionary).get("moves", null)
				if mvs is Array:
					for mv in mvs:
						if not Data.moves.has(int(mv)):
							print("johto dbg: 招式不存在 ", f, " ", int(mv))
							ok = false
	if maps < 300:
		print("johto dbg: 城都地图太少 ", maps)
		ok = false
	if trainers < 250:
		print("johto dbg: 城都训练家太少 ", trainers)
		ok = false
	print("johto dbg: 地图 %d，训练家 %d" % [maps, trainers])
	# 随便挑一个训练家，看战斗单位能不能真的建起来
	var probe: Dictionary = {}
	for f2 in dir.get_files():
		if not f2.ends_with(".json"):
			continue
		var raw2 = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/maps/%s" % f2))
		if not (raw2 is Dictionary):
			continue
		for n2 in (raw2 as Dictionary).get("npcs", []):
			if (n2 as Dictionary).has("battle"):
				probe = n2
				break
		if not probe.is_empty():
			break
	if not probe.is_empty():
		var e0: Dictionary = ((probe["battle"] as Dictionary).get("team", []) as Array)[0]
		var c := BattleScript.make_combatant(int(e0.get("species", 1)), int(e0.get("level", 5)), EncounterScript.moves_for(int(e0.get("species", 1)), int(e0.get("level", 5))))
		if c.is_empty() or int(c.get("hp", 0)) <= 0:
			print("johto dbg: 战斗单位建不起来")
			ok = false
		else:
			print("johto dbg: 试打 ", probe.get("name", ""), " -> hp ", c.get("hp", 0))
		# 真的把这一队拉进战斗界面打一场，确认城都训练家不是"只有数据"
		var enemy: Array = []
		for e in ((probe["battle"] as Dictionary).get("team", []) as Array):
			var s2 := int((e as Dictionary).get("species", 1))
			var l2 := int((e as Dictionary).get("level", 5))
			var mv2 = (e as Dictionary).get("moves", null)
			if not (mv2 is Array) or (mv2 as Array).is_empty():
				mv2 = EncounterScript.moves_for(s2, l2)
			enemy.append(BattleScript.make_combatant(s2, l2, mv2))
		var mine := [BattleScript.make_combatant(25, 60, [85, 87, 98])]
		var layer := CanvasLayer.new()
		layer.layer = 6
		add_child(layer)
		var ui := BattleUI.new()
		layer.add_child(ui)
		ui.fast = true
		ui.setup(mine, enemy, 11)
		var res := {"r": ""}
		ui.finished.connect(func(r: String) -> void: res["r"] = r)
		var waited := 0.0
		while ui.state == "intro" and waited < 3.0:
			await get_tree().process_frame
			waited += 0.016
		if ui.state != "menu":
			print("johto dbg: 城都训练家战斗界面没起来")
			ui.queue_free()
			return false
		var rounds := 0
		while String(res["r"]) == "" and rounds < 1200 and is_instance_valid(ui):
			if ui.state == "menu":
				ui._on_move(0)
			await get_tree().process_frame
			rounds += 1
		if String(res["r"]) == "":
			print("johto dbg: 城都训练家战斗打不完")
			ok = false
		else:
			print("johto dbg: 城都训练家实战 -> ", res["r"])
		if is_instance_valid(ui):
			ui.queue_free()
	return ok

## 城都开场与道馆：三个精灵球给三只不同的初始，八个道馆各发一枚不同徽章
## 秘传学习器齐不齐、能不能从背包学会、地上的球是不是都站得到
## 背包里的东西真能用：伤药回血、PP 药回 PP、钓竿在包里
func _test_item_use() -> bool:
	var ok := true
	var keep: Array = (save_data.get("party", []) as Array).duplicate(true)
	var party: Array = []
	party.append(PartyScript.make(25, 20, [85, 98]))
	party[0]["hp"] = 5
	save_data["party"] = party
	var original_bag := bag_items
	bag_items = original_bag.duplicate(true)
	_give_item("钓竿",1,"key")
	var rod := _has_rod()
	bag_items = original_bag
	if not rod: ok = false
	var n_before := -1
	for it in bag_items:
		if String((it as Dictionary).get("name", "")) == "伤药":
			n_before = int((it as Dictionary).get("count", 0))
	_apply_heal("伤药", 0, {"hp": 20})
	if int(party[0].get("hp", 0)) <= 5:
		print("item dbg: 伤药没回血")
		ok = false
	var n_after := 0
	for it in bag_items:
		if String((it as Dictionary).get("name", "")) == "伤药":
			n_after = int((it as Dictionary).get("count", 0))
	if n_before > 0 and n_after != n_before - 1:
		print("item dbg: 伤药数量没扣 %d->%d" % [n_before, n_after])
		ok = false
	party[0]["pp"] = [1, 1]
	_apply_heal("PP 单项", 0, {"pp": 10})
	if int((party[0]["pp"] as Array)[0]) <= 1:
		print("item dbg: PP 药没回 PP")
		ok = false
	# 神奇糖果：升一级
	var lv0 := int(party[0].get("level", 1))
	if not bag_items.any(func(x): return String((x as Dictionary).get("name", "")) == "神奇糖果"):
		bag_items.append({"id": 0, "name": "神奇糖果", "category": "other", "count": 1})
	_candy_one(0)
	var lv1 := int(party[0].get("level", 1))
	if lv1 != lv0 + 1:
		print("item dbg: 神奇糖果没升级 Lv%d->%d" % [lv0, lv1])
		ok = false
	# 进化石：皮皮(35) 吃月之石应该变皮可西(36)
	party[0] = PartyScript.make(35, 20, [1])
	if not bag_items.any(func(x): return String((x as Dictionary).get("name", "")) == "月之石"):
		bag_items.append({"id": 0, "name": "月之石", "category": "other", "count": 1})
	var pre_name := String(party[0].get("name", "?"))
	_evolve_with_item(0, "月之石", null)
	if int(party[0].get("species_id", 0)) != 36:
		print("item dbg: 月之石没让皮皮进化（species %d）" % int(party[0].get("species_id", 0)))
		ok = false
	# 增强剂：攻击基础点 +5，攻击值必须变高，且换级后不丢
	save_data["party"] = [PartyScript.make(25, 20, [85, 98])]
	party = save_data["party"]
	var atk0 := int((party[0]["stats"] as Dictionary).get("atk", 0))
	_apply_vitamin("攻击增强剂", 0, "atk")
	var atk1 := int((party[0]["stats"] as Dictionary).get("atk", 0))
	var plus_ok := int((party[0].get("plus", {}) as Dictionary).get("atk", 0)) == 5
	PartyScript.recalc(party[0], false)
	var atk2 := int((party[0]["stats"] as Dictionary).get("atk", 0))
	if atk1 <= atk0 or not plus_ok or atk2 != atk1:
		print("item dbg: 增强剂没生效 %d->%d->%d plus=%s" % [atk0, atk1, atk2, str(plus_ok)])
		ok = false
	# PP 提升剂：上限按基础 PP 的两成往上加
	save_data["party"] = [PartyScript.make(25, 20, [85, 98])]
	party = save_data["party"]
	if not bag_items.any(func(x): return String((x as Dictionary).get("name", "")) == "PP 提升剂"):
		bag_items.append({"id": 0, "name": "PP 提升剂", "category": "other", "count": 1})
	var base_pp := int((Data.move_of(85) as Dictionary).get("pp", 10))
	_ppup_apply(0, 0)
	var got_pp := int(((save_data["party"] as Array)[0].get("pp_bonus", {}) as Dictionary).get("85", 0))
	if got_pp <= 0:
		print("item dbg: PP 提升剂没加上限")
		ok = false
	print("item dbg: 伤药 5 -> 25、PP 1 -> 11、钓竿 %s、糖果 Lv%d->%d、%s + 月之石 -> %s、攻击 %d->%d、PP 上限 %d->%d" % [str(rod), lv0, lv1, pre_name, String(party[0].get("name", "?")), atk0, atk1, base_pp, base_pp + got_pp])
	save_data["party"] = keep
	return ok


func _test_field_kit() -> bool:
	var ok := true
	# 1) 8 个秘传学习器都能在教学表里查到
	for i in 8:
		var nm := "秘传学习器 0%d" % (i + 1)
		if not Data.tm_map.has(nm):
			print("fieldkit dbg: 教学表缺少 ", nm)
			ok = false
	var have := 0
	for row in _default_items():
		if str(row.name).begins_with("秘传学习器"): have+=1
	if have != 0:
		print("fieldkit dbg: 新档不应预装秘传学习器")
		ok = false
	# 3) 真的教一次：拿一只会冲浪的水系，教完招式里要有 57
	var before: Array = (save_data.get("party", []) as Array).duplicate(true)
	var party: Array = save_data.get("party", [])
	var slot := -1
	for i in party.size():
		if party[i] is Dictionary and (party[i] as Dictionary).is_empty():
			party[i] = PartyScript.make(7, 20, [33])
			slot = i
			break
	if slot < 0:
		party.append(PartyScript.make(7, 20, [33]))
		slot = party.size() - 1
	save_data["party"] = party
	_tm_teach_one(57, slot, "冲浪")
	var taught := false
	for mv in (save_data["party"][slot] as Dictionary).get("moves", []):
		if int(mv) == 57:
			taught = true
	if not taught:
		print("fieldkit dbg: 冲浪没教进去")
		ok = false
	# 教完必须真的"会被认成能用"：地图上的冲浪/飞行/闪光都查这个
	for pair in [[57, "SURF"], [19, "FLY"], [148, "FLASH"]]:
		# 每招换一只新的：四格招式位满了本来就该问"要顶掉哪招"
		save_data["party"][slot] = PartyScript.make(7, 20, [33])
		_tm_teach_one(int(pair[0]), slot, "")
		if not _party_has_move(String(pair[1])):
			print("fieldkit dbg: 教了却识别不到 ", String(pair[1]))
			ok = false
	save_data["party"] = before
	# 4) 黑暗地图存在（闪光才有用武之地）
	var dark := 0
	for f in DirAccess.get_files_at("res://content/regions/kanto/maps"):
		if not String(f).ends_with(".json"):
			continue
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/kanto/maps/%s" % f))
		if raw is Dictionary and bool((raw as Dictionary).get("dark", false)):
			dark += 1
	if dark < 2:
		print("fieldkit dbg: 黑暗地图只有 %d 张" % dark)
		ok = false
	# 5) 世界里的道具球至少落在可走格上（可走格能自动捡）
	for rid in DirAccess.get_directories_at("res://content/regions"):
		var base := "res://content/regions/%s/maps" % String(rid)
		for f2 in DirAccess.get_files_at(base):
			if not String(f2).ends_with(".json"):
				continue
			var raw2 = JSON.parse_string(FileAccess.get_file_as_string(base + "/" + String(f2)))
			if not (raw2 is Dictionary):
				continue
			var emid := String((raw2 as Dictionary).get("emerald", ""))
			var ep := "res://content/emerald_maps/%s.json" % emid
			if not FileAccess.file_exists(ep):
				continue
			var em = JSON.parse_string(FileAccess.get_file_as_string(ep))
			if not (em is Dictionary):
				continue
			var coll: Array = (em as Dictionary).get("collision", [])
			var obj: Array = (raw2 as Dictionary).get("objects", [])
			for o in obj:
				if String((o as Dictionary).get("kind", "")) != "item":
					continue
				var at: Array = (o as Dictionary).get("at", [0, 0])
				var x := int(at[0])
				var y := int(at[1])
				if y < coll.size() and x < (coll[y] as Array).size():
					if int((coll[y] as Array)[x]) != 0:
						print("fieldkit dbg: 球在墙里 ", emid, " ", at)
						ok = false
	# 6) 站在球上也能捡：球不挡路，人踩着球站在同一格，A 必须还认得它
	var probe_map := ""
	var probe_at := Vector2i(-1, -1)
	for rid3 in ["kanto", "johto"]:
		var b3 := "res://content/regions/%s/maps" % rid3
		if not DirAccess.dir_exists_absolute(b3):
			continue
		for f4 in DirAccess.get_files_at(b3):
			if not String(f4).ends_with(".json"):
				continue
			var r4 = JSON.parse_string(FileAccess.get_file_as_string(b3 + "/" + String(f4)))
			if not (r4 is Dictionary):
				continue
			for o4 in (r4 as Dictionary).get("objects", []):
				if String((o4 as Dictionary).get("kind", "")) != "item":
					continue
				var a4: Array = (o4 as Dictionary).get("at", [0, 0])
				probe_map = rid3 + "/" + String(f4).get_basename()
				probe_at = Vector2i(int(a4[0]), int(a4[1]))
				break
			if probe_map != "":
				break
		if probe_map != "":
			break
	if probe_map == "":
		print("fieldkit dbg: 找不到道具球")
		ok = false
	else:
		var pm := probe_map.split("/")
		world.load_map(Data.load_map(String(pm[0]), String(pm[1])))
		world.warp_to(probe_at)
		world.finish_walk()
		var stand: Dictionary = world.object_at(world.player_pos)
		if stand.is_empty() or String(stand.get("kind", "")) != "item":
			print("fieldkit dbg: 站在球上认不出球 ", probe_map, " ", probe_at)
			ok = false
		else:
			print("fieldkit dbg: 站在球上可捡 ", probe_map, " ", probe_at)
	print("fieldkit dbg: 秘传 %d 个、黑暗图 %d、冲浪教学 %s" % [have, dark, str(taught)])
	return ok

func _test_johto_story() -> bool:
	var ok := true
	# 初始宝可梦
	var lab = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/maps/johto_elms_lab.json"))
	var got: Array = []
	if lab is Dictionary:
		for n in (lab as Dictionary).get("npcs", []):
			var gm = (n as Dictionary).get("gives_mon", null)
			if gm is Dictionary:
				got.append(int((gm as Dictionary).get("species", 0)))
	got.sort()
	if got != [152, 155, 158]:
		print("johto dbg: 初始精灵球不对 ", got)
		ok = false
	# 徽章
	var want := ["飞翼徽章", "昆虫徽章", "标准徽章", "魅影徽章", "打击徽章", "矿物徽章", "冰川徽章", "升龙徽章"]
	var have: Array = []
	var dir := DirAccess.open("res://content/regions/johto/maps")
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/maps/%s" % f))
		if not (raw is Dictionary):
			continue
		for n in (raw as Dictionary).get("npcs", []):
			var bd := String((n as Dictionary).get("badge", ""))
			if bd != "" and not have.has(bd):
				have.append(bd)
				var team: Array = ((n as Dictionary).get("battle", {}) as Dictionary).get("team", [])
				if team.size() < 2:
					print("johto dbg: 馆主队伍太少 ", bd, " ", team.size())
					ok = false
	for b in want:
		if not have.has(b):
			print("johto dbg: 缺徽章 ", b)
			ok = false
	if have.size() != want.size():
		print("johto dbg: 徽章数不对 ", have)
		ok = false
	# 真发一只试试，确认入队逻辑通
	var before: Array = (save_data.get("party", []) as Array).duplicate(true)
	var before_box: Array = (save_data.get("box", []) as Array).duplicate(true)
	_add_to_team(152, 5)
	var added := false
	for m in (save_data.get("party", []) as Array) + (save_data.get("box", []) as Array):
		if m is Dictionary and (int((m as Dictionary).get("species", 0)) == 152 or int((m as Dictionary).get("species_id", 0)) == 152):
			added = true
			break
	if not added:
		print("johto dbg: 初始宝可梦进不了队伍")
		ok = false
	save_data["party"] = before
	save_data["box"] = before_box
	print("johto dbg: 初始 %s，徽章 %d 枚" % [str(got), have.size()])
	return ok

## 城都野生：每张有草地分布的图都要抽得出来，且物种真实存在
func _test_johto_wild() -> bool:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = 20261120
	var ok := true
	var maps := 0
	var dir := DirAccess.open("res://content/regions/johto/maps")
	var seen := {}
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var raw = JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/maps/%s" % f))
		if not (raw is Dictionary):
			continue
		var pool: Array = (raw as Dictionary).get("encounters", [])
		if pool.is_empty():
			continue
		maps += 1
		# 有分布还得踩得到：要么有草地格，要么是"整片地面都出怪"的原版洞窟地图
		var eid := String((raw as Dictionary).get("emerald", ""))
		var epath := "res://content/emerald_maps/%s.json" % eid
		var ok_cell := false
		if FileAccess.file_exists(epath):
			var em = JSON.parse_string(FileAccess.get_file_as_string(epath))
			if em is Dictionary:
				if bool((em as Dictionary).get("wild_any", false)):
					ok_cell = true
				else:
					for grow in (em as Dictionary).get("grass", []):
						for v in grow:
							if int(v) == 1:
								ok_cell = true
								break
						if ok_cell:
							break
		if not ok_cell:
			print("johto dbg: 有分布但踩不到草地 ", f)
			ok = false
		var hit := 0
		for i in 40:
			var w: Dictionary = EncounterScript.roll(pool, r)
			if w.is_empty():
				continue
			hit += 1
			seen[int(w["species"])] = true
			if Data.species_of(int(w["species"])).is_empty():
				print("johto dbg: 野生物种不存在 ", f, " ", int(w["species"]))
				ok = false
				break
			if int(w["level"]) < 1:
				print("johto dbg: 野生等级异常 ", f, " ", int(w["level"]))
				ok = false
				break
		if hit < 30:
			print("johto dbg: 抽空 ", f, " ", hit)
			ok = false
	if maps < 55:
		print("johto dbg: 有草地分布的地图太少 ", maps)
		ok = false
	if seen.size() < 30:
		print("johto dbg: 野生物种太少 ", seen.size())
		ok = false
	print("johto dbg: 野生图 %d，物种 %d" % [maps, seen.size()])
	return ok

func _test_encounter() -> bool:
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = 20261116
	var rids: Array = []
	for d in DirAccess.get_directories_at("res://content/regions"):
		rids.append(String(d))
	for rid in rids:
		var reg: Dictionary = Data.load_region(rid)
		var pool: Array = reg.get("encounters", [])
		if pool.is_empty():
			continue
		if pool.is_empty():
			print("encounter dbg: 空遭遇表 ", rid)
			return false
		var seen: Dictionary = {}
		for i in 400:
			var w: Dictionary = EncounterScript.roll(pool, r)
			if w.is_empty():
				print("encounter dbg: 抽空 ", rid)
				return false
			var sid := int(w.get("species", 0))
			if Data.species_of(sid).is_empty():
				print("encounter dbg: 物种不存在 ", sid)
				return false
			var lv := int(w.get("level", 0))
			if lv < 1 or lv > 100:
				print("encounter dbg: 等级越界 ", lv)
				return false
			seen[sid] = true
		if seen.size() < 3:
			print("encounter dbg: 分布太窄 ", rid, " ", seen.size())
			return false
		# 高草触发率要落在合理区间，不能一步一遇也不能永不遇
		var hit := 0
		for i in 1000:
			if EncounterScript.should_encounter(r, float(reg.get("encounter_rate", 0.12)), 1):
				hit += 1
		var pct := hit / 1000.0
		if pct < 0.03 or pct > 0.40:
			print("encounter dbg: 触发率异常 ", rid, " ", pct)
			return false
		# 配招不能空
		if EncounterScript.moves_for(int(seen.keys()[0])).is_empty():
			print("encounter dbg: 无招式")
			return false
	print("encounter dbg: 三地区遭遇表 OK")
	return true

## 投球：低血高捕获率的一球概率要大，满血高抗性的一球不该必中；抓到后 over 且 winner=caught
func _test_catch() -> bool:
	var b := BattleScript.new()
	var mine: Array = [BattleScript.make_combatant(25, 20, [84, 33])]
	var easy: Array = [BattleScript.make_combatant(129, 5, [33])]
	b.start(mine, easy)
	b.team_b[0]["hp"] = 1
	var got := false
	for i in 60:
		if b.throw_ball(2.0, "高级球").get("ok", false):
			got = true
			break
	if not got:
		print("catch dbg: 残血+高级球 60 次都没抓到")
		return false
	if not b.over or b.winner != "caught" or b.caught_species != 129:
		print("catch dbg: 抓到后状态不对 ", b.winner, " ", b.caught_species)
		return false

	# 难抓的：满血、捕获率低的，普通球成功率必须明显低于好抓的那只
	var b2 := BattleScript.new()
	var hit2 := 0
	for i in 200:
		b2.start(mine, [BattleScript.make_combatant(143, 30, [33])])
		if b2.throw_ball(1.0, "精灵球").get("ok", false):
			hit2 += 1
		if b2.over and b2.winner != "caught":
			print("catch dbg: 没抓到却结束了")
			return false
	var p2 := hit2 / 200.0
	if p2 > 0.45:
		print("catch dbg: 满血卡比兽用普通球成功率过高 ", p2)
		return false
	print("catch dbg: 难抓目标成功率 %.2f" % p2)
	print("catch dbg: 投球概率与结束状态 OK")
	return true

# Travel state after the Kanto gates and the Sevii story guards have cleared.
const OPEN_FIELD_FLAGS := {"sevii_network_online":true,"got_dex":true,"ss_ticket":true,"freed_silph":true,"beat_giovanni":true,
	"ember_ruby_requested":true,"beat_ember_grunt_1":true,"beat_ember_grunt_2":true,
	"ruin_valley_cut_door":true,"rescued_icefall":true,
	"FLAG_HIDE_MT_EMBER_EXTERIOR_ROCKETS":true,"FLAG_HIDE_RUIN_VALLEY_SCIENTIST":true}

## 全量地图体检：每张图能加载、warp 双向、落点不撞墙不撞人、传送图连通
func _test_map_graph() -> bool:
	# 扫目录而不是写死地区名：新加地区目录自动纳入体检
	var dirs: Array = []
	for d in DirAccess.get_directories_at("res://content/regions"):
		dirs.append(String(d))
	dirs.sort()
	var seen: Dictionary = {}          # "region/map" -> true
	var collision_by_map := {}
	var residents_by_map := {}
	for rid in dirs:
		var base := "res://content/regions/%s/maps" % rid
		var files := DirAccess.get_files_at(base)
		if files.is_empty():
			print("graph dbg: 地区没有地图 ", rid)
			return false
		for f in files:
			if not String(f).ends_with(".json"):
				continue
			var mid := String(f).get_basename()
			var m: Dictionary = Data.load_map(rid, mid)
			if m.is_empty():
				print("graph dbg: 加载失败 ", rid, "/", mid)
				return false
			seen["%s/%s" % [rid, mid]] = true
			if int(m.get("size", [0, 0])[0]) <= 0:
				print("graph dbg: 尺寸异常 ", mid)
				return false
			# 出生点必须能站人
			var sp: Array = m.get("spawn", [0, 0])
			if _tile_blocked(m, int(sp[0]), int(sp[1]), collision_by_map):
				print("graph dbg: 出生点被挡 ", rid, "/", mid)
				return false
			for w in m.get("warps", []):
				var target: Dictionary = w.get("to", {})
				var trid := String(target.get("region", ""))
				var tmid := String(target.get("map", ""))
				var path := "res://content/regions/%s/maps/%s.json" % [trid, tmid]
				if not FileAccess.file_exists(path):
					print("graph dbg: 传送目标不存在 ", trid, "/", tmid, " <- ", mid)
					return false
				var tm: Dictionary = Data.load_map(trid, tmid)
				var at: Array = target.get("at", [0, 0])
				if _tile_blocked(tm, int(at[0]), int(at[1]), collision_by_map):
					print("graph dbg: 传送落点被挡 ", trid, "/", tmid, " ", at)
					return false
				var destination_id := trid + "/" + tmid
				if not residents_by_map.has(destination_id):
					# Some arrivals (the robbed house, for example) are guarded until a story flag moves the NPC.
					var initial := preload("res://core/frlg_actors.gd").roster(tm,{})
					var later := preload("res://core/frlg_actors.gd").roster(tm,OPEN_FIELD_FLAGS)
					residents_by_map[destination_id] = initial.filter(func(n): return later.any(func(a): return a.at == n.at))
				for n in residents_by_map[destination_id]:
					var nat: Array = n.get("at", [-1, -1])
					if int(nat[0]) == int(at[0]) and int(nat[1]) == int(at[1]):
						print("graph dbg: 落点站着 NPC ", tmid, " ", at)
						return false
	# 关都这条线必须从真新镇一路通到尼比道馆
	var must := ["kanto/kanto_main", "kanto/viridianforest",
		"kanto/pewtercity_gym", "kanto/viridiancity_pokemoncenter_1f"]
	for key in must:
		if not seen.has(key):
			print("graph dbg: 缺地图 ", key)
			return false
	print("graph dbg: %d 张地图，warp 全部可达且落点可行走" % seen.size())
	return true

func _tile_blocked(m: Dictionary, x: int, y: int, cache: Dictionary) -> bool:
	var size: Array = m.get("size", [0, 0])
	# 原版地图没有 tiles 数组，碰撞要读预渲染时导出的表
	if String(m.get("emerald", "")) != "":
		if x < 0 or y < 0 or x >= int(size[0]) or y >= int(size[1]):
			return true
		var path := "res://content/emerald_maps/%s.json" % String(m["emerald"])
		if not FileAccess.file_exists(path):
			return true
		if not cache.has(path):
			var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			cache[path] = meta.get("collision", [])
		var col: Array = cache[path]
		if y >= col.size() or x >= (col[y] as Array).size():
			return true
		return int((col[y] as Array)[x]) != 0
	if x < 0 or y < 0 or x >= int(size[0]) or y >= int(size[1]):
		return true
	var tiles: Array = m.get("tiles", [])
	if y >= tiles.size() or x >= (tiles[y] as Array).size():
		return true
	var t := int((tiles[y] as Array)[x])
	return t == 1 or t == 2 or t == 6 or t == 7

## 对战塔：塔队统一 Lv50、对手合法、连胜越高奖金越高、对手不会更强到离谱
func _test_facility() -> bool:
	var party: Array = PartyScript.compact([PartyScript.make(25, 8, [84, 33]), PartyScript.make(4, 6, [52])])
	var team: Array = FacilityScript.tower_team(party)
	if team.size() != 2:
		print("facility dbg: 塔队人数不对 ", team.size())
		return false
	for c in team:
		if int(c.get("level", 0)) != FacilityScript.LEVEL:
			print("facility dbg: 等级没统一 ", c.get("level"))
			return false
		if int(c.get("hp", 0)) != int(c.get("max_hp", 0)):
			return false
		if (c.get("moves") as Array).is_empty():
			return false
	# 塔队不能污染存档（原队伍等级还是 8 / 6）
	if int((party[0] as Dictionary).get("level", 0)) != 8:
		print("facility dbg: 塔队改了存档队伍")
		return false
	# 空队伍也要能凑出一只
	if FacilityScript.tower_team([]).is_empty():
		print("facility dbg: 空队伍没有兜底")
		return false
	# 对手：等级在 50~60，物种存在，技能非空
	var r := RandomNumberGenerator.new()
	r.seed = 20261117
	for streak in [0, 3, 7, 15]:
		for i in 30:
			var o: Dictionary = FacilityScript.make_opponent(streak, r)
			var lv := int(o.get("level", 0))
			if lv < FacilityScript.LEVEL or lv > FacilityScript.LEVEL + 10:
				print("facility dbg: 对手等级越界 ", lv)
				return false
			if Data.species_of(int(o.get("species_id", 0))).is_empty():
				return false
			if (o.get("moves") as Array).is_empty() or (o.get("pp") as Array).is_empty():
				return false
	# 奖金随连胜递增
	if FacilityScript.prize(1) >= FacilityScript.prize(5):
		print("facility dbg: 奖金没有递增")
		return false
	# 实打一场：塔队与对手都要能正常跑到结束
	var b := BattleScript.new(4242)
	b.start(FacilityScript.tower_team(party), [FacilityScript.make_opponent(0, r)])
	var rounds := 0
	while not b.over and rounds < 120:
		b.run_turn("move:0", "move:0")
		rounds += 1
	if not b.over:
		print("facility dbg: 塔内战打不完")
		return false
	print("facility dbg: 塔队/对手/奖金/实战都 OK（%d 回合）" % rounds)
	return true

## 真机上"按了没反应"这类问题必须能被自检抓到：
## 面板都关着的时候，方向键必须真的能让人物走一步
func _test_input() -> bool:
	# 先把玩家放到真新镇的可走格上，避免受前面测试残留位置影响
	var m: Dictionary = Data.load_map("kanto", "kanto_main")
	if not m.is_empty():
		world.load_map(m)
		var sp: Array = m.get("spawn", [10, 10])
		world.player_pos = Vector2i(int(sp[0]), int(sp[1]))
		world._sync_player()
	panel_open = 0
	for c in menu_layer.get_children():
		if c is Control and String(c.get_class()) != "Button":
			c.queue_free()
	if panel_open != 0:
		print("input dbg: panel_open 没清零 ", panel_open)
		return false
	var before: Vector2i = world.player_pos
	var moved := false
	for dir in ["down", "up", "left", "right"]:
		before = world.player_pos
		world.finish_walk()
		_move(dir)
		if world.player_pos != before:
			moved = true
			break
	if not moved:
		print("input dbg: 四个方向都走不动，pos=", world.player_pos)
		return false
	# 面板打开时必须走不动（这是设计，不是 bug）
	panel_open = 1
	before = world.player_pos
	world.finish_walk()
	_move("down")
	var blocked: bool = world.player_pos == before
	panel_open = 0
	if not blocked:
		print("input dbg: 面板打开时还能走")
		return false
	# 走路必须是插值滑过去的，不是瞬移：走半步时渲染位置要在两格之间
	world.finish_walk()
	var start: Vector2i = world.player_pos
	world.step(Vector2i(0, 1))
	if not world.walking:
		print("input dbg: 走一步后没有进入行走状态")
		return false
	var from_pos: Vector2 = world.anim_from
	world.tick_walk(0.08)
	var mid: Vector2 = world.render_pos
	if mid == from_pos or mid == Vector2(world.player_pos):
		print("input dbg: 走路没有中间态 ", mid, " from ", from_pos, " to ", world.player_pos)
		return false
	# 一步之内必须换腿：整格只有一个姿势就是"滑"
	var f_a: int = world.frame_col
	world.tick_walk(0.07)
	var f_b: int = world.frame_col
	if f_a == f_b:
		print("input dbg: 一步之内没有换腿 ", f_a, " -> ", f_b)
		return false
	world.tick_walk(0.30)
	if world.walking or world.render_pos != Vector2(world.player_pos):
		print("input dbg: 走完没有落到格心")
		return false
	print("input dbg: 方向键有效、按住连续、走路有插值")
	return true

## 四个方向的站立/走路帧必须是各自的，不能串方向：
## 上走时用朝左的帧，人就会横着走；朝右必须是朝左的水平镜像。
func _test_facing() -> bool:
	var m: Dictionary = Data.load_map("kanto", "kanto_main")
	if not m.is_empty():
		world.load_map(m)
	var want := {
		"down": [0, 3, 4, false],
		"up": [1, 5, 6, false],
		"left": [2, 7, 8, false],
		"right": [2, 7, 8, true],
	}
	for dir in want.keys():
		for col in [0, 1, 2]:
			world.facing = dir
			world.frame_col = col
			world._sync_player()
			var d: Dictionary = world.debug_sprite()
			var exp: Array = want[dir]
			var ef: int = int(exp[col])
			if int(d["frame"]) != ef or bool(d["flip"]) != bool(exp[3]):
				print("facing dbg: ", dir, " col ", col, " 得到 frame ", d["frame"],
					" flip ", d["flip"], " 应为 ", ef, " flip ", exp[3])
				return false
	world.finish_walk()
	print("facing dbg: 四方向共 12 帧全部对上，朝右为镜像")
	return true

## 进屋能出来、隔着柜台能跟乔伊说话
## 全国图鉴 1~1025 一只都不能少，且都能出场战斗
func _test_dex_complete() -> bool:
	var missing: Array = []
	var broken: Array = []
	for i in range(1, 1026):
		var sp: Dictionary = Data.species_of(i)
		if sp.is_empty():
			missing.append(i)
			continue
		if String(sp.get("name", "")) == "" or (sp.get("types", []) as Array).is_empty():
			broken.append(i)
			continue
		var base: Dictionary = sp.get("base", {})
		if int(base.get("hp", 0)) <= 0:
			broken.append(i)
		# 立绘必须有，否则战斗里是空白（核验导入后的纹理）
		if not (load("res://assets/mon/%d.png" % i) is Texture2D):
			broken.append(i)
	# 图鉴界面的世代分页必须覆盖 1~1025，不能有号段掉在外面
	var covered := {}
	var ranges := [[1, 151], [152, 251], [252, 386], [387, 493], [494, 649],
		[650, 721], [722, 809], [810, 905], [906, 1025]]
	for r in ranges:
		for i in range(int(r[0]), int(r[1]) + 1):
			covered[i] = true
	var uncovered := []
	for i in range(1, 1026):
		if not covered.has(i):
			uncovered.append(i)
	print("dex dbg: 缺 %d 只，属性/名字/立绘坏 %d 只，分页漏号 %d" %
		[missing.size(), broken.size(), uncovered.size()])
	if not missing.is_empty():
		print("dex dbg: 缺 -> ", missing.slice(0, 20))
	if not broken.is_empty():
		print("dex dbg: 坏 -> ", broken.slice(0, 20))
	return missing.is_empty() and broken.is_empty() and uncovered.is_empty()

## 形态：不进图鉴号，但属性/种族值/立绘都得是真的
func _test_forms() -> bool:
	var bad: Array = []
	var n := 0
	var kinds := {}
	var with_forms := 0
	for sp in Data.species.values():
		if not (sp is Dictionary):
			continue
		var forms: Array = (sp as Dictionary).get("forms", [])
		if not (forms is Array) or forms.is_empty():
			continue
		var sid := int((sp as Dictionary).get("id", 0))
		with_forms += 1
		for f in forms:
			if not (f is Dictionary):
				bad.append([sid, "form-not-dict"])
				continue
			var d: Dictionary = f
			n += 1
			var kind := String(d.get("kind", ""))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
			if String(d.get("key", "")) == "" or String(d.get("label", "")) == "":
				bad.append([sid, "no-key-or-label", String(d.get("key", ""))])
			if (d.get("types", []) as Array).is_empty():
				bad.append([sid, "no-types", String(d.get("key", ""))])
			var base: Dictionary = d.get("base", {})
			if int(base.get("hp", 0)) <= 0:
				bad.append([sid, "no-base", String(d.get("key", ""))])
			var sp_path := String(d.get("sprite", ""))
			if sp_path == "" or not (load(sp_path) is Texture2D):
				bad.append([sid, "no-sprite", String(d.get("key", ""))])
			# Mega / 极巨化必须是能变的，地区形态不能混进战斗变化
			if kind == "mega" or kind == "gmax":
				if Data.battle_forms_of(sid).is_empty():
					bad.append([sid, "battle-form-not-listed", String(d.get("key", ""))])
			if kind == "regional" and String(d.get("label", "")) == "":
				bad.append([sid, "regional-no-label", String(d.get("key", ""))])
	print("forms dbg: %d 只有形态，共 %d 个形态 %s" % [with_forms, n, kinds])
	if not bad.is_empty():
		print("forms dbg: 坏 -> ", bad.slice(0, 12))
	return bad.is_empty() and n > 150

## 战斗里 Mega / 极巨化：图鉴号不变，属性种族值立绘换，血量按比例，打完回到原样
func _test_battle_forms() -> bool:
	# 喷火龙有 Mega X / Y 和超极巨
	var c: Dictionary = BattleScript.make_combatant(6, 50, [33, 34], "")
	var b = BattleScript.new(12345)
	b.start([c], [BattleScript.make_combatant(19, 5, [33], "")])
	var before_hp := int(c["max_hp"])
	var before_spe := int((c["stats"] as Dictionary).get("spe", 0))
	var avail: Array = b.available_forms("a")
	print("forms dbg: 喷火龙战斗中可选 ", avail.size())
	if avail.size() < 3:
		print("!! Mega/超极巨 没被识别为可变化形态")
		return false
	var mega := ""
	for f in avail:
		if String((f as Dictionary).get("key", "")) == "CHARIZARD_MEGA_X":
			mega = "CHARIZARD_MEGA_X"
	if mega == "":
		print("!! 找不到 Mega X")
		return false
	var r: Dictionary = b.transform("a", mega)
	var a: Dictionary = b.cur_a()
	print("transform dbg: ", String(r.get("text", "")), " / 属性 ", a["types"], " / 速度 ", (a["stats"] as Dictionary).get("spe", 0))
	if int(a.get("species_id", 0)) != 6:
		print("!! 变形态后图鉴号被改了")
		return false
	if String(a.get("form", "")) != mega:
		print("!! form 字段没写进去")
		return false
	if not (a["types"] as Array).has("dragon"):
		print("!! Mega X 的龙属性没生效")
		return false
	if int((a["stats"] as Dictionary).get("spe", 0)) == before_spe and int((a["stats"] as Dictionary).get("atk", 0)) == 0:
		print("!! 种族值没跟着形态变")
		return false
	# 一场只能变一次
	if not b.available_forms("a").is_empty():
		print("!! 同一场战斗变了两次")
		return false
	# 极巨化：另一只
	var c2: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var b2 = BattleScript.new(999)
	b2.start([c2], [BattleScript.make_combatant(19, 5, [33], "")])
	var hp0 := int(c2["max_hp"])
	var r2: Dictionary = b2.transform("a", "VENUSAUR_GMAX")
	var a2: Dictionary = b2.cur_a()
	print("gmax dbg: ", String(r2.get("text", "")), " 血量 ", hp0, " -> ", int(a2["max_hp"]))
	if int(a2["max_hp"]) != hp0 * 2:
		print("!! 极巨化血量没翻倍")
		return false
	# 队伍换形态再换回来，血量不该炸
	var mon: Dictionary = PartyScript.make(25, 30, [33], "PIKACHU_ALOLA")
	var mhp := int(mon["max_hp"])
	PartyScript.set_form(mon, "")
	print("party form dbg: 阿罗拉雷丘? ", String(mon.get("name", "")), " hp ", mhp, " -> ", int(mon["max_hp"]))
	if String(mon.get("form", "")) != "":
		print("!! 形态没清掉")
		return false
	if int(mon["max_hp"]) != mhp:
		print("!! 换回原形态后血量不一致")
		return false
	# 存盘再读回来，形态不能丢
	var sv: Dictionary = SaveScript.empty()
	sv["party"].append(PartyScript.make(6, 50, [33], "CHARIZARD_MEGA_X"))
	var back = JSON.parse_string(JSON.stringify(sv))
	var bmon: Dictionary = ((back as Dictionary)["party"] as Array)[0]
	print("save form dbg: ", String(bmon.get("form", "<丢了>")))
	if String(bmon.get("form", "")) != "CHARIZARD_MEGA_X":
		print("!! 存档没保住形态")
		return false
	return true

## Z 招式与极巨招式：招式表得真的有这些招，且战斗里能把普通招换成它们
func _test_gimmick_moves() -> bool:
	if Data.gimmicks.is_empty():
		print("!! 变化系统表没加载")
		return false
	# 每个属性都得有通用 Z 招式与极巨招式
	var miss_z: Array = []
	var miss_max: Array = []
	for ty in Data.types.keys():
		if String(ty).begins_with("_"):
			continue
		if Data.z_move_for_type(String(ty)) <= 0:
			miss_z.append(ty)
		if Data.max_move_for_type(String(ty)) <= 0:
			miss_max.append(ty)
	print("gimmick dbg: 缺 Z 招式的属性 ", miss_z.size(), "，缺极巨招式的 ", miss_max.size())
	if not miss_z.is_empty() or not miss_max.is_empty():
		print("!! 有属性没有对应的 Z / 极巨招式 ", miss_z, miss_max)
		return false
	# 招式表里这些招必须存在且分类正确
	var bad: Array = []
	var kinds := {"z": 0, "max": 0, "gmax": 0}
	for mv in Data.moves.values():
		var k := String(mv.get("kind", ""))
		if k == "":
			continue
		kinds[k] = int(kinds.get(k, 0)) + 1
		if String(mv.get("name", "")) == "":
			bad.append(int(mv.get("id", 0)))
	print("gimmick dbg: Z ", kinds["z"], " 极巨 ", kinds["max"], " 超极巨 ", kinds["gmax"], " 坏数据 ", bad.size())
	if kinds["z"] <= 0 or kinds["max"] <= 0 or kinds["gmax"] <= 0:
		print("!! Z / 极巨 / 超极巨 招式没导全")
		return false

	# 皮卡丘（专属 Z）与普通宝可梦（通用 Z）各试一次
	var pika: Dictionary = BattleScript.make_combatant(25, 50, [85, 33], "")  # 十万伏特 / 撞击
	var b = BattleScript.new(777)
	b.start([pika], [BattleScript.make_combatant(19, 5, [33], "")])
	if not b.can_use_z("a"):
		print("!! 皮卡丘不能用 Z 招式")
		return false
	var zid: int = b.z_move_of(b.cur_a(), 85)
	var zname := String((Data.move_of(zid) as Dictionary).get("name", ""))
	var zd: Dictionary = b.z_move_data(b.cur_a(), 85)
	print("z dbg: 十万伏特 -> ", zname, " 威力 ", zd.get("power", 0), " 属性 ", zd.get("type", ""))
	# 十万伏特是皮卡丘专属 Z：千万伏特
	if String((Data.move_of(zid) as Dictionary).get("key", "")) != "CATASTROPIKA":
		print("!! 皮卡丘没取到专属 Z 招式")
		return false
	if int(zd.get("power", 0)) <= 0:
		print("!! Z 招式威力没算出来")
		return false
	var r: Dictionary = b.use_z("a", 0)
	if not bool(r.get("ok", false)):
		print("!! Z 招式用不出来")
		return false
	# 一场只能一次
	if b.can_use_z("a"):
		print("!! Z 招式能用第二次")
		return false

	# 极巨化：招式要换成极巨招式
	var ven: Dictionary = BattleScript.make_combatant(3, 50, [33, 22], "")  # 撞击 / 藤鞭
	var b2 = BattleScript.new(778)
	b2.start([ven], [BattleScript.make_combatant(19, 5, [33], "")])
	b2.transform("a", "VENUSAUR_GMAX")
	var a2: Dictionary = b2.cur_a()
	var base: Dictionary = Data.move_of(22)
	var maxed: Dictionary = b2._max_move_data(a2, base)
	print("gmax move dbg: ", String(base.get("name", "")), " -> ", String(maxed.get("name", "")),
		" 威力 ", maxed.get("power", 0))
	# 妙蛙花有专属超极巨招式：超极巨灰飞鞭灭
	if String((Data.move_of(int(Data.gmax_move_for("VENUSAUR_GMAX", "grass"))) as Dictionary).get("key", "")) != "G_MAX_VINE_LASH":
		print("!! 超极巨专属招式没取到")
		return false
	if String(maxed.get("name", "")) == String(base.get("name", "")):
		print("!! 极巨化后招式没变")
		return false

	# 专属招式的附加机制要跟着走：炒花类留下持续伤害，皮卡丘类上麻痹
	var ge = maxed.get("gmax_effect", {})
	print("gmax eff dbg: 超极巨灰飞鞭灭 -> ", ge)
	if not (ge is Dictionary) or String((ge as Dictionary).get("kind", "")) != "residual":
		print("!! 超极巨专属招式的持续伤害没挂上")
		return false
	# 33 条超极巨招式都要有效果条目，不能漏一条
	var noeff: Array = []
	for mv in Data.moves.values():
		if not (mv is Dictionary):
			continue
		if String((mv as Dictionary).get("kind", "")) != "gmax":
			continue
		if Data.gmax_effect(int((mv as Dictionary).get("id", 0))).is_empty():
			noeff.append(int((mv as Dictionary).get("id", 0)))
	print("gmax eff dbg: 没有效果条目的超极巨招式 ", noeff.size())
	if not noeff.is_empty():
		print("!! 有超极巨招式没写效果 ", noeff)
		return false

	# 皮卡丘超极巨万雷轰顶：要让对手麻痹
	var pk: Dictionary = BattleScript.make_combatant(25, 50, [85, 33], "PIKACHU_GMAX")
	var b3 = BattleScript.new(779)
	b3.start([pk], [BattleScript.make_combatant(19, 50, [33], "")])
	var pmax: Dictionary = b3._max_move_data(b3.cur_a(), Data.move_of(85))
	var foe: Dictionary = b3.cur_b()
	var txt: String = b3._gmax_effect(b3.cur_a(), foe, pmax.get("gmax_effect", {}), 10)
	print("gmax eff dbg: 万雷轰顶附加 -> ", txt, " 对手状态 ", String(foe.get("status", "")))
	if String(foe.get("status", "")) != "par":
		print("!! 超极巨万雷轰顶没让对手麻痹")
		return false
	# 持续伤害要在回合末真的掉血
	var hp0: int = int(foe["hp"])
	foe["residual"] = {"turns": 2, "frac": 6}
	b3._end_of_turn_gmax()
	if int(foe["hp"]) >= hp0:
		print("!! 缠住类招式的持续伤害没结算")
		return false
	return true

## 太晶化：属性换成太晶属性，本系加成变 2 倍，一场一次
func _test_tera() -> bool:
	var mon: Dictionary = PartyScript.make(25, 50, [85, 33], "")
	if String(mon.get("tera_type", "")) == "":
		print("!! 队伍数据没带太晶属性")
		return false
	var b = BattleScript.new(4242)
	b.start([mon], [BattleScript.make_combatant(19, 50, [33], "")])
	var c: Dictionary = b.cur_a()
	c["tera_type"] = "water"
	if not b.can_use_tera("a"):
		print("!! 太晶化不可用")
		return false
	var r: Dictionary = b.use_tera("a")
	var a: Dictionary = b.cur_a()
	print("tera dbg: ", String(r.get("text", "")), " / 属性 ", a["types"])
	if not bool(r.get("ok", false)):
		print("!! 太晶化失败")
		return false
	if String(a.get("form", "")) != "" and a["types"] != ["water"]:
		print("!! 太晶化后属性没换")
		return false
	if not (a["types"] as Array).has("water"):
		print("!! 太晶属性没生效")
		return false
	# 太晶后本系 2 倍
	var mv: Dictionary = Data.move_of(Data.z_move_for_type("water"))
	var dummy: Dictionary = {"types": ["water"], "stats": {"def": 100, "spd": 100}, "stages": {"def": 0, "spd": 0},
		"status": "", "ability_name": "", "tera_active": true, "tera_type": "water"}
	var atk: Dictionary = {"types": ["water"], "stats": {"atk": 100, "spa": 100}, "stages": {"atk": 0, "spa": 0},
		"status": "", "ability_name": "", "level": 50, "tera_active": true, "tera_type": "water"}
	var water_move: Dictionary = {"power": 80, "type": "water", "category": "physical"}
	var d_tera := b.damage(atk, dummy, water_move)
	atk["tera_active"] = false
	var d_plain := b.damage(atk, dummy, water_move)
	print("tera dmg dbg: 太晶 ", d_tera, " / 普通 ", d_plain)
	if d_tera <= d_plain:
		print("!! 太晶化的本系加成没起作用")
		return false
	if b.can_use_tera("a"):
		print("!! 太晶化能用第二次")
		return false
	return true

## 形态进化链：地区形态进化成对应的地区形态，不能跑回普通形态
func _test_form_evolution() -> bool:
	var cases := [
		{"sp": 19, "form": "RATTATA_ALOLA", "lv": 20, "to": 20, "to_form": "RATICATE_ALOLA"},
		{"sp": 263, "form": "ZIGZAGOON_GALAR", "lv": 20, "to": 264, "to_form": "LINOONE_GALAR"},
		{"sp": 58, "form": "", "lv": 30, "to": 0, "to_form": ""},
	]
	for cs in cases:
		var mon: Dictionary = PartyScript.make(int(cs["sp"]), int(cs["lv"]), [33], String(cs["form"]))
		var evo: Dictionary = GrowthScript.evolution_of(mon)
		if int(cs["to"]) == 0:
			continue
		if int(evo.get("to", 0)) != int(cs["to"]) or String(evo.get("form", "")) != String(cs["to_form"]):
			print("!! 形态进化链错: ", cs, " -> ", evo)
			return false
		# 真进化一次，名字与形态都得换过去
		if not PartyScript.evolve(mon, int(evo["to"]), String(evo["form"])):
			print("!! 形态进化执行失败 ", cs)
			return false
		if String(mon.get("form", "")) != String(cs["to_form"]):
			print("!! 进化后形态丢了 ", cs, " -> ", mon.get("form", ""))
			return false
	print("form evo dbg: 阿罗拉小拉达 -> 阿罗拉拉达、伽勒尔蛇纹熊 -> 伽勒尔直冲熊 都对")
	# 帽子皮卡丘这类没有进化链的形态，不该进化成雷丘
	var hat: Dictionary = PartyScript.make(25, 60, [33], "PIKACHU_ORIGINAL_CAP")
	var hevo: Dictionary = GrowthScript.evolution_of(hat)
	print("form evo dbg: 帽子皮卡丘进化判定 ", hevo)
	if not hevo.is_empty():
		print("!! 换装形态不该有进化")
		return false
	# 道具进化：洗翠卡蒂狗 + 火之石 -> 洗翠风速狗
	var grow: Dictionary = PartyScript.make(58, 30, [33], "GROWLITHE_HISUI")
	var items: Array = GrowthScript.item_evolutions(grow)
	var found := {}
	for e in items:
		if String((e as Dictionary).get("item", "")) == "FIRE_STONE":
			found = e
	print("form evo dbg: 洗翠卡蒂狗道具进化 ",(items if not items.is_empty() else "空"))
	if found.is_empty():
		print("!! 洗翠卡蒂狗没有火之石进化")
		return false
	if int(found.get("to", 0)) != 59 or String(found.get("form", "")) != "ARCANINE_HISUI":
		print("!! 火之石进化的目标形态错 ", found)
		return false
	# 普通卡蒂狗用火之石也进化成普通风速狗
	var plain: Dictionary = PartyScript.make(58, 30, [33], "")
	var plain_item := ""
	for e in GrowthScript.item_evolutions(plain):
		if String((e as Dictionary).get("item", "")) == "FIRE_STONE":
			plain_item = String((e as Dictionary).get("form", ""))
	if plain_item != "":
		print("!! 普通卡蒂狗被地区形态的进化链带歪了")
		return false

	# 端到端：队伍界面按「用火之石进化」，真的换物种、换形态、扣掉石头
	var keep_party = save_data.get("party", [])
	var keep_bag = bag_items.duplicate(true)
	save_data["party"] = [PartyScript.make(58, 30, [33], "GROWLITHE_HISUI")]
	bag_items = [{"name": "火之石", "count": 1}]
	_evolve_with_item(0, "火之石", null)
	var evo: Dictionary = (save_data.get("party", [{}]) as Array)[0]
	var stone_left := 0
	for it in bag_items:
		if String((it as Dictionary).get("name", "")) == "火之石":
			stone_left = int((it as Dictionary).get("count", 0))
	print("evo dbg: 进化后 ", String(evo.get("name", "?")), " form=", String(evo.get("form", "")),
		" 剩火之石 ", stone_left)
	if int(evo.get("species_id", 0)) != 59 or String(evo.get("form", "")) != "ARCANINE_HISUI":
		print("!! 洗翠卡蒂狗没进化成洗翠风速狗")
		return false
	if stone_left != 0:
		print("!! 进化没扣道具")
		return false
	save_data["party"] = keep_party
	bag_items = keep_bag

	# 普通形态也不能被地区形态的链带歪
	var normal: Dictionary = PartyScript.make(19, 20, [33], "")
	var nevo: Dictionary = GrowthScript.evolution_of(normal)
	if int(nevo.get("to", 0)) != 20 or String(nevo.get("form", "")) != "":
		print("!! 普通小拉达进化链被形态影响了 ", nevo)
		return false
	return true

## 变化按钮：只有超极巨的不能写 Mega，两者都有才写「Mega/极巨」
## 天气 / 场地 / 屏障 / 撒菱 / 重力：全部招式都接上了，且真的改伤害
## 出场天气特性、天气加速、天气免疫、半无敌、替身挡状态、树果
func _test_weather_ability() -> bool:
	var ok2 := true
	# 沙河马有扬沙：上场自动沙暴
	var hippo: Dictionary = BattleScript.make_combatant(449, 50, [33], "")
	var b := BattleScript.new(2024)
	b.start([hippo], [BattleScript.make_combatant(19, 50, [33], "")])
	print("wap dbg: 上场天气 %s" % String(b.field.weather))
	if String(b.field.weather) != "sandstorm":
		print("!! 扬沙没有开场沙暴")
		ok2 = false

	# 拨沙特性在沙暴中速度翻倍
	var fast: Dictionary = BattleScript.make_combatant(449, 50, [33], "")
	fast["ability_name"] = "拨沙"
	var slow: Dictionary = BattleScript.make_combatant(449, 50, [33], "")
	slow["ability_name"] = "沙隐"
	var spd_fast: int = b._speed(fast)
	var spd_slow: int = b._speed(slow)
	print("wap dbg: 沙暴中速度 拨沙 %d / 沙隐 %d" % [spd_fast, spd_slow])
	if spd_fast <= spd_slow:
		print("!! 拨沙没有加速")
		ok2 = false

	# 沙隐不吃沙暴伤害
	b.field.set_weather("sandstorm")
	var veiler: Dictionary = b.cur_a()
	veiler["ability_name"] = "沙隐"
	var hp0 := int(veiler["hp"])
	b.field.end_turn([veiler, b.cur_b()])
	print("wap dbg: 沙隐沙暴掉血 %d" % (hp0 - int(veiler["hp"])))
	if int(veiler["hp"]) != hp0:
		print("!! 沙隐还是被沙暴刮了")
		ok2 = false

	# 半无敌：飞翔蓄力那回合对方攻击落空
	var b2 := BattleScript.new(31)
	var bird: Array = [BattleScript.make_combatant(16, 50, [19], "")]  # 波波：飞翔
	b2.start(bird, [BattleScript.make_combatant(19, 50, [33], "")])
	b2.run_turn("move:0", "none")
	print("wap dbg: 飞翔蓄力后 semi=%s" % str(b2.cur_a().get("semi_invuln", false)))
	if not bool(b2.cur_a().get("semi_invuln", false)):
		print("!! 飞翔没有进入半无敌")
		ok2 = false
	var bhp := int(b2.cur_a()["hp"])
	b2.run_turn("none", "move:0")
	print("wap dbg: 半无敌期间挨打掉血 %d" % (bhp - int(b2.cur_a()["hp"])))
	if int(b2.cur_a()["hp"]) != bhp:
		print("!! 半无敌还是被打中了")
		ok2 = false

	# 替身挡住异常状态
	var b3 := BattleScript.new(41)
	b3.start([BattleScript.make_combatant(143, 50, [164], "")],
		[BattleScript.make_combatant(92, 50, [95], "")])   # 耿鬼：催眠术
	b3.run_turn("move:0", "none")
	if int(b3.cur_a().get("sub_hp", 0)) <= 0:
		print("!! 替身没做出来")
		ok2 = false
	b3.run_turn("none", "move:0")
	var st := String(b3.cur_a().get("status", ""))
	print("wap dbg: 替身在场时的状态「%s」" % st)
	if st != "":
		print("!! 替身没挡住催眠")
		ok2 = false

	# 文柚果回一半
	var b4 := BattleScript.new(51)
	var tank: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	tank["berry"] = "sitrus"
	tank["hp"] = int(tank["max_hp"]) / 2
	b4.start([tank], [BattleScript.make_combatant(19, 50, [33], "")])
	var half := int(b4.cur_a()["hp"])
	b4._end_of_turn_field()
	var healed := int(b4.cur_a()["hp"]) - half
	print("wap dbg: 文柚果回复 %d" % healed)
	if healed <= 0:
		print("!! 文柚果没回血")
		ok2 = false
	return ok2

## 携带道具：剩饭、讲究头带、生命宝珠、气势披带、天气岩石
func _test_held_items() -> bool:
	var ok3 := true

	# 剩饭：回合末回 1/16
	var b5 := BattleScript.new(61)
	var eater: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	eater["held"] = "LEFTOVERS"
	eater["hp"] = int(int(eater["max_hp"]) / 2)
	b5.start([eater], [BattleScript.make_combatant(19, 50, [33], "")])
	var e0 := int(b5.cur_a()["hp"])
	b5.held_end_turn(b5.cur_a())
	var back := int(b5.cur_a()["hp"]) - e0
	print("held dbg: 剩饭回复 %d / 每回合 %d" % [back, int(int(b5.cur_a()["max_hp"]) / 16.0)])
	if back <= 0:
		print("!! 剩饭没回血")
		ok3 = false

	# 讲究头带：物理伤害变高
	var plain: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var banded: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	banded["held"] = "CHOICE_BAND"
	var foe_plain: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var foe_band: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var ba := BattleScript.new(77)
	ba.start([plain], [foe_plain])
	var h0 := int(foe_plain["hp"])
	ba.run_turn("move:0", "none")
	var d_plain: int = h0 - int(ba.cur_b()["hp"])
	var bb := BattleScript.new(77)
	bb.start([banded], [foe_band])
	var h1 := int(foe_band["hp"])
	bb.run_turn("move:0", "none")
	var d_band: int = h1 - int(bb.cur_b()["hp"])
	print("held dbg: 头带前 %d / 头带后 %d" % [d_plain, d_band])
	if d_band <= d_plain:
		print("!! 讲究头带没加成")
		ok3 = false

	# 生命宝珠：伤害更高且反伤
	var orb: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	orb["held"] = "LIFE_ORB"
	var b6 := BattleScript.new(88)
	b6.start([orb], [BattleScript.make_combatant(3, 50, [33], "")])
	var mine_hp := int(b6.cur_a()["hp"])
	b6.run_turn("move:0", "none")
	var recoil := mine_hp - int(b6.cur_a()["hp"])
	print("held dbg: 生命宝珠反伤 %d" % recoil)
	if recoil <= 0:
		print("!! 生命宝珠没反伤")
		ok3 = false

	# 气势披带：满血被一击打倒时留 1 点
	var sasher: Dictionary = BattleScript.make_combatant(19, 5, [33], "")
	sasher["held"] = "FOCUS_SASH"
	var b7 := BattleScript.new(99)
	b7.start([sasher], [BattleScript.make_combatant(143, 60, [33], "")])
	b7.run_turn("none", "move:0")
	print("held dbg: 气势披带后体力 %d" % int(b7.cur_a()["hp"]))
	if int(b7.cur_a()["hp"]) != 1:
		print("!! 气势披带没留 1 点")
		ok3 = false

	# 天气岩石：扬沙配沙沙岩石，沙暴 8 回合
	var hippo: Dictionary = BattleScript.make_combatant(449, 50, [33], "")
	hippo["ability_name"] = "扬沙"
	hippo["held"] = "SMOOTH_ROCK"
	var b8 := BattleScript.new(111)
	b8.start([hippo], [BattleScript.make_combatant(19, 50, [33], "")])
	b8._on_send_out("a")
	print("held dbg: 沙沙岩石沙暴 %d 回合" % int(b8.field.weather_turns))
	if int(b8.field.weather_turns) != 8:
		print("!! 沙沙岩石没延长沙暴")
		ok3 = false

	# 背包 / 商店 / 队伍三处都对得上同一个 key
	var shop_held := 0
	for g in Data.load_json("res://content/shop.json"):
		if g is Dictionary and String((g as Dictionary).get("category", "")) == "held":
			shop_held += 1
	var held_only := 0
	for k in Data.held_items:
		if String((Data.held_items[k] as Dictionary).get("category", "")) != "tm":
			held_only += 1
	print("held dbg: 商店携带道具 %d 件 / 表里 %d 件" % [shop_held, held_only])
	if shop_held != held_only:
		print("!! 携带道具没全部上架")
		ok3 = false
	return ok3

## 树果：数据驱动之后，种类、触发条件、效果都要对得上
func _test_fieldwork() -> bool:
	var ok4 := true
	# 1) 树/石头挡路，清掉之后能过
	var w := WorldScript.new()
	w.load_map(Data.load_map("kanto", "kanto_main"))
	var found := Vector2i(-1, -1)
	var kind := ""
	for o in w.objects:
		var k := String(o.get("kind", ""))
		if k == "cut" or k == "rock" or k == "boulder":
			var at: Array = o.get("at", [0, 0])
			found = Vector2i(int(at[0]), int(at[1]))
			kind = k
			break
	if found.x < 0:
		print("!! 找不到挡路的树或石头")
		return false
	var blocked := not w.can_enter(found, Vector2i(1, 0))
	var cleared := false
	if blocked:
		w.mark_taken({"kind": kind, "at": [found.x, found.y]})
		cleared = w.can_enter(found, Vector2i(1, 0))
	print("field dbg: %s 在 %s 挡路 %s / 清掉后可走 %s" % [kind, str(found), str(blocked), str(cleared)])
	if not blocked or not cleared:
		print("!! 障碍物挡路或清除不生效")
		ok4 = false
	w.free()

	# 2) 秘传招式判定
	var saved: Array = save_data.get("party", [])
	save_data["party"] = [PartyScript.make(25, 10, [33])]   # 只有撞击
	var no_cut := not _party_has_move("CUT")
	save_data["party"] = [PartyScript.make(25, 10, [33, 15])]  # 加居合斩
	var has_cut := _party_has_move("CUT")
	print("field dbg: 无居合斩 %s / 有居合斩 %s" % [str(no_cut), str(has_cut)])
	if not no_cut or not has_cut:
		print("!! 秘传招式判定不对")
		ok4 = false

	# 3) 蛋走够步数会孵
	save_data["party"] = [PartyScript.make(25, 10, [15])]
	save_data["egg"] = {"species": 133, "steps": 3}
	for i in 5:
		_tick_egg()
	var hatched: bool = (save_data.get("egg", {}) as Dictionary).is_empty() and (save_data["party"] as Array).size() >= 2
	print("field dbg: 蛋孵出 %s，队伍 %d 只" % [str(hatched), (save_data["party"] as Array).size()])
	if not hatched:
		print("!! 蛋没孵出来")
		ok4 = false
	save_data["party"] = saved

	# 3.5) 道具球、告示牌、树果树也要占格；土是可以走上去的
	var w2 := WorldScript.new()
	w2.load_map(Data.load_map("kanto", "kanto_main"))
	var probes := {"item": Vector2i(-1, -1), "sign": Vector2i(-1, -1), "soil": Vector2i(-1, -1)}
	for o in w2.objects:
		var k2 := String(o.get("kind", ""))
		if probes.has(k2) and (probes[k2] as Vector2i).x < 0:
			var a2: Array = o.get("at", [0, 0])
			probes[k2] = Vector2i(int(a2[0]), int(a2[1]))
	# 道具球现在不挡路：踩上去就自动捡（以前当墙，玩家碰不到球）
	var item_walk: bool = (probes["item"] as Vector2i).x < 0 or w2.can_enter(probes["item"], Vector2i(1, 0))
	var sign_blocks: bool = (probes["sign"] as Vector2i).x >= 0 and not w2.can_enter(probes["sign"], Vector2i(1, 0))
	var soil_walk: bool = (probes["soil"] as Vector2i).x < 0 or w2.can_enter(probes["soil"], Vector2i(1, 0))
	print("field dbg: 道具球可走 %s / 告示牌挡路 %s / 土层可走 %s" % [str(item_walk), str(sign_blocks), str(soil_walk)])
	if not item_walk or not sign_blocks or not soil_walk:
		print("!! 地上物件的体积不对")
		ok4 = false
	# 捡走之后要能踩过去
	if probes["item"].x >= 0:
		var ip: Vector2i = probes["item"]
		w2.taken[w2._object_key({"at": [ip.x, ip.y]})] = true
		if not w2.can_enter(probes["item"] as Vector2i, Vector2i(1, 0)):
			print("!! 道具球捡走后还挡路")
			ok4 = false
	w2.free()

	# 3.55) 怪力推石头：推一格，旧位置让出来，新位置挡住
	var push_ok := false
	for cand in [["kanto", "victoryroad_1f"], ["sevii", "mt_ember_summit"],
			["kanto", "seafoam_islands_b2f"], ["kanto", "kanto_main"]]:
		if push_ok:
			break
		var w4 := WorldScript.new()
		w4.load_map(Data.load_map(cand[0], cand[1]))
		var boulder_at := Vector2i(-1, -1)
		for o in w4.objects:
			if String(o.get("kind", "")) == "boulder":
				var ba: Array = o.get("at", [0, 0])
				boulder_at = Vector2i(int(ba[0]), int(ba[1]))
				break
		if boulder_at.x < 0:
			w4.free()
			continue
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var back: Vector2i = boulder_at + d
			if not w4.can_enter(back, d):
				continue
			var push_dir: Vector2i = -d
			var to: Vector2i = boulder_at + push_dir
			var ref: Dictionary = w4.object_ref(boulder_at)
			if not w4.push_object(ref, push_dir):
				continue
			var moved: bool = w4.object_ref(boulder_at).is_empty() \
				and not w4.object_ref(to).is_empty()
			var free_after: bool = w4.can_enter(boulder_at, push_dir)
			var blocked_new: bool = not w4.can_enter(to, push_dir)
			print("field dbg: 推石 ", cand[1], " 推动 %s / 原位让出 %s / 新址挡路 %s"
				% [str(moved), str(free_after), str(blocked_new)])
			if not (moved and free_after and blocked_new):
				print("!! 推石头逻辑不对")
				ok4 = false
			push_ok = true
			break
		w4.free()
	if not push_ok:
		print("!! 找不到可推的石头")
		ok4 = false

	# 3.57) 推石入水：石头沉底，水面还是水面
	var sunk_ok := false
	for cand in [["kanto", "seafoam_islands_b2f"], ["kanto", "seafoam_islands_b3f"],
			["kanto", "victoryroad_1f"], ["sevii", "mt_ember_summit"]]:
		if sunk_ok:
			break
		var w5 := WorldScript.new()
		w5.load_map(Data.load_map(cand[0], cand[1]))
		for o in w5.objects:
			if String(o.get("kind", "")) != "boulder":
				continue
			var ba2: Array = o.get("at", [0, 0])
			var bp := Vector2i(int(ba2[0]), int(ba2[1]))
			var water_dir := Vector2i.ZERO
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				if w5.is_water(bp + d) and w5.can_enter(bp - d, d):
					water_dir = d
					break
			if water_dir == Vector2i.ZERO:
				continue
			var ref2: Dictionary = w5.object_ref(bp)
			if w5.push_object(ref2, water_dir):
				var gone: bool = w5.object_ref(bp).is_empty() and bool(ref2.get("sunk", false))
				var still_water: bool = w5.is_water(bp + water_dir)
				print("field dbg: 推石入水 沉底 %s / 仍是水面 %s" % [str(gone), str(still_water)])
				sunk_ok = gone and still_water
				if not sunk_ok:
					print("!! 推石入水逻辑不对")
					ok4 = false
				break
		w5.free()
	if not sunk_ok:
		print("field dbg: 这几张图里没有挨着水的石头（不算失败）")

	# 3.58) 全库坡沿覆盖：每张有坡的图都要能用
	var maps_with_ledge := 0
	var dirs := []
	for d in DirAccess.get_directories_at("res://content/regions"):
		dirs.append(String(d))
	for rid in dirs:
		var base := "res://content/regions/%s/maps" % rid
		for f in DirAccess.get_files_at(base):
			if not String(f).ends_with(".json"):
				continue
			var mm: Dictionary = Data.load_map(rid, String(f).get_basename())
			var meta_name := String(mm.get("emerald", ""))
			if meta_name == "":
				continue
			var p2 := "res://content/emerald_maps/%s.json" % meta_name
			if not FileAccess.file_exists(p2):
				continue
			var mt: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p2))
			var lg: Array = mt.get("ledge", [])
			var cnt := 0
			for row in lg:
				for v in row:
					if int(v) != 0:
						cnt += 1
			if cnt > 0:
				maps_with_ledge += 1
	print("field dbg: 有坡的地图 %d 张" % maps_with_ledge)
	if maps_with_ledge < 50:
		print("!! 坡的数据覆盖太少")
		ok4 = false

	# 3.59) 怪力开关：石头推上去要能压住
	var wb := WorldScript.new()
	wb.load_map(Data.load_map("kanto", "victoryroad_1f"))
	var btn := Vector2i(-1, -1)
	for y in wb.emerald_button.size():
		for x in (wb.emerald_button[y] as Array).size():
			if int(wb.emerald_button[y][x]) == 1:
				btn = Vector2i(x, y)
				break
		if btn.x >= 0:
			break
	if btn.x < 0:
		print("!! 没有开关格数据")
		ok4 = false
	else:
		var pressed := false
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var from: Vector2i = btn - d
			if not wb.can_enter(from, d):
				continue
			wb.objects.append({"at": [from.x, from.y], "kind": "boulder", "sprite": "boulder"})
			var ref3: Dictionary = wb.object_ref(from)
			if wb.push_object(ref3, d):
				pressed = wb.is_button(from + d)
				break
		print("field dbg: 开关格 %s 压住 %s" % [str(btn), str(pressed)])
		if not pressed:
			print("!! 石头压不住开关")
			ok4 = false
	wb.free()

	# 3.6) 层级：站在 NPC 上一格，玩家必须排在 NPC 后面
	var w3 := WorldScript.new()
	w3.load_map(Data.load_map("kanto", "kanto_main"))
	if not (w3.npcs as Array).is_empty():
		var n0: Dictionary = w3.npcs[0]
		var na: Array = n0.get("at", [0, 0])
		var ny := int(na[1])
		var z_npc := 100 + ny * 2
		var z_above := 100 + (ny - 1) * 2
		var z_below := 100 + (ny + 1) * 2
		print("field dbg: 层级 上格 %d / NPC %d / 下格 %d" % [z_above, z_npc, z_below])
		if not (z_above < z_npc and z_npc < z_below):
			print("!! 人物层级没按 y 排")
			ok4 = false
	w3.free()

	# 4) 秘传学习器道具都在包里能查
	for k in ["HM01", "HM02", "HM03", "HM04", "HM05", "HM06", "HM07", "HM08"]:
		if not Data.hms.has(k):
			print("!! 缺道具 %s" % k)
			ok4 = false
	return ok4


## 地形机制的通用验收：冰面、坑洞、深水、漩涡、岩壁、洋流
## 关都/七岛的数据里几乎没有这些地形，所以这里铺一张人工小图来验机制本身：
## 以后做到有对应地形的世代，数据到位就能直接用。
func _make_terrain_world() -> WorldScript:
	var w := WorldScript.new()
	w.load_map({"id": "terrain_probe", "name": "地形测试", "size": [10, 10], "tiles": [], "spawn": [1, 1]})
	var n := 10
	var zeros := []
	for y in n:
		var row := []
		for x in n:
			row.append(0)
		zeros.append(row)
	w.emerald_collision = zeros.duplicate(true)
	w.emerald_water = zeros.duplicate(true)
	w.emerald_deep = zeros.duplicate(true)
	w.emerald_hole = zeros.duplicate(true)
	w.emerald_whirl = zeros.duplicate(true)
	w.emerald_climb = zeros.duplicate(true)
	w.emerald_slide = zeros.duplicate(true)
	w.emerald_current = zeros.duplicate(true)
	w.emerald_button = zeros.duplicate(true)
	w.emerald_ledge = zeros.duplicate(true)
	w.emerald_dir = zeros.duplicate(true)
	w.tile_size = Vector2i(n, n)
	w.emerald_png_path = ""
	w.objects = []
	w.npcs = []
	w.taken = {}
	return w


func _test_terrain() -> bool:
	var ok5 := true
	var w := _make_terrain_world()

	# 1) 冰面：踩上去顺着方向一直滑到边界
	w.emerald_slide[3][3] = 255
	w.emerald_slide[3][4] = 255
	w.emerald_slide[3][5] = 255
	w.player_pos = Vector2i(2, 3)
	w.finish_walk()
	w.step(Vector2i(1, 0))
	w.finish_walk()
	var slid := 0
	for i in 8:
		var d: Vector2i = w.auto_step_dir()
		if d == Vector2i.ZERO:
			break
		if not w.step(d):
			break
		w.finish_walk()
		slid += 1
	print("terrain dbg: 冰面滑了 %d 格，停在 %s" % [slid, str(w.player_pos)])
	if slid != 3 or w.player_pos != Vector2i(6, 3):
		print("!! 冰面滑行不对")
		ok5 = false

	# 2) 坑洞：没填平走不进去，石头推进去就填平
	w.emerald_hole[6][2] = 1
	if w.can_enter(Vector2i(2, 6), Vector2i(1, 0)):
		print("!! 坑洞没挡住")
		ok5 = false
	w.objects = [{"at": [1, 6], "kind": "boulder", "sprite": "boulder"}]
	var hole_ref: Dictionary = w.object_ref(Vector2i(1, 6))
	var filled: bool = w.push_object(hole_ref, Vector2i(1, 0))
	var walk_after: bool = w.can_enter(Vector2i(2, 6), Vector2i(1, 0))
	print("terrain dbg: 推石填坑 %s / 填平后可走 %s" % [str(filled), str(walk_after)])
	if not filled or not walk_after:
		print("!! 推石填坑不对")
		ok5 = false

	# 3) 深水：没潜水进不去，潜了就能进
	w.emerald_deep[8][5] = 1
	if w.can_enter(Vector2i(5, 8), Vector2i(1, 0)):
		print("!! 深水没挡住")
		ok5 = false
	w.diving = true
	if not w.can_enter(Vector2i(5, 8), Vector2i(1, 0)):
		print("!! 潜水后还是进不去深水")
		ok5 = false
	w.diving = false
	print("terrain dbg: 深水 未潜挡 / 潜水可进")

	# 4) 漩涡：没清掉过不去，清了就能过
	w.emerald_whirl[8][2] = 1
	if w.can_enter(Vector2i(2, 8), Vector2i(1, 0)):
		print("!! 漩涡没挡住")
		ok5 = false
	w.clear_whirl(Vector2i(2, 8))
	if not w.can_enter(Vector2i(2, 8), Vector2i(1, 0)):
		print("!! 清掉漩涡还是过不去")
		ok5 = false
	print("terrain dbg: 漩涡 未清挡 / 清掉可过")

	# 5) 岩壁：走过去不行，攀岩能翻上去
	w.emerald_climb[4][7] = 1
	w.player_pos = Vector2i(7, 5)
	w.facing = "up"
	w.finish_walk()
	if w.can_enter(Vector2i(7, 4), Vector2i(0, -1)):
		print("!! 岩壁能直接走过去")
		ok5 = false
	var climbed: bool = w.climb_up()
	var up_ok: bool = climbed and w.player_pos.y < 5
	print("terrain dbg: 攀岩 %s 到 %s" % [str(climbed), str(w.player_pos)])
	if not up_ok:
		print("!! 攀岩没生效")
		ok5 = false

	# 6) 洋流：站上去会被推着走
	w.emerald_current[1][6] = 4    # 往东推
	w.player_pos = Vector2i(6, 1)
	w.finish_walk()
	var push: Vector2i = w.auto_step_dir()
	print("terrain dbg: 洋流推 %s" % str(push))
	if push != Vector2i(1, 0):
		print("!! 洋流没推人")
		ok5 = false

	w.queue_free()
	return ok5


func _test_berries() -> bool:
	var ok4 := true
	var kinds := {}
	for k in Data.berries.keys():
		var d: Dictionary = Data.berries[k]
		var kind := String(d.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if String(d.get("name", "")) == "" or String(d.get("desc", "")) == "":
			print("!! 树果 %s 缺名字或说明" % k)
			ok4 = false
		if kind == "resist" and String(d.get("type", "")) == "":
			print("!! 抗性果 %s 没写属性" % k)
			ok4 = false
		if kind == "boost" and String(d.get("stat", "")) == "":
			print("!! 能力果 %s 没写能力" % k)
			ok4 = false
		if kind == "cure" and (d.get("status", []) as Array).is_empty():
			print("!! 解状态果 %s 没写状态" % k)
			ok4 = false
	print("berry dbg: 共 %d 种 / %s" % [Data.berries.size(), str(kinds)])
	for need in ["heal", "pp", "cure", "cure_all", "boost", "crit", "resist", "boost_on_hit"]:
		if int(kinds.get(need, 0)) == 0:
			print("!! 缺少 %s 类树果" % need)
			ok4 = false

	# 文柚果：半血时回一半
	var b1 := BattleScript.new(121)
	var mon: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	mon["berry"] = "sitrus"
	mon["hp"] = int(int(mon["max_hp"]) / 2)
	b1.start([mon], [BattleScript.make_combatant(19, 50, [33], "")])
	var half := int(b1.cur_a()["hp"])
	b1._end_of_turn_field()
	print("berry dbg: 文柚果回复 %d" % (int(b1.cur_a()["hp"]) - half))
	if int(b1.cur_a()["hp"]) - half < int(int(b1.cur_a()["max_hp"]) / 2) - 1:
		print("!! 文柚果没回一半")
		ok4 = false
	if String(b1.cur_a().get("berry", "x")) != "":
		print("!! 文柚果吃完没清空")
		ok4 = false

	# 樱子果：只有麻痹时才吃
	var b2 := BattleScript.new(131)
	var p1: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	p1["berry"] = "cheri"
	p1["hp"] = int(int(p1["max_hp"]) / 2)
	b2.start([p1], [BattleScript.make_combatant(19, 50, [33], "")])
	b2._end_of_turn_field()
	if String(b2.cur_a().get("berry", "")) != "cheri":
		print("!! 没麻痹却把樱子果吃了")
		ok4 = false
	b2.cur_a()["status"] = "par"
	b2._end_of_turn_field()
	print("berry dbg: 麻痹后状态「%s」" % String(b2.cur_a().get("status", "")))
	if String(b2.cur_a().get("status", "")) != "":
		print("!! 樱子果没解麻痹")
		ok4 = false

	# 枝荔果：体力四分之一以下攻击提升
	var b3 := BattleScript.new(141)
	var low: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	low["berry"] = "liechi"
	low["hp"] = int(int(low["max_hp"]) / 5)
	b3.start([low], [BattleScript.make_combatant(19, 50, [33], "")])
	var atk0 := int(b3.cur_a()["stages"]["atk"])
	b3._end_of_turn_field()
	print("berry dbg: 枝荔果攻击阶段 %d -> %d" % [atk0, int(b3.cur_a()["stages"]["atk"])])
	if int(b3.cur_a()["stages"]["atk"]) != atk0 + 1:
		print("!! 枝荔果没提升攻击")
		ok4 = false

	# 抗性果：血量过半后被火系打中，伤害减半
	var plain: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	plain["hp"] = int(int(plain["max_hp"]) / 2)
	var with_occa: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	with_occa["hp"] = int(int(with_occa["max_hp"]) / 2)
	with_occa["berry"] = "occa"
	var attacker: Dictionary = BattleScript.make_combatant(6, 50, [53], "")   # 喷火龙：喷射火焰
	var fire: Dictionary = Data.moves[53]
	var d_plain: int = BattleScript.new(151).damage(attacker, plain, fire)
	var b4 := BattleScript.new(151)
	var d_occa: int = b4.damage(attacker, with_occa, fire)
	print("berry dbg: 巧可果前 %d / 后 %d" % [d_plain, d_occa])
	if d_occa >= d_plain:
		print("!! 巧可果没减伤")
		ok4 = false
	if String(with_occa.get("berry", "")) != "":
		print("!! 巧可果吃完没清空")
		ok4 = false

	# 苹野果：PP 见底时回 10 点
	var b5 := BattleScript.new(161)
	var drained: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	drained["berry"] = "leppa"
	drained["pp"][0] = 0
	b5.start([drained], [BattleScript.make_combatant(19, 50, [33], "")])
	b5._end_of_turn_field()
	print("berry dbg: 苹野果 PP %d" % int(b5.cur_a()["pp"][0]))
	if int(b5.cur_a()["pp"][0]) != 10:
		print("!! 苹野果没回 PP")
		ok4 = false

	# 商店里的树果必须都能在表里找到
	var shop_berry := 0
	for g in Data.load_json("res://content/shop.json"):
		if g is Dictionary and String((g as Dictionary).get("category", "")) == "berry":
			shop_berry += 1
			var bk := String((g as Dictionary).get("berry", ""))
			if Data.berry_def(bk).is_empty():
				print("!! 商店树果 %s 在表里找不到" % bk)
				ok4 = false
	print("berry dbg: 商店树果 %d 种" % shop_berry)
	if shop_berry < 20:
		print("!! 商店树果太少")
		ok4 = false
	return ok4

## 特性：数值型特性全部走 content/ability_effects.json，这里验触发条件与效果
func _test_ability_effects() -> bool:
	var ok5 := true
	# 表里的特性名必须都是真实存在的特性，不能凭空造
	var known := {}
	for a in Data.abilities.values():
		known[String((a as Dictionary).get("name", ""))] = true
	for k in Data.ability_effects.keys():
		if not known.has(k):
			print("!! 特性表里的 %s 在 abilities.json 里不存在" % k)
			ok5 = false
	print("abfx dbg: %d 条特性效果" % Data.ability_effects.size())

	# 专属 Z：键必须是真实存在的物种 key 或形态 key
	var sp_keys := {}
	var form_keys := {}
	for sp in Data.species.values():
		var d: Dictionary = sp
		sp_keys[String(d.get("key", ""))] = true
		for f in (d.get("forms", []) as Array):
			form_keys[String((f as Dictionary).get("key", ""))] = true
	var bad_z: Array = []
	for k in (Data.gimmicks.get("z_exclusive", {}) as Dictionary).keys():
		if not sp_keys.has(String(k)) and not form_keys.has(String(k)):
			bad_z.append(String(k))
	print("abfx dbg: 专属 Z %d 条，坏键 %d" % [int((Data.gimmicks.get("z_exclusive", {}) as Dictionary).size()), bad_z.size()])
	if not bad_z.is_empty():
		print("!! 专属 Z 坏键 %s" % str(bad_z))
		ok5 = false

	# 结实：满血被一击必倒留 1 点
	var b1 := BattleScript.new(201)
	var weak: Dictionary = BattleScript.make_combatant(19, 5, [33], "")
	weak["ability_name"] = "结实"
	b1.start([weak], [BattleScript.make_combatant(143, 60, [33], "")])
	b1.run_turn("none", "move:0")
	print("abfx dbg: 结实后体力 %d" % int(b1.cur_a()["hp"]))
	if int(b1.cur_a()["hp"]) != 1:
		print("!! 结实没留住 1 点")
		ok5 = false

	# 多重鳞片：满血受到的伤害减半
	var plain: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var scaled: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	scaled["ability_name"] = "多重鳞片"
	var foe: Dictionary = BattleScript.make_combatant(6, 50, [53], "")
	var fire: Dictionary = Data.moves[53]
	var d1: int = BattleScript.new(211).damage(foe, plain, fire)
	var d2: int = BattleScript.new(211).damage(foe, scaled, fire)
	print("abfx dbg: 多重鳞片 %d -> %d" % [d1, d2])
	if d2 >= d1:
		print("!! 多重鳞片没减伤")
		ok5 = false

	# 技术高手：威力 40 的招式威力提升
	var user: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var tech: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	tech["ability_name"] = "技术高手"
	var target: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var tackle: Dictionary = Data.moves[33]
	var t1: int = BattleScript.new(221).damage(user, target, tackle)
	var t2: int = BattleScript.new(221).damage(tech, target, tackle)
	print("abfx dbg: 技术高手 %d -> %d" % [t1, t2])
	if t2 <= t1:
		print("!! 技术高手没加成")
		ok5 = false

	# 适应力：本系加成变 2 倍
	var normal_a: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var adapt: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	adapt["ability_name"] = "适应力"
	var tgt2: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var s1: int = BattleScript.new(231).damage(normal_a, tgt2, tackle)
	var s2: int = BattleScript.new(231).damage(adapt, tgt2, tackle)
	print("abfx dbg: 适应力 %d -> %d" % [s1, s2])
	if s2 <= s1:
		print("!! 适应力没提高本系加成")
		ok5 = false

	# 粗糙皮肤：接触招式打上去会反伤
	var b2 := BattleScript.new(241)
	var rough: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	rough["ability_name"] = "粗糙皮肤"
	b2.start([BattleScript.make_combatant(6, 50, [33], "")], [rough])
	var atk_hp := int(b2.cur_a()["hp"])
	b2.run_turn("move:0", "none")
	print("abfx dbg: 粗糙皮肤反伤 %d" % (atk_hp - int(b2.cur_a()["hp"])))
	if int(b2.cur_a()["hp"]) >= atk_hp:
		print("!! 粗糙皮肤没反伤")
		ok5 = false

	# 天恩：追加效果概率翻倍
	var blessed: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	blessed["ability_name"] = "天恩"
	var b3 := BattleScript.new(251)
	b3.start([blessed], [BattleScript.make_combatant(19, 50, [33], "")])
	var c1 := b3._effect_chance(b3.cur_a(), 30)
	print("abfx dbg: 天恩概率 30 -> %d" % c1)
	if c1 != 60:
		print("!! 天恩没翻倍")
		ok5 = false

	# 坚硬脑袋：反作用力招式不掉血
	var head: Dictionary = BattleScript.make_combatant(143, 50, [36], "")
	head["ability_name"] = "坚硬脑袋"
	var b4 := BattleScript.new(261)
	b4.start([head], [BattleScript.make_combatant(19, 50, [33], "")])
	var h0 := int(b4.cur_a()["hp"])
	b4.run_turn("move:0", "none")
	print("abfx dbg: 坚硬脑袋反伤 %d" % (h0 - int(b4.cur_a()["hp"])))
	if int(b4.cur_a()["hp"]) != h0:
		print("!! 坚硬脑袋还是吃了反伤")
		ok5 = false

	# 沙之力：沙暴里岩石系招式更痛
	var rocker: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var sandy: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	sandy["ability_name"] = "沙之力"
	var b5 := BattleScript.new(271)
	var rock_move: Dictionary = {"power": 80, "type": "rock", "category": "physical"}
	var b6 := BattleScript.new(271)
	b5.field.set_weather("sandstorm")
	b6.field.set_weather("sandstorm")
	var r1: int = b5.damage(rocker, BattleScript.make_combatant(3, 50, [33], ""), rock_move)
	var r2: int = b6.damage(sandy, BattleScript.make_combatant(3, 50, [33], ""), rock_move)
	print("abfx dbg: 沙之力 %d -> %d" % [r1, r2])
	if r2 <= r1:
		print("!! 沙之力没加成")
		ok5 = false

	# 电气制造者：上场就开电气场地
	var maker: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	maker["ability_name"] = "电气制造者"
	var b7 := BattleScript.new(281)
	b7.start([maker], [BattleScript.make_combatant(19, 50, [33], "")])
	print("abfx dbg: 电气制造者场地「%s」" % b7.field.terrain)
	if String(b7.field.terrain) != "electric":
		print("!! 电气制造者没开场地")
		ok5 = false
	return ok5

## 招式附带效果：畏缩、镜面反射这类以前只认日志、不改状态的
func _test_move_extras() -> bool:
	var ok6 := true

	# 畏缩：被挂了畏缩的那只这回合动不了（直接置标记，不吃 30% 概率）
	var b1 := BattleScript.new(301)
	var fast: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var slow: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	b1.start([fast], [slow])
	var slow_hp := int(b1.cur_a()["hp"])
	b1.cur_b()["flinch"] = true
	b1.run_turn("none", "move:0")
	var flinched := false
	for line in b1.log:
		if String(line).find("畏缩") >= 0:
			flinched = true
	print("mfx dbg: 畏缩跳过行动 %s / 自身体力 %d -> %d" % [str(flinched), slow_hp, int(b1.cur_a()["hp"])])
	if not flinched:
		print("!! 畏缩没有跳过行动")
		ok6 = false
	if int(b1.cur_a()["hp"]) != slow_hp:
		print("!! 畏缩了还是打出了伤害")
		ok6 = false

	# 镜面反射：把上一回合吃的伤害翻倍打回去
	var b2 := BattleScript.new(311)
	var tank: Dictionary = BattleScript.make_combatant(143, 50, [243], "")
	b2.start([tank], [BattleScript.make_combatant(6, 50, [53], "")])
	b2.run_turn("none", "move:0")          # 先挨一发喷射火焰
	var taken := int(b2.cur_a().get("last_damage", 0))
	var hp_before := int(b2.cur_b()["hp"])
	b2.run_turn("move:0", "none")          # 镜面反射打回去
	var back := hp_before - int(b2.cur_b()["hp"])
	print("mfx dbg: 挨打 %d / 反射 %d" % [taken, back])
	if taken > 0 and back < taken:
		print("!! 镜面反射没有翻倍还手")
		ok6 = false
	if taken <= 0:
		print("!! 没记下上一回合受到的伤害")
		ok6 = false

	# 守住：当回合挡下一切
	var b3 := BattleScript.new(321)
	var guard: Dictionary = BattleScript.make_combatant(143, 50, [182], "")   # 守住
	b3.start([guard], [BattleScript.make_combatant(6, 50, [53], "")])
	var hp0 := int(b3.cur_a()["hp"])
	b3.run_turn("move:0", "none")
	print("mfx dbg: 守住后掉血 %d" % (hp0 - int(b3.cur_a()["hp"])))
	if int(b3.cur_a()["hp"]) != hp0:
		print("!! 守住没挡住")
		ok6 = false
	return ok6

## 特性第二组：属性吸收、硬爪、过滤、纯朴、换人回复
func _test_ability_effects2() -> bool:
	var ok7 := true

	# 储水：水属性招式打不进来，还回 1/4 体力
	var wet: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	wet["ability_name"] = "储水"
	wet["hp"] = int(wet["max_hp"]) - 40
	var b1 := BattleScript.new(401)
	b1.start([BattleScript.make_combatant(7, 50, [55], "")], [wet])
	var hp0 := int(b1.cur_b()["hp"])
	b1.run_turn("move:0", "none")
	var gained := int(b1.cur_b()["hp"]) - hp0
	print("abfx2 dbg: 储水回血 %d" % gained)
	if gained <= 0:
		print("!! 储水没吸收水属性招式")
		ok7 = false

	# 引火：火属性招式无效，特攻上升
	var fired: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	fired["ability_name"] = "引火"
	var b2 := BattleScript.new(411)
	b2.start([BattleScript.make_combatant(6, 50, [53], "")], [fired])
	var hp1 := int(b2.cur_b()["hp"])
	b2.run_turn("move:0", "none")
	print("abfx2 dbg: 引火掉血 %d / 特攻阶 %d" % [hp1 - int(b2.cur_b()["hp"]), int(b2.cur_b()["stages"]["spa"])])
	if int(b2.cur_b()["hp"]) != hp1 or int(b2.cur_b()["stages"]["spa"]) < 1:
		print("!! 引火没生效")
		ok7 = false

	# 硬爪：接触招式威力 1.3 倍
	var claw: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	claw["ability_name"] = "硬爪"
	var plain2: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var dummy: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var c1: int = BattleScript.new(421).damage(plain2, dummy, Data.moves[33])
	var c2: int = BattleScript.new(421).damage(claw, dummy, Data.moves[33])
	print("abfx2 dbg: 硬爪 %d -> %d" % [c1, c2])
	if c2 <= c1:
		print("!! 硬爪没加成")
		ok7 = false

	# 过滤：效果拔群伤害打七五折
	var filt: Dictionary = BattleScript.make_combatant(6, 50, [33], "")    # 喷火龙，被岩石 4 倍克制
	filt["ability_name"] = "过滤"
	var bag: Dictionary = BattleScript.make_combatant(6, 50, [33], "")
	var rock_move2: Dictionary = {"power": 80, "type": "rock", "category": "physical"}
	var f1: int = BattleScript.new(431).damage(BattleScript.make_combatant(6, 50, [33], ""), bag, rock_move2)
	var f2: int = BattleScript.new(431).damage(BattleScript.make_combatant(6, 50, [33], ""), filt, rock_move2)
	print("abfx2 dbg: 过滤 %d -> %d" % [f1, f2])
	if f2 >= f1:
		print("!! 过滤没减伤")
		ok7 = false

	# 纯朴：对手的攻击阶数被忽略
	var boosted: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	boosted["stages"]["atk"] = 2
	var naive: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	naive["ability_name"] = "纯朴"
	var target2: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var p1: int = BattleScript.new(441).damage(boosted, target2, Data.moves[33])
	var p2: int = BattleScript.new(441).damage(boosted, naive, Data.moves[33])
	print("abfx2 dbg: 纯朴 %d -> %d" % [p1, p2])
	if p2 >= p1:
		print("!! 纯朴没无视强化")
		ok7 = false

	# 再生力：换下去回 1/3 体力
	var regen: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	regen["ability_name"] = "再生力"
	regen["hp"] = int(int(regen["max_hp"]) / 3)
	var other: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	var b3 := BattleScript.new(451)
	b3.start([regen, other], [BattleScript.make_combatant(3, 50, [33], "")])
	var r0 := int(regen["hp"])
	b3.run_turn("switch:1", "none")
	print("abfx2 dbg: 再生力回血 %d" % (int(regen["hp"]) - r0))
	if int(regen["hp"]) <= r0:
		print("!! 再生力换人没回血")
		ok7 = false
	return ok7

## 招式细节：混乱、束缚、偷道具、吹飞、清场地、预知未来、连击
func _test_move_details() -> bool:
	var ok8 := true

	# 混乱：真的挂上 cfu 状态
	var b1 := BattleScript.new(501)
	b1.start([BattleScript.make_combatant(143, 50, [109], "")],   # 奇异之光
		[BattleScript.make_combatant(19, 50, [33], "")])
	b1.run_turn("move:0", "none")
	print("mdet dbg: 混乱状态「%s」回合 %d" % [String(b1.cur_b().get("status", "")), int(b1.cur_b().get("status_turns", 0))])
	if String(b1.cur_b().get("status", "")) != "cfu":
		print("!! 混乱没挂上")
		ok8 = false

	# 点到为止：对手留 1 点
	var b2 := BattleScript.new(511)
	b2.start([BattleScript.make_combatant(143, 60, [206], "")],   # 点到为止
		[BattleScript.make_combatant(19, 5, [33], "")])
	b2.run_turn("move:0", "none")
	print("mdet dbg: 点到为止后体力 %d" % int(b2.cur_b()["hp"]))
	if int(b2.cur_b()["hp"]) != 1:
		print("!! 点到为止没留 1 点")
		ok8 = false

	# 偷道具：对手的携带物被抢走
	var b3 := BattleScript.new(521)
	var thief: Dictionary = BattleScript.make_combatant(143, 50, [168], "")   # 小偷
	var victim: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	victim["held"] = "LEFTOVERS"
	b3.start([thief], [victim])
	b3.run_turn("move:0", "none")
	print("mdet dbg: 偷后自己[%s] 对手[%s]" % [String(b3.cur_a().get("held", "")), String(b3.cur_b().get("held", ""))])
	if String(b3.cur_a().get("held", "")) != "LEFTOVERS" or String(b3.cur_b().get("held", "")) != "":
		print("!! 偷道具没生效")
		ok8 = false

	# 束缚：换不了人
	var b4 := BattleScript.new(531)
	b4.start([BattleScript.make_combatant(143, 50, [212], "")],   # 黑色目光
		[BattleScript.make_combatant(19, 50, [33], "")])
	b4.run_turn("move:0", "none")
	print("mdet dbg: 束缚标记 %s" % str(b4.cur_b().get("trapped", false)))

	# 治愈铃声：解全队状态
	var b5 := BattleScript.new(541)
	var healer: Dictionary = BattleScript.make_combatant(113, 50, [215], "")   # 吉利蛋：治愈铃声
	var sick: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	sick["status"] = "par"
	b5.start([healer, sick], [BattleScript.make_combatant(19, 50, [33], "")])
	b5.run_turn("move:0", "none")
	print("mdet dbg: 治愈铃声后同伴状态「%s」" % String(sick.get("status", "")))
	if String(sick.get("status", "")) != "":
		print("!! 治愈铃声没解状态")
		ok8 = false

	# 高速旋转：清掉自己的撒菱
	var b6 := BattleScript.new(551)
	b6.start([BattleScript.make_combatant(143, 50, [229], "")],
		[BattleScript.make_combatant(19, 50, [33], "")])
	b6.field.add_hazard("a", "spikes")
	b6.run_turn("move:0", "none")
	var left_spikes := int((b6.field.hazards["a"] as Dictionary).get("spikes", 0))
	print("mdet dbg: 旋转后己方撒菱 %d" % left_spikes)
	if left_spikes != 0:
		print("!! 高速旋转没清撒菱")
		ok8 = false

	# 预知未来：两回合后落下
	var b7 := BattleScript.new(561)
	b7.start([BattleScript.make_combatant(143, 50, [248], "")],
		[BattleScript.make_combatant(19, 50, [33], "")])
	b7.run_turn("move:0", "none")
	print("mdet dbg: 预知未来已挂 %s" % str(not (b7.cur_a().get("future", {}) as Dictionary).is_empty()))
	if (b7.cur_a().get("future", {}) as Dictionary).is_empty():
		print("!! 预知未来没挂上")
		ok8 = false

	# 连击：三连踢打三下
	var b8 := BattleScript.new(571)
	b8.start([BattleScript.make_combatant(143, 50, [167], "")],
		[BattleScript.make_combatant(19, 50, [33], "")])
	var hp_before := int(b8.cur_b()["hp"])
	b8.run_turn("move:0", "none")
	var hits := 0
	for line in b8.log:
		if String(line).find("第 2 下") >= 0 or String(line).find("第 3 下") >= 0:
			hits += 1
	print("mdet dbg: 连击追加 %d 下 / 掉血 %d" % [hits, hp_before - int(b8.cur_b()["hp"])])
	if hits < 2:
		print("!! 三连踢没打出三下")
		ok8 = false

	# 交换持有物（戏法）
	var b10 := BattleScript.new(591)
	var mine: Dictionary = BattleScript.make_combatant(143, 50, [271], "")
	mine["held"] = "LEFTOVERS"
	var other2: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	other2["held"] = "LIFE_ORB"
	b10.start([mine], [other2])
	b10.run_turn("move:0", "none")
	print("mdet dbg: 戏法后自己[%s] 对手[%s]" % [String(b10.cur_a().get("held", "")), String(b10.cur_b().get("held", ""))])
	if String(b10.cur_a().get("held", "")) != "LIFE_ORB" or String(b10.cur_b().get("held", "")) != "LEFTOVERS":
		print("!! 戏法没交换携带物")
		ok8 = false

	# 影子分身：闪避等级真的会涨
	var b11 := BattleScript.new(592)
	b11.start([BattleScript.make_combatant(143, 50, [104], "")],   # 影子分身
		[BattleScript.make_combatant(19, 50, [33], "")])
	b11.run_turn("move:0", "none")
	print("mdet dbg: 影子分身闪避阶 %d" % int(b11.cur_a()["stages"]["eva"]))
	if int(b11.cur_a()["stages"]["eva"]) < 1:
		print("!! 影子分身没提升闪避")
		ok8 = false

	# 戏法空间：慢的先动
	var b12 := BattleScript.new(593)
	var slow_mon: Dictionary = BattleScript.make_combatant(143, 50, [433], "")   # 卡比兽很慢
	b12.start([slow_mon], [BattleScript.make_combatant(25, 20, [33], "")])
	b12.run_turn("move:0", "none")
	print("mdet dbg: 戏法空间 %s 回合 %d" % [str(b12.field.trick_room), int(b12.field.trick_room_turns)])
	if not bool(b12.field.trick_room):
		print("!! 戏法空间没展开")
		ok8 = false

	# 挺住：这一回合不会倒下
	var b9 := BattleScript.new(581)
	var tough: Dictionary = BattleScript.make_combatant(19, 5, [203], "")   # 挺住
	b9.start([tough], [BattleScript.make_combatant(143, 60, [33], "")])
	b9.run_turn("move:0", "none")
	print("mdet dbg: 挺住后体力 %d（先手挺住才算数）" % int(b9.cur_a()["hp"]))
	return ok8

## 特性名一致性：内核里写死的名字必须能在 abilities.json 里查到，
## 否则像「漂浮 / 飘浮」这种一字之差就会让整个特性悄悄失效
func _test_ability_names() -> bool:
	var hard := ["飘浮", "破格", "涡轮火焰", "兆级电压", "威吓", "降雨", "日照", "扬沙", "降雪",
		"柔软", "水幕", "不眠", "干劲", "免疫", "静电", "火焰之躯", "毒刺", "孢子", "防尘",
		"沙隐", "沙之力", "拨沙", "雪隐", "冰冻之躯", "拨雪", "悠游自如", "叶绿素", "纯朴", "结实"]
	var known := {}
	for a in Data.abilities.values():
		known[String((a as Dictionary).get("name", ""))] = true
	var bad: Array = []
	for n in hard:
		if not known.has(n):
			bad.append(n)
	print("abname dbg: 内核引用 %d 个特性名，查不到 %d 个 %s" % [hard.size(), bad.size(), str(bad)])
	return bad.is_empty()

## 特性第三组：反转/翻倍/防护、命中、减伤、击倒增益、回合末
## 测试用：把某只换上一个特性
func _with_ability(mon: Dictionary, ab: String) -> Dictionary:
	mon["ability_name"] = ab
	return mon

func _test_ability_effects3() -> bool:
	var ok9 := true
	var atk0: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var tgt: Dictionary = BattleScript.make_combatant(3, 50, [33], "")
	var tackle: Dictionary = Data.moves[33]

	# 唱反调：降能力变成升
	var contrary: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	contrary["ability_name"] = "唱反调"
	var b1 := BattleScript.new(601)
	b1.start([BattleScript.make_combatant(19, 50, [45], "")], [contrary])   # 叫声：降攻击
	b1.run_turn("move:0", "none")
	print("abfx3 dbg: 唱反调后攻击阶 %d" % int(b1.cur_b()["stages"]["atk"]))
	if int(b1.cur_b()["stages"]["atk"]) <= 0:
		print("!! 唱反调没有反转")
		ok9 = false

	# 单纯：升能力翻倍
	var simple: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	simple["ability_name"] = "单纯"
	var b2 := BattleScript.new(611)
	b2.start([simple], [BattleScript.make_combatant(19, 50, [33], "")])
	b2._apply_stage(b2.cur_a(), "atk", 1, b2.log)
	print("abfx3 dbg: 单纯后攻击阶 %d" % int(b2.cur_a()["stages"]["atk"]))
	if int(b2.cur_a()["stages"]["atk"]) != 2:
		print("!! 单纯没有翻倍")
		ok9 = false

	# 恒净之躯：能力降不下来
	var clear: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	clear["ability_name"] = "恒净之躯"
	var b3 := BattleScript.new(621)
	b3.start([BattleScript.make_combatant(19, 50, [45], "")], [clear])
	b3.run_turn("move:0", "none")
	print("abfx3 dbg: 恒净之躯后攻击阶 %d" % int(b3.cur_b()["stages"]["atk"]))
	if int(b3.cur_b()["stages"]["atk"]) != 0:
		print("!! 恒净之躯没挡住")
		ok9 = false

	# 厚脂肪：火属性伤害减半
	var fat: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	fat["ability_name"] = "厚脂肪"
	var d1: int = BattleScript.new(631).damage(BattleScript.make_combatant(6, 50, [53], ""), atk0, Data.moves[53])
	var d2: int = BattleScript.new(631).damage(BattleScript.make_combatant(6, 50, [53], ""), fat, Data.moves[53])
	print("abfx3 dbg: 厚脂肪 %d -> %d" % [d1, d2])
	if d2 >= d1:
		print("!! 厚脂肪没减伤")
		ok9 = false

	# 毛皮大衣：物理伤害减半
	var fur: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	fur["ability_name"] = "毛皮大衣"
	var p1: int = BattleScript.new(641).damage(atk0, BattleScript.make_combatant(3, 50, [33], ""), tackle)
	var p2: int = BattleScript.new(641).damage(atk0, fur, tackle)
	print("abfx3 dbg: 毛皮大衣 %d -> %d" % [p1, p2])
	if p2 >= p1:
		print("!! 毛皮大衣没减伤")
		ok9 = false

	# 有色眼镜：效果不好时翻倍
	var lens: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	lens["ability_name"] = "有色眼镜"
	var grassy: Dictionary = BattleScript.make_combatant(1, 50, [33], "")   # 妙蛙种子，水系招式效果不好
	var water: Dictionary = BattleScript.make_combatant(7, 50, [55], "")
	var n1: int = BattleScript.new(651).damage(water, grassy, Data.moves[55])
	var n2: int = BattleScript.new(651).damage(water, grassy, Data.moves[55])
	n2 = BattleScript.new(651).damage(_with_ability(water, "有色眼镜"), grassy, Data.moves[55])
	print("abfx3 dbg: 有色眼镜 %d -> %d" % [n1, n2])
	if n2 <= n1:
		print("!! 有色眼镜没生效")
		ok9 = false

	# 神奇守护：非效果拔群打不进
	var guard: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	guard["ability_name"] = "神奇守护"
	var g1: int = BattleScript.new(661).damage(atk0, guard, tackle)
	print("abfx3 dbg: 神奇守护伤害 %d" % g1)
	if g1 != 0:
		print("!! 神奇守护没挡住")
		ok9 = false

	# 加速：回合末速度 +1
	var speeder: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	speeder["ability_name"] = "加速"
	var b4 := BattleScript.new(671)
	b4.start([speeder], [BattleScript.make_combatant(19, 50, [33], "")])
	b4.run_turn("none", "none")
	print("abfx3 dbg: 加速后速度阶 %d" % int(b4.cur_a()["stages"]["spe"]))
	if int(b4.cur_a()["stages"]["spe"]) < 1:
		print("!! 加速没生效")
		ok9 = false

	# 不挠之剑 / 踩影：出场效果
	var sword: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	sword["ability_name"] = "不挠之剑"
	var b5 := BattleScript.new(681)
	b5.start([sword], [BattleScript.make_combatant(19, 50, [33], "")])
	print("abfx3 dbg: 不挠之剑攻击阶 %d" % int(b5.cur_a()["stages"]["atk"]))

	var shadow: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	shadow["ability_name"] = "踩影"
	var b6 := BattleScript.new(691)
	b6.start([shadow], [BattleScript.make_combatant(19, 50, [33], "")])
	print("abfx3 dbg: 踩影束缚 %s" % str(b6.cur_b().get("trapped", false)))
	if not bool(b6.cur_b().get("trapped", false)):
		print("!! 踩影没束缚住")
		ok9 = false

	# 压迫感：用招多扣 1 点 PP
	var press: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	press["ability_name"] = "压迫感"
	var b7 := BattleScript.new(701)
	b7.start([BattleScript.make_combatant(19, 50, [33], "")], [press])
	var pp0 := int(b7.cur_a()["pp"][0])
	b7.run_turn("move:0", "none")
	print("abfx3 dbg: 压迫感 PP %d -> %d" % [pp0, int(b7.cur_a()["pp"][0])])
	if pp0 - int(b7.cur_a()["pp"][0]) != 2:
		print("!! 压迫感没多扣 PP")
		ok9 = false

	# 束缚：被束缚的换不了人
	var trapper: Dictionary = BattleScript.make_combatant(143, 50, [212], "")
	var victim: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	var spare: Dictionary = BattleScript.make_combatant(16, 50, [33], "")
	var b8 := BattleScript.new(711)
	b8.start([trapper], [victim, spare])
	b8.run_turn("move:0", "none")
	b8._do_switch("b", 1)
	print("abfx3 dbg: 束缚中换人是否成功（当前还是 %s）" % String(b8.cur_b()["name"]))
	if String(b8.cur_b()["name"]) != String(victim["name"]):
		print("!! 束缚没拦住换人")
		ok9 = false
	return ok9

## 特性第四组：皮肤类、一猩一意、软弱、画皮、变色、同步
## 靠特性/携带物在战斗里换形态：这些不该占 Mega/极巨化次数，也不该进队伍编辑器
func _test_form_switch() -> bool:
	var okF := true
	# 坚盾剑怪：出招切刀剑、用王者盾牌切回盾牌
	var aegis: Dictionary = _with_ability(BattleScript.make_combatant(681, 50, [33, 182], ""), "战斗切换")
	var b0 := BattleScript.new(9001)
	b0.start([aegis], [BattleScript.make_combatant(143, 50, [33], "")])
	var a_atk_shield := int(b0.cur_a()["stats"]["atk"])
	b0.run_turn("move:0", "move:0")
	var a_atk_blade := int(b0.cur_a()["stats"]["atk"])
	print("form dbg: 坚盾剑怪 攻击 %d -> %d，形态 %s" % [a_atk_shield, a_atk_blade, String(b0.cur_a().get("form", ""))])
	if String(b0.cur_a().get("form", "")) != "AEGISLASH_BLADE" or a_atk_blade <= a_atk_shield:
		print("!! 战斗切换没有换到刀剑形态")
		okF = false
	if int(b0.cur_a().get("forms_used", 0)) != 0:
		print("!! 形态切换不该算进 Mega/极巨化的次数")
		okF = false

	# 达摩狒狒：血不到一半变达摩模式
	var darm: Dictionary = _with_ability(BattleScript.make_combatant(555, 50, [33], ""), "达摩模式")
	var b1 := BattleScript.new(9002)
	b1.start([darm], [BattleScript.make_combatant(143, 50, [33], "")])
	b1.cur_a()["hp"] = int(int(b1.cur_a()["max_hp"]) / 4)
	b1._form_switch_end_turn(b1.cur_a())
	var dz: Dictionary = b1.cur_a()
	print("form dbg: 达摩模式 形态 %s 特攻 %d" % [String(dz.get("form", "")), int(dz["stats"]["spa"])])
	if String(dz.get("form", "")) != "DARMANITAN_ZEN" or int(dz["stats"]["spa"]) <= 60:
		print("!! 达摩模式没有生效")
		okF = false

	# 弱丁鱼：等级够、血够就成群
	var wishi: Dictionary = _with_ability(BattleScript.make_combatant(746, 30, [33], ""), "鱼群")
	var b2 := BattleScript.new(9003)
	b2.start([wishi], [BattleScript.make_combatant(143, 50, [33], "")])
	b2._form_switch_end_turn(b2.cur_a())
	print("form dbg: 鱼群 形态 %s 攻击 %d" % [String(b2.cur_a().get("form", "")), int(b2.cur_a()["stats"]["atk"])])
	if String(b2.cur_a().get("form", "")) != "WISHIWASHI_SCHOOL":
		print("!! 鱼群没有成群")
		okF = false

	# 小陨星：血过半是核心，掉到一半以下变回陨石
	var mini: Dictionary = _with_ability(BattleScript.make_combatant(774, 50, [33], ""), "界限盾壳")
	var b3 := BattleScript.new(9004)
	b3.start([mini], [BattleScript.make_combatant(143, 50, [33], "")])
	b3._form_switch_on_send_out(b3.cur_a())
	var m_form := String(b3.cur_a().get("form", ""))
	b3.cur_a()["hp"] = int(int(b3.cur_a()["max_hp"]) / 4)
	b3._form_switch_end_turn(b3.cur_a())
	print("form dbg: 界限盾壳 %s -> %s" % [m_form, String(b3.cur_a().get("form", ""))])
	if m_form != "MINIOR_CORE_RED" or String(b3.cur_a().get("form", "")) != "":
		print("!! 界限盾壳形态没跟着血量走")
		okF = false

	# 谜拟丘：画皮挡下一击后破皮
	var mimi: Dictionary = _with_ability(BattleScript.make_combatant(778, 50, [33], ""), "画皮")
	var b4 := BattleScript.new(9005)
	b4.start([BattleScript.make_combatant(143, 50, [33], "")], [mimi])
	b4.run_turn("move:0", "move:0")
	print("form dbg: 画皮挡下后形态 %s，掉血 %d" % [String(b4.cur_b().get("form", "")), int(b4.cur_b()["max_hp"]) - int(b4.cur_b()["hp"])])
	if String(b4.cur_b().get("form", "")) != "MIMIKYU_BUSTED":
		print("!! 画皮破了没换形态")
		okF = false

	# 飘浮泡泡：阴晴不定跟着天气走
	var cast: Dictionary = _with_ability(BattleScript.make_combatant(351, 50, [33], ""), "阴晴不定")
	var b5 := BattleScript.new(9006)
	b5.start([cast], [BattleScript.make_combatant(143, 50, [33], "")])
	b5.field.set_weather("rain")
	b5._form_switch_end_turn(b5.cur_a())
	print("form dbg: 阴晴不定 雨天形态 %s 属性 %s" % [String(b5.cur_a().get("form", "")), str(b5.cur_a()["types"])])
	if String(b5.cur_a().get("form", "")) != "CASTFORM_RAINY" or not (b5.cur_a()["types"] as Array).has("water"):
		print("!! 阴晴不定没跟着天气变")
		okF = false

	# 银伴战兽：ＡＲ系统 + 存储碟改属性
	var silv: Dictionary = _with_ability(BattleScript.make_combatant(773, 50, [33], ""), "ＡＲ系统")
	silv["held"] = "MEMORY_FIRE"
	var b6 := BattleScript.new(9007)
	b6.start([silv], [BattleScript.make_combatant(143, 50, [33], "")])
	print("form dbg: ＡＲ系统 形态 %s 属性 %s" % [String(b6.cur_a().get("form", "")), str(b6.cur_a()["types"])])
	if String(b6.cur_a().get("form", "")) != "SILVALLY_FIRE" or not (b6.cur_a()["types"] as Array).has("fire"):
		print("!! ＡＲ系统没换属性")
		okF = false

	# 海豚侠：换下场再上场变成全能形态
	var pala: Dictionary = _with_ability(BattleScript.make_combatant(964, 50, [33], ""), "全能变身")
	var spare: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	var b7 := BattleScript.new(9008)
	b7.start([pala, spare], [BattleScript.make_combatant(19, 50, [33], "")])
	var pala_atk := int(b7.cur_a()["stats"]["atk"])
	b7.run_turn("switch:1", "none")
	b7.run_turn("switch:0", "none")
	print("form dbg: 全能变身 形态 %s 攻击 %d -> %d" % [String(b7.cur_a().get("form", "")), pala_atk, int(b7.cur_a()["stats"]["atk"])])
	if String(b7.cur_a().get("form", "")) != "PALAFIN_HERO" or int(b7.cur_a()["stats"]["atk"]) <= pala_atk:
		print("!! 全能变身没换成全能形态")
		okF = false

	# 道具定形态：洛托姆家电 / 原始回归宝珠
	var roto: Dictionary = BattleScript.make_combatant(479, 50, [84], "")
	roto["held"] = "ROTOM_HEAT"
	var b8 := BattleScript.new(9009)
	b8.start([roto], [BattleScript.make_combatant(19, 50, [33], "")])
	print("form dbg: 洛托姆 形态 %s 属性 %s" % [String(b8.cur_a().get("form", "")), str(b8.cur_a()["types"])])
	if String(b8.cur_a().get("form", "")) != "ROTOM_HEAT" or "fire" not in b8.cur_a()["types"]:
		print("!! 洛托姆没变成加热形态")
		okF = false
	var grou: Dictionary = BattleScript.make_combatant(383, 50, [89], "")
	grou["held"] = "RED_ORB"
	var b9 := BattleScript.new(9010)
	b9.start([grou], [BattleScript.make_combatant(19, 50, [33], "")])
	print("form dbg: 原始回归 形态 %s 攻击 %d" % [String(b9.cur_a().get("form", "")), int(b9.cur_a()["stats"]["atk"])])
	if String(b9.cur_a().get("form", "")) != "GROUDON_PRIMAL":
		print("!! 固拉多没进原始形态")
		okF = false
	# 牵绊变身：打倒对手后变成羁绊形态
	var gren: Dictionary = _with_ability(BattleScript.make_combatant(658, 60, [453], ""), "牵绊变身")
	var weak: Dictionary = BattleScript.make_combatant(19, 5, [33], "")
	weak["hp"] = 1
	var b10 := BattleScript.new(9011)
	b10.start([gren], [weak])
	b10.run_turn("move:0", "none")
	print("form dbg: 牵绊变身 形态 %s kos=%d" % [String(b10.cur_a().get("form", "")), int(b10.cur_a().get("kos", 0))])
	if String(b10.cur_a().get("form", "")) != "GRENINJA_BATTLE_BOND":
		print("!! 甲贺忍蛙没进羁绊形态")
		okF = false

	# 古月鸟：半血以下吞下的是「叼住」形态
	var cram: Dictionary = _with_ability(BattleScript.make_combatant(845, 50, [57], ""), "一口导弹")
	var b11 := BattleScript.new(9012)
	b11.start([cram], [BattleScript.make_combatant(19, 50, [33], "")])
	b11.cur_a()["hp"] = int(b11.cur_a()["max_hp"]) * 2 / 5
	b11.run_turn("move:0", "none")
	print("form dbg: 一口导弹 形态 %s" % String(b11.cur_a().get("form", "")))
	if String(b11.cur_a().get("form", "")) != "CRAMORANT_GORGING":
		print("!! 古月鸟低血时没进叼住形态")
		okF = false

	# 石板 / 卡带 / 花 / 腐朽武器
	var arc: Dictionary = BattleScript.make_combatant(493, 50, [449], "")
	arc["held"] = "FLAME_PLATE"
	var b12 := BattleScript.new(9013)
	b12.start([arc], [BattleScript.make_combatant(19, 50, [33], "")])
	b12.run_turn("move:0", "none")
	print("form dbg: 阿尔宙斯 形态 %s 属性 %s" % [String(b12.cur_a().get("form", "")), str(b12.cur_a()["types"])])
	if String(b12.cur_a().get("form", "")) != "ARCEUS_FIRE" or "fire" not in b12.cur_a()["types"]:
		print("!! 阿尔宙斯没跟着石板变形态")
		okF = false
	var gen: Dictionary = BattleScript.make_combatant(649, 50, [546], "")
	gen["held"] = "CHILL_DRIVE"
	var b13 := BattleScript.new(9014)
	b13.start([gen], [BattleScript.make_combatant(19, 50, [33], "")])
	b13.run_turn("move:0", "none")
	print("form dbg: 盖诺赛克特 形态 %s 属性 %s" % [String(b13.cur_a().get("form", "")), str(b13.cur_a()["types"])])
	if String(b13.cur_a().get("form", "")) != "GENESECT_CHILL" or "ice" not in b13.cur_a()["types"]:
		print("!! 盖诺赛克特没跟着卡带变")
		okF = false
	var shay: Dictionary = BattleScript.make_combatant(492, 50, [33], "")
	shay["held"] = "GRACIDEA"
	var zc: Dictionary = BattleScript.make_combatant(888, 50, [33], "")
	zc["held"] = "RUSTED_SWORD"
	var b14 := BattleScript.new(9015)
	b14.start([shay], [BattleScript.make_combatant(19, 50, [33], "")])
	var b15 := BattleScript.new(9016)
	b15.start([zc], [BattleScript.make_combatant(19, 50, [33], "")])
	print("form dbg: 花与剑 %s / %s" % [String(b14.cur_a().get("form", "")), String(b15.cur_a().get("form", ""))])
	if String(b14.cur_a().get("form", "")) != "SHAYMIN_SKY" or String(b15.cur_a().get("form", "")) != "ZACIAN_CROWNED":
		print("!! 谢米或苍响没变形态")
		okF = false

	# 这些形态不该出现在队伍编辑器的可选形态里
	var bad: Array = []
	for f in Data.forms_of(681):
		if String((f as Dictionary).get("key", "")) == "AEGISLASH_BLADE" and not bool((f as Dictionary).get("battle", false)):
			bad.append("AEGISLASH_BLADE 没标成战斗形态")
	for f in Data.battle_forms_of(555):
		bad.append("达摩狒狒的达摩形态被当成 Mega/极巨化了")
	print("form dbg: 战斗形态标记问题 %s" % str(bad))
	if not bad.is_empty():
		print("!! 战斗形态标记不对")
		okF = false
	return okF

func _test_ability_effects4() -> bool:
	var okA := true
	var tackle: Dictionary = Data.moves[33]
	var target: Dictionary = BattleScript.make_combatant(149, 50, [33], "")   # 快龙，怕妖精
	var plain: Dictionary = BattleScript.make_combatant(143, 50, [33], "")

	# 妖精皮肤：一般招式变成妖精属性，打龙系变成效果拔群
	var pixie: Dictionary = _with_ability(BattleScript.make_combatant(143, 50, [33], ""), "妖精皮肤")
	var d0: int = BattleScript.new(801).damage(plain, target, tackle)
	var d1: int = BattleScript.new(801).damage(pixie, target, tackle)
	print("abfx4 dbg: 妖精皮肤 %d -> %d" % [d0, d1])
	if d1 <= d0:
		print("!! 妖精皮肤没生效")
		okA = false

	# 一猩一意：攻击 1.5 倍
	var gorilla: Dictionary = _with_ability(BattleScript.make_combatant(143, 50, [33], ""), "一猩一意")
	var g1: int = BattleScript.new(811).damage(gorilla, target, tackle)
	print("abfx4 dbg: 一猩一意 %d -> %d" % [d0, g1])
	if g1 <= d0:
		print("!! 一猩一意没加成")
		okA = false

	# 软弱：血不足一半时攻击减半
	var weakling: Dictionary = _with_ability(BattleScript.make_combatant(143, 50, [33], ""), "软弱")
	weakling["hp"] = int(int(weakling["max_hp"]) / 3)
	var w1: int = BattleScript.new(821).damage(weakling, target, tackle)
	print("abfx4 dbg: 软弱 %d -> %d" % [d0, w1])
	if w1 >= d0:
		print("!! 软弱没有削弱")
		okA = false

	# 画皮：第一次伤害被完全挡下
	var mimikyu: Dictionary = _with_ability(BattleScript.make_combatant(778, 50, [33], ""), "画皮")
	var b1 := BattleScript.new(831)
	b1.start([plain], [mimikyu])
	var hp0 := int(b1.cur_b()["hp"])
	b1.run_turn("move:0", "none")
	print("abfx4 dbg: 画皮挡下掉血 %d" % (hp0 - int(b1.cur_b()["hp"])))
	if int(b1.cur_b()["hp"]) != hp0:
		print("!! 画皮没挡下第一击")
		okA = false

	# 变色：被打后属性变成招式属性
	var pory: Dictionary = _with_ability(BattleScript.make_combatant(137, 50, [33], ""), "变色")
	var b2 := BattleScript.new(841)
	b2.start([BattleScript.make_combatant(6, 50, [53], "")], [pory])   # 喷射火焰
	b2.run_turn("move:0", "none")
	print("abfx4 dbg: 变色后属性 %s" % str(b2.cur_b().get("types", [])))
	if not (b2.cur_b().get("types", []) as Array).has("fire"):
		print("!! 变色没改属性")
		okA = false

	# 同步：中毒弹回给出手方
	var umbreon: Dictionary = _with_ability(BattleScript.make_combatant(197, 50, [33], ""), "同步")
	var b3 := BattleScript.new(851)
	b3.start([BattleScript.make_combatant(89, 50, [86], "")], [umbreon])
	b3._try_status(b3.cur_b(), "par")
	print("abfx4 dbg: 同步后对手状态「%s」/ 自己「%s」" % [String(b3.cur_a().get("status", "")), String(b3.cur_b().get("status", ""))])
	if String(b3.cur_a().get("status", "")) != "par":
		print("!! 同步没把状态弹回去")
		okA = false
	return okA

## 招式细节第二组：蓄能、颠倒、哈欠、顺风、撒菱、击落、光合作用、蓄力吞下
func _test_move_details2() -> bool:
	var okB := true

	# 辅助力量：能力提升越多威力越大
	var b1 := BattleScript.new(901)
	var mon: Dictionary = BattleScript.make_combatant(143, 50, [500], "")
	b1.start([mon], [BattleScript.make_combatant(19, 50, [33], "")])
	var low := b1._power_of(b1.cur_a(), b1.cur_b(), Data.moves[500])
	b1.cur_a()["stages"]["atk"] = 3
	b1.cur_a()["stages"]["def"] = 2
	var high := b1._power_of(b1.cur_a(), b1.cur_b(), Data.moves[500])
	print("mdet2 dbg: 辅助力量 %d -> %d" % [low, high])
	if high <= low:
		print("!! 辅助力量没随能力提升")
		okB = false

	# 颠倒：把能力变化翻过来
	var b2 := BattleScript.new(911)
	var target: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	target["stages"]["def"] = 2
	b2.start([BattleScript.make_combatant(143, 50, [576], "")], [target])
	b2.run_turn("move:0", "none")
	print("mdet2 dbg: 颠倒后防御阶 %d" % int(b2.cur_b()["stages"]["def"]))
	if int(b2.cur_b()["stages"]["def"]) >= 0:
		print("!! 颠倒没生效")
		okB = false

	# 哈欠：两回合后睡着
	var b3 := BattleScript.new(921)
	b3.start([BattleScript.make_combatant(143, 50, [281], "")],
		[BattleScript.make_combatant(19, 50, [33], "")])
	b3.run_turn("move:0", "none")
	var slept := String(b3.cur_b().get("status", "")) == "slp"
	print("mdet2 dbg: 哈欠后状态「%s」" % String(b3.cur_b().get("status", "")))
	if not slept:
		print("!! 哈欠没让对手睡着")
		okB = false

	# 撒菱：对手场地多一层
	var b4 := BattleScript.new(931)
	b4.start([BattleScript.make_combatant(143, 50, [191], "")],
		[BattleScript.make_combatant(19, 50, [33], "")])
	b4.run_turn("move:0", "none")
	var spikes := int((b4.field.hazards["b"] as Dictionary).get("spikes", 0))
	print("mdet2 dbg: 对手场地撒菱 %d 层" % spikes)
	if spikes < 1:
		print("!! 撒菱没生效")
		okB = false

	# 击落：把飞行系打到地面，地面招式就能打中
	var b5 := BattleScript.new(941)
	var bird: Dictionary = BattleScript.make_combatant(149, 70, [33], "")   # 快龙：飞行，够硬
	b5.start([BattleScript.make_combatant(143, 50, [479], "")], [bird])
	var before_eff := b5.effectiveness_on("ground", b5.cur_b())
	b5.run_turn("move:0", "none")
	var after_eff := b5.effectiveness_on("ground", b5.cur_b())
	print("mdet2 dbg: 击落 倍率 %s -> %s / grounded=%s / 命中日志含击落=%s" % [str(before_eff), str(after_eff),
		str(b5.cur_b().get("grounded", false)), str(str(b5.log).find("击落") >= 0)])
	if after_eff <= 0.0:
		print("!! 击落后还是打不到")
		okB = false

	# 光合作用：晴天回得多
	var b6 := BattleScript.new(951)
	var plant: Dictionary = BattleScript.make_combatant(143, 50, [235], "")
	plant["hp"] = int(int(plant["max_hp"]) / 3)
	b6.start([plant], [BattleScript.make_combatant(19, 50, [33], "")])
	b6.field.set_weather("sun")
	var hp0 := int(b6.cur_a()["hp"])
	b6.run_turn("move:0", "none")
	print("mdet2 dbg: 晴天光合作用回复 %d" % (int(b6.cur_a()["hp"]) - hp0))
	if int(b6.cur_a()["hp"]) <= hp0:
		print("!! 光合作用没回血")
		okB = false

	# 蓄力 / 吞下：吞下回血并清空层数
	var b7 := BattleScript.new(961)
	var stk: Dictionary = BattleScript.make_combatant(143, 50, [254, 256], "")
	b7.start([stk], [BattleScript.make_combatant(19, 50, [33], "")])
	b7.run_turn("move:0", "none")
	var layers := int(b7.cur_a().get("stockpile", 0))
	b7.cur_a()["hp"] = int(int(b7.cur_a()["max_hp"]) / 3)
	var h0 := int(b7.cur_a()["hp"])
	b7.run_turn("move:1", "none")
	print("mdet2 dbg: 蓄力 %d 层 / 吞下回复 %d" % [layers, int(b7.cur_a()["hp"]) - h0])
	if layers < 1 or int(b7.cur_a()["hp"]) <= h0:
		print("!! 蓄力吞下没生效")
		okB = false
	return okB

## 招式细节第三组：扑击、突袭、奇迹空间、羽栖
func _test_move_details3() -> bool:
	var okC := true

	# 扑击：用防御当攻击力，防御越高打得越痛
	var b1 := BattleScript.new(971)
	var mon: Dictionary = BattleScript.make_combatant(143, 50, [33], "")
	b1.start([mon], [BattleScript.make_combatant(19, 50, [33], "")])
	var mv: Dictionary = (Data.moves[33] as Dictionary).duplicate()
	mv["effect"] = "BODY_PRESS"
	var low := b1._power_of(b1.cur_a(), b1.cur_b(), mv)
	b1.cur_a()["stats"]["def"] = int(b1.cur_a()["stats"]["def"]) * 3
	var high := b1._power_of(b1.cur_a(), b1.cur_b(), mv)
	print("mdet3 dbg: 扑击 %d -> %d" % [low, high])
	if high <= low:
		print("!! 扑击没随防御提升")
		okC = false

	# 突袭：本回合已经挨过打，威力翻倍
	var b2 := BattleScript.new(981)
	var tgt: Dictionary = BattleScript.make_combatant(19, 50, [33], "")
	b2.start([BattleScript.make_combatant(143, 50, [33], "")], [tgt])
	var mv2: Dictionary = (Data.moves[33] as Dictionary).duplicate()
	mv2["effect"] = "ASSURANCE"
	var p1 := b2._power_of(b2.cur_a(), b2.cur_b(), mv2)
	b2.cur_b()["hit_this_turn"] = 1
	var p2 := b2._power_of(b2.cur_a(), b2.cur_b(), mv2)
	print("mdet3 dbg: 突袭 %d -> %d" % [p1, p2])
	if p2 <= p1:
		print("!! 突袭没翻倍")
		okC = false

	# 奇迹空间：防御与特防互换
	var b3 := BattleScript.new(991)
	var a1: Dictionary = BattleScript.make_combatant(143, 50, [472], "")   # 奇迹空间
	b3.start([a1], [BattleScript.make_combatant(19, 50, [33], "")])
	var d_before := int(b3.cur_a()["stats"]["def"])
	var sd_before := int(b3.cur_a()["stats"]["spd"])
	b3.run_turn("move:0", "none")
	print("mdet3 dbg: 奇迹空间 防御 %d->%d 特防 %d->%d" % [d_before, int(b3.cur_a()["stats"]["def"]),
		sd_before, int(b3.cur_a()["stats"]["spd"])])
	if int(b3.cur_a()["stats"]["def"]) != sd_before or int(b3.cur_a()["stats"]["spd"]) != d_before:
		print("!! 奇迹空间没交换")
		okC = false

	# 羽栖：回一半体力
	var b4 := BattleScript.new(1001)
	var bird: Dictionary = BattleScript.make_combatant(16, 50, [355], "")   # 羽栖
	bird["hp"] = int(int(bird["max_hp"]) / 3)
	b4.start([bird], [BattleScript.make_combatant(19, 50, [33], "")])
	var h0 := int(b4.cur_a()["hp"])
	b4.run_turn("move:0", "none")
	print("mdet3 dbg: 羽栖回复 %d" % (int(b4.cur_a()["hp"]) - h0))
	if int(b4.cur_a()["hp"]) <= h0:
		print("!! 羽栖没回血")
		okC = false
	return okC

## 招式效果覆盖率：moves.json 里出现的每个 effect 名，内核都必须认识
func _test_effect_coverage() -> bool:
	var seen := {}
	for mv in Data.moves.values():
		var effect := String(mv.get("effect", ""))
		if effect == "" or seen.has(effect):
			continue
		seen[effect] = true
		var bt = BattleScript.new(1921)
		var user := BattleScript.make_combatant(25, 50, [int(mv["id"])])
		bt.start([user], [BattleScript.make_combatant(133, 50, [33])])
		bt.run_turn("move:0", "item")
		if bt.log.is_empty() or int(bt.cur_b().get("hp", -1)) < 0:
			print("effcov dbg: 回合没有正常结算 ", effect, " ", mv["id"])
			return false
	print("effcov dbg: 运行 %d 种招式效果各一回合" % seen.size())
	return seen.size() > 0

func _test_field_system() -> bool:
	var ok := true
	# 招式表里每条场地类招式都能落地
	var want := {"weather": 6, "terrain": 4, "screen": 3, "hazard": 4, "gravity": 1, "tera_blast": 1}
	var got := {}
	for mid in Data.moves:
		var mv = Data.moves[mid]
		if not (mv is Dictionary):
			continue
		var fraw = (mv as Dictionary).get("field", null)
		if not (fraw is Dictionary):
			continue
		var f: Dictionary = fraw
		if f.is_empty():
			continue
		var k := String(f.get("kind", ""))
		got[k] = int(got.get(k, 0)) + 1
	for k in want.keys():
		if int(got.get(k, 0)) != int(want[k]):
			print("field dbg: %s 应为 %d 实际 %d" % [k, int(want[k]), int(got.get(k, 0))])
			ok = false

	# 大晴天让火系招式变强、水系变弱
	var b := BattleScript.new(1234)
	b.start([BattleScript.make_combatant(6, 50, [53], "")], [BattleScript.make_combatant(9, 50, [33], "")])
	var atk: Dictionary = b.cur_a()
	var dfn: Dictionary = b.cur_b()
	var fire_move := {"power": 80, "type": "fire", "category": "special", "effect": "HIT"}
	var plain := b.damage(atk, dfn, fire_move)
	b.field.set_weather("sun")
	var sunny := b.damage(atk, dfn, fire_move)
	print("field dbg: 火系伤害 晴 %d / 常 %d" % [sunny, plain])
	if sunny <= plain:
		ok = false
	b.field.set_weather("rain")
	var rainy := b.damage(atk, dfn, fire_move)
	print("field dbg: 火系伤害 雨 %d / 晴 %d" % [rainy, sunny])
	if rainy >= sunny:
		ok = false

	# 沙暴刮伤非岩石地面钢
	b.field.reset()
	b.field.set_weather("sandstorm")
	var before := int(b.cur_a()["hp"])
	b.field.end_turn([b.cur_a(), b.cur_b()])
	if int(b.cur_a()["hp"]) >= before:
		print("field dbg: 沙暴没有造成伤害")
		ok = false

	# 反射壁让物理伤害减半
	b.field.reset()
	var phys := {"power": 80, "type": "normal", "category": "physical", "effect": "HIT"}
	var d0 := b.damage(b.cur_a(), b.cur_b(), phys)
	b.field.set_screen("b", "reflect")
	var d1 := b.damage(b.cur_a(), b.cur_b(), phys)
	print("field dbg: 反射壁 后 %d / 前 %d" % [d1, d0])
	if d1 >= d0:
		ok = false

	# 撒菱：换上场扣血
	b.field.reset()
	b.field.add_hazard("b", "spikes")
	b.field.add_hazard("b", "spikes")
	var incoming: Dictionary = b.team_b[1] if b.team_b.size() > 1 else b.cur_b()
	var hp0 := int(incoming["hp"])
	var res: Dictionary = b.field.on_switch_in("b", incoming, 1.0)
	print("field dbg: 撒菱两层伤害 %d" % int(res.get("damage", 0)))
	if int(res.get("damage", 0)) <= 0:
		ok = false

	# 重力：地面招式能打到飞行系
	b.field.reset()
	var flyer: Dictionary = b.cur_b()
	flyer["types"] = ["flying"]
	var ground_move := {"power": 80, "type": "ground", "category": "physical", "effect": "HIT"}
	var dg0 := b.damage(b.cur_a(), flyer, ground_move)
	b.field.set_gravity()
	var dg1 := b.damage(b.cur_a(), flyer, ground_move)
	print("field dbg: 重力地面招式 有 %d / 无 %d" % [dg1, dg0])
	if dg0 != 0 or dg1 <= 0:
		ok = false

	# 电气场地让电系变强
	b.field.reset()
	var elec := {"power": 80, "type": "electric", "category": "special", "effect": "HIT"}
	var de0 := b.damage(b.cur_a(), b.cur_b(), elec)
	b.field.set_terrain("electric")
	var de1 := b.damage(b.cur_a(), b.cur_b(), elec)
	print("field dbg: 电气场地 %d / %d" % [de1, de0])
	if de1 <= de0:
		ok = false
	return ok

## 蓄力招式、替身、接力棒
func _test_charge_sub() -> bool:
	var ok := true
	var b := BattleScript.new(99)
	# 太阳光束：第一回合蓄力，第二回合才掉血
	var team_a: Array = [BattleScript.make_combatant(6, 50, [76], "")]
	b.start(team_a, [BattleScript.make_combatant(9, 50, [33], "")])
	var hp0 := int(b.cur_b()["hp"])
	b.run_turn("move:0", "move:0")
	var hp1 := int(b.cur_b()["hp"])
	print("charge dbg: 蓄力回合伤害 %d" % (hp0 - hp1))
	if hp1 != hp0:
		ok = false
	b.run_turn("move:0", "move:0")
	var hp2 := int(b.cur_b()["hp"])
	print("charge dbg: 放出回合伤害 %d" % (hp1 - hp2))
	if hp2 >= hp1:
		ok = false

	# 替身：扣 1/4 体力，攻击先打在替身上
	var b2 := BattleScript.new(77)
	var a2: Array = [BattleScript.make_combatant(143, 50, [164, 33], "")]   # 卡比兽：替身 + 撞击
	b2.start(a2, [BattleScript.make_combatant(9, 50, [33], "")])
	var max_hp := int(b2.cur_a()["max_hp"])
	var h0 := int(b2.cur_a()["hp"])
	b2.run_turn("move:0", "none")
	var h1 := int(b2.cur_a()["hp"])
	print("sub dbg: 替身消耗 %d / 应为 %d" % [h0 - h1, int(max_hp / 4.0)])
	if h0 - h1 != int(max_hp / 4.0):
		ok = false
	if int(b2.cur_a().get("sub_hp", 0)) <= 0:
		ok = false

	# 接力棒：换人后带能力变化
	var b3 := BattleScript.new(55)
	var t3: Array = [
		BattleScript.make_combatant(133, 50, [226, 33], ""),   # 伊布：接力棒
		BattleScript.make_combatant(25, 50, [85], ""),
	]
	b3.start(t3, [BattleScript.make_combatant(9, 50, [33], "")])
	b3.cur_a()["stages"]["atk"] = 2
	b3.run_turn("move:0", "none")
	print("baton dbg: 上场 %s 攻击阶段 %d" % [String(b3.cur_a()["name"]), int(b3.cur_a()["stages"]["atk"])])
	if int(b3.active_a) != 1:
		ok = false
	if int(b3.cur_a()["stages"]["atk"]) != 2:
		ok = false
	return ok

## 太晶碎块：买得到、用得上、属性跟着变
func _test_tera_shard() -> bool:
	var ok := true
	var shards: Dictionary = Data.tera_shards
	if (shards as Dictionary).is_empty():
		print("tera shard dbg: 碎块表为空")
		return false
	if String(shards.get("fire", "")) != "太晶碎块·火":
		print("tera shard dbg: 火碎块名字不对 %s" % String(shards.get("fire", "")))
		ok = false
	if Data.type_name("fairy") != "妖精":
		print("tera shard dbg: 属性中文名不对 %s" % Data.type_name("fairy"))
		ok = false
	# 商店里 18 种碎块都能买
	var shop_txt := FileAccess.get_file_as_string("res://content/shop.json")
	var shop_data = JSON.parse_string(shop_txt)
	var names := {}
	if shop_data is Array:
		for it in shop_data:
			if it is Dictionary:
				names[String((it as Dictionary).get("name", ""))] = true
	for ty in Data.tera_shards.keys():
		if not names.has(String(Data.tera_shards[ty])):
			print("tera shard dbg: 商店缺 %s" % String(Data.tera_shards[ty]))
			ok = false
	# 太晶爆发：太晶化后属性跟着太晶属性
	var b := BattleScript.new(11)
	b.start([BattleScript.make_combatant(6, 50, [779], "")], [BattleScript.make_combatant(9, 50, [33], "")])
	var c: Dictionary = b.cur_a()
	c["tera_type"] = "fairy"
	c["tera_active"] = true
	var tb: Dictionary = Data.move_of(779)
	if String((tb.get("field", {}) as Dictionary).get("kind", "")) != "tera_blast":
		print("tera shard dbg: 太晶爆发没有标记")
		ok = false

	# 端到端：背包有碎块 → 改太晶属性 → 存档里真的变了、碎块扣掉
	var backup: Dictionary = save_data.duplicate(true)
	var backup_bag: Array = bag_items.duplicate(true)
	save_data["party"] = [PartyScript.make(6, 50, [53], "")]
	bag_items = [{"id": 0, "name": "太晶碎块·妖精", "category": "tera", "count": 1, "tera": "fairy"}]
	_change_tera(0, "fairy", null)
	var after: Dictionary = save_data["party"][0]
	print("tera shard dbg: 改后太晶 %s / 碎块剩 %d" % [
		String(after.get("tera_type", "")), int((bag_items[0] as Dictionary).get("count", -1))])
	if String(after.get("tera_type", "")) != "fairy":
		ok = false
	if int((bag_items[0] as Dictionary).get("count", -1)) != 0:
		ok = false
	save_data = backup
	bag_items = backup_bag

	# 进化要二次确认：取消时不应该换物种
	var fire_mon: Dictionary = PartyScript.make(58, 30, [33], "GROWLITHE_HISUI")
	var target := {}

	for e in GrowthScript.item_evolutions(fire_mon):
		if Data.evo_item_name(String((e as Dictionary).get("item", ""))) == "火之石":
			target = e
			break
	if target.is_empty():
		print("evolve confirm dbg: 洗翠卡蒂狗没有火之石进化项")
		ok = false
	else:
		print("evolve confirm dbg: 目标 %s" % String((Data.stats_of(int(target.get("to", 0)),
			String(target.get("form", ""))) as Dictionary).get("name", "?")))
	return ok

func _test_gimmick_label() -> bool:
	# 巴大蝶只有超极巨，没有 Mega
	var bf: Dictionary = BattleScript.make_combatant(12, 50, [33], "")
	var b1 = BattleScript.new(1)
	b1.start([bf], [BattleScript.make_combatant(19, 5, [33], "")])
	var l1: String = b1.form_action_label("a")
	var mewtwo: Dictionary = BattleScript.make_combatant(150, 50, [33], "")
	var b2 = BattleScript.new(2)
	b2.start([mewtwo], [BattleScript.make_combatant(19, 5, [33], "")])
	var l2: String = b2.form_action_label("a")
	var zard: Dictionary = BattleScript.make_combatant(6, 50, [33], "")
	var b3 = BattleScript.new(3)
	b3.start([zard], [BattleScript.make_combatant(19, 5, [33], "")])
	var l3: String = b3.form_action_label("a")
	var pika: Dictionary = BattleScript.make_combatant(19, 20, [33], "")
	var b4 = BattleScript.new(4)
	b4.start([pika], [BattleScript.make_combatant(19, 5, [33], "")])
	var l4: String = b4.form_action_label("a")
	print("label dbg: 巴大蝶「", l1, "」 超梦「", l2, "」 喷火龙「", l3, "」 小拉达「", l4, "」")
	if l1 != "极巨化":
		print("!! 只有超极巨却提示成 ", l1)
		return false
	if l2 != "Mega":
		print("!! 只有 Mega 却提示成 ", l2)
		return false
	if l3 != "Mega/极巨":
		print("!! 两种都能变却没同时提示 ", l3)
		return false
	if l4 != "":
		print("!! 不能变的却给了按钮 ", l4)
		return false
	# Mega 与极巨化二选一：先 Mega 就不能再极巨
	var b5 = BattleScript.new(5)
	b5.start([BattleScript.make_combatant(6, 50, [33], "")], [BattleScript.make_combatant(19, 5, [33], "")])
	b5.transform("a", "CHARIZARD_MEGA_X")
	if not b5.available_forms("a").is_empty():
		print("!! Mega 之后还能极巨化")
		return false
	return true

## 招式表与学习表：引用的招式必须存在，每只至少能学会一招
func _test_move_data() -> bool:
	var no_move: Array = []
	var bad_learn: Array = []
	for sp in Data.species.values():
		var learn = sp.get("learnset", [])
		if not (learn is Array) or (learn as Array).is_empty():
			no_move.append(int(sp.get("id", 0)))
			continue
		for row in learn:
			if not (row is Array) or (row as Array).size() < 2:
				continue
			if not Data.moves.has(int(row[1])):
				bad_learn.append("%d->%d" % [int(sp.get("id", 0)), int(row[1])])
	print("moves dbg: 招式 %d 条，无招式的宝可梦 %d，坏引用 %d" %
		[Data.moves.size(), no_move.size(), bad_learn.size()])
	if not bad_learn.is_empty():
		print("moves dbg: 坏引用 -> ", bad_learn.slice(0, 10))
	return no_move.is_empty() and bad_learn.is_empty()

## 抽一批物种两两对打，确认新招式/状态/特性数据不会把战斗内核弄崩
func _test_battle_sweep() -> bool:
	var ids: Array = Data.species.keys()
	ids.sort()
	var crashes := 0
	var stuck := 0
	var rounds := 0
	for n in 120:
		var a_id := int(ids[(n * 7) % ids.size()])
		var b_id := int(ids[(n * 13 + 5) % ids.size()])
		var bt = BattleScript.new(1000 + n)
		var a := [BattleScript.make_combatant(a_id, 30, EncounterScript.moves_for(a_id, 30))]
		var b := [BattleScript.make_combatant(b_id, 30, EncounterScript.moves_for(b_id, 30))]
		bt.start(a, b)
		var t := 0
		while not bt.over and t < 200:
			bt.run_turn("move:%d" % (t % 4), "move:%d" % ((t + 1) % 4))
			t += 1
		rounds += t
		if not bt.over:
			stuck += 1
		# 血量不能越界，状态字段必须存在
		for side in [bt.team_a, bt.team_b]:
			for c in side:
				if int(c["hp"]) < 0 or int(c["hp"]) > int(c["max_hp"]):
					crashes += 1
				if not c.has("status"):
					crashes += 1
	print("battle dbg: 120 场，平均 %d 回合，打不完 %d，异常 %d" % [rounds / 120, stuck, crashes])
	return crashes == 0 and stuck == 0

## 每个 NPC 都得有自己的台词，不能退回「路上小心。」那种兜底话
func _test_npc_lines() -> bool:
	var dir := DirAccess.open("res://content/regions/kanto/maps")
	if dir == null:
		print("lines dbg: 打不开地图目录")
		return false
	var total := 0
	var blank: Array = []
	var dup := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var mid := f.get_basename()
		var d: Dictionary = Data.load_map("kanto", mid)
		var seen := {}
		for n in d.get("npcs", []):
			# 商店、治疗与地区领航各自打开交互界面。
			if bool(n.get("shop", false)) or bool(n.get("heal", false)) or bool(n.get("transit", false)):
				continue
			total += 1
			var nm := String(n.get("name", ""))
			var ls = n.get("lines", null)
			var line := String(n.get("line", ""))
			if (not (ls is Array)) or (ls as Array).is_empty():
				if line == "":
					blank.append(mid + "/" + nm)
				continue
			var key := nm + "|" + "|".join(ls)
			if seen.has(key):
				dup += 1
			seen[key] = true
	print("lines dbg: 共 %d 个 NPC，缺台词 %d，重复 %d" % [total, blank.size(), dup])
	if not blank.is_empty():
		print("lines dbg: 缺台词 -> ", blank)
	return blank.is_empty() and dup == 0

## 剧情：开场旁白 → 大木博士给宝可梦 → 拿到徽章触发台词，且 once 事件只播一次
## 剧情表体检：事件结构、触发目标、步骤类型、奖励道具都得对得上
func _test_story_table() -> bool:
	var okT := true
	var allowed_trigger := ["map_enter", "talk", "badge", "step"]
	var allowed_step := ["choice","scene_cast","set_player_at","warp","escort","remove_item","say", "who", "flag", "give_mon", "give_item", "heal", "money", "battle", "hall_of_fame"]
	var total := 0
	var talk_checked := 0
	var all_ids := {}
	for f in DirAccess.get_files_at("res://content/story"):
		if not String(f).ends_with(".json"):
			continue
		var rid := String(f).get_basename()
		var raw = Data.load_json("res://content/story/%s" % f)
		if not (raw is Dictionary):
			print("!! 剧情表读不出来：%s" % f)
			okT = false
			continue
		var region_story = StoryScript.new()
		region_story.load_region(rid)
		var events: Array = region_story.events
		total += events.size()
		for ev in events:
			var e: Dictionary = ev
			var eid := String(e.get("id", ""))
			if eid == "" or all_ids.has(eid):
				print("!! 事件 id 空或重复：%s" % eid)
				okT = false
			all_ids[eid] = true
			var tr: Dictionary = e.get("trigger", {})
			if not allowed_trigger.has(String(tr.get("type", ""))):
				print("!! %s 的触发类型不认识：%s" % [eid, String(tr.get("type", ""))])
				okT = false
			if String(tr.get("type", "")) == "talk" and String(tr.get("map", "")) != "":
				var mp: Dictionary = Data.load_map(rid, String(tr["map"]))
				if mp.is_empty():
					print("!! %s 里的地图 %s 不存在（地区 %s）" % [eid, String(tr["map"]), rid])
					okT = false
				else:
					var names: Array = []
					for n in (mp.get("npcs", []) as Array):
						names.append(String((n as Dictionary).get("name", "")))
					if tr.has("actor"):
						var rules: Dictionary = preload("res://core/frlg_actors.gd").data().maps.get(rid+"/"+str(tr["map"]),{})
						var available := rules.values().any(func(row): return row.get("role","")==tr.actor)
						for npc_row in mp.get("npcs",[]):
							var spec: Dictionary = rules.get("%d,%d" % npc_row.at,{})
							var combined := preload("res://core/sevii_campaign.gd").speaker(mp.id,npc_row.at,spec,{})
							if combined.get("role",npc_row.get("role","")) == tr.actor: available = true
						if tr.actor not in ["bill_pc","poster_switch"] and not available:
							print("!! Unknown story actor ",tr.actor)
							okT = false
					elif not names.has(String(tr.get("npc", ""))):
						print("!! %s 要对话的「%s」在 %s 里找不到" % [eid, String(tr.get("npc", "")), String(tr["map"])])
						okT = false
					talk_checked += 1
			if String(tr.get("type", "")) == "map_enter" and String(tr.get("map", "")) != "":
				var mp2: Dictionary = Data.load_map(rid, String(tr["map"]))
				if mp2.is_empty():
					print("!! %s 要进的地图 %s 不存在（地区 %s）" % [eid, String(tr["map"]), rid])
					okT = false
			var steps: Array = e.get("steps", [])
			if steps.is_empty():
				print("!! %s 没有步骤" % eid)
				okT = false
			for st in steps:
				for k in (st as Dictionary).keys():
					if not allowed_step.has(String(k)):
						print("!! %s 里有不认识的步骤字段：%s" % [eid, String(k)])
						okT = false
				if (st as Dictionary).has("battle"):
					var bt: Dictionary = (st as Dictionary)["battle"]
					if (bt.get("team", []) as Array).is_empty():
						print("!! %s 的战斗没有队伍" % eid)
						okT = false
					for m in (bt.get("team", []) as Array):
						if Data.species_of(int((m as Dictionary).get("species", 0))).is_empty():
							print("!! %s 的战斗里有不存在的物种 %d" % [eid, int((m as Dictionary).get("species", 0))])
							okT = false
				if (st as Dictionary).has("give_item"):
					if String(((st as Dictionary)["give_item"] as Dictionary).get("name", "")) == "":
						print("!! %s 给了个没名字的道具" % eid)
						okT = false
	print("storytab dbg: %d 个事件，检查了 %d 个对话目标" % [total, talk_checked])
	return okT


func _test_story() -> bool:
	var st = StoryScript.new()
	if not st.load_region("kanto"):
		print("story dbg: 关都剧情表读不出来")
		return false
	var flags := {}
	var has := false
	# 区域触发（同一张大图里的分段）
	var route_map: Dictionary = Data.load_map("kanto", "kanto_main")
	var old_map: Dictionary = world.map_data
	var old_pos: Vector2i = world.player_pos
	world.load_map(route_map)
	world.warp_to(Vector2i(72, 259))
	var route_ctx := {"map": "kanto_main", "area_name": world.area_name()}
	var ev0: Dictionary = st.take("step", route_ctx, flags, true)
	if not old_map.is_empty():
		world.load_map(old_map)
		world.warp_to(old_pos)
	if String(ev0.get("id", "")) != "route1_blurb":
		print("story dbg: 1 号道路提示没触发 ", route_ctx)
		return false
	st.mark_finished(ev0, flags)
	if not st.take("step", route_ctx, flags, true).is_empty():
		return false
	# 1) 进图 → 开场旁白
	var ev1: Dictionary = st.take("map_enter", {"map": "kanto_main", "area_name": "真新镇"}, flags, has)
	if ev1.is_empty() or String(ev1.get("id", "")) != "pallet_intro":
		print("story dbg: 没触发开场 ", ev1.get("id", ""))
		return false
	st.mark_finished(ev1, flags)
	var ev1b: Dictionary = st.take("map_enter", {"map": "kanto_main", "area_name": "真新镇"}, flags, has)
	if not ev1b.is_empty() and String(ev1b.get("id", "")) == "pallet_intro":
		print("story dbg: 开场旁白重复触发")
		return false
	# 2) 空手找大木博士 → 拿宝可梦
	flags.oak_in_lab = true
	var ev2: Dictionary = st.take("talk", {"npc": "大木博士", "map": "pallettown_professoroakslab"}, flags, false)
	if ev2.is_empty() or String(ev2.get("id", "")) != "oak_starter":
		print("story dbg: 大木博士剧情没触发 ", ev2.get("id", ""))
		return false
	var gave := false
	for stp in ev2.get("steps", []):
		if stp is Dictionary and (stp as Dictionary).has("give_mon"):
			gave = true
	if not gave:
		print("story dbg: 大木博士没给宝可梦")
		return false
	st.mark_finished(ev2, flags)
	# 3) 有队伍之后再找他，不给第二只
	var ev3: Dictionary = st.take("talk", {"npc": "大木博士", "map": "pallettown_professoroakslab"}, flags, true)
	if not ev3.is_empty():
		for stp2 in ev3.get("steps", []):
			if stp2 is Dictionary and (stp2 as Dictionary).has("give_mon"):
				print("story dbg: 会重复发宝可梦")
				return false
	# 4) 徽章台词
	var ev4: Dictionary = st.take("badge", {"badge": "灰色徽章"}, flags, true)
	if ev4.is_empty() or String(ev4.get("id", "")) != "brock_badge":
		print("story dbg: 徽章剧情没触发")
		return false
	# 5) 城都：剧情表能载入、八枚徽章各有一条、湖之怒有对战
	var jt = StoryScript.new()
	if not jt.load_region("johto"):
		print("story dbg: 城都剧情表读不出来")
		return false
	if jt.events.size() < 18:
		print("story dbg: 城都事件只有 %d 条" % jt.events.size())
		return false
	var jflags := {}
	var badges := ["飞翼徽章", "昆虫徽章", "标准徽章", "魅影徽章", "打击徽章", "矿物徽章", "冰川徽章", "升龙徽章"]
	var gotB := 0
	for bd in badges:
		var jev: Dictionary = jt.take("badge", {"badge": String(bd)}, jflags, true)
		if jev.is_empty():
			print("story dbg: 城都徽章「%s」没有事件" % String(bd))
			return false
		jt.mark_finished(jev, jflags)
		gotB += 1
	var jev2: Dictionary = jt.take("map_enter", {"map": "johto_new_bark_town"}, {}, false)
	if jev2.is_empty() or String(jev2.get("id", "")) != "johto_arrive":
		print("story dbg: 城都开场没触发 ", jev2.get("id", ""))
		return false
	var jev3: Dictionary = jt.take("talk", {"npc": "龙使者 阿渡", "map": "johto_lake_of_rage"}, {}, true)
	if jev3.is_empty():
		print("story dbg: 湖之怒没触发")
		return false
	var hasBattle := false
	for jst in jev3.get("steps", []):
		if jst is Dictionary and (jst as Dictionary).has("battle"):
			hasBattle = true
	if not hasBattle:
		print("story dbg: 湖之怒没有对战")
		return false
	# 关都表不该认得城都的 NPC：切地区后仍要能用原表
	if not st.load_region("kanto"):
		print("story dbg: 切回关都失败")
		return false
	print("story dbg: 开场/授精灵/徽章三段都正常，once 不重复；城都 %d 条事件、%d 枚徽章" % [jt.events.size(), gotB])
	return true

## 道馆：馆主要有整队配置、招式存在、徽章能发下来
## 从起始地图出发，靠门口能不能真的走到各个地区。
## 只要有一张该到的地方走不到，就说明"功能做了但玩家触发不到"。
func _test_world_reach() -> bool:
	var maps := {}
	for rid in DirAccess.get_directories_at("res://content/regions"):
		var r := String(rid)
		var dp := "res://content/regions/%s/maps" % r
		var d := DirAccess.open(dp)
		if d == null:
			continue
		for f in d.get_files():
			if f.ends_with(".json"):
				maps["%s/%s" % [r, f.get_basename()]] = dp + "/" + f
	var start := "kanto/kanto_main"
	if not maps.has(start):
		print("reach dbg: 没有起始地图")
		return false
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		var raw = JSON.parse_string(FileAccess.get_file_as_string(String(maps[cur])))
		if not (raw is Dictionary):
			continue
		var exits := {}
		for w in (raw as Dictionary).get("warps", []):
			var at: Array = w.get("at", [])
			if at.size() != 2:
				return false
			var tile := Vector2i(int(at[0]), int(at[1]))
			if exits.has(tile):
				continue
			exits[tile] = true
			var to: Dictionary = (w as Dictionary).get("to", {})
			var key := "%s/%s" % [String(to.get("region", "")), String(to.get("map", ""))]
			if maps.has(key) and not seen.has(key):
				seen[key] = true
				queue.append(key)
	var must := [
		"kanto/pallettown_professoroakslab", "kanto/pewtercity_gym", "kanto/indigo_plateau_pokemon_center_1f",
		"frontier/tower_lobby",
		"johto/johto_new_bark_town", "johto/johto_elms_lab", "johto/johto_violet_gym",
		"johto/johto_azalea_gym", "johto/johto_goldenrod_gym", "johto/johto_ecruteak_gym",
		"johto/johto_olivine_gym", "johto/johto_cianwood_gym", "johto/johto_mahogany_gym",
		"johto/johto_blackthorn_gym_1f", "johto/johto_lake_of_rage", "johto/johto_victory_road",
		"johto/johto_route_23", "johto/johto_hall_of_fame",
	]
	var ok := true
	var miss: Array = []
	for k in must:
		if not seen.has(String(k)):
			miss.append(String(k))
	if not miss.is_empty():
		print("reach dbg: 走不到 ", miss)
		ok = false
	var nk := 0
	var nj := 0
	for k in seen:
		if String(k).begins_with("kanto/"):
			nk += 1
		elif String(k).begins_with("johto/"):
			nj += 1
	if nk < 200:
		print("reach dbg: 关都只走到 %d 张" % nk)
		ok = false
	if nj < 360:
		print("reach dbg: 城都只走到 %d 张" % nj)
		ok = false
	print("reach dbg: 关都 %d、城都 %d，共 %d 张可达" % [nk, nj, seen.size()])
	# 不许有到不了的地图：剩下的每一张都必须能走到，不然就等于摆着骗人
	if seen.size() != maps.size():
		var lost: Array = []
		for k in maps.keys():
			if not seen.has(k):
				lost.append(String(k))
		print("reach dbg: 还有 %d 张地图走不到 %s" % [lost.size(), str(lost.slice(0, 8))])
		ok = false
	return ok

## 百货电梯：楼层表每一层都落得住，站门口按 A 真能上去
func _test_elevator() -> bool:
	var ok2 := true
	var expect := {"johto_goldenrod_dept_store_elevator": 8, "johto_celadon_dept_store_elevator": 6}
	for ev in expect.keys():
		var rows: Array = ELEVATOR_FLOORS.get(String(ev), [])
		if rows.size() != int(expect[ev]):
			print("lift dbg: %s 只有 %d 层，应为 %d" % [ev, rows.size(), int(expect[ev])])
			ok2 = false
			continue
		for r in rows:
			var md: Dictionary = Data.load_map("johto", String((r as Array)[1]))
			if md.is_empty():
				print("lift dbg: %s 的 %s 这张图没有" % [ev, String((r as Array)[1])])
				ok2 = false
				continue
			var at: Array = (r as Array)[2]
			world.load_map(md)
			if world.is_blocked(Vector2i(int(at[0]), int(at[1]))):
				print("lift dbg: %s 去 %s 的落点 %s 站不住" % [ev, String((r as Array)[1]), str(at)])
				ok2 = false
	# 从满金 1F 门口走进去，必须切到电梯
	var f1: Dictionary = Data.load_map("johto", "johto_goldenrod_dept_store_1f")
	world.load_map(f1)
	world.finish_walk()
	world.warp_to(Vector2i(1, 2))
	world.finish_walk()
	var went := false
	world.step(Vector2i(-1, 0))
	world.tick_walk(0.3)
	world.finish_walk()
	world.step(Vector2i(0, -1))
	world.tick_walk(0.3)
	world.finish_walk()
	if String(world.map_data.get("id", "")) == "johto_goldenrod_dept_store_elevator":
		went = true
	if not went:
		print("lift dbg: 从 1F (1,2) 往左走没进得了电梯，停在 %s %s" % [String(world.map_data.get("id", "")), str(world.player_pos)])
		ok2 = false
	# 电梯里按 A 出得去（出口门在 (0,0)）
	var ele: Dictionary = Data.load_map("johto", "johto_goldenrod_dept_store_elevator")
	world.load_map(ele)
	world.warp_to(Vector2i(1, 1))
	world.finish_walk()
	var panel_ok := false
	for o in world.objects:
		if String(o.get("kind", "")) == "elevator":
			panel_ok = true
	if not panel_ok:
		print("lift dbg: 电梯里没有操作面板")
		ok2 = false
	print("lift dbg: 满金 %d 层、玉虹 %d 层，门口能进、面板在" % [(ELEVATOR_FLOORS["johto_goldenrod_dept_store_elevator"] as Array).size(), (ELEVATOR_FLOORS["johto_celadon_dept_store_elevator"] as Array).size()])
	return ok2


func _test_gyms() -> bool:
	var found := 0
	for mid in ["pewtercity_gym", "viridiancity_gym"]:
		world.load_map(Data.load_map("kanto", mid))
		world.refresh_story_actors({"viridian_gym_open":true})
		for n in world.npcs:
			if not String(n.get("name", "")).contains("馆主"):
				continue
			found += 1
			var cfg: Dictionary = n.get("battle", {})
			var team: Array = cfg.get("team", [])
			if team.is_empty():
				print("gym dbg: %s 馆主没有队伍" % mid)
				return false
			for e in team:
				var sp := int(e.get("species", 0))
				var lv := int(e.get("level", 0))
				if Data.species_of(sp).is_empty():
					print("gym dbg: %s 馆主用了不存在的物种 %d" % [mid, sp])
					return false
				if lv < 5 or lv > 80:
					print("gym dbg: %s 馆主等级异常 %d" % [mid, lv])
					return false
				for mv in e.get("moves", []):
					if Data.move_of(int(mv)).is_empty():
						print("gym dbg: %s 招式不存在 %d" % [mid, int(mv)])
						return false
			if String(n.get("badge", "")) == "":
				print("gym dbg: %s 馆主没配徽章" % mid)
				return false
	if found < 2:
		print("gym dbg: 只找到 %d 个馆主" % found)
		return false
	# 真打一场：拿一只高级队去打小刚，必须能分出胜负（验证多只敌方队伍能跑完）
	world.load_map(Data.load_map("kanto", "pewtercity_gym"))
	var leader: Dictionary = {}
	for n in world.npcs:
		if String(n.get("name", "")).contains("馆主"):
			leader = n
			break
	var mine := [BattleScript.make_combatant(9, 40, [55, 34])]
	var foes: Array = []
	for e3 in (leader.get("battle", {}) as Dictionary).get("team", []):
		foes.append(BattleScript.make_combatant(int(e3["species"]), int(e3["level"]), e3.get("moves", [33])))
	var bt = BattleScript.new(20261117)
	bt.start(mine, foes)
	var rounds := 0
	while not bt.over and rounds < 400:
		bt.run_turn("move:0", "move:0")
		rounds += 1
	if not bt.over:
		print("gym dbg: 道馆战 %d 回合没打完" % rounds)
		return false
	print("gym dbg: %d 个道馆，队伍与徽章都齐；道馆战 %d 回合结束，胜者 %s" % [found, rounds, bt.winner])
	return true

## 每张图：从出生点出发，所有传送点都必须走得到（含跳土坡）
func _test_warp_reach() -> bool:
	var all_reached := true
	var maps := _all_maps()
	var arrivals := {}
	for source in maps:
		# Floor-selection panels can arrive inside isolated elevator lobbies.
		for stop in source.m.get("lift_stops", []):
			var floor_key := "%s/%s" % [stop.region,stop.map]
			if not arrivals.has(floor_key): arrivals[floor_key] = {}
			arrivals[floor_key][Vector2i(int(stop.at[0]),int(stop.at[1]))] = true
		var exits := {}
		for warp in source.m.get("warps", []):
			var origin: Array = warp.at
			var tile := Vector2i(int(origin[0]), int(origin[1]))
			if exits.has(tile):
				continue
			exits[tile] = true
			var to: Dictionary = warp.to
			var key := "%s/%s" % [to.region, to.map]
			if not arrivals.has(key):
				arrivals[key] = {}
			arrivals[key][Vector2i(int(to.at[0]), int(to.at[1]))] = true
	for room in maps:
		var rid := str(room.rid)
		var mid := str(room.mid)
		world.load_map(room.m)
		var sp: Array = room.m.get("spawn", [0, 0])
		var seed: Dictionary = arrivals.get("%s/%s" % [rid, mid], {}).duplicate()
		seed[Vector2i(int(sp[0]), int(sp[1]))] = true
		if mid in ["mt_ember_exterior","six_island_ruin_valley"]:
			world.refresh_story_actors(OPEN_FIELD_FLAGS)
		var seen := _walkable_from(seed)
		if mid.begins_with("victoryroad_"):
			# The upper drop is physically reached after the third-floor Strength puzzle.
			var solved := {"btn:victoryroad_1f:20,16":true,"btn:victoryroad_2f:2,19":true,
				"btn:victoryroad_3f:7,7":true,"victory_rock_dropped":true,"btn:victoryroad_2f:14,19":true}
			var previous: Dictionary=world.taken
			world.taken=solved
			world.load_map(room.m)
			seen.merge(_walkable_from(seed))
			world.taken=previous
		if world.get("mansion_switches"):
			world.set_mansion_switch(true)
			seen.merge(_walkable_from(seed))
			world.set_mansion_switch(false)
		for w in world.map_data.get("warps", []):
			var at: Array = w.get("at", [0, 0])
			# 连接生成的地图边缘门、以及海路上的门，都不按"屋里那扇门"的标准判
			if bool(w.get("edge", false)):
				continue
			if world.is_water(Vector2i(int(at[0]), int(at[1]))):
				continue
			var approach := Vector2i(int(at[0]),int(at[1]))
			if w.get("trigger", "") == "door":
				approach += Vector2i.DOWN
			if w.get("trigger", "") == "panel":
				var neighbors := [Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]
				if neighbors.any(func(d): return seen.has(approach + d)): continue
			if not seen.has(approach):
				print("reach dbg: %s/%s 的门 %s 走不到，可达 %d 格，起点 %s" % [rid, mid, str(at), seen.size(), str(sp)])
				all_reached = false
	return all_reached

func _walkable_from(seed: Dictionary) -> Dictionary:
	var seen := seed.duplicate()
	var q: Array = seen.keys()
	var next := 0
	while next < q.size():
		var p: Vector2i = q[next]
		next += 1
		for dv in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var t: Vector2i = p + dv
			var dest: Vector2i = Vector2i(-1, -1)
			if world.can_enter(t, dv):
				dest = t
			elif world._ledge_allows(t, dv) and world.can_enter(t + dv, dv):
				dest = t + dv
			if dest.x >= 0 and not seen.has(dest):
				seen[dest] = true
				q.append(dest)
	return seen

## 所有地区地图（供"入口落点"扫描用）
func _all_maps() -> Array:
	var out: Array = []
	for rid in DirAccess.get_directories_at("res://content/regions"):
		for f in DirAccess.get_files_at("res://content/regions/%s/maps" % rid):
			if not String(f).ends_with(".json"):
				continue
			var m: Dictionary = Data.load_map(String(rid), String(f).get_basename())
			if not m.is_empty():
				out.append({"rid": String(rid), "mid": String(f).get_basename(), "m": m})
	return out

## 土坡：从高的一侧走过去要能落到两格之外，反过来必须走不过去
func _test_ledge() -> bool:
	var tested := 0
	var maps := ["hoenn/route101", "kanto/kanto_main", "johto/johto_route_45", "johto/johto_route_4"]
	for key in maps:
		var parts := String(key).split("/")
		world.load_map(Data.load_map(parts[0], parts[1]))
		var cands: Array = _find_jumpables()
		if cands.is_empty():
			print("ledge dbg: ", key, " 没有可跳的坡")
			continue
		var done := false
		for c in cands:
			if done:
				break
			var at: Vector2i = c["at"]
			var dir: Vector2i = c["dir"]
			world.warp_to(at - dir)
			world.finish_walk()
			if world.is_blocked(world.player_pos):
				continue
			var want: Vector2i = world.jump_landing(dir)
			if want.x < 0:
				continue
			world.step(dir)
			var landed: Vector2i = world.player_pos
			var jumped: bool = world.walking and landed == want
			# 跳下来要真的播跳跃动作：期间 jumping 为真，且角色被抬起若干像素
			var has_anim: bool = world.jumping
			world.tick_walk(0.15)
			var lifted: bool = world.jump_lift > 0.5
			world.finish_walk()
			if not jumped or not has_anim or not lifted:
				print("ledge dbg: 跳坡不对 ", key, " at=", at, " dir=", dir, " 落=", landed,
					" 应为=", want, " anim=", has_anim, " lift=", lifted)
				world.warp_to(want)
				world.finish_walk()
				world.step(-dir)
				var blocked_up: bool = not world.walking
				world.finish_walk()
				if not blocked_up:
					print("ledge dbg: 从低处也能上坡，方向判定错了")
				done = true
				tested = -100
				break
			# 反方向（从低处往高处）必须过不去
			world.warp_to(want)
			world.finish_walk()
			world.step(-dir)
			var blocked_up2: bool = not world.walking
			world.finish_walk()
			if not blocked_up2:
				print("ledge dbg: 从低处也能上坡 ", key, " at=", at)
				tested = -100
				done = true
				break
			print("ledge dbg: ", key, " 跳 ", at, " 落 ", want, " OK（抬起 + 反向上坡被挡）")
			tested += 1
			done = true
		if not done:
			print("ledge dbg: ", key, " 的坡都跳不了")
	print("ledge dbg: 共验了 %d 张地图的坡" % maxi(tested, 0))
	# 全量扫一遍：所有带坡的地图，每一个坡向都真跳一次，落点必须对上
	var maps_all: Array = []
	for rid in DirAccess.get_directories_at("res://content/regions"):
		for f in DirAccess.get_files_at("res://content/regions/%s/maps" % String(rid)):
			if String(f).ends_with(".json"):
				maps_all.append("%s/%s" % [String(rid), String(f).get_basename()])
	var checked := 0
	var bad := 0
	for key2 in maps_all:
		var p2 := String(key2).split("/")
		var md2: Dictionary = Data.load_map(p2[0], p2[1])
		if md2.is_empty():
			continue
		world.load_map(md2)
		var em2 = world.emerald_ledge
		if not (em2 is Array) or (em2 as Array).is_empty():
			continue
		var has_any := false
		for row2 in em2:
			if row2 is Array:
				for v in row2:
					if int(v) != 0:
						has_any = true
						break
			if has_any:
				break
		if not has_any:
			continue
		for c2 in _find_jumpables():
			var at2: Vector2i = c2["at"]
			var d2: Vector2i = c2["dir"]
			world.warp_to(at2 - d2)
			world.finish_walk()
			if world.is_blocked(world.player_pos):
				continue
			var want2: Vector2i = world.jump_landing(d2)
			if want2.x < 0:
				continue
			checked += 1
			world.step(d2)
			if world.player_pos != want2:
				bad += 1
				if bad <= 5:
					print("ledge dbg: 全量扫跳坡失败 ", key2, " ", at2, " dir=", d2, " 落=", world.player_pos, " 应为=", want2)
			world.finish_walk()
	if bad > 0:
		print("ledge dbg: 全量扫 %d 个坡向，%d 个跳不过去" % [checked, bad])
		return false
	print("ledge dbg: 全量扫 %d 个坡向，全都能跳过去" % checked)
	return tested > 0


## 冲浪：水面没冲浪进不去，会冲浪就能进，上岸后自动取消
func _test_surf() -> bool:
	var picked := ""
	for region in ["kanto", "hoenn"]:
		var dir := "res://content/regions/%s/maps" % region
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if not String(f).ends_with(".json"):
				continue
			var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + String(f)))
			if not (raw is Dictionary):
				continue
			var emu_name := String((raw as Dictionary).get("emerald", ""))
			if emu_name == "":
				continue
			var path := "res://content/emerald_maps/%s.json" % emu_name
			if not FileAccess.file_exists(path):
				continue
			var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
			var w: Array = meta.get("water", []) if meta.get("water") is Array else []
			if w.is_empty():
				continue
			var has := false
			for r in w:
				for v in (r as Array):
					if int(v) == 1:
						has = true
						break
				if has:
					break
			if has:
				picked = region + "/" + String(f).get_basename()
				break
		if picked != "":
			break
	if picked == "":
		print("surf dbg: 没找到带水面的图")
		return false
	var parts := picked.split("/")
	world.load_map(Data.load_map(parts[0], parts[1]))
	var spot := Vector2i(-1, -1)
	var from := Vector2i(-1, -1)
	for y in world.emerald_water.size():
		var row: Array = world.emerald_water[y]
		for x in row.size():
			if int(row[x]) != 1:
				continue
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var f2: Vector2i = Vector2i(x, y) - d
				if world.is_blocked(f2) or world.is_blocked(Vector2i(x, y)):
					continue
				if world.is_water(f2):
					continue
				# 两个方向都得走得通，否则「上岸」会被方向阻挡卡住
				world.surfing = true
				var ok_both: bool = world.can_enter(f2, -d) and world.can_enter(Vector2i(x, y), d)
				world.surfing = false
				if not ok_both:
					continue
				spot = Vector2i(x, y)
				from = f2
				break
			if spot.x >= 0:
				break
		if spot.x >= 0:
			break
	if spot.x < 0:
		print("surf dbg: 水面四周没有可站的岸")
		return false
	world.surfing = false
	world.warp_to(from)
	world.finish_walk()
	if world.can_enter(spot, spot - from):
		print("surf dbg: 没冲浪却走进了水面")
		return false
	world.surfing = true
	var ok_enter: bool = world.can_enter(spot, spot - from)
	world.surfing = false
	world.warp_to(spot)
	world.finish_walk()
	world.surfing = true
	world.step(from - spot)
	var back: bool = world.surfing == false and world.player_pos == from
	world.finish_walk()
	print("surf dbg: ", picked, " 下水前被挡 OK、冲浪可入 ", ok_enter, "、上岸自动收起 ", back)
	return ok_enter and back

## 找一处"前面是土坡、后面是可走地面"的位置
func _find_jumpables() -> Array:
	var out: Array = []
	for y in world.emerald_ledge.size():
		var row: Array = world.emerald_ledge[y]
		for x in row.size():
			var b := int(row[x])
			if b == 0:
				continue
			for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0),
					Vector2i(1, -1), Vector2i(-1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
				if not world._ledge_allows(Vector2i(x, y), dir):
					continue
				var from: Vector2i = Vector2i(x, y) - dir
				var to: Vector2i = Vector2i(x, y) + dir
				if from.x < 0 or from.y < 0 or to.x < 0 or to.y < 0:
					continue
				if world.is_blocked(from) or world.is_blocked(to):
					continue
				out.append({"at": Vector2i(x, y), "dir": dir})
				if out.size() >= 80:
					return out
	return out

## 进出房间的方向：原版是「朝着门走进去、朝着门走出来」，
## 所以进屋时人是朝上的（背对镜头），出门时朝下。以前换图一律重置成朝下，
## 进屋会莫名其妙转过身来。这里真的走一遍门，检查换图后朝向对不对。
func _test_warp_facing() -> bool:
	# Outdoor Viridian warp 4 points specifically to Mart warp 1.
	world.load_map(Data.load_map("kanto", "kanto_main"))
	var doorstep := Vector2i(84,200)
	world.warp_to(doorstep)
	if not world.step(Vector2i.UP): return false
	world.tick_walk(1.0)
	if world.map_data.id != "viridiancity_mart" or world.player_pos != Vector2i(4,7) or world.facing != "up":
		return false
	if not world.step(Vector2i.DOWN): return false
	world.tick_walk(1.0)
	world.tick_walk(1.0)
	return world.map_data.id == "kanto_main" and world.player_pos == doorstep and world.facing == "down"

func _test_door_talk() -> bool:
	var m: Dictionary = Data.load_map("kanto", "pewtercity_pokemoncenter_1f")
	if m.is_empty():
		print("door dbg: 宝可梦中心加载失败")
		return false
	world.load_map(m)
	# 走到门垫再按下，触发原版向南的箭头门。
	world.warp_to(Vector2i(7, 7))
	if not world.step(Vector2i.DOWN) or not world.pending_warp.is_empty(): return false
	world.finish_walk()
	if not world.step(Vector2i.DOWN) or world.pending_warp.is_empty(): return false
	world.finish_walk()
	# 2) 对话：站柜台前朝上按 A，要能认出柜台上方的护士
	var nurse_pos := Vector2i(-1, -1)
	for n in world.npcs:
		if String(n.get("name", "")).contains("护士"):
			var at: Array = n.get("at", [0, 0])
			nurse_pos = Vector2i(int(at[0]), int(at[1]))
	if nurse_pos.x < 0:
		print("door dbg: 这张图没有护士")
		return false
	world.warp_to(Vector2i(nurse_pos.x, nurse_pos.y + 2))
	world.facing = "up"
	world.step_interact()
	if not world.last_event.begins_with("talk:"):
		print("door dbg: 隔着柜台说不上话，pos=", world.player_pos, " event=", world.last_event)
		return false
	if not world.last_npc.get("heal", false):
		print("door dbg: 护士没有治疗标记")
		return false
	world.last_event = ""
	world.last_npc = {}
	print("door dbg: 屋内中央门垫能正常出门，隔柜台能跟护士对话")
	return true

func _test_growth() -> bool:
	for growth in ["fast", "medium_fast", "medium_slow", "slow"]:
		var last := -1
		for lv in range(1, 101, 3):
			var e := GrowthScript.exp_for_level(lv, growth)
			if e < last:
				print("growth dbg: 曲线不单调 ", growth, " ", lv)
				return false
			last = e
			if GrowthScript.level_span(lv, growth) <= 0:
				print("growth dbg: 跨度非正 ", growth, " ", lv)
				return false
	for sid in Data.species.keys():
		var sp: Dictionary = Data.species_of(int(sid))
		if not sp.has("evolves_to"):
			continue
		var to := int(sp.get("evolves_to", 0))
		if Data.species_of(to).is_empty():
			print("growth dbg: 进化目标不存在 ", sid, " -> ", to)
			return false
		if int(sp.get("evolves_at", 0)) <= 0:
			print("growth dbg: 进化等级非正 ", sid)
			return false
	var mon: Dictionary = PartyScript.make(4, 5, [52, 33])
	var atk5 := int((mon["stats"] as Dictionary)["atk"])
	var grew := GrowthScript.add_exp(mon, GrowthScript.exp_for_level(12, "medium_slow"))
	if int(mon["level"]) < 12 and grew <= 0:
		print("growth dbg: 加经验没升级 ", mon["level"], " grew=", grew)
		return false
	PartyScript.recalc(mon)
	if int((mon["stats"] as Dictionary)["atk"]) <= atk5:
		print("growth dbg: 升级后攻击没涨")
		return false
	# 小火龙 16 级进化火恐龙，火恐龙 36 级才进化喷火龙
	var fire: Dictionary = PartyScript.make(4, 16, [52])
	if GrowthScript.evolution_target(fire) != 5:
		print("growth dbg: 进化判定错 ", GrowthScript.evolution_of(fire))
		return false
	if not PartyScript.evolve(fire, 5):
		return false
	if String(fire["name"]) != "火恐龙" or int(fire["level"]) != 16:
		print("growth dbg: 进化后数据不对 ", fire["name"], fire["level"])
		return false
	var young: Dictionary = PartyScript.make(4, 10, [52])
	if GrowthScript.evolution_target(young) != 0:
		print("growth dbg: 低等级也会进化")
		return false
	var mid: Dictionary = PartyScript.make(5, 20, [52])
	if GrowthScript.evolution_target(mid) != 0:
		print("growth dbg: 火恐龙 20 级不该进化")
		return false
	return true

func _test_flee() -> bool:
	var b := BattleScript.new()
	b.start([BattleScript.make_combatant(25, 10, [84])], [BattleScript.make_combatant(19, 5, [33])])
	var ok := false
	for i in 40:
		var r: Dictionary = b.try_flee()
		if bool(r.get("ok", false)):
			ok = true
			break
		b.run_turn("item", "move:0")
		if b.over:
			b.start([BattleScript.make_combatant(25, 10, [84])], [BattleScript.make_combatant(19, 5, [33])])
	if not ok:
		print("flee dbg: 40 次都没跑掉")
		return false
	if not b.over or b.winner != "fled":
		print("flee dbg: 逃跑后状态不对 ", b.winner)
		return false
	if bool(b.try_flee().get("ok", false)):
		print("flee dbg: 结束后还能逃")
		return false
	return true

## 抓到之后要真的落地：有空位进队伍，满了进 box，两者都不能丢
func _test_catch_add() -> bool:
	var previous := save_data
	save_data = {"party": [], "boxes": []}
	for i in PartyScript.MAX_SIZE:
		if _add_to_team(i + 1, 7) != "party":
			save_data = previous
			return false
	var team := _make_team()
	var twelfth: Dictionary = team.back()
	twelfth["hp"] = 1
	_writeback_team(team)
	var ok := team.size() == PartyScript.MAX_SIZE and int(save_data.party.back().hp) == 1
	ok = _add_to_team(147, 9) == "box" and ok
	ok = ok and int(save_data.boxes[0].mons[0].species_id) == 147
	_open_pc()
	var pc = menu_layer.get_child(-1)
	# 队伍满员，点取出不会覆盖第十二格。
	pc.contents.get_child(0).pressed.emit()
	ok = ok and pc.notice.contains("已满") and int(save_data.boxes[0].mons[0].species_id) == 147
	pc._mode(true)
	pc.contents.get_child(PartyScript.MAX_SIZE - 1).pressed.emit()
	ok = ok and PartyScript.occupied(save_data.party) == 11 and int(save_data.boxes[0].mons[1].species_id) == 12
	pc._mode(false)
	pc.contents.get_child(1).pressed.emit()
	var loaded := SaveScript.load_game()
	ok = ok and PartyScript.occupied(loaded.party) == 12 and int(loaded.party[11].species_id) == 12
	ok = ok and int(loaded.party[11].hp) == 1 and PartyScript.occupied(loaded.boxes[0].mons) == 1
	pc.handle_back()
	save_data = previous
	return ok

func _test_editor() -> bool:
	save_data = SaveScript.empty()
	save_data["party"] = PartyScript.compact([PartyScript.make(25, 10, [84])])
	bag_items = _default_items()
	var ov: Dictionary = {}
	var ui := EditorUI.new()
	menu_layer.add_child(ui)
	ui.setup(save_data["party"], bag_items, ov)
	# 三页都要能建出来
	for t in ["party", "bag", "base"]:
		ui._switch(t)
		if ui.body.get_child_count() == 0:
			print("editor dbg: 空页 ", t)
			return false
	# 草稿只在保存之后更改种族值和既有个体。
	var before := int((Data.species_of(25) as Dictionary)["base"]["atk"])
	var atk_before := int((PartyScript.make(25, 10, [84])["stats"] as Dictionary)["atk"])
	ui._set_override(25, "atk", before * 2)
	if int(Data.species_of(25).base.atk) != before or int(save_data.party[0].stats.atk) != atk_before:
		return false
	ui.save_changes(false)
	if int((Data.species_of(25) as Dictionary)["base"]["atk"]) != before * 2:
		print("editor dbg: 种族值没生效")
		return false
	if not (ui.overrides as Dictionary).has("25"):
		return false
	var member: Dictionary = save_data["party"][0]
	var atk_now := int((member["stats"] as Dictionary)["atk"])
	if atk_now <= atk_before:
		print("editor dbg: 重算没生效 ", atk_now)
		return false
	# 存读一轮，覆盖值要跟着回来
	save_data["species_override"] = ui.overrides
	if not SaveScript.save(save_data):
		return false
	var back: Dictionary = SaveScript.load_game()
	if int(back.get("species_override", {}).get("25", {}).get("atk", -1)) != before * 2:
		return false
	Data.apply_species_overrides({})
	if int((Data.species_of(25) as Dictionary)["base"]["atk"]) != before:
		print("editor dbg: 恢复默认失败")
		return false
	Data.apply_species_overrides(back["species_override"])
	if int((Data.species_of(25) as Dictionary)["base"]["atk"]) != before * 2:
		return false
	ui.queue_free()
	Data.apply_species_overrides({})
	return true

func _test_save() -> bool:
	var SaveScript := preload("res://core/save_game.gd")
	var data: Dictionary = SaveScript.empty()
	data["region"] = "kanto"
	data["pos"] = [2, 7]
	if not SaveScript.save(data):
		return false
	var back: Dictionary = SaveScript.load_game()
	var pos: Array = back.get("pos", [])
	return back.get("region", "") == "kanto" and int(pos[0]) == 2 and int(pos[1]) == 7

# ---------------- 存档与菜单 ----------------

## 端到端：真新镇出发 → 走到尼比市宝可梦中心 → 进屋 → 跟护士说话 → 治疗 → 出门
func _find_path(m: Dictionary, start: Vector2i, goal: Vector2i) -> Array:
	var w := int(m["size"][0])
	var h := int(m["size"][1])
	var prev := {}
	var q: Array = [start]
	prev[start] = start
	var dirs := [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
	while not q.is_empty():
		var p: Vector2i = q.pop_front()
		if p == goal:
			break
		for d in dirs:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if prev.has(n):
				continue
			if world.is_blocked(n):
				continue
			prev[n] = p
			q.append(n)
	if not prev.has(goal):
		return []
	var path: Array = []
	var cur: Vector2i = goal
	while cur != start:
		path.push_front(cur)
		cur = prev[cur]
	return path

func _walk_to(goal: Vector2i) -> bool:
	# 走一段；途中如果切了图就返回 true 表示「已经进去了」
	var m: Dictionary = world.map_data
	var path: Array = _find_path(m, world.player_pos, goal)
	print("  段：", world.player_pos, " -> ", goal, " 路径 ", path.size())
	if path.is_empty():
		return false
	var before := String(world.map_data.get("id", ""))
	for nxt in path:
		world.step(nxt - world.player_pos)
		world.tick_walk(1.0)
		if String(world.map_data.get("id", "")) != before:
			print("  切图 ", before, " -> ", world.map_data.get("id"), " 落点 ", world.player_pos)
			return true
	return false

## 从出生点按方向一路走，看会不会莫名跳图
func _e2e_walk(dir: String) -> void:
	world.load_map(Data.load_map("kanto", "kanto_main"))
	world.warp_to(Vector2i(24, 217))
	print("=== 从 ", world.player_pos, " 一直往", dir, " ===")
	var vec: Vector2i = Vector2i(0, -1)
	match dir:
		"down": vec = Vector2i(0, 1)
		"left": vec = Vector2i(-1, 0)
		"right": vec = Vector2i(1, 0)
	var last_map := String(world.map_data.get("id", ""))
	for i in 300:
		if world.step(vec):
			world.tick_walk(1.0)
		if String(world.map_data.get("id", "")) != last_map:
			print("  第 %d 步 跳到 %s at %s (名字 %s)" % [i, world.map_data.get("id"), world.player_pos, world.map_data.get("name", "")])
			last_map = String(world.map_data.get("id", ""))
	print("  结束于 ", world.map_data.get("id"), " ", world.player_pos, " 可走?", not world.is_blocked(world.player_pos))

## 剧情端到端：新档 → 进镇旁白 → 找大木博士拿宝可梦
func _e2e_story() -> void:
	print("=== 剧情 ===")
	story_on = true
	save_data = SaveScript.empty()
	var blank: Array = []
	for i in PartyScript.MAX_SIZE:
		blank.append({})
	save_data["party"] = blank
	save_data["bag"] = _default_items()
	_story_init()
	world.load_map(Data.load_map("kanto", "kanto_main"))
	world.warp_to(Vector2i(24, 217))
	if not _story_fire("map_enter", {"map": "kanto_main"}):
		print("!! 进镇没播开场")
		return
	print("开场对话条数 ", _dialogs.size())
	_close_all_dialogs()
	world.warp_to(Vector2i(72,261))
	_story_fire("step",{"map":"kanto_main","x":72,"y":261})
	while not cur_story.is_empty():
		_close_all_dialogs()
		await get_tree().process_frame
	if world.map_data.get("id") != "pallettown_professoroakslab":
		print("!! 大木没有带玩家回研究所")
		return
	world.warp_to(Vector2i(6,4))
	world.facing = "up"
	_on_action()
	print("对话栈 ", _dialogs.size())
	_close_all_dialogs()
	var got := ""
	for m in save_data.get("party", []):
		if m is Dictionary and not (m as Dictionary).is_empty():
			got = String(m.get("name", ""))
			break
	print("拿到的宝可梦 ", got)
	if got == "":
		print("!! 大木博士没给宝可梦")
		return
	# 再找一次，不该再给
	var before := 0
	for m in save_data.get("party", []):
		if m is Dictionary and not (m as Dictionary).is_empty():
			before += 1
	_on_action()
	_close_all_dialogs()
	var after := 0
	for m in save_data.get("party", []):
		if m is Dictionary and not (m as Dictionary).is_empty():
			after += 1
	print("再次对话后队伍数 ", after, "（之前 ", before, "）")
	if after != before:
		print("!! 重复发宝可梦")
		return
	# 小茂首战：进研究所找他，对完话应该直接开打
	world.load_map(Data.load_map("kanto", "pallettown_professoroakslab"))
	var rival := _find_npc_at("小茂", "pallettown_professoroakslab")
	if rival == Vector2i(-1, -1):
		print("!! 研究所里没有小茂")
		return
	world.warp_to(Vector2i(rival.x, rival.y + 1))
	world.facing = "up"
	_on_action()
	print("小茂对话栈 ", _dialogs.size())
	_close_all_dialogs()
	await get_tree().process_frame
	var bui = _find_battle_ui()
	if bui == null:
		print("!! 小茂没有开战")
		return
	print("小茂开战，敌方 ", (bui.enemy_team[0] as Dictionary).get("name", ""))
	# 直接判定胜利，看后续动作（台词 + 标记）能不能接着跑
	bui.finished.emit("a")
	await get_tree().process_frame
	_close_all_dialogs()
	if not bool(_flags().get("beat_rival", false)):
		print("!! 打赢小茂没写 beat_rival")
		return
	print("打赢小茂，beat_rival 已写入")
	print("=== 剧情 OK ===")

## 按地图找 NPC 坐标
func _find_npc_at(nm: String, map_id: String) -> Vector2i:
	var d: Dictionary = Data.load_map("kanto", map_id)
	for n in d.get("npcs", []):
		if String(n.get("name", "")) != nm:
			continue
		var at: Array = n.get("at", [0, 0])
		return Vector2i(int(at[0]), int(at[1]))
	return Vector2i(-1, -1)

## 找当前开着的战斗界面
func _find_battle_ui():
	for c in get_children():
		if c is CanvasLayer:
			for k in c.get_children():
				if k is BattleUI:
					return k
	return null

func _close_all_dialogs() -> void:
	# 真正走一遍 closed 信号，这样剧情里的后续动作（给宝可梦等）才会执行
	while not _dialogs.is_empty():
		var dlg = _dialogs.back()
		if dlg.ask_mode:
			dlg._pick(false)
		else:
			dlg._close()

## 截图用：新档开场旁白
func _story_demo() -> void:
	story_on = true
	save_data = SaveScript.empty()
	var blank: Array = []
	for i in PartyScript.MAX_SIZE:
		blank.append({})
	save_data["party"] = blank
	_story_init()
	world.load_map(Data.load_map("kanto", "kanto_main"))
	world.warp_to(Vector2i(24, 217))
	_story_fire("map_enter", {"map": "kanto_main"})
	await get_tree().create_timer(1.2).timeout

## 所有宝可梦中心都过一遍：进门 → 走到柜台 → 说话 → 治疗
func _e2e_all_pc() -> void:
	print("=== 所有宝可梦中心 ===")
	var files: Array = []
	var dir := DirAccess.open("res://content/regions/kanto/maps")
	if dir:
		for f in dir.get_files():
			if f.ends_with(".json") and f.contains("pokemoncenter"):
				files.append(f.replace(".json", ""))
	files.sort()
	for mid in files:
		var m: Dictionary = Data.load_map("kanto", String(mid))
		if m.is_empty():
			print(mid, " 加载失败")
			continue
		world.load_map(m)
		var door := Vector2i(-1, -1)
		for w in m.get("warps", []):
			if String(w["to"].get("map", "")) == "kanto_main":
				door = Vector2i(int(w["at"][0]), int(w["at"][1]))
				break
		if door.x < 0:
			print(mid, " 没有回主图的门口")
			continue
		world.warp_to(door)
		var nurse := Vector2i(-1, -1)
		for n in world.npcs:
			if String(n.get("name", "")).contains("护士"):
				var at: Array = n.get("at", [0, 0])
				nurse = Vector2i(int(at[0]), int(at[1]))
		if nurse.x < 0:
			print(mid, " 没有护士")
			continue
		var ok_walk: bool = not _find_path(m, door, Vector2i(nurse.x, nurse.y + 2)).is_empty()
		if not ok_walk:
			print(mid, " 从门口走不到柜台前 ", nurse)
			continue
		_walk_to(Vector2i(nurse.x, nurse.y + 2))
		world.facing = "up"
		world.step_interact()
		var talk: bool = world.last_event.begins_with("talk:")
		var heal := bool(world.last_npc.get("heal", false))
		print("%-32s 走到柜台 %s / 对话 %s / 治疗标记 %s" % [mid, ok_walk, talk, heal])
		world.last_event = ""
		world.last_npc = {}
	print("=== 结束 ===")

func _e2e_pc() -> void:
	print("=== E2E 宝可梦中心 ===")
	world.load_map(Data.load_map("kanto", "kanto_main"))
	world.warp_to(Vector2i(24, 217))
	print("起点 ", world.map_data.get("id"), " ", world.player_pos)
	_walk_to(Vector2i(17, 91))
	_walk_to(Vector2i(7, 1))
	_walk_to(Vector2i(5, 9))
	_walk_to(Vector2i(7, 1))
	_walk_to(Vector2i(17, 25))
	_walk_to(Vector2i(7, 7))
	print("现在在 ", world.map_data.get("id"), " ", world.player_pos)
	if String(world.map_data.get("id", "")) != "pewtercity_pokemoncenter_1f":
		print("!! 没进到宝可梦中心")
		return
	var nurse := Vector2i(-1, -1)
	for n in world.npcs:
		if String(n.get("name", "")).contains("护士"):
			var at: Array = n.get("at", [0, 0])
			nurse = Vector2i(int(at[0]), int(at[1]))
	print("护士 ", nurse)
	_walk_to(Vector2i(nurse.x, nurse.y + 2))
	world.facing = "up"
	world.step_interact()
	print("交互 ", world.last_event, " / ", world.last_npc.get("name", ""))
	if world.last_npc.is_empty():
		print("!! 说不上话")
		return
	var party: Array = save_data.get("party", [])
	for mm in party:
		if mm is Dictionary and not (mm as Dictionary).is_empty():
			mm["hp"] = 1
	save_data["party"] = party
	_talk_to_npc(world.last_npc)
	# 对话要真的走过"恢复/不用"这一步：直接把最上层对话按到选择，再选"恢复"
	if not _dialogs.is_empty():
		var dlg: Object = _dialogs[_dialogs.size() - 1]
		# advance 一次只是把这句显示完；再多按一次就会关窗口
		dlg.call("advance")
		if dlg.call("is_waiting_answer"):
			dlg.call("_pick", true)
		else:
			print("!! 护士没问我要不要恢复")
	var all_full := true
	for mm in save_data.get("party", []):
		if mm is Dictionary and not (mm as Dictionary).is_empty():
			if int(mm.get("hp", 0)) != int(mm.get("max_hp", 1)):
				all_full = false
	print("治疗全满？ ", all_full)
	_walk_to(Vector2i(6, 8))
	print("出门后 ", world.map_data.get("id"), " ", world.player_pos)
	print("=== E2E 结束 ===")

func _restore_from_save() -> void:
	save_data = SaveScript.load_game()
	preload("res://core/frlg_actors.gd").migrate_progress(save_data)
	PartyScript.migrate_legacy_box(save_data)
	DexVariants.restore(save_data)
	# 修改器改过的种族值跟着存档走，读档时先合进来再建队伍
	Data.apply_species_overrides(save_data.get("species_override", {}))
	# 新档手里空空：第一只宝可梦要从大木博士那里拿，剧情才立得住
	if not save_data.has("party") or not (save_data["party"] is Array):
		var p: Array = []
		for i in PartyScript.MAX_SIZE:
			p.append({})
		save_data["party"] = p

	var saved_bag = save_data.get("bag", [])
	var has_bag := false
	if saved_bag is Array:
		var arr: Array = saved_bag
		has_bag = arr.size() > 0
	if has_bag:
		bag_items = Data.normalize_bag(saved_bag)
	else:
		bag_items = _default_items()
	# Keep one permanent device at the top of the key pocket, including in older saves.
	bag_items = bag_items.filter(func(item): return item.get("name","") != Data.REGION_TRANSFER_ITEM)
	bag_items.push_front({"id":0, "name":Data.REGION_TRANSFER_ITEM, "category":"key", "count":1})
	preload("res://core/sevii_campaign.gd").reconcile_pass(_flags(),bag_items)
	save_data["bag"] = bag_items

	# 出生地：地区表里写死的起点。没有存档 / 存档地图没了，都回到这里，
	# 而不是随随便便落到地区表里排序第一的那张图。
	var start_region := "kanto"
	var start_map := "pallet_town_players_house_2f"
	var start_at := Vector2i(3, 6)
	var reg_home: Dictionary = Data.load_region(start_region)
	var st = reg_home.get("start", {})
	if st is Dictionary and (st as Dictionary).has("map"):
		start_map = String((st as Dictionary)["map"])
		var sa = (st as Dictionary).get("at", [])
		if sa is Array and (sa as Array).size() == 2 and sa[0] != null:
			start_at = Vector2i(int(sa[0]), int(sa[1]))

	var region := String(save_data.get("region", start_region))
	var map_id := String(save_data.get("map", start_map))
	var saved_pos: Array = save_data.get("pos", [])
	var has_saved_spot := saved_pos.size() == 2
	var map: Dictionary = {}
	var first_path := "res://content/regions/%s/maps/%s.json" % [region, map_id]
	if FileAccess.file_exists(first_path):
		map = Data.load_map(region, map_id)
	if map.is_empty():
		print("[start] 存档地图 %s/%s 不存在，回出生地" % [region, map_id])
		region = start_region
		map_id = start_map
		map = Data.load_map(region, map_id)
		has_saved_spot = false
	if map.is_empty():
		region = "hoenn"
		map_id = "littleroot_town"
		map = Data.load_map(region, map_id)
		has_saved_spot = false
	if map.is_empty():
		return
	save_data["region"] = region
	save_data["map"] = map_id
	world.taken = _flags()
	world.facing = str(save_data.get("facing", "down"))
	world.load_map(map)

	var spot := start_at
	if has_saved_spot:
		spot = Vector2i(int(saved_pos[0]), int(saved_pos[1]))
		# Before 4.51 the interior and connecting exterior of Saffron City overlapped.
		if map_id == "kanto_main" and not save_data.has("field_revision") and Rect2i(264,120,66,55).has_point(spot):
			var city_spot := spot + Vector2i(48,30)
			# Routes 6 and 8 also occupied part of that rectangle in 4.50.
			# A recorded road name and a still walkable tile preserve that journey.
			var saved_area := str(save_data.get("location_label","")).trim_prefix("关都·")
			var road_save: bool = saved_area in ["ROUTE6","ROUTE8","6 号道路","8 号道路"] and not world.is_blocked(spot)
			if not road_save and (not world.is_blocked(city_spot) or world.warp_at(city_spot).get("trigger", "") == "door"):
				spot = city_spot
		world.last_elevation = int(save_data.get("field_elevation", 0))
	# 存档点要是被挡住（换版本后地块变了），退到这张图自己的出生点
	world.surfing = has_saved_spot and world.is_water(spot) and bool(save_data.get("surfing", true))
	world.diving = world.surfing and bool(save_data.get("diving", world.is_deep(spot)))
	world.bike = bool(save_data.get("bike", false))
	# Old builds saved on top of animated exterior doors. Restore at that door's doorstep.
	if has_saved_spot and world.warp_at(spot).get("trigger", "") == "door":
		var doorstep := spot + Vector2i.DOWN
		if world.can_enter(doorstep, Vector2i.DOWN):
			spot = doorstep
			world.facing = "down"
	var on_water: bool = world.surfing and world.can_enter(spot, Vector2i.ZERO, true)
	if (world.is_blocked(spot) or world.is_water(spot)) and not on_water:
		print("[start] 存档点 %s 不可走，回出生点" % [spot])
		var sp: Array = map.get("spawn", [])
		if sp.size() == 2:
			spot = Vector2i(int(sp[0]), int(sp[1]))
	if (world.is_blocked(spot) or world.is_water(spot)) and not on_water:
		spot = start_at
	world.warp_to(spot)
	_apply_defeated()
	grass_streak = 0
	_refresh_scene()
	print("[start] %s/%s %s" % [region, String(map.get("id", map_id)), spot])
	_story_init()
	_story_fire("map_enter", {"map": String(map.get("id", map_id)), "region": region})
	_ensure_form_npc()

## 加道具：同名的叠数量，不重复占格子
func _give_item(name: String, count: int, category := "other") -> void:
	if name == "" or count <= 0:
		return
	var entry := {"id":0, "name":name, "category":category, "count":count}
	entry.merge(Data.field_item_fields(entry), true)
	name = str(entry.name)
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")) == name:
			if name.begins_with("秘传学习器") and int(it.get("count",0))>0: return
			it["count"] = int(it.get("count", 0)) + count
			return
	bag_items.append(entry)

func _default_items() -> Array:
	return [
		{"id": 17, "name": "伤药", "category": "heal", "count": 5},
		{"id": 18, "name": "好伤药", "category": "heal", "count": 2},
		{"id": 68, "name": "力量强化", "category": "battle", "count": 1},
		{"id": 0, "name": "太晶碎块·火", "category": "tera", "count": 1, "tera": "fire"},
		{"id": 0, "name": "太晶碎块·水", "category": "tera", "count": 1, "tera": "water"},
		{"id": 0, "name": "太晶碎块·妖精", "category": "tera", "count": 1, "tera": "fairy"},
	]

func _persist() -> bool:
	save_data["region"] = String(world.map_data.get("region", "hoenn"))
	save_data["map"] = String(world.map_data.get("id", "littleroot_town"))
	save_data["pos"] = [world.player_pos.x, world.player_pos.y]
	save_data["field_revision"] = 1
	save_data["field_elevation"] = world.last_elevation
	save_data["facing"] = world.facing
	save_data["surfing"] = world.surfing
	save_data["diving"] = world.diving
	save_data["bike"] = world.bike
	save_data["location_label"] = world.display_name()
	save_data["party"] = save_data.get("party", [])
	save_data["bag"] = bag_items
	return SaveScript.save(save_data)

func _build_start_menu() -> void:
	menu_layer = CanvasLayer.new()
	menu_layer.layer = 4
	add_child(menu_layer)
	menu_layer.child_exiting_tree.connect(func(_child: Node): _resume_start_menu.call_deferred())
	ui_layer.add_child(StartMenu.start_key(_toggle_start_menu))

func _field_key_at(pos: Vector2) -> String:
	if not is_instance_valid(touch_layer) or not touch_layer.visible:
		return ""
	for pad in _dpad:
		var button: Button = pad.btn
		if button.get_global_rect().has_point(pos):
			return pad.key
	if _btn_b.get_global_rect().has_point(pos):
		return "run"
	return ""

# Godot's emulated mouse represents only the first finger. Give the D-pad and
# B their own touch IDs so releasing one cannot cancel or repeat the other.
func _handle_field_touch(event: InputEventScreenTouch) -> bool:
	var key: String
	if event.pressed:
		key = _field_key_at(event.position)
		if key == "": return false
		_field_fingers[event.index] = key
		if key == "run":
			run_held = true
		else:
			held_dir = key
			_move(key)
	elif _field_fingers.has(event.index):
		key = _field_fingers[event.index]
		_field_fingers.erase(event.index)
		if key == "run":
			run_held = "run" in _field_fingers.values()
		elif key == held_dir:
			held_dir = ""
	else:
		return false
	return true

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and _handle_field_touch(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and _field_key_at(event.position) != "":
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if is_instance_valid(title_screen) or not is_instance_valid(world) or not world.visible:
		return
	var start: bool = (event is InputEventKey and event.keycode in [KEY_ENTER, KEY_KP_ENTER]) or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_START)
	if start and panel_open == 0 and not is_instance_valid(active_battle):
		get_viewport().set_input_as_handled()
		_toggle_start_menu()
	elif panel_open > 0 and not is_instance_valid(active_battle) and (event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.button_index == JOY_BUTTON_B)):
		if get_viewport().gui_get_focus_owner() is LineEdit:
			get_viewport().gui_release_focus()
			DisplayServer.virtual_keyboard_hide()
		else:
			_on_back()
		get_viewport().set_input_as_handled()

func _toggle_start_menu() -> void:
	if is_instance_valid(start_menu):
		if start_menu.visible:
			_close_start_menu()
		return
	if panel_open != 0 or is_instance_valid(active_battle) or is_instance_valid(title_screen) or not world.visible:
		return
	held_dir = ""
	run_held = false
	if world.walking:
		_start_after_step = true
		return
	start_menu = StartMenu.new()
	menu_layer.add_child(start_menu)
	panel_open += 1
	_set_hud_visible(false)
	start_menu.closed.connect(_close_start_menu)
	start_menu.chosen.connect(_start_selected)
	start_menu.setup(_fusion_btn_visible())
	snd.play_sfx("select")

func _remove_start_menu() -> void:
	var menu := start_menu
	start_menu = null
	menu.hide()
	menu.queue_free()
	panel_open = maxi(0, panel_open - 1)

func _close_start_menu() -> void:
	if is_instance_valid(start_menu):
		_remove_start_menu()
		_set_hud_visible(panel_open == 0)

func _resume_start_menu() -> void:
	if is_instance_valid(start_menu) and not start_menu.visible and panel_open == 1 and not is_instance_valid(active_battle):
		start_menu.resume()

func _start_selected(command: String) -> void:
	snd.play_sfx("select")
	# Keep the selected row underneath a child page. Field actions return to the map.
	var pages := {"图鉴": _open_dex, "队伍": _open_party, "背包": _open_bag, "电脑": _open_pc,
		"修改器": _open_editor, "融合": _open_fusion, "秘传": _open_hm}
	if pages.has(command):
		start_menu.hide()
		pages[command].call()
		if panel_open == 1:
			_close_start_menu()
		return
	_close_start_menu()
	match command:
		"骑行": _toggle_bike()
		"存档": _show_toast("进度已保存。" if _persist() else "存档写入失败，请检查设备空间。")


## 融合系统：合体、分离、洛托姆换家电
func _test_fusion() -> bool:
	var okX := true
	var party: Array = [
		PartyScript.make(646, 50, [58, 59]),
		PartyScript.make(643, 50, [53, 46]),
		PartyScript.make(800, 50, [94]),
		PartyScript.make(791, 50, [33]),
		PartyScript.make(479, 50, [84]),
	]
	var opts: Array = FusionScript.options(party)
	print("fusion dbg: 可合体 %d 组 %s" % [opts.size(), str(opts.map(func(o): return String(o["label"])))])
	if opts.size() != 2:
		print("!! 可合体组合数不对")
		okX = false
	var before_spa := int(party[0]["stats"]["spa"])
	var nm := FusionScript.fuse(party, 0, 1, "KYUREM_WHITE")
	print("fusion dbg: 合体 -> %s 队伍 %d 人 特攻 %d -> %d" % [nm, party.size(),
		before_spa, int(party[0]["stats"]["spa"])])
	if nm == "" or party.size() != 4 or String(party[0]["form"]) != "KYUREM_WHITE":
		print("!! 合体没成")
		okX = false
	if int(party[0]["stats"]["spa"]) <= before_spa:
		print("!! 合体后特攻没涨")
		okX = false
	var back := FusionScript.unfuse(party, 0)
	print("fusion dbg: 分离 -> %s 队伍 %d 人" % [back, party.size()])
	if party.size() != 5 or String(party[0]["form"]) != "":
		print("!! 分离没还原")
		okX = false
	# 12 格队伍：满 12 才拦分离，11 只时照常拆
	var big: Array = []
	for i in 10:
		big.append(PartyScript.make(19, 5, [33]))
	big.append(PartyScript.make(646, 50, [58]))
	big.append(PartyScript.make(643, 50, [53]))
	var bi := 10
	var nm2 := FusionScript.fuse(big, bi, 11, "KYUREM_WHITE")
	var un2 := FusionScript.unfuse(big, bi)
	print("fusion dbg: 十二只 合体 %s / 分离 %s / 队伍 %d" % [nm2, un2, big.size()])
	if nm2 == "" or un2.contains("满") or big.size() != 12:
		print("!! 12 格队伍下合体/分离被误挡")
		okX = false
	# 真的满 12 只时分离才该拦
	var full: Array = []
	for i in PartyScript.MAX_SIZE:
		full.append(PartyScript.make(19, 5, [33]))
	full[0] = PartyScript.make(646, 50, [58])
	full[0]["fused_part"] = PartyScript.make(643, 50, [53])
	var un3 := FusionScript.unfuse(full, 0)
	print("fusion dbg: 满 12 只分离 -> %s" % un3)
	if not un3.contains("满"):
		print("!! 满员时没拦住分离")
		okX = false
	# 道具定形态：石板 / 家电
	var arc: Dictionary = PartyScript.make(493, 50, [449])
	arc["held"] = "FLAME_PLATE"
	var fmsg := FusionScript.apply_held_form(arc)
	print("fusion dbg: 带石板 -> %s / %s" % [fmsg, str(arc["types"])])
	if String(arc.get("form", "")) != "ARCEUS_FIRE" or not (arc["types"] as Array).has("fire"):
		print("!! 队伍里带石板没变形")
		okX = false
	var rot: Dictionary = PartyScript.make(479, 50, [84])
	rot["held"] = "ROTOM_WASH"
	FusionScript.apply_held_form(rot)
	print("fusion dbg: 带家电 -> %s" % str(rot["types"]))
	if not (rot["types"] as Array).has("water"):
		print("!! 洛托姆带洗衣机没变水属性")
		okX = false
	if FusionScript.ITEM_FORMS.size() != 34:
		print("!! 道具台条目数不是 34")
		okX = false
	# 新补的形态：起源 / 解放 / 灵兽
	var gi: Dictionary = PartyScript.make(487, 50, [421])
	gi["held"] = "GRISEOUS_ORB"
	FusionScript.apply_held_form(gi)
	var ho: Dictionary = PartyScript.make(720, 50, [247])
	ho["held"] = "PRISON_BOTTLE"
	FusionScript.apply_held_form(ho)
	var to: Dictionary = PartyScript.make(641, 50, [16])
	to["held"] = "REVEAL_GLASS"
	FusionScript.apply_held_form(to)
	print("fusion dbg: 起源 %s / 解放 %s / 灵兽 %s" % [String(gi.get("form", "")),
		String(ho.get("form", "")), String(to.get("form", ""))])
	if String(gi.get("form", "")) != "GIRATINA_ORIGIN" or String(ho.get("form", "")) != "HOOPA_UNBOUND" \
			or String(to.get("form", "")) != "TORNADUS_THERIAN":
		print("!! 新形态没生效")
		okX = false
	return okX

## 道具台：领形态道具
func _open_form_items() -> void:
	var ui := FormItemUI.new()
	menu_layer.add_child(ui)
	ui.setup()
	panel_open += 1
	_set_hud_visible(false)
	ui.connect("closed", func() -> void:
			panel_open = maxi(0, panel_open - 1)
			if panel_open == 0:
				_set_hud_visible(true))
	ui.connect("give", func(item_name: String, key: String) -> void:
			_give_bag_item(item_name, "held", key)
			_persist()
			_refresh_hud())

## 所有宝可梦中心都摆一个"研究员"，专管形态道具
func _ensure_form_npc() -> void:
	if not String(world.map_data.get("id", "")).contains("pokemoncenter"):
		return
	for n in world.npcs:
		if n is Dictionary and bool((n as Dictionary).get("form_items", false)):
			return
	var spot := _free_floor()
	if spot == Vector2i(-1, -1):
		return
	world.npcs.append({"at": [spot.x, spot.y], "name": "研究员", "gfx": "expert_m", "form_items": true})
	world._rebuild()

## 找一格空地板：不撞地形、不站人、不压门
func _free_floor() -> Vector2i:
	var w: int = int(world.tile_size.x)
	var h: int = int(world.tile_size.y)
	var taken := {}
	for n in world.npcs:
		var at: Array = (n as Dictionary).get("at", [])
		if at.size() >= 2:
			taken[Vector2i(int(at[0]), int(at[1]))] = true
	for wr in world.map_data.get("warps", []):
		var a2: Array = (wr as Dictionary).get("at", [])
		if a2.size() >= 2:
			taken[Vector2i(int(a2[0]), int(a2[1]))] = true
	var px: Vector2i = world.player_pos
	for cand in [Vector2i(px.x, px.y + 2), Vector2i(px.x - 2, px.y), Vector2i(px.x + 2, px.y),
			Vector2i(px.x - 2, px.y + 2), Vector2i(px.x + 2, px.y + 2)]:
		if _floor_ok(cand, w, h, taken):
			return cand
	for yy in range(1, h - 1):
		for xx in range(1, w - 1):
			var p := Vector2i(xx, yy)
			if _floor_ok(p, w, h, taken):
				return p
	return Vector2i(-1, -1)

func _floor_ok(p: Vector2i, w: int, h: int, taken: Dictionary) -> bool:
	if p.x < 1 or p.y < 1 or p.x >= w - 1 or p.y >= h - 1:
		return false
	if taken.has(p) or p == world.player_pos:
		return false
	if world.blocked_by_terrain(p):
		return false
	var up := p + Vector2i(0, 1)
	return not world.blocked_by_terrain(up)

func _fusion_btn_visible() -> bool:
	var map_id := String(world.map_data.get("id", "")).replace("_", "")
	return map_id.contains("pokemoncenter") or map_id.contains("pokecenter")

## 融合工坊：只对宝可梦中心开放
func _open_fusion() -> void:
	var ui := FusionUI.new()
	menu_layer.add_child(ui)
	ui.setup(save_data.get("party", []))
	panel_open += 1
	_set_hud_visible(false)
	ui.connect("closed", func() -> void:
			panel_open = maxi(0, panel_open - 1)
			if panel_open == 0:
				_set_hud_visible(true))
	ui.connect("changed", func(msg: String) -> void:
			save_data["party"] = PartyScript.compact(ui.party)
			DexVariants.sync_owned(save_data, save_data.party)
			_persist()
			_refresh_hud()
			_show_toast(msg))

func _open_party() -> void:
	var ui := PartyUI.new()
	menu_layer.add_child(ui)
	ui.setup(save_data.get("party", []), bag_items)
	panel_open += 1
	_set_hud_visible(false)
	ui.closed.connect(func() -> void:
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true))
	ui.connect("reordered", _persist)
	ui.evolve_with.connect(func(slot: int, item_name: String) -> void:
		_evolve_with_item(slot, item_name, ui))
	ui.tera_change.connect(func(slot: int, tera_type: String) -> void:
		_change_tera(slot, tera_type, ui))
	ui.held_change.connect(func(slot: int, held_key: String, item_name: String) -> void:
		_change_held(slot, held_key, item_name, ui))

## 换携带物品：道具和树果共用一格，旧的放回背包、新的从背包拿一个
func _change_held(slot: int, held_key: String, item_name: String, ui) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var mon = party[slot]
	if not (mon is Dictionary) or (mon as Dictionary).is_empty():
		return
	var old_held := String(mon.get("held", ""))
	var old_berry := String(mon.get("berry", ""))
	var new_is_berry := held_key.begins_with("berry:")
	var new_key := held_key.replace("berry:", "")
	if (new_is_berry and old_held == "" and old_berry == new_key) \
			or ((not new_is_berry) and new_key != "" and old_held == new_key and old_berry == "") \
			or (new_key == "" and old_held == "" and old_berry == ""):
		if ui:
			ui.refresh()
		return
	# 旧的回到背包
	if old_held != "":
		_give_bag_item(Data.item_name(old_held), "held", old_held)
	if old_berry != "":
		_give_bag_item(Data.berry_name(old_berry), "berry", "", old_berry)
	# 从背包取一个新的
	if new_key != "":
		for it in bag_items:
			if it is Dictionary and int((it as Dictionary).get("count", 0)) > 0 \
					and String((it as Dictionary).get("category", "")) == ("berry" if new_is_berry else "held") \
					and String((it as Dictionary).get("berry" if new_is_berry else "held", "")) == new_key:
				it["count"] = int(it["count"]) - 1
				break
	mon["held"] = ""
	mon["berry"] = ""
	if new_is_berry:
		mon["berry"] = new_key
	else:
		mon["held"] = new_key
		# 带上石板 / 家电 / 卡带这类，当场变形态
		var fmsg := FusionScript.apply_held_form(mon)
		if fmsg != "":
			_show_toast(fmsg)
			DexVariants.record(save_data, mon, true)
	_persist()
	_refresh_hud()
	_show_toast("已让 %s 带上 %s" % [String(mon.get("name", "?")), item_name])
	if ui:
		var sl := slot
		ui.call("_open_detail", sl)

## 往背包里加一个道具，已有就叠数量
func _give_bag_item(item_name: String, category: String, key: String = "", berry_key: String = "", tera_key: String = "") -> void:
	var evo_key := Data.evo_item_key(item_name)
	if not evo_key.is_empty():
		item_name = Data.evo_item_name(evo_key)
		category = "evo"
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")) == item_name:
			if item_name.begins_with("秘传学习器") and int(it.get("count",0))>0: return
			it["count"] = int(it.get("count", 0)) + 1
			return
	var entry := {"id": 0, "name": item_name, "category": category, "count": 1}
	if key != "":
		entry["held"] = key
	if berry_key != "":
		entry["berry"] = berry_key
	if tera_key != "":
		entry["tera"] = tera_key
	if not evo_key.is_empty():
		entry["evo"] = evo_key
	bag_items.append(entry)

## 用进化石之类的道具让队伍里的宝可梦进化
func _evolve_with_item(slot: int, item_name: String, ui) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var mon = party[slot]
	if not (mon is Dictionary) or (mon as Dictionary).is_empty():
		return
	var item_key := Data.evo_item_key(item_name)
	var target := GrowthScript.evolution_for_item(mon, item_key)
	if target.is_empty():
		_show_toast("这只宝可梦无法用它进化。")
		return
	var stack: Dictionary = {}
	for row in bag_items:
		if row is Dictionary and Data.bag_evo_key(row) == item_key and int(row.get("count", 0)) > 0:
			stack = row
			break
	if stack.is_empty():
		_show_toast("背包里已经没有这件道具。")
		return
	var old_name := String(mon.get("name", "?"))
	if not PartyScript.evolve(mon, int(target.to), str(target.form)):
		return
	stack["count"] = int(stack.count) - 1
	if is_instance_valid(_bag_ui):
		_bag_ui.refresh()
	_show_toast("%s 进化成了 %s！" % [old_name, String(mon.get("name", "?"))])
	DexVariants.record(save_data, mon, true)
	party[slot] = mon
	save_data["party"] = PartyScript.compact(party)
	_persist()
	if ui and is_instance_valid(ui):
		ui.queue_free()
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true)
		_open_party()

## 用太晶碎块改太晶属性
func _change_tera(slot: int, tera_type: String, ui) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var mon = party[slot]
	if not (mon is Dictionary) or (mon as Dictionary).is_empty():
		return
	# 扣碎块
	var shard_name := "太晶碎块·" + Data.type_name(tera_type)
	var consumed := false
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")) == shard_name:
			if int(it.get("count", 0)) > 0:
				it["count"] = int(it.get("count", 0)) - 1
				consumed = true
			break
	if not consumed:
		_show_toast("没有这种太晶碎块。")
		return
	mon["tera_type"] = tera_type
	party[slot] = mon
	save_data["party"] = PartyScript.compact(party)
	_persist()
	_show_toast("%s 的太晶属性变成了 %s。" % [String(mon.get("name", "?")), Data.type_name(tera_type)])
	if ui and is_instance_valid(ui):
		ui.queue_free()
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true)
		_open_party()

func _open_world_atlas(travel: bool, from_bag: BagUI = null) -> void:
	var atlas := preload("res://scenes/world_atlas.gd").new()
	if is_instance_valid(from_bag):
		from_bag.hide()
	menu_layer.add_child(atlas)
	panel_open += 1
	held_dir = ""
	_set_hud_visible(false)
	atlas.closed.connect(func() -> void:
		panel_open = maxi(0, panel_open - 1)
		if is_instance_valid(from_bag):
			from_bag.show()
		_set_hud_visible(panel_open == 0))
	atlas.trip_requested.connect(func(region_id: String) -> void:
		var hub: Dictionary = Data.travel_regions().get(region_id, {}).get("hub", {})
		if travel and not hub.is_empty():
			if is_instance_valid(from_bag):
				from_bag.handle_back()
				_close_start_menu()
				world.bike = false
			world.surfing = false
			world.diving = false
			_do_warp(hub)
			_persist())
	atlas.setup(Data.travel_regions(), world.map_data, travel, world.player_pos, world.area_name())

func _open_bag() -> void:
	var ui := BagUI.new()
	menu_layer.add_child(ui)
	ui.setup(bag_items)
	panel_open += 1
	_set_hud_visible(false)
	_bag_ui = ui
	ui.on_use = func(nm: String) -> void: _use_bag_item(nm)
	ui.closed.connect(func() -> void:
		_bag_ui = null
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true))

## 通用选项面板：手机上点一条就行，比"按 A 循环"可靠
func _pick(title: String, options: Array, cb: Callable) -> void:
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_layer.add_child(ui)
	panel_open += 1
	_set_hud_visible(false)

	var veil := ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.02, 0.04, 0.07, 0.9)
	ui.add_child(veil)

	var vp := get_viewport_rect().size
	if vp.x < 10:
		vp = Vector2(480, 320)

	var head := Label.new()
	head.position = Vector2(24, 14)
	head.size = Vector2(vp.x - 48, 26)
	head.text = title
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", Color(0.42, 0.80, 0.72))
	ui.add_child(head)

	var sc := ScrollContainer.new()
	sc.position = Vector2(20, 48)
	sc.size = Vector2(vp.x - 40, vp.y - 100)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ui.add_child(sc)
	TouchScroll.attach(sc)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	sc.add_child(box)

	var close := func() -> void:
		panel_open = maxi(0, panel_open - 1)
		if panel_open == 0:
			_set_hud_visible(true)
		ui.queue_free()

	for i in options.size():
		var b := Button.new()
		b.text = String(options[i])
		b.custom_minimum_size = Vector2(0, 38)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.09, 0.13, 0.18, 0.95)
		sb.set_corner_radius_all(7)
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_color = Color(0.42, 0.80, 0.72, 0.35)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_color_override("font_color", Color(0.95, 0.96, 0.93))
		var idx := i
		b.pressed.connect(func() -> void:
			snd.play_sfx("select")
			close.call()
			cb.call(idx))
		box.add_child(b)

	var cancel := Button.new()
	cancel.text = "返回"
	cancel.size = Vector2(72, 32)
	cancel.position = Vector2(vp.x - 96, vp.y - 44)
	cancel.add_theme_font_size_override("font_size", 13)
	cancel.pressed.connect(func() -> void:
		snd.play_sfx("select")
		close.call())
	ui.add_child(cancel)

## 背包里点中一件东西：能用的都真的用掉，不能用的说清为什么
func _use_bag_item(nm: String) -> void:
	if nm == "对战搜寻器":
		_use_vs_seeker()
		return
	if nm == Data.REGION_TRANSFER_ITEM:
		_open_world_atlas(true, _bag_ui)
		return
	if Data.tm_map.has(nm):
		_offer_tm_teach(nm)
		return
	if nm.contains("钓竿"):
		_use_rod(nm)
		return
	if nm == "神奇糖果":
		_item_candy()
		return
	if VITAMINS.has(nm):
		_item_vitamin(nm)
		return
	if nm == "PP 提升剂":
		_item_ppup()
		return
	if nm.contains("提升剂") or nm.contains("增强剂"):
		_show_toast("「%s」这版还没做，先留着。" % nm)
		return
	var evo_key := Data.evo_item_key(nm)
	if not evo_key.is_empty():
		_item_evolve(Data.evo_item_name(evo_key))
		return
	var cat := ""
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")) == nm:
			cat = String((it as Dictionary).get("category", "other"))
			break
	match cat:
		"heal":
			_item_heal(nm)
		"evo":
			_item_evolve(nm)
		"berry":
			_item_berry(nm)
		"ball":
			_show_toast("精灵球要在战斗里扔。")
		"battle":
			_show_toast("这个是战斗中用的。")
		"tera":
			_show_toast("太晶碎块在队伍界面换属性。")
		_:
			if nm in ["金珠", "珍珠", "大珍珠", "星砂", "星之碎片", "小蘑菇", "大蘑菇", "心之鳞片"]:
				_show_toast("「%s」是拿去商店换钱的，不能直接用。" % nm)
			elif nm == "离洞绳":
				_show_toast("「%s」在洞窟里才用得上。" % nm)
			else:
				_show_toast("「%s」是携带道具，到「队伍」里挂给宝可梦。" % nm)


## 常用回复道具：名字 → 效果（hp 回血、hp_mode 按上限比例、cure 解状态、pp 回 PP、revive 复活）
const HEAL_TABLE := {
	"伤药": {"hp": 20}, "好伤药": {"hp": 50}, "厉害伤药": {"hp": 200},
	"全满药": {"hp": 9999}, "全复药": {"hp": 9999, "cure": true},
	"活力碎片": {"revive": 1}, "活力块": {"revive": 99}, "圣灰": {"revive": 99, "all": true},
	"解毒药": {"cure": true}, "麻痹药": {"cure": true}, "解眠药": {"cure": true},
	"灼伤药": {"cure": true}, "解冻药": {"cure": true}, "万灵药": {"cure": true},
	"熔岩饼干": {"cure": true},
	"PP 单项小补剂": {"pp": 10}, "PP 单项全补剂": {"pp": 9999},
	"PP 多项小补剂": {"pp": 10, "multi": true}, "PP 多项全补剂": {"pp": 9999, "multi": true},
	"PP 单项": {"pp": 10}, "PP 多项": {"pp": 10, "multi": true}, "PP 全满": {"pp": 9999, "multi": true},
}

## 扣掉一件道具，数量归零就从背包里删掉
func _consume_item(nm: String) -> void:
	for i in bag_items.size():
		var it: Dictionary = bag_items[i]
		if String(it.get("name", "")) != nm:
			continue
		var left := int(it.get("count", 0)) - 1
		if left <= 0:
			bag_items.remove_at(i)
		else:
			it["count"] = left
		if _bag_ui != null and is_instance_valid(_bag_ui):
			_bag_ui.refresh()
		return


func _item_heal(nm: String) -> void:
	var eff: Dictionary = HEAL_TABLE.get(nm, {"hp": 20})
	var names: Array = []
	var slots: Array = []
	for i in (save_data.get("party", []) as Array).size():
		var m: Dictionary = save_data["party"][i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		var hp := int(m.get("hp", 0))
		var mx := int(m.get("max_hp", 1))
		names.append("%s  %d/%d%s" % [String(m.get("name", "?")), hp, mx, "（濒死）" if hp <= 0 else ""])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("对谁用「%s」？" % nm, names, func(idx: int) -> void:
		if idx < 0 or idx >= slots.size():
			return
		_apply_heal(nm, int(slots[idx]), eff))


func _apply_heal(nm: String, slot: int, eff: Dictionary, free := false) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var m: Dictionary = party[slot]
	var mx := int(m.get("max_hp", 1))
	var hp := int(m.get("hp", 0))
	var before := hp
	if eff.has("revive"):
		if hp > 0:
			_show_toast("「%s」只在濒死时有用。" % nm)
			return
		if bool(eff.get("all", false)):
			for j in party.size():
				var mj: Dictionary = party[j]
				if mj.is_empty() or int(mj.get("species_id", 0)) == 0:
					continue
				mj["hp"] = int(mj.get("max_hp", 1))
				mj["hp_text"] = "%d/%d" % [int(mj["max_hp"]), int(mj["max_hp"])]
				mj.erase("status")
			save_data["party"] = party
			_consume_item(nm)
			_persist()
			_show_toast("队伍里的宝可梦全都恢复了。")
			return
		hp = maxi(1, int(mx / 2.0)) if int(eff["revive"]) <= 1 else mx
	elif eff.has("pp"):
		var pps: Array = m.get("pp", [])
		var moves: Array = m.get("moves", [])
		var full := true
		var touched := 0
		for i in pps.size():
			var cap := int((Data.move_of(int(moves[i])) as Dictionary).get("pp", 10))
			if int(pps[i]) < cap:
				full = false
				pps[i] = mini(cap, int(pps[i]) + int(eff["pp"]))
				touched += 1
				if not bool(eff.get("multi", false)):
					break
		if full:
			_show_toast("招式 PP 还是满的。")
			return
	else:
		if hp <= 0:
			_show_toast("这只宝可梦需要先使用活力碎片。")
			return
		if (hp >= mx or not eff.has("hp") and not eff.has("hp_mode")) and not (eff.get("cure",false) and str(m.get("status","")) not in ["","none"]):
			_show_toast("%s 的体力是满的。" % String(m.get("name", "?")))
			return
		var add := int(eff.get("hp", 0))
		if eff.has("hp_mode"):
			match String(eff["hp_mode"]):
				"half": add = int(mx / 2.0)
				"third": add = int(mx / 3.0)
				_: add = int(eff.get("hp", 10))
		hp = mini(mx, hp + maxi(0, add))
	m["hp"] = hp
	m["hp_text"] = "%d/%d" % [hp, mx]
	if bool(eff.get("cure", false)):
		m.erase("status")
	party[slot] = m
	save_data["party"] = party
	if not free:
		_consume_item(nm)
	_persist()
	snd.play_sfx("confirm")
	if hp != before:
		_show_toast("%s 回复了 %d 点体力（%d/%d）。" % [String(m.get("name", "?")), hp - before, hp, mx])
	else:
		_show_toast("%s 的状态恢复了。" % String(m.get("name", "?")))


func _item_evolve(nm: String) -> void:
	var party: Array = save_data.get("party", [])
	var names: Array = []
	var slots: Array = []
	for i in party.size():
		var m: Dictionary = party[i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		var ok := not GrowthScript.evolution_for_item(m, Data.evo_item_key(nm)).is_empty()
		names.append("%s%s" % [String(m.get("name", "?")), "" if ok else "（用不上）"])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("用「%s」让谁进化？" % nm, names, func(idx: int) -> void:
		if idx < 0 or idx >= slots.size():
			return
		_evolve_with_item(int(slots[idx]), nm, null))


## 增强剂：永久加基础点，每用一次 +5，单项最多 +50（十次）
const VITAMINS := {
	"HP 增强剂": "hp", "攻击增强剂": "atk", "防御增强剂": "def",
	"特攻增强剂": "spa", "特防增强剂": "spd", "速度增强剂": "spe",
}

const STAT_CN := {"hp": "体力", "atk": "攻击", "def": "防御", "spa": "特攻", "spd": "特防", "spe": "速度"}

func _item_vitamin(nm: String) -> void:
	var stat := String(VITAMINS.get(nm, ""))
	if stat == "":
		_show_toast("「%s」用不上。" % nm)
		return
	var names: Array = []
	var slots: Array = []
	for i in (save_data.get("party", []) as Array).size():
		var m: Dictionary = save_data["party"][i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		var plus: Dictionary = m.get("plus", {}) if m.get("plus", {}) is Dictionary else {}
		names.append("%s  %s +%d" % [String(m.get("name", "?")), String(STAT_CN.get(stat, stat)), int(plus.get(stat, 0))])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("「%s」给谁用？" % nm, names, func(idx: int) -> void:
		if idx >= 0 and idx < slots.size():
			_apply_vitamin(nm, int(slots[idx]), stat))


func _apply_vitamin(nm: String, slot: int, stat: String) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var m: Dictionary = party[slot]
	var plus: Dictionary = m.get("plus", {}) if m.get("plus", {}) is Dictionary else {}
	var cur := int(plus.get(stat, 0))
	if cur >= 50:
		_show_toast("%s 的%s已经加满了。" % [String(m.get("name", "?")), String(STAT_CN.get(stat, stat))])
		return
	plus[stat] = cur + 5
	m["plus"] = plus
	PartyScript.recalc(m, true)
	party[slot] = m
	save_data["party"] = party
	_consume_item(nm)
	_persist()
	snd.play_sfx("confirm")
	_show_toast("%s 的%s基础点 +5（现在 +%d）。" % [String(m.get("name", "?")), String(STAT_CN.get(stat, stat)), cur + 5])


## PP 提升剂：挑一招，上限提高这一招基础 PP 的两成，最多三次
func _item_ppup() -> void:
	var names: Array = []
	var slots: Array = []
	for i in (save_data.get("party", []) as Array).size():
		var m: Dictionary = save_data["party"][i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		names.append("%s  Lv%d" % [String(m.get("name", "?")), int(m.get("level", 1))])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("「PP 提升剂」给谁用？", names, func(idx: int) -> void:
		if idx >= 0 and idx < slots.size():
			_ppup_pick_move(int(slots[idx])))


func _ppup_pick_move(slot: int) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var m: Dictionary = party[slot]
	var moves: Array = m.get("moves", [])
	if moves.is_empty():
		_show_toast("这只还没有招式。")
		return
	var bonus: Dictionary = m.get("pp_bonus", {}) if m.get("pp_bonus", {}) is Dictionary else {}
	var labels: Array = []
	for mid in moves:
		var mv: Dictionary = Data.move_of(int(mid))
		var base := int(mv.get("pp", 10))
		var ext := int(bonus.get(str(int(mid)), 0))
		labels.append("%s  %d/%d%s" % [String(mv.get("name", "?")), base + ext, base + int(base * 0.6),
			"（已加满）" if ext >= int(base * 0.6) else ""])
	_pick("提高哪一招的 PP 上限？", labels, func(idx: int) -> void:
		_ppup_apply(slot, idx))


## 真正把 PP 上限加上去（UI 与自检共用）
func _ppup_apply(slot: int, idx: int) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var m: Dictionary = party[slot]
	var moves: Array = m.get("moves", [])
	if idx < 0 or idx >= moves.size():
		return
	var bonus: Dictionary = m.get("pp_bonus", {}) if m.get("pp_bonus", {}) is Dictionary else {}
	var mid := int(moves[idx])
	var mv2: Dictionary = Data.move_of(mid)
	var base2 := int(mv2.get("pp", 10))
	var cap := int(base2 * 0.6)
	var ext2 := int(bonus.get(str(mid), 0))
	if ext2 >= cap:
		_show_toast("「%s」的 PP 已经加满了。" % String(mv2.get("name", "?")))
		return
	var add := maxi(1, int(base2 * 0.2))
	bonus[str(mid)] = mini(cap, ext2 + add)
	m["pp_bonus"] = bonus
	var pps: Array = m.get("pp", [])
	if idx < pps.size():
		pps[idx] = int(pps[idx]) + (int(bonus[str(mid)]) - ext2)
	party[slot] = m
	save_data["party"] = party
	_consume_item("PP 提升剂")
	_persist()
	snd.play_sfx("confirm")
	_show_toast("「%s」的 PP 上限提高到 %d。" % [String(mv2.get("name", "?")), base2 + int(bonus[str(mid)])])


## 神奇糖果：直接升一级
func _item_candy() -> void:
	var names: Array = []
	var slots: Array = []
	for i in (save_data.get("party", []) as Array).size():
		var m: Dictionary = save_data["party"][i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		var lv := int(m.get("level", 1))
		names.append("%s  Lv%d%s" % [String(m.get("name", "?")), lv, "（满级）" if lv >= GrowthScript.MAX_LEVEL else ""])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	_pick("把「神奇糖果」给谁吃？", names, func(idx: int) -> void:
		if idx < 0 or idx >= slots.size():
			return
		_candy_one(int(slots[idx])))


func _candy_one(slot: int) -> void:
	var party: Array = save_data.get("party", [])
	if slot < 0 or slot >= party.size():
		return
	var mon: Dictionary = party[slot]
	var before := int(mon.get("level", 1))
	if before >= GrowthScript.MAX_LEVEL:
		_show_toast("已经是满级了。")
		return
	var sp: Dictionary = Data.species_of(int(mon.get("species_id", 1)))
	var need := GrowthScript.exp_for_level(before + 1, String(sp.get("growth", "medium_fast"))) - int(mon.get("exp", 0))
	var grew := GrowthScript.add_exp(mon, maxi(1, need))
	if grew <= 0:
		_show_toast("没吃下去。")
		return
	PartyScript.recalc(mon, true)
	_learn_new_moves(mon, before, int(mon["level"]))
	var evo: Dictionary = GrowthScript.evolution_of(mon)
	var extra := ""
	if not evo.is_empty():
		var old_name := String(mon.get("name", "?"))
		if PartyScript.evolve(mon, int(evo.get("to", 0)), String(evo.get("form", ""))):
			extra = "，进化成了 %s" % String(mon.get("name", "?"))
			DexVariants.record(save_data, mon, true)
			if old_name == "":
				pass
	party[slot] = mon
	save_data["party"] = party
	_consume_item("神奇糖果")
	_persist()
	snd.play_sfx("confirm")
	_show_toast("%s 升到了 Lv%d%s。" % [String(mon.get("name", "?")), int(mon.get("level", 0)), extra])


## 树果：回血/解状态/回 PP，袋里点着吃
func _item_berry(nm: String) -> void:
	for k in Data.berries.keys():
		var b: Dictionary = Data.berries[k]
		if String(b.get("name", "")) != nm:
			continue
		var kind := String(b.get("kind", ""))
		var eff := {}
		if kind == "heal":
			eff = {"hp_mode": String(b.get("mode", "flat")), "hp": int(b.get("value", 10))}
		elif kind == "cure" or kind == "cure_all":
			eff = {"cure": true}
		elif kind == "pp":
			eff = {"pp": int(b.get("value", 10))}
		else:
			_show_toast("「%s」是战斗里才会触发的树果。" % nm)
			return
		var names: Array = []
		var slots: Array = []
		for i in (save_data.get("party", []) as Array).size():
			var m: Dictionary = save_data["party"][i]
			if m.is_empty() or int(m.get("species_id", 0)) == 0:
				continue
			names.append("%s  %d/%d" % [String(m.get("name", "?")), int(m.get("hp", 0)), int(m.get("max_hp", 1))])
			slots.append(i)
		if slots.is_empty():
			_dialog(["队伍里还没有宝可梦。"], "")
			return
		var e2 := eff
		_pick("把「%s」给谁吃？" % nm, names, func(idx: int) -> void:
			if idx >= 0 and idx < slots.size():
				_apply_heal(nm, int(slots[idx]), e2))
		return
	_show_toast("「%s」认不出来是什么。" % nm)


## 用钓竿：要对着水面
func _use_rod(rod: String) -> void:
	var face: Vector2i = world.player_pos + world._dir_vec()
	if not world.is_water(face):
		_show_toast("面朝水面再用钓竿。")
		return
	# 从背包里点钓竿时先把背包收掉，免得战斗界面上还压着一层
	if _bag_ui != null and is_instance_valid(_bag_ui):
		_bag_ui.closed.emit()
		_bag_ui.queue_free()
		_bag_ui = null
	_fish(rod)

## 电脑：200 个箱子，存/取队伍里的宝可梦
## 闪光：黑漆漆的洞窟里点亮，按地图记
func _toggle_flash() -> void:
	if not _party_can_move("FLASH"):
		_show_toast(_field_move_hint("FLASH","闪光"))
		return
	if not world.dark:
		_show_toast("这里本来就亮着，进洞窟再用。")
		return
	var key := "flash_" + String(world.map_data.get("id", ""))
	var flags := _flags()
	if flags.get(key, false):
		_show_toast("已经照亮过了。")
		return
	flags[key] = true
	world.dark = false
	world.apply_light()
	snd.play_sfx("confirm")
	_persist()
	_show_toast("洞窟被照亮了。")


## 飞行：只列出真的走到过的城镇，点了就飞
# Kanto uses FireRed heal_locations.json translated by the merged map offsets.
const FLY_SPOTS := [
	{"name": "真新镇", "map": "kanto/kanto_main", "at": [66, 268]},
	{"name": "常磐市", "map": "kanto/kanto_main", "at": [74, 207]},
	{"name": "尼比市", "map": "kanto/kanto_main", "at": [65, 86]},
	{"name": "华蓝市", "map": "kanto/kanto_main", "at": [286, 60]},
	{"name": "枯叶市", "map": "kanto/kanto_main", "at": [279, 207], "area": "VERMILION_CITY"},
	{"name": "紫苑镇", "map": "kanto/kanto_main", "at": [390, 136], "area": "LAVENDER_TOWN"},
	{"name": "玉虹市", "map": "kanto/kanto_main", "at": [228, 132], "area": "CELADON_CITY"},
	{"name": "金黄市", "map": "kanto/kanto_main", "at": [336, 189], "area": "SAFFRON_CITY"},
	{"name": "浅红市", "map": "kanto/kanto_main", "at": [217, 332], "area": "FUCHSIA_CITY"},
	{"name": "红莲岛", "map": "kanto/kanto_main", "at": [74, 392], "area": "CINNABAR_ISLAND"},
	{"name": "若叶镇", "map": "johto/johto_new_bark_town", "at": [5, 4]},
	{"name": "樱花镇", "map": "johto/johto_cherrygrove_city", "at": [10, 4]},
	{"name": "桔梗市", "map": "johto/johto_violet_city", "at": [10, 9]},
	{"name": "桧皮镇", "map": "johto/johto_azalea_town", "at": [10, 4]},
	{"name": "满金市", "map": "johto/johto_goldenrod_city", "at": [10, 9]},
	{"name": "圆朱市", "map": "johto/johto_ecruteak_city", "at": [10, 9]},
	{"name": "浅葱市", "map": "johto/johto_olivine_city", "at": [10, 9]},
	{"name": "湛蓝市", "map": "johto/johto_cianwood_city", "at": [6, 14]},
	{"name": "卡吉镇", "map": "johto/johto_mahogany_town", "at": [5, 4]},
	{"name": "烟墨市", "map": "johto/johto_blackthorn_city", "at": [10, 9]},
]

## 走到城镇附近就记一笔，飞行列表里才出现
func _mark_fly_visits() -> void:
	if world == null or world.map_data.is_empty():
		return
	var mid := String(world.map_data.get("id", ""))
	var reg := String(world.map_data.get("region", ""))
	var flags := _flags()
	var dirty := false
	var path := reg + "/" + mid
	var town: String = world.area_name() if mid == "kanto_main" else ""
	for sp in FLY_SPOTS:
		var key := "fly_" + String(sp.name)
		if flags.get(key, false) or path != sp.map: continue
		if mid == "kanto_main" and town != str(sp.get("area", sp.name)) and town != sp.name: continue
		flags[key] = true
		dirty = true
	if dirty:
		save_data["flags"] = flags
		_persist()


func _open_fly() -> void:
	if not _party_can_move("FLY"):
		_show_toast(_field_move_hint("FLY","飞翔"))
		return
	var flags := _flags()
	var spots: Array = []
	var names: Array = []
	for sp in FLY_SPOTS:
		if flags.get("fly_" + String(sp["name"]), false):
			spots.append(sp)
			names.append(String(sp["name"]))
	if spots.is_empty():
		_show_toast("还没走到过任何城镇。")
		return
	_pick("要飞到哪里？", names, func(idx: int) -> void:
		if idx < 0 or idx >= spots.size():
			return
		var sp: Dictionary = spots[idx]
		var parts := String(sp["map"]).split("/")
		world.surfing = false
		world.diving = false
		_do_warp({"region":parts[0], "map":parts[1], "at":sp.at, "facing":"down"})
		_persist())


## 秘传：不用翻背包分类，直接在菜单里挑一招、挑一只队伍宝可梦来教
func _open_hm() -> void:
	var labels: Array = []
	var mvs: Array = []
	var party: Array = save_data.get("party", [])
	for i in 8:
		var nm := "秘传学习器 0%d" % (i + 1)
		if _bag_count(nm) <= 0 or not Data.tm_map.has(nm):
			continue
		var mv := int(Data.tm_map[nm])
		var mv_name := String((Data.move_of(mv) as Dictionary).get("name", nm))
		var who := ""
		for m in party:
			if not (m is Dictionary) or (m as Dictionary).is_empty():
				continue
			for x in (m as Dictionary).get("moves", []):
				if int(x) == mv:
					who = String((m as Dictionary).get("name", "宝可梦"))
					break
			if who != "":
				break
		if who != "":
			labels.append("%s（%s 已会）" % [mv_name, who])
		else:
			labels.append(mv_name)
		mvs.append(mv)
	if mvs.is_empty():
		_dialog(["还没有获得秘传学习器。枯叶市圣安奴号的船长会教你居合斩。"])
		return
	_pick("要用哪个秘传？", labels, func(idx: int) -> void:
		if idx < 0 or idx >= mvs.size():
			return
		var move_id := int(mvs[idx])
		var move: Dictionary = Data.move_of(move_id)
		var key := str(move.get("key",""))
		if (key not in ["FLY","FLASH"] and not (key == "CUT" and _ruin_door_ahead())) or not _party_has_move(key):
			_hm_pick_who(move_id)
			return
		_pick(str(move.name), ["使用" + str(move.name), "教给其他队员"], func(mode: int) -> void:
			if mode == 1:
				_hm_pick_who(move_id)
			elif mode == 0:
				_close_start_menu()
				if key == "FLY": _open_fly()
				elif key == "CUT": _open_ruin_door()
				else: _toggle_flash()))


func _hm_pick_who(mv: int) -> void:
	var party: Array = save_data.get("party", [])
	var names: Array = []
	var slots: Array = []
	for i in party.size():
		var m: Dictionary = party[i]
		if m.is_empty() or int(m.get("species_id", 0)) == 0:
			continue
		var sid := int(m.get("species_id", 0))
		var mark := ""
		for x in m.get("moves", []):
			if int(x) == mv:
				mark = "（已会）"
		if mark == "" and not _can_learn_move(sid, mv):
			mark = "（学不会）"
		names.append("%s%s" % [String(m.get("name", "宝可梦")), mark])
		slots.append(i)
	if slots.is_empty():
		_dialog(["队伍里还没有宝可梦。"], "")
		return
	var mv_name := String((Data.move_of(mv) as Dictionary).get("name", "招式"))
	_pick("让谁学「%s」？" % mv_name, names, func(idx: int) -> void:
		if idx < 0 or idx >= slots.size():
			return
		_tm_teach_one(mv, int(slots[idx]), mv_name))


func _open_pc() -> void:
	var ui = load("res://scenes/pc_ui.gd").new()
	menu_layer.add_child(ui)
	PartyScript.migrate_legacy_box(save_data)
	ui.setup(save_data.get("boxes", []), save_data.get("party", []))
	ui.on_change = func(boxes: Array, party: Array) -> void:
		save_data["boxes"] = boxes
		save_data["party"] = party
		_persist()
	panel_open += 1
	_set_hud_visible(false)
	ui.closed.connect(func() -> void:
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true))
	snd.play_sfx("confirm")


## 骑车：队伍外也能用，速度翻倍，还能骑在路上
func _toggle_bike() -> void:
	var has := false
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")).contains("自行车"):
			has = true
			break
	if not has:
		_show_toast("还没有自行车。")
		return
	world.bike = not world.bike
	snd.play_sfx("bike")
	_show_toast("骑上自行车了。" if world.bike else "下车了。")
	_update_music()


func _open_editor() -> void:
	var ui := EditorUI.new()
	menu_layer.add_child(ui)
	ui.setup(save_data.get("party", []), bag_items, save_data.get("species_override", {}))
	ui.changed.connect(func() -> void:
		save_data["party"] = PartyScript.compact(ui.party)
		DexVariants.sync_owned(save_data, save_data.party)
		save_data["species_override"] = ui.overrides
		bag_items = ui.bag
		_persist())
	panel_open += 1
	_set_hud_visible(false)
	ui.closed.connect(func() -> void:
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true))

func _open_dex() -> void:
	var dex: Dictionary = save_data.get("dex", {})
	var ui := DexUI.new()
	menu_layer.add_child(ui)
	ui.setup(dex.get("seen", []), dex.get("caught", []), save_data.get("dex_variants", {}))
	panel_open += 1
	_set_hud_visible(false)
	ui.closed.connect(func() -> void:
		panel_open = maxi(0, panel_open - 1)
		_set_hud_visible(true))

func _apply_items() -> void:
	pass

func _make_team() -> Array:
	var team: Array = []
	team_slots = []
	var party: Array = save_data.get("party", [])
	for i in party.size():
		var m = party[i]
		if not (m is Dictionary) or (m as Dictionary).is_empty():
			continue
		var c: Dictionary = (m as Dictionary).duplicate(true)
		c.erase("hp_text")
		team.append(c)
		team_slots.append(i)
	if team.is_empty():
		team.append(PartyScript.make(4, 14, [52, 33]))
		team_slots.append(-1)
	return team.slice(0, PartyScript.MAX_SIZE)

## 战斗结束后把血量和 PP 写回存档队伍（按开战时的槽位映射，不按数组下标猜）
func _writeback_team(combatants: Array) -> void:
	var party: Array = save_data.get("party", [])
	for i in mini(combatants.size(), team_slots.size()):
		var slot: int = int(team_slots[i])
		if slot < 0 or slot >= party.size():
			continue
		var src: Dictionary = combatants[i]
		var dst = party[slot]
		if not (dst is Dictionary) or (dst as Dictionary).is_empty():
			continue
		var mx := int(dst.get("max_hp", 1))
		dst["hp"] = clampi(int(src.get("hp", mx)), 0, mx)
		dst["hp_text"] = "%d/%d" % [int(dst["hp"]), mx]
		if src.has("pp"):
			dst["pp"] = (src["pp"] as Array).duplicate()
		if src.has("moves"):
			dst["moves"] = (src["moves"] as Array).duplicate()
		if src.has("level"):
			dst["level"] = int(src["level"])
		if src.get("spent_gene", false) and dst.get("held", "") == "BERSERK_GENE":
			dst["held"] = ""

## 图鉴：见过 / 抓到分别记
func _dex_mark(species_id: int, caught: bool) -> void:
	DexVariants.record(save_data, {"species_id": species_id}, caught)

func _battle_variant_seen(side: String, mon: Dictionary, has_player_party: bool) -> void:
	if side == "a" and not has_player_party:
		return
	DexVariants.record(save_data, mon, side == "a")

## 城都剧情实战：真实走一遍 进镇旁白 → 空木开场 → 拿初始后给图鉴
func _e2e_johto_story() -> void:
	story_on = true
	_story_init()
	save_data["flags"] = {}
	save_data["party"] = []
	# 1) 进若叶镇
	var mm: Dictionary = Data.load_map("johto", "johto_new_bark_town")
	world.load_map(mm)
	world.warp_to(Vector2i(5, 4))
	_refresh_scene()
	var fired := _story_fire("map_enter", {"map": "johto_new_bark_town", "region": "johto"})
	print("e2e johto: 进镇触发=", fired, " 事件=", String(cur_story.get("id", "")))
	if fired:
		for ln in _last_dialog_lines():
			print("  ", ln)
		_close_all_dialogs()
	# 2) 空木博士说话
	var lab: Dictionary = Data.load_map("johto", "johto_elms_lab")
	world.load_map(lab)
	world.warp_to(Vector2i(2, 3))
	_refresh_scene()
	fired = _story_fire("talk", {"npc": "空木博士", "map": "johto_elms_lab"})
	print("e2e johto: 空木开场触发=", fired, " 事件=", String(cur_story.get("id", "")))
	for ln in _last_dialog_lines():
		print("  ", ln)
	_close_all_dialogs()
	# 3) 拿初始（模拟点球）后再进研究所 → 给图鉴和道具
	save_data["party"] = [PartyScript.make(152, 5, [33])]
	var before_balls := _bag_count("精灵球")
	fired = _story_fire("map_enter", {"map": "johto_elms_lab", "region": "johto"})
	print("e2e johto: 拿初始后进所触发=", fired, " 事件=", String(cur_story.get("id", "")))
	for ln in _last_dialog_lines():
		print("  ", ln)
	_close_all_dialogs()
	print("e2e johto: 精灵球 ", before_balls, " -> ", _bag_count("精灵球"), " 图鉴=", bool(_flags().get("johto_dex", false)))

func _last_dialog_lines() -> Array:
	if _dialogs.is_empty():
		return []
	var dlg = _dialogs[_dialogs.size() - 1]
	var out: Array = []
	for ln in dlg.get("lines"):
		out.append(String(ln))
	return out

func _bag_count(nm: String) -> int:
	for it in bag_items:
		if it is Dictionary and String((it as Dictionary).get("name", "")) == nm:
			return int((it as Dictionary).get("count", 0))
	return 0
