extends "test_hoenn_items.gd"
const Lady := preload("res://core/emerald_lilycove_lady.gd")
const LADY := "LilycoveCity_PokemonCenter_1F_EventScript_LilycoveLady"

func click_prefix(prefix: String) -> void:
	for node in game.menu_layer.get_children():
		if node.is_queued_for_deletion():continue
		for b in node.find_children("*","Button",true,false):
			if b.is_visible_in_tree() and b.text.begins_with(prefix):
				b.pressed.emit()
				return
	check(false,"visible option "+prefix)

func fill_form(words: Array) -> void:
	var forms: Array=game.menu_layer.get_children().filter(func(n):return n.has_meta("lily_entry") and not n.is_queued_for_deletion())
	check(forms.size()==1,"one editable touch form")
	if forms.is_empty():return
	var fields: Array=forms[0].find_children("*","LineEdit",true,false)
	check(fields.size()==words.size(),"editable fields match task")
	for i in mini(fields.size(),words.size()):fields[i].text=words[i]
	click_prefix("确定")

func give_lady(state: Dictionary, item: String) -> void:
	Lady.favor(game,state)
	click_prefix(item+" ×")
	dismiss()

func test_quiz(state: Dictionary) -> void:
	for index in 16:
		var question: Dictionary=Lady.data().quiz[index]
		state.quiz.index=index
		state.quiz.erase("last")
		var before:=int(game._bag_count(Lady.name_for(question.prize)))
		Lady.quiz(game,state)
		choose(question.options[int(question.correct)])
		check(game._bag_count(Lady.name_for(question.prize))==before+1,"quiz reward "+question.prize)
		dismiss()
		Lady.quiz(game,state)
		check(game._bag_count(Lady.name_for(question.prize))==before+1,"existing quiz record prevents duplication")
		dismiss()
	state.quiz.index=0
	state.quiz.erase("last")
	var mail:=int(game._bag_count("闪亮邮件"))
	Lady.quiz(game,state)
	choose("照相机")
	check(game._bag_count("闪亮邮件")==mail,"incorrect answer gets no prize")
	dismiss()
	var stock:=int(game._bag_count("伤药"))
	Lady.compose_quiz(game,state)
	fill_form(["哪种树果能恢复PP？","苹野果"])
	click_prefix("伤药 ×")
	check(game._bag_count("伤药")==stock-1 and state.quiz.custom.prompt.contains("树果"),"custom question escrows actual item")
	dismiss()
	Lady.compose_quiz(game,state)
	choose("请身边的同伴作答")
	fill_form(["橙橙果"])
	check(state.quiz.has("custom") and game._bag_count("伤药")==stock-1,"wrong local answer leaves prize")
	dismiss()
	Lady.compose_quiz(game,state)
	choose("请身边的同伴作答")
	fill_form(["苹野果"])
	check(not state.quiz.has("custom") and game._bag_count("伤药")==stock,"correct local answer returns a single prize")
	dismiss()

func test_favors(state: Dictionary) -> void:
	for index in 6:
		var request: Dictionary=Lady.data().favor[index]
		var key: String=request.items[0]
		var nm:=Lady.name_for(key)
		var before:=int(game._bag_count(Lady.name_for(request.prize)))
		state.favor={"index":index,"favorite":key,"liked":0}
		game._give_item(nm,1)
		give_lady(state,nm)
		check(game._bag_count(Lady.name_for(request.prize))==before+1,"favorite wins original category prize "+request.prize)
	state.favor={"index":2,"favorite":"LEMONADE","liked":0}
	game._give_item("伤药",5,"heal")
	var count:=int(game._bag_count("攻击增强剂"))
	for n in 5:
		state.turn+=1
		give_lady(state,"伤药")
	check(game._bag_count("攻击增强剂")==count+1,"five accepted items win normal favor prize")
	state.favor={"index":0,"favorite":"REPEL","liked":0}
	game._give_item("劲爽汽水",1,"heal")
	give_lady(state,"劲爽汽水")
	check(state.favor.liked==0,"wrong category consumes gift without progress")

func test_blocks(state: Dictionary) -> void:
	state.current=2
	var f: Dictionary=game._flags()
	for round_index in 2:
		state.contest={"index":1,"good":0,"other":0}
		f.h_blocks=[]
		for i in 5:
			f.h_blocks.append({"name":"测试方块","flavor":[0,12 if round_index==0 else 0,0,0,0]})
			state.turn+=1
			Lady.contest(game,state)
			choose("测试方块")
			dismiss()
		check(f.h_blocks.is_empty() and state.broadcast.success==(round_index==0),"five fed blocks create matching broadcast")
		check(Lady.television(game) and not Lady.television(game),"broadcast plays once")
		dismiss()

func test_mail_and_sales() -> void:
	game.save_data.party=[game.PartyScript.make(260,50,[57])]
	var mon: Dictionary=game.save_data.party[0]
	var before:=int(game._bag_count("闪亮邮件"))
	game._use_bag_item("闪亮邮件")
	check(game.panel_open>0,"prize mail opens from real bag")
	choose(mon.name)
	fill_form(["晚点在水静市见。"])
	check(mon.h_letter.text=="晚点在水静市见。" and game._bag_count("闪亮邮件")==before-1,"written letter belongs to actual party member")
	check(Save.load_game().party[0].h_letter.text==mon.h_letter.text,"written letter survives saving")
	dismiss()
	Lady.post(game)
	choose(mon.name)
	choose("取回信纸")
	check(not mon.has("h_letter") and game._bag_count("闪亮邮件")==before,"mail returned once")
	dismiss()
	var money:=int(game.save_data.money)
	var pearls:=int(game._bag_count("大珍珠"))
	visit("em_lilycove_city_department_store_1f")
	talk("LilycoveCity_DepartmentStore_1F_EventScript_Greeter")
	choose("出售贵重物品")
	click_prefix("大珍珠")
	choose("出售")
	check(game.save_data.money==money+3750 and game._bag_count("大珍珠")==pearls-1,"valuable has original half-price sale")
	dismiss()

func run() -> void:
	Save.use_test_slot()
	Save.new_game()
	game=load("res://scenes/boot.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await preload("regional_start.gd").enter(game,"hoenn")
	dismiss()
	var f: Dictionary=game._flags()
	var native: Dictionary=root.get_node("Data").load_map("hoenn",Lady.MAP)
	for number in 6:
		f.erase("h_lily_ladies")
		game.save_data.js_trainer_id=number
		Lady.prepare(game,native)
		var state:=Lady.record(game)
		var lady: Dictionary=native.npcs[3]
		var companion: Dictionary=native.npcs[4]
		check(state.current==number>>1 and lady.native_gfx==Lady.GFX[number>>1],"trainer ID selects native lady "+str(number))
		check(Lady.visible(companion,f)==int(number>=4),"contest companion only on correct record")
		for actor in [lady,companion]:
			var sp:=Sprite2D.new()
			preload("res://core/hoenn_field.gd").draw(sp,actor,"down")
			check(sp.texture!=null,"overworld artwork "+actor.native_gfx)
			sp.free()
	var state:=Lady.record(game)
	state.current=0
	visit(Lady.MAP)
	check(game.world.npcs.any(func(n):return n.get("source_script","")==LADY and n.native_gfx==Lady.GFX[0]),"center spawns first visitor at original position")
	talk(LADY)
	choose("交换本地活动记录")
	dismiss()
	check(state.current==1 and game.world.npcs.any(func(n):return n.get("source_script","")==LADY and n.native_gfx==Lady.GFX[1]),"talking to lady swaps visible native actor")
	talk(LADY)
	choose("交换本地活动记录")
	dismiss()
	check(game.world.npcs.any(func(n):return n.get("source_script","").ends_with("ContestLadyMon")),"contest companion appears on actual floor")
	talk(LADY)
	choose("看看她想要什么")
	check(not game._dialogs.is_empty(),"interact with visiting contest lady without a block")
	dismiss()
	talk(LADY)
	choose("交换本地活动记录")
	dismiss()
	check(state.current==0 and not game.world.npcs.any(func(n):return n.get("source_script","").ends_with("ContestLadyMon")),"original visitor returns and companion leaves")
	test_quiz(state)
	test_favors(state)
	test_blocks(state)
	test_mail_and_sales()
	Save.clear_test_slot()
	print("LILYCOVE LADY ", "FAIL" if failed else "PASS"," (",checks," checks)")
	quit(1 if failed else 0)
