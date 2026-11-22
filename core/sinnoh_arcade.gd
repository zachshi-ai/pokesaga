extends RefCounted

const FR:=preload("res://core/frlg_sidequests.gd")
const GAME:=preload("res://scenes/sinnoh_slots.gd")
const LIMIT:=50000
const HIDDEN_TYPES:=["fighting","flying","poison","ground","rock","bug","ghost","steel","fire","water","grass","electric","psychic","ice","dragon","dark"]
const CHAT:={"GameCorner_LadyExplainSlotMachines":"平时从左轮开始停。皮皮出现后盯住红七，奖励局要照着它指的顺序停轮。","GameCorner_MaylenesDad":"皮皮是一位好伙伴。它朝哪边指，你就按哪边。","GameCorner_Guitarist":"我朋友靠机台赢了好多代币。奖品都在隔壁换。","GameCorner_Worker":"先去找柜台买代币吧！","GameCorner_LadyPokeBalls":"皮皮探出头的时候，就看你的本领啦。","VeilstoneCityPrizeExchange_OldMan":"这里的学习器都是用帷幕的代币兑换的。"}

static func interact(g,side,script: String) -> bool:
	if script=="VeilstoneCitySoutheastHouse_Clown":
		if g._flags().get("s_coin_case",false):FR.say(g,"我知道了，你又来看我变戏法！","小丑")
		else:
			var hand: int=g.rng.randi_range(0,1)
			g._pick("小丑把代币藏进了哪只手？",["右手","左手"],func(i):
				if i!=hand:FR.say(g,"猜错啦！再看一遍我的表演吧。","小丑")
				else:
					if g._bag_count("代币盒")==0:g._give_item("代币盒",1,"key")
					side.change(g,"s_coin_case")
					FR.say(g,"猜对了！这个代币盒送给你。","小丑"))
		return true
	if CHAT.has(script):
		FR.say(g,CHAT[script],"帷幕游戏厅")
		return true
	if script=="GameCorner_Looker":
		FR.say(g,"严酷山的事已经解决。我在这里照顾自己的宝可梦。" if g._flags().get("s_charon_arrested",false) else "嘘，调查员偶尔也需要休息。","帅哥")
		return true
	if script=="VeilstoneCityPrizeExchange_Guitarist":
		FR.pick_party(g,"查看哪只宝可梦的觉醒力量？",func(m):return not m.get("is_egg",false),func(i):
			var m: Dictionary=g.save_data.party[i]
			var value:=0
			var stats:=["hp","atk","def","spe","spa","spd"]
			for k in stats.size():value+=(int(m.get("ivs",{}).get(stats[k],31))%2)<<k
			var type_name: String=g.get_node("/root/Data").type_name(HIDDEN_TYPES[floori(value*15.0/63.0)])
			FR.say(g,"它的觉醒力量是%s属性。"%type_name if side.data().machines.TM10.species.has(float(m.species_id)) else "它不能学习觉醒力量。","吉他手"))
		return true
	if script=="GameCorner_BgSignBonusRounds":
		FR.say(g,"最高连续奖励 %d 轮。连续完成十轮后，去柜台领取纪念品。"%int(g.save_data.get("s_slots_record",0)),"机台记录")
		return true
	if not (script.begins_with("GameCorner_SlotMachine_") or script in ["GameCorner_CoinsClerk","GameCorner_OldMan20Coins","GameCorner_Farmer","VeilstoneCityPrizeExchange_Receptionist"]):return false
	if g._bag_count("代币盒")==0:
		FR.say(g,"要带代币盒才能使用。帷幕市东南屋里的小丑会变个戏法。","帷幕游戏厅")
		return true
	var coins:=int(g.save_data.get("s_coins",0))
	if script.begins_with("GameCorner_SlotMachine_"):
		open(g,int(script.get_slice("_",2)))
	elif script=="GameCorner_CoinsClerk":
		if int(g.save_data.get("s_slots_record",0))>=10 and not g._flags().get("s_slots_tm64",false):side.receive(g,"s_slots_tm64","TM64",1,"游戏厅柜台")
		else:
			g._pick("帷幕代币　%d / 50000"%coins,["50 枚　₽1000","500 枚　₽10000","离开"],func(i):
				if i>1:return
				var n:=50 if i==0 else 500
				if coins+n>LIMIT or int(g.save_data.money)<n*20:FR.say(g,"钱不够，或代币盒放不下这些代币。","游戏厅柜台")
				else:
					g.save_data.money-=n*20
					g.save_data.s_coins=coins+n
					g._persist()
					FR.say(g,"已收下 %d 枚代币。"%n,"游戏厅柜台"))
	elif script=="VeilstoneCityPrizeExchange_Receptionist":
		var goods: Array=side.data().game_prizes
		var names: Array=[]
		for row in goods:
			var title: String=side.item_name(row[0])
			if str(row[0]).begins_with("TM"):title="%s · %s"%[row[0],g.get_node("/root/Data").move_of(int(side.data().machines[row[0]].move)).name]
			names.append("%s　%d 枚"%[title,int(row[1])])
		g._pick("奖品兑换　持有 %d 枚"%coins,names+["返回"],func(i):
			if i>=goods.size():return
			var row: Array=goods[i]
			if coins<int(row[1]):FR.say(g,"兑换这个奖品还差 %d 枚。"%(int(row[1])-coins),"奖品兑换")
			else:
				g._pick("用 %d 枚兑换%s？"%[int(row[1]),side.item_name(row[0])],["兑换","取消"],func(j):
					if j!=0 or int(g.save_data.get("s_coins",0))<int(row[1]):return
					g.save_data.s_coins-=int(row[1])
					side.give(g,row[0])
					g._persist()
					FR.say(g,"收下了%s。"%side.item_name(row[0]),"奖品兑换")))
	else:
		var n:=20 if script=="GameCorner_OldMan20Coins" else 50
		var flag:="s_coins_gift_%d"%n
		if g._flags().get(flag,false) or coins+n>LIMIT:FR.say(g,"试试那边的机器。皮皮出现时要留心！","游戏厅客人")
		else:
			g.save_data.s_coins=coins+n
			side.change(g,flag)
			FR.say(g,"这些 %d 枚代币给你！"%n,"游戏厅客人")
	return true

static func open(g,number: int) -> void:
	if not g.save_data.has("s_slot_grades"):
		var grades:=[0,5,1,1,4,4,2,2,2,3,3,3]
		for i in 12:
			for j in range(i+1,12):
				var idx: int=g.rng.randi_range(0,11)
				var value=grades[i]
				grades[i]=grades[idx]
				grades[idx]=value
		g.save_data.s_slot_grades=grades
		g._persist()
	var ui:=GAME.new()
	ui.name="VeilstoneSlots"
	g.menu_layer.add_child(ui)
	g.panel_open+=1
	g._set_hud_visible(false)
	g.held_dir=""
	ui.setup(int(g.save_data.get("s_coins",0)),int(g.save_data.get("s_slots_record",0)),number,int(g.save_data.s_slot_grades[number]),g.rng)
	ui.settled.connect(func(delta,best):
		g.save_data.s_coins=clampi(int(g.save_data.get("s_coins",0))+int(delta),0,LIMIT)
		g.save_data.s_slots_record=maxi(int(best),int(g.save_data.get("s_slots_record",0)))
		g._persist())
	ui.closed.connect(func():
		g.panel_open=maxi(0,g.panel_open-1)
		g._set_hud_visible(g.panel_open==0))
