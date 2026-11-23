extends "res://tools/test_region_journey.gd"
const Field=preload("res://core/alola_field.gd")
const Machines=preload("res://core/alola_machines.gd")
const Routes=preload("res://core/alola_routes.gd")

func run() -> void:
	Save.use_test_slot()
	await title()
	expect(await preload("regional_start.gd").enter(game,"alola","carried","ultra_sun"),"enter from new shared game")
	game._close_all_dialogs()
	var db=root.get_node("Data")
	var book:Dictionary=Machines.book(game._flags())
	for v in Field.VERSIONS:
		var f:Dictionary={"a_version":v,"a_starter":725}
		var table:Dictionary=Machines.book(f)
		expect(table.size()==100,v+" has 100 machines")
		for num in table:
			var row:Dictionary=table[num]
			var m:Dictionary=db.load_map("alola",row.map)
			expect(not m.is_empty(),v+" machine map "+num)
			if row.has("at"):
				var xy:Array=row.at
				expect(m.physics.collision[int(xy[1])][int(xy[0])]==0,v+" reachable ground on TM "+num)
	expect(Machines.book({"a_version":"sun"})["24"].map=="alola_poni_plains" and book["24"].map=="alola_sandy_cave","TM24 changes with edition")
	expect(not Machines.take(game,"54") and game._bag_count(Field.machine_name(game,54))==0,"Hala's TM held until grand trial")
	game._close_all_dialogs()
	var cash:int=game.save_data.money
	game.save_data.money=50001
	expect(Machines.take(game,"7") and game._bag_count(Field.machine_name(game,7))==1 and game.save_data.money==1,"Royal Avenue machine purchase charges exact price")
	game._close_all_dialogs()
	var party=load("res://core/party.gd")
	var mon:Dictionary=party.make(725,10,[10])
	game.save_data.party=[mon]
	Field.give_machine(game,1)
	game._use_bag_item(Field.machine_name(game,1))
	var label:=str(mon.name)
	if press(game.menu_layer.get_child(-1),label):
		await process_frame
	expect(526 in mon.moves and game._bag_count(Field.machine_name(game,1))==1,"teaching Work Up uses Gen VII compatibility and preserves TM")
	game._close_all_dialogs()
	var piles:Array=Routes.edition_objects(db.load_map("alola","alola_wilds"),game._flags(),[]).filter(func(o):return o.has("alola_pile") and "coba" in o.alola_pile)
	expect(piles.size()==1,"Coba Berry source for Royal Avenue")
	if piles.size()==1:
		Routes.harvest(game,piles[0])
		var bag:=game.bag_items.duplicate(true) as Array
		Routes.harvest(game,piles[0])
		expect(game.bag_items==bag,"daily harvest cannot repeat")
	game.save_data.money=cash
	game.queue_free()
	await process_frame
	Save.clear_test_slot()
	print("ALOLA FIELD ", "FAIL" if failed else "PASS"," checks=",checks)
	quit(1 if failed else 0)
