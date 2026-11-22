extends RefCounted
const SUITS:=["皮卡丘","胖丁","蚊香蝌蚪","走路草"]
const JOHTO_MONS:=[[63,5,100],[104,15,800],[202,15,1500]]
const KANTO_MONS:=[[25,25,2222],[137,15,5555],[246,40,8888]]
const JOHTO_TMS:=[[25,5500],[14,5500],[38,5500]]
const KANTO_TMS:=[[32,1500],[29,3500],[15,7500]]

static func enough(g,cost:int)->bool:
	if g._bag_count("代币盒")==0:g._dialog(["需要代币盒。"]);return false
	if int(g.save_data.get("j_coins",0))<cost:g._dialog(["代币不足。"]);return false
	return true

static func machine(g,obj:Dictionary)->bool:
	if g.world.map_data.get("id","") not in ["johto_goldenrod_game_corner","johto_celadon_game_corner","johto_celadon_game_corner_prize_room"]:return false
	var key:=str(obj.get("source_script",""))
	if key.ends_with("TMVendor") or key.ends_with("PokemonVendor"):prizes(g,key.ends_with("PokemonVendor"),false);return true
	if "CardFlip" in key:
		if enough(g,3):card(g,[])
		return true
	if "Slot" in key:
		if enough(g,1):g._pick("转轮　选择代币",["1 枚 · 中间一行","2 枚 · 三行","3 枚 · 三行及两条对角线"],func(i):
			if i>=0 and i<3 and enough(g,i+1):reels(g,i+1))
		return true
	return false

static func reels(g,bet:int):
	g.save_data.j_coins-=bet;g._persist()
	var ui=preload("res://scenes/crystal_reels.gd").new()
	g.menu_layer.add_child(ui);g.panel_open+=1;g.held_dir="";g._set_hud_visible(false)
	ui.setup(bet,g.rng)
	ui.finished.connect(func(won:int):
		g.save_data.j_coins=mini(9999,int(g.save_data.j_coins)+won)
		g.panel_open=maxi(0,g.panel_open-1);g._set_hud_visible(true);ui.queue_free()
		g._persist();g._dialog(["赢得了%d枚代币！"%won if won else "这次没有连成一线。"]))

static func card(g,discard:Array):
	if not enough(g,3):return
	var last:="" if discard.is_empty() else "　上张 %s%d"%[SUITS[int(discard[-1])%4],int(discard[-1])/4+1]
	g._pick("翻牌　每局3枚"+last,["猜一种花色 · 12枚","猜两个花色之一 · 6枚","猜一个数字 · 18枚","猜一对数字之一 · 9枚","猜一张牌 · 72枚"],func(i):
		if i<0 or i>4:return
		var labels:Array=[]
		var groups:Array=[]
		var rewards:=[12,6,18,9,72]
		for n in [4,2,6,3,24][i]:
			var ids:Array=[]
			for c in 24:
				var suit:=c%4
				var rank_value:=int(c/4)
				if [suit,int(suit/2),rank_value,int(rank_value/2),c][i]==n:ids.append(c)
			var label:String
			match i:
				0:label=SUITS[n]
				1:label="%s 或 %s"%[SUITS[2*n],SUITS[2*n+1]]
				2:label=str(n+1)
				3:label="%d 或 %d"%[2*n+1,2*n+2]
				_:label="%s %d"%[SUITS[n%4],n/4+1]
			labels.append(label);groups.append(ids)
		g._pick("要猜哪一组？",labels,func(j):
			if j<0 or j>=labels.size() or not enough(g,3):return
			var deck:=range(24).filter(func(c):return c not in discard)
			var draw:int=deck[g.rng.randi_range(0,deck.size()-1)]
			var won:=int(rewards[i]) if draw in groups[j] else 0
			g.save_data.j_coins=mini(9999,int(g.save_data.j_coins)-3+won);g._persist()
			var used:=discard+[draw]
			g._pick("翻开了%s %d　%s"%[SUITS[draw%4],draw/4+1,("赢得%d枚"%won if won else "未猜中")],["再来一局","收起代币盒"],func(k):
				if k==0:card(g,[] if used.size()>=12 else used))))

static func prizes(g,mon:bool,johto:bool):
	if not enough(g,0):return
	var goods:Array=JOHTO_MONS if johto else KANTO_MONS
	if not mon:goods=JOHTO_TMS if johto else KANTO_TMS
	var labels:Array=[]
	for row in goods:
		var name_text:String=g.get_node("/root/Data").species_of(row[0]).name if mon else "城都招式学习器 %02d"%row[0]
		labels.append("%s　%d枚"%[name_text,row[-1]])
	g._pick("兑换奖品　现有%d枚"%int(g.save_data.get("j_coins",0)),labels,func(i):
		if i<0 or i>=goods.size():return
		var row:Array=goods[i]
		if not enough(g,row[-1]):return
		if mon and g.PartyScript.occupied(g.save_data.party)>=g.PartyScript.MAX_SIZE:g._dialog(["请给奖品宝可梦留一个队伍空位。"]);return
		g.save_data.j_coins-=int(row[-1])
		if mon:
			var pokemon:Dictionary=g.PartyScript.make(row[0],row[1],g.EncounterScript.moves_for(row[0],row[1]))
			g._store_mon(pokemon)
		else:g._give_item("城都招式学习器 %02d"%row[0],1,"tm")
		g._persist();g._dialog(["奖品已经交给你了。"],"奖品柜台"))
