extends SceneTree
const Save:=preload("res://core/save_game.gd")
func _initialize():run.call_deferred()
func run():
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:
		print("Launch paired Godot processes via tools/test_frlg_wire.py.")
		quit()
		return
	var kind:=args[0]
	var role:=args[1]
	Save.use_test_slot()
	var g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	if is_instance_valid(g.title_screen):g.title_screen.new_button.pressed.emit()
	await process_frame
	g._close_all_dialogs()
	var party=load("res://core/party.gd")
	g.save_data.party=[party.make(25 if kind=="jump" else 85,30,[33])]
	var side=load("res://core/frlg_sidequests.gd")
	if kind=="battle":
		g.save_data.party=[party.make(150,100,[94]) if role=="host" else party.make(129,5,[150])]
		side.interact(g,{"at":[10,2],"side":["link_battle","通信对战接待员"],"side_flag":""})
	else:side.joyful(g,kind)
	var picker=g.menu_layer.get_child(-1)
	picker.find_children("*","Button",true,false)[0].pressed.emit()
	var room=g.menu_layer.get_node("LinkBattle" if kind=="battle" else "JoyfulGame")
	room.set_process(false)
	if role=="host":room.host_room()
	else:room.join_room("127.0.0.1")
	var last_phase:=""
	var previous:=-1
	var started=false
	var outcome: Dictionary={}
	for tick in 40000:
		await process_frame
		OS.delay_msec(2)
		room._process(0.02)
		if room.phase!=last_phase:
			last_phase=room.phase
			print("WIRE PHASE ",role," ",last_phase)
		if kind=="battle":
			if room.phase=="lobby" and role=="host" and room.foe_id!=0:room.begin()
			if room.phase=="match":
				started=true
				if not room.committed:room.layout.find_children("*","Button",true,false)[0].pressed.emit()
			if room.phase=="result" and not room.claim.disabled:
				room.claim.pressed.emit()
				var wins:int=g._flags().get("fr_link_wins",0)
				outcome={"wins":wins}
				break
		elif room.phase=="lobby" and role=="host" and room.players.size()==2:room.begin()
		if room.phase=="arena":
			started=true
			var ui=room.arena
			if kind=="jump":
				var threshold: float=ui.cycle*0.85-ui.air_time()*0.53
				if (previous!=room.turn) and ui.elapsed>=threshold:
					previous=room.turn
					ui.buttons.get_child(0).pressed.emit()
				if role=="host" and ui.score>=5000:
					ui.buttons.get_child(-1).pressed.emit()
			else:
				for fruit in ui.network_berries:
					if float(fruit[1])>=0.72:ui.buttons.get_child(int(fruit[0])).pressed.emit()
				if role=="host" and room.scores.values().max()>=3100:
					ui.buttons.get_child(-1).pressed.emit()
		if room.phase=="result" and kind!="battle":
			if room.confirm_button.disabled:continue
			outcome=room.queued_result.duplicate(true)
			var item_name:String=root.get_node("Data").berry_name(str(outcome.prize))
			var before:int=g._bag_count(item_name)
			room.confirm_button.pressed.emit()
			var after:int=g._bag_count(item_name)
			outcome["bag_increment"]=after-before
			outcome["saved"]=Save.existing().flags.get("fr_"+kind+"_record",{})
			break
		if room.phase=="error":
			print("WIRE ERROR ",role," ",room.phase)
			break
	if outcome.is_empty() or not started or (kind!="battle" and (int(outcome.bag_increment)!=int(outcome.amount) or int(outcome.saved.get("points",-1))!=int(outcome.points))):
		printerr("WIRE FAIL ",kind," ",role," ",outcome)
		quit(1)
		return
	print("WIRE RESULT ",JSON.stringify(outcome))
	g.queue_free()
	await process_frame
	Save.clear_test_slot()
	quit()
