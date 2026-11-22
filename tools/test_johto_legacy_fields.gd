extends SceneTree
## Resume older walking, surfing and merged-cave saves, then push an Ice Path boulder.
const Save=preload("res://core/save_game.gd")
const D={"u":Vector2i.UP,"d":Vector2i.DOWN,"l":Vector2i.LEFT,"r":Vector2i.RIGHT}
const FACING={"u":"up","d":"down","l":"left","r":"right"}
var game
var world
var checks:=0
var failed:=false

func _initialize(): call_deferred("run")

func expect(value: bool, label: String):
	checks+=1
	if not value:
		failed=true
		push_error("LEGACY FIELD " + label)

func restore_old(mid: String, at: Array, flags: Dictionary={}, surfing:=false):
	var data:=Save.empty()
	data.origin="johto"
	data.region="johto"
	data.map=mid
	data.pos=at
	data.surfing=surfing
	data.badges=["标准徽章","魅影徽章"]
	data.party=[load("res://core/party.gd").make(160,40,[57,70])]
	data.flags=flags
	Save.save(data)
	game._restore_from_save()
	game._close_all_dialogs()

func roster() -> Array:
	var rows:=[]
	for npc in world.npcs:
		rows.append([npc.get("role",""),npc.name,npc.at.duplicate()])
	return rows

func round_trip(label: String):
	var at: Vector2i=world.player_pos
	var mode: bool=world.surfing
	var actors:=roster()
	var original: String=world.map_data.id
	game._persist()
	game._restore_from_save()
	expect(world.map_data.id==original and world.player_pos==at and world.surfing==mode,label+" feet and travel mode after native reload")
	expect(roster()==actors,label+" ordinary and story actors after native reload")

func odd_egg():
	var items=load("res://core/johto_items.gd")
	var species: Dictionary={}
	var shiny:=0
	for n in 100:
		var choice: Dictionary=items.odd_egg(n)
		species[int(choice.species)]=int(species.get(int(choice.species),0))+1
		if choice.shiny=="star": shiny+=1
	expect(species=={172:9,173:19,174:19,238:16,240:12,239:14,236:11} and shiny==14,"Crystal's seven Odd Egg species and shiny chances")
	restore_old("johto_day_care",[2,2])
	var elder: Dictionary=world._npc_at(Vector2i(4,5))
	var swimmers: Array=game.save_data.party.duplicate(true)
	game.save_data.party=[]
	for i in 12: game.save_data.party.append(swimmers[0].duplicate(true))
	world.warp_to(Vector2i(4,7))
	world.facing="up"
	game._on_action()
	game._close_all_dialogs()
	expect(not game._flags().get("j_odd_egg_received",false) and game._bag_count("奇异蛋")==0,"full twelve-member party can return for the Odd Egg")
	game.save_data.party=swimmers
	game.save_data.egg={"species":133,"steps":42}
	game._on_action()
	game._close_all_dialogs()
	var egg: Dictionary=game.save_data.get("j_odd_egg",{}).duplicate(true)
	expect(not elder.is_empty() and game._bag_count("奇异蛋")==1 and egg.get("steps",0)==5120,"old daycare save can take the one-time Odd Egg across the counter")
	if egg.is_empty(): return
	expect(game.save_data.egg=={"species":133,"steps":42},"normal daycare egg is preserved")
	game._on_action()
	game._close_all_dialogs()
	expect(game._bag_count("奇异蛋")==1 and game.save_data.j_odd_egg==egg,"second visit cannot reroll or duplicate the gift")
	world.warp_to(Vector2i(3,8))
	for i in 2560:
		for dir in ["right","left"]:
			game._move(dir)
			world.tick_walk(1)
			game._close_all_dialogs()
		if i==1279:
			round_trip("Odd Egg midpoint")
			expect(game.save_data.j_odd_egg.steps==2560 and game.save_data.j_odd_egg.species==egg.species and game.save_data.j_odd_egg.shiny==egg.shiny,"saved egg keeps its steps, species and shininess")
	var born: Array=game.save_data.party.filter(func(m):return not m.is_empty() and int(m.species_id)==int(egg.species))
	expect(game._flags().get("j_odd_egg_hatched",false) and game._bag_count("奇异蛋")==0 and born.size()==1,"Odd Egg hatches once after 5120 player steps")
	if born.size()==1:
		expect(born[0].level==5 and born[0].moves==egg.moves and 146 in born[0].moves and born[0].shiny_kind==egg.shiny,"baby retains fixed moves, level and shiny form")
	expect(game.save_data.party.any(func(m):return not m.is_empty() and int(m.species_id)==133),"the independently placed ordinary egg hatches too")
	round_trip("Odd Egg hatch")
	world.warp_to(Vector2i(4,7))
	world.facing="up"
	game._on_action()
	game._close_all_dialogs()
	expect(game._bag_count("奇异蛋")==0 and not game.save_data.has("j_odd_egg"),"daycare service resumes without another Odd Egg after reopen")

func run():
	Save.use_test_slot()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"johto")
	world=game.world
	for suffix in ["mahogany_side","blackthorn_side"]:
		var old: String="johto_ice_path_b2_f_"+suffix
		restore_old(old,[1,4])
		expect(world.map_data.id=="hgss_ice_path_b2f" and (world.player_pos.x<32)==(suffix=="mahogany_side") and not world.is_blocked(world.player_pos),suffix+" migrated to the matching chamber")
		expect(world.objects.filter(func(o):return o.kind in ["hidden","item"]).size()==5,"the five original ice cave pickups share one map")
		round_trip(suffix)
	restore_old("johto_route_41",[12,12],{},true)
	expect(world.surfing and world.is_water(world.player_pos) and world._player_sprite.texture==world.PLAYER_SURF,"old sea save retains Emerald surf and a reachable water tile")
	round_trip("Route 41 surf")
	for has_card in [false,true]:
		restore_old("johto_cherrygrove_city",[16,3],{"j_map_card":has_card})
		var guide:=world.npcs.filter(func(o):return o.get("johto_gift_map","")=="johto_cherrygrove_city") as Array
		expect(guide.is_empty()==has_card and world._npc_at(world.player_pos).is_empty(),"guide timing on a legacy city save")
		expect(not world.surfing and world._player_sprite.texture==world.PLAYER_WALK,"Emerald walker preserved")
		round_trip("Cherrygrove map card "+str(has_card))
	restore_old("johto_ice_path_b1_f",[8,1])
	world.warp_to(Vector2i(25,8)) # Native ladder landing at the start of the replay.
	var rocks: Array=world.objects.filter(func(o):return o.has("ice_rock"))
	expect(rocks.size()==5 and world.npcs.all(func(n):return n.name!="岩石"),"native Strength boulders replace talking placeholders")
	for mark in "lluulllddddddldlUUluRRlddrruUUUruLL":
		var dir: String=mark.to_lower()
		if mark!=dir:
			world.facing=FACING[dir]
			game._on_action()
			game._close_all_dialogs()
		if not world.step(D[dir]):
			expect(false,"could not walk the solution at "+str(world.player_pos)+" "+dir)
			break
		world.tick_walk(1)
	expect(world.taken.get("ice:pit:3",false),"third boulder fell through its real floor opening")
	if world.step(Vector2i.LEFT): world.tick_walk(1)
	expect(world.map_data.id=="hgss_ice_path_b2f" and world.player_pos==Vector2i(20,10),"player follows the third pit to its original landing")
	expect(world.object_at(Vector2i(19,10)).get("ice_rest",0)==3 and not world.can_enter(Vector2i(19,10),Vector2i.LEFT),"fallen rock stops a slide on B2")
	round_trip("B2 fallen boulder")
	expect(world.object_at(Vector2i(19,10)).get("ice_rest",0)==3,"fallen rock stays after save and reopen")
	restore_old("johto_oaks_lab",[2,2],{"j2_silver_pass":true})
	world.warp_to(Vector2i(8,7))
	world.facing="up"
	game._on_action()
	game._close_all_dialogs()
	var machine:=preload("res://core/johto_items.gd").HM_CLIMB
	expect(game._bag_count(machine)==1,"Oak supplies the missing Rock Climb HM to a previously authorized save")
	expect(game._can_learn_move(160,431) and game._can_learn_move(75,431) and not game._can_learn_move(148,431),"HGSS Feraligatr, Graveler and Dragonair HM compatibility")
	game._use_bag_item(machine)
	var buttons:=game.menu_layer.get_child(-1).find_children("*","Button",true,false) as Array
	for b in buttons:
		if b.text=="大力鳄": b.pressed.emit(); break
	game._close_all_dialogs()
	expect(game._party_has_move("ROCK_CLIMB") and not game._party_can_move("ROCK_CLIMB"),"backpack teaches Rock Climb and its field use checks the Earth Badge")
	game.save_data.badges.append("绿色徽章")
	game.save_data.regional_badges.johto.append("绿色徽章")
	expect(game._party_can_move("ROCK_CLIMB"),"Earth Badge permits Rock Climb")
	round_trip("Oak HM08")
	expect(game._bag_count(machine)==1 and game._party_has_move("ROCK_CLIMB"),"HM and learned move survive reopen")
	odd_egg()
	Save.clear_test_slot()
	print("JOHTO LEGACY FIELD ",checks," checks ","FAIL" if failed else "PASS")
	quit(1 if failed else 0)
