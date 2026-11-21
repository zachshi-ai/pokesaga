extends SceneTree

const Save := preload("res://core/save_game.gd")
const Items := preload("res://core/johto_items.gd")
var game
var failed := false

func _initialize():
	call_deferred("run")

func expect(ok: bool, label: String):
	if not ok:
		failed=true
		push_error("JOHTO ITEMS " + label)
	else: print("CHECK ",label)

func warp(room: String):
	game._close_all_dialogs()
	game._do_warp({"region":"johto","map":"johto_"+room,"at":[1,1]})
	game._close_all_dialogs()

func actor(room: String, pos: Array) -> Dictionary:
	warp(room)
	var match_row: Dictionary = game.world._npc_at(Vector2i(pos[0],pos[1]))
	if match_row.is_empty(): push_error("No NPC in " + room + str(pos))
	return match_row

func choose(label: String):
	var menu=game.menu_layer.get_child(-1)
	for b in menu.find_children("*","Button",true,false):
		if b.text==label and not b.is_queued_for_deletion():
			b.pressed.emit()
			return
	expect(false,"missing button "+label)

func gift(room: String, pos: Array, item: String, choices: Array=[]):
	var n := actor(room,pos)
	game._talk_to_npc(n)
	for option in choices: choose(option)
	expect(game._bag_count(item)==1,room + " gives " + item)
	game._close_all_dialogs()

func test_rods():
	var map := "new_bark_town"
	for rod in Items.RODS:
		warp(map)
		var water := Vector2i(-1,-1)
		for y in game.world.tile_size.y:
			for x in game.world.tile_size.x:
				var t := Vector2i(x,y)
				if game.world.is_water(t) and y>0 and not game.world.is_water(t+Vector2i.UP):
					water=t
					break
			if water.x>=0: break
		expect(water.x>=0,"New Bark shoreline")
		if water.x<0: return
		game.world.player_pos=water+Vector2i.UP
		game.world.facing="down"
		game._use_bag_item(rod)
		expect(is_instance_valid(game.active_battle),"cast "+rod+" at water")
		if not is_instance_valid(game.active_battle): return
		var mon: Dictionary=game.active_battle.battle.cur_b()
		var pool := Items.fish_pool("johto_"+map,rod,game._is_night())
		expect(pool.any(func(slot):return slot.species==mon.species_id and slot.min==mon.level),"fish species and level "+rod)
		game.active_battle.finished.emit("fled")
		game._close_all_dialogs()

func test_egg():
	warp("players_house_2f")
	game._give_item("波克比的蛋",1,"key")
	var a := Vector2i(1,1)
	game.world.player_pos=a
	var dir := "right" if game.world.can_step(Vector2i.RIGHT) else "down"
	var back := "left" if dir=="right" else "up"
	for n in 1280:
		for d in [dir,back]:
			game._move(d)
			game.world.tick_walk(1)
			game._close_all_dialogs()
		if n==639:
			game._persist()
			expect(int(Save.load_game().get("j_togepi_steps",-1))==1280,"egg progress after 1280 walking steps survives save")
	expect(game._bag_count("波克比的蛋")==0 and Items.has_partner(game,175),"Togepi hatches at 2560 field steps")
	if Items.has_partner(game,175):
		var elm: Dictionary=actor("elms_lab",[2,1])
		game._talk_to_npc(elm)
		expect(game._bag_count("不变之石")==1,"show actual hatched Togepi to Elm")

func test_trade_and_legend():
	warp("route_36")
	game._flags().j_tree_clear=true
	gift("route_36",[22,4],"城都招式学习器 08")
	game._give_item("红色鳞片",1,"key")
	gift("mr_pokemons_house",[1,2],"学习装置",["交换"])
	expect(game._bag_count("红色鳞片")==0,"red scale consumed by exchange")
	warp("goldenrod_game_corner")
	game.save_data.money=2000
	for k in 2:
		game._talk_to_npc(game.world._npc_at(Vector2i(1,1)))
		choose("50枚　¥1000")
		game._close_all_dialogs()
	expect(game.save_data.money==0 and game.save_data.j_coins==100,"two exact coin purchases")
	game._talk_to_npc(game.world._npc_at(Vector2i(8,1)))
	choose("凯西　100枚")
	expect(game.save_data.j_coins==0 and Items.has_partner(game,63,true),"buy Abra with the case's actual balance")
	warp("pewter_city")
	gift("pewter_city",[14,8],"银色之羽")
	game._talk_to_npc(actor("whirl_island_lugia_chamber",[1,5]))
	check_legend_battle(249,60)
	game._flags().j_beasts=true
	game._flags().j_radio_free=true
	warp("tin_tower_1f")
	check_legend_battle(245,40)
	expect(not Items.visible("suicune",game._flags()) and game._flags().get("j_suicune36",false),"clear the tower and future Suicune sightings")
	game._add_to_team(243,40)
	game._add_to_team(244,40)
	game._flags().johto_champion=true
	gift("tin_tower_1f",[4,0],"虹色之羽")
	game._talk_to_npc(actor("tin_tower_roof",[4,2]))
	check_legend_battle(250,60)

func check_legend_battle(sid: int,level: int):
	expect(is_instance_valid(game.active_battle),"encounter legendary "+str(sid))
	if not is_instance_valid(game.active_battle): return
	var battle=game.active_battle.battle
	expect(battle.cur_b().species_id==sid and battle.cur_b().level==level,"legendary level and species "+str(sid))
	game._give_item("大师球",1,"ball")
	game.active_battle._throw("大师球")
	expect(battle.winner=="caught" and game._bag_count("大师球")==0,"throw and consume Master Ball")
	game.active_battle.finished.emit(battle.winner)
	game._close_all_dialogs()
	expect(Items.has_partner(game,sid,true),"legendary saved after capture")

func test_apricorns():
	const Apricorns := preload("res://core/johto_apricorns.gd")
	game._flags().j_well_clear=true
	for map in Apricorns.TREES:
		for loc in Apricorns.TREES[map]:
			var xy: PackedStringArray=loc.split(",")
			var fruit: String=Apricorns.TREES[map][loc]
			var tree: Dictionary=actor(map.trim_prefix("johto_"),[int(xy[0]),int(xy[1])])
			game._talk_to_npc(tree)
			game._close_all_dialogs()
			game._talk_to_npc(tree)
			expect(game._bag_count(fruit)==1,fruit+" harvested once per day")
			game._talk_to_npc(actor("kurts_house",[7,1]))
			choose(fruit)
			choose("交给他 1 个")
			expect(game._bag_count(fruit)==0 and Save.load_game().get("j_apricorn_order",{}).get("fruit","")==fruit,"Kurt saves order "+fruit)
			game._close_all_dialogs()
			game._talk_to_npc(game.world._npc_at(Vector2i(7,1)))
			expect(not game.save_data.get("j_apricorn_order",{}).is_empty(),"craft waits until next date")
			# Exercise the following day's pickup without changing the computer clock.
			game.save_data.j_apricorn_order.date="2000-01-01"
			game._close_all_dialogs()
			game._talk_to_npc(game.world._npc_at(Vector2i(7,1)))
			expect(game._bag_count(Apricorns.BALLS[fruit])>0 and not game.save_data.has("j_apricorn_order"),"Kurt delivers "+Apricorns.BALLS[fruit])
	var p={"species_id":35,"level":60,"sex":"male"}
	var t={"species_id":35,"level":10,"sex":"female"}
	var sp: Dictionary=root.get_node("Data").species_of(35)
	for pair in [["等级球",8],["月亮球",4],["甜蜜球",8],["诱饵球",3]]:
		expect(Apricorns.adjusted_rate(pair[0],p,t,sp,30.0,true)==30.0*pair[1],"battle effect "+pair[0])
	expect(Apricorns.adjusted_rate("速度球",p,{"species_id":243},sp,30.0,false)==120.0,"Fast Ball on fleeing Raikou")
	expect(Apricorns.adjusted_rate("沉重球",p,{"species_id":143},sp,25.0,false)==65.0,"Heavy Ball on Snorlax")

func test_gs_ball():
	warp("goldenrod_pokecenter_1f")
	game._do_warp({"region":"johto","map":"johto_goldenrod_city","at":[7,14]})
	expect(game._bag_count("GS球")==1,"Goldenrod receptionist gives GS Ball on champion's way out")
	game._talk_to_npc(actor("kurts_house",[7,1]))
	expect(game._bag_count("GS球")==0 and game.save_data.has("j_gs_date"),"Kurt studies GS Ball")
	game.save_data.j_gs_date="2000-01-01"
	game._talk_to_npc(actor("azalea_town",[3,2]))
	expect(game._bag_count("GS球")==1 and game._flags().get("j_gs_return",false),"Kurt returns GS Ball outside on following date")
	warp("ilex_forest")
	var shrine: Dictionary=game.world.object_at(Vector2i(4,11))
	game._handle_object(shrine)
	choose("放上去")
	check_legend_battle(251,30)
	expect(game._bag_count("GS球")==0 and game._flags().get("j_celebi",false),"shrine consumes GS Ball once")

func test_channels():
	# All moves are known in this fixture. Remove one badge at a time to verify field controls.
	var lead: Dictionary=game.save_data.party[0]
	lead.moves=[57,127,250]
	game._do_warp({"region":"johto","map":"johto_tohjo_falls","at":[5,6]})
	game._close_all_dialogs()
	game.world.surfing=true
	game.world.facing="up"
	game.save_data.badges.erase("升龙徽章")
	game._on_action()
	game._close_all_dialogs()
	game._move("up")
	game.world.tick_walk(1.0)
	expect(game.world.player_pos==Vector2i(5,6),"uncleared Tohjo waterfall blocks running/walking without Rising Badge")
	game.save_data.badges.append("升龙徽章")
	game._on_action()
	expect(game.world.player_pos==Vector2i(5,3),"A ascends the full real Tohjo waterfall and lands above it")
	game._close_all_dialogs()
	game._do_warp({"region":"johto","map":"johto_dragons_den_b1_f","at":[5,9]})
	game._close_all_dialogs()
	game.world.surfing=true
	game.world.facing="down"
	game.save_data.badges.erase("冰川徽章")
	game._on_action()
	game._close_all_dialogs()
	expect(not game.world.can_step(Vector2i.DOWN),"Dragon's Den whirlpool blocks passage without Glacier Badge")
	game.save_data.badges.append("冰川徽章")
	game._on_action()
	game._close_all_dialogs()
	game._move("down")
	game.world.tick_walk(1)
	expect(game.world.player_pos==Vector2i(5,10) and game.world.whirl_cleared(Vector2i(5,10)),"use Whirlpool and surf across the real Dragon's Den current")

func run():
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.johto_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	game._add_to_team(158,15)
	gift("players_house_1f",[3,2],"宝可装置")
	expect(game.world.npcs.filter(func(n):return n.name=="妈妈").size()==1,"one mother in the house")
	gift("cherrygrove_city",[16,3],"地图卡",["好"])
	gift("radio_tower_1f",[6,3],"收音机卡",["参加","对","对","不对","对","不对"])
	gift("radio_tower_2f",[7,2],"蓝卡")
	gift("goldenrod_underground",[3,12],"代币盒")
	gift("goldenrod_bike_shop",[3,1],"自行车")
	warp("goldenrod_city")
	game._use_bag_item("自行车")
	expect(game.world.bike,"bicycle toggles")
	game._use_bag_item("自行车")
	gift("ecruteak_itemfinder_house",[1,1],"探宝器")
	gift("route_32_pokecenter_1f",[0,2],"破旧钓竿")
	gift("olivine_good_rod_house",[1,1],"好钓竿")
	gift("route_12_super_rod_house",[2,1],"厉害钓竿")
	gift("olivine_cafe",[2,1],"秘传学习器 04")
	game._talk_to_npc(actor("cianwood_city",[5,23]))
	expect(game._bag_count("秘传学习器 02")==0,"wife waits for Chuck")
	for move in Items.BADGES:
		expect(game._required_field_badge(move)==Items.BADGES[move],move+" badge gate")
		game.save_data.badges.append(Items.BADGES[move])
		expect(game._required_field_badge(move).is_empty(),move+" accepts the right badge")
	gift("cianwood_city",[5,23],"秘传学习器 02")
	gift("ice_path_1f",[15,3],"秘传学习器 07")
	expect(game.world._npc_at(Vector2i(15,3)).is_empty(),"collected Ice Path HM disappears")
	expect(root.get_node("Data").tm_map[Items.HM_WHIRL]==250 and root.get_node("Data").tm_map["秘传学习器 06"]==249,"Crystal whirlpool and Kanto rock smash stay distinct")
	test_rods()
	test_egg()
	test_trade_and_legend()
	test_apricorns()
	test_gs_ball()
	test_channels()
	Save.clear_test_slot()
	print("JOHTO ITEMS ", "FAIL" if failed else "PASS")
	quit(1 if failed else 0)
