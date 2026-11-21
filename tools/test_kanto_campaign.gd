extends SceneTree
## Exercise native field switches, room gates, save migration and the champion record.
const Save = preload("res://core/save_game.gd")
const Rules = preload("res://core/kanto_campaign.gd")
var game
var failed := false

func _initialize():
	call_deferred("run")

func check(value: bool, message: String):
	if not value:
		failed=true
		push_error("KANTO: "+message)

func enter(mid: String, at := Vector2i(2,3)):
	game._do_warp({"region":"kanto","map":mid,"at":[at.x,at.y]})
	game._close_all_dialogs()

func buttons(root_node: Node) -> Dictionary:
	var result := {}
	for node in root_node.find_children("*","Button",true,false):
		if node.is_visible_in_tree(): result[node.text]=node
	return result

func press_tile(at: Array):
	game.world.warp_to(Vector2i(int(at[0]),int(at[1])+1))
	game.world.facing="up"
	game._on_action()

func travel_inputs(sequence: String) -> bool:
	var dirs := {"u":"up","d":"down","l":"left","r":"right"}
	for leg: String in sequence.split(" "):
		if leg.begins_with("A") or leg.begins_with("P"):
			game.world.facing=dirs[leg[1]]
			game._on_action()
			if leg.begins_with("A"):
				var options:=buttons(game.menu_layer)
				if not options.has("按下"):
					check(false,"missing mansion statue at %s %s" % [game.world.map_data.id,game.world.player_pos])
					return false
				options["按下"].pressed.emit()
			game._close_all_dialogs()
		else:
			for _i in int(leg.substr(1)):
				game._move(dirs[leg[0]])
				game.world.tick_walk(0.6)
				if is_instance_valid(game.active_battle):
					game.active_battle.finished.emit("fled")
				game._close_all_dialogs()
	return true

func replay_mansion(routes: Dictionary):
	enter("pokemon_mansion_1f",Vector2i(8,33))
	if not travel_inputs(routes.mansion[0]): return
	check(game._flags().get("secret_key",false),"walk from 1F through 3F drop to basement key")
	travel_inputs(routes.mansion[1]+" d1")
	check(game.world.map_data.id=="kanto_main","exit mansion at southeast door with Secret Key")

func replay_victory_road(routes: Dictionary):
	var world=game.world
	enter("victoryroad_1f",Vector2i(11,20))
	for row: Dictionary in routes.victory_road:
		travel_inputs(row.inputs)
		var at: Array=row.finish
		var arrived: bool=world.map_data.id==at[0] and world.player_pos==Vector2i(int(at[1]),int(at[2]))
		check(arrived,"%s stopped at %s %s, expected %s" % [row.stage,world.map_data.id,world.player_pos,at])
		if not arrived: return
	for f in ["btn:victoryroad_1f:20,16","btn:victoryroad_2f:2,19","btn:victoryroad_3f:7,7","victory_rock_dropped","btn:victoryroad_2f:14,19"]:
		check(game._flags().get(f,false),"missing Victory Road switch "+f)

func fight_elite(entry: Dictionary, outcome: String, ace_level: int, berry: String):
	enter(entry.room)
	check(game.world.map_data.id==entry.room,"round gate "+str(entry.name))
	var speaker: Array=game.world.npcs.filter(func(row):return row.get("role","").begins_with("league_"))
	if speaker.is_empty():
		check(false,"missing speaker "+str(entry.name))
		return
	press_tile(speaker[0].at)
	game._close_all_dialogs()
	if not is_instance_valid(game.active_battle):
		check(false,"missing battle "+str(entry.name))
		return
	var team: Array=game.active_battle.enemy_team
	check(team.size()==(6 if entry.name=="小茂" else 5),"team size "+str(entry.name))
	check(team[-1].level==ace_level and team[-1].berry==berry,"ace configuration "+str(entry.name))
	game.active_battle.finished.emit(outcome)
	game._close_all_dialogs()
	await process_frame

func run():
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.title_screen.new_button.pressed.emit()
	await process_frame
	game._close_all_dialogs()
	var fl: Dictionary=game._flags()
	var legacy={"flags":{"silph_co_5f:22,21":true},"badges":["深红徽章"],"bag":[{"name":"ITEM_SECRET_KEY","count":1}]}
	Rules.migrate(legacy)
	check(legacy.flags.card_key and legacy.flags.secret_key and legacy.bag[0].name=="秘密钥匙" and legacy.flags.cinnabar_quiz_6,"old save key and quiz migration")
	check(Rules.passage_message({"id":"kanto_main","region":"kanto"},{"region":"kanto","map":"cinnabarisland_gym"},game.save_data)!="","locked Cinnabar gym")
	check(Rules.checkpoint({"id":"kanto_main","region":"kanto"},Vector2i(13,179),Vector2i.UP,[])!="","native Route 23 checkpoint")
	enter("rocket_hideout_b1f")
	enter("rocket_hideout_elevator")
	check(game.world.map_data.id=="rocket_hideout_b1f","elevator without key")
	fl.lift_key=true
	enter("rocket_hideout_elevator")
	game.world.warp_to(Vector2i(1,2))
	game.world.facing="left"
	game._on_action()
	var stops:=buttons(game.menu_layer)
	for label in ["B1F","B2F","B4F"]: check(stops.has(label),"missing elevator stop "+label)
	if stops.has("B4F"): stops["B4F"].pressed.emit()
	check(game.world.map_data.id=="rocket_hideout_b4f" and game.world.player_pos==Vector2i(20,24),"actual elevator departure B4F")
	check(game.world.blocked_by_terrain(Vector2i(17,13)),"native Rocket barrier closed")
	fl.hideout_guard_1_win=true
	game.world.refresh_story_actors(fl)
	check(game.world.blocked_by_terrain(Vector2i(17,13)),"one guard leaves barrier closed")
	fl.hideout_guard_2_win=true
	game.world.refresh_story_actors(fl)
	check(not game.world.blocked_by_terrain(Vector2i(17,13)),"native Rocket barrier opens")
	enter("silph_co_3f")
	press_tile([10,13])
	game._close_all_dialogs()
	check(not fl.get("silph_door_3_1",false),"cannot open Silph gate without Card Key")
	fl.card_key=true
	press_tile([10,13])
	game._close_all_dialogs()
	check(fl.get("silph_door_3_1",false) and not game.world.blocked_by_terrain(Vector2i(10,13)),"Card Key opens physical door")
	enter("vermilioncity_gym")
	var bins: Array=Rules.field_rules("vermilioncity_gym")[0].controls
	fl.surge_bin=6
	press_tile(bins[6])
	game._close_all_dialogs()
	check(fl.get("surge_first",false),"first Vermilion switch")
	press_tile(bins[1 if fl.get("surge_second_bin",0)!=1 else 4])
	game._close_all_dialogs()
	check(not fl.get("surge_first",false),"incorrect second switch resets lock")
	press_tile(bins[int(fl.surge_bin)])
	game._close_all_dialogs()
	press_tile(bins[int(fl.surge_second_bin)])
	game._close_all_dialogs()
	check(fl.get("surge_open",false) and not game.world.blocked_by_terrain(Vector2i(5,7)),"unlocked Vermilion laser")
	var fixture_path: String=get_script().resource_path.get_base_dir().path_join("kanto_traversals.json")
	var traversal: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
	replay_mansion(traversal)
	enter("cinnabarisland_gym")
	var quizzes: Array=Rules.field_rules("cinnabarisland_gym")
	for i in quizzes.size():
		press_tile(quizzes[i].controls[0])
		var replies:=buttons(game.menu_layer)
		var answer: String="是" if Rules.data().quizzes[i].answer else "否"
		check(replies.has(answer),"quiz "+str(i+1))
		if replies.has(answer):replies[answer].pressed.emit()
		game._close_all_dialogs()
		check(fl.get("cinnabar_quiz_"+str(i+1),false),"quiz gate opens "+str(i+1))
	enter("indigo_plateau_pokemon_center_1f")
	enter("pokemon_league_loreleis_room")
	check(game.world.map_data.id=="indigo_plateau_pokemon_center_1f","eight badge condition")
	game.save_data.party=[load("res://core/party.gd").make(25,80,[85,98,70])]
	for badge in Rules.BADGES.slice(0,7):
		game._grant_badge(badge)
		game._close_all_dialogs()
	enter("pewtercity_gym")
	var brock: Dictionary=game.world.npcs.filter(func(n): return n.get("badge","")=="灰色徽章")[0]
	press_tile(brock.at)
	game._close_all_dialogs()
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		game._close_all_dialogs()
		await process_frame
	game._persist()
	game._restore_from_save()
	fl=game._flags()
	press_tile(brock.at)
	check(not game._dialogs.is_empty() and game._dialogs.back().lines==brock.post and not is_instance_valid(game.active_battle),"gym leader remembers a victory and uses his post-battle dialogue after reload")
	game._close_all_dialogs()
	enter("kanto_main",Vector2i(84,191))
	game._move("up")
	game.world.tick_walk(0.6)
	check(game.world.map_data.id=="viridiancity_gym","seven badges open the real Viridian Gym door")
	travel_inputs(traversal.viridian_gym.inputs)
	check(game.world.player_pos==Vector2i(2,3),"walk from gym door to Giovanni")
	game.world.facing="up"
	game._on_action()
	game._close_all_dialogs()
	check(is_instance_valid(game.active_battle),"Giovanni challenges for the Earth Badge")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		game._close_all_dialogs()
		await process_frame
	check(fl.get("beat_giovanni",false) and fl.get("kanto_eight_badges",false),"Earth Badge and league entry")
	game._do_warp({"region":"kanto","map":"kanto_main","at":[33,196]})
	game._move("up")
	game.world.tick_walk(0.6)
	game._close_all_dialogs()
	check(is_instance_valid(game.active_battle),"Route 22 rival after final gym")
	check(game.world._npc_at(Vector2i(32,195)).get("role","")=="visiting_rival","rival appears in the original lane")
	if is_instance_valid(game.active_battle):
		game.active_battle.finished.emit("a")
		game._close_all_dialogs()
		await process_frame
	check(not game.world.npcs.any(func(n):return n.get("role","")=="visiting_rival"),"rival leaves when the scene ends")
	replay_victory_road(traversal)
	enter("indigo_plateau_pokemon_center_1f")
	var rounds: Array=Rules.data().league
	await fight_elite(rounds[0],"a",54,"sitrus")
	await fight_elite(rounds[1],"b",56,"sitrus")
	check(game.world.map_data.id=="indigo_plateau_pokemon_center_1f","league defeat sends the party back to the lobby")
	check(not fl.get(rounds[0].flag,false),"league defeat resets the first round")
	var levels := [54,56,58,60,63]
	for i in rounds.size():
		await fight_elite(rounds[i],"a",levels[i],"sitrus")
		check(fl.get(rounds[i].flag,false),"round completion "+str(rounds[i].name))
	enter("pokemon_league_hall_of_fame")
	check(fl.get("kanto_champion",false) and game.save_data.hall_of_fame.kanto[0].species_id==25,"Kanto Hall of Fame registration")
	if fl.get("kanto_champion",false):
		game._persist()
		game._restore_from_save()
		fl=game._flags()
		check(game.save_data.hall_of_fame.kanto.size()==1 and fl.kanto_champion,"record survives reload")
		fl.sevii_network_online=true
		enter("indigo_plateau_pokemon_center_1f")
		var rematch_levels := [66,68,70,72,75]
		var rematch_berries := ["cheri","persim","chesto","persim","sitrus"]
		for i in rounds.size():
			await fight_elite(rounds[i],"a",rematch_levels[i],rematch_berries[i])
			check(fl.get("repeat_"+str(rounds[i].flag),false),"rematch completion "+str(rounds[i].name))
		enter("pokemon_league_hall_of_fame")
		check(fl.get("kanto_rematch_complete",false),"stronger rematch ceremony")
		game._persist()
		game._restore_from_save()
		check(game.save_data.hall_of_fame.kanto.size()==1 and game._flags().kanto_rematch_complete,"rematch preserves first champion record")
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("KANTO CAMPAIGN ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
