extends RefCounted
const HOME:="johto_players_house_2f"
const SQUARE:="johto_mount_moon_square"
const SHOP:=[[900,600,"好伤药"],[4000,270,"除虫喷雾"],[7000,600,"好伤药"],[10000,1800,"doll_charmander"],[15000,3000,"月之石"],[19000,600,"好伤药"],[30000,4800,"doll_clefairy"],[40000,900,"厉害伤药"],[50000,8000,"doll_pikachu"],[100000,22800,"doll_big_snorlax"]]
const EXTRA:=[[600,"好伤药"],[90,"解毒药"],[180,"精灵球"],[450,"离洞绳"],[500,"超级球"]]
const DOLLS:={"doll_charmander":"小火龙玩偶","doll_clefairy":"皮皮玩偶","doll_pikachu":"皮卡丘玩偶","doll_big_snorlax":"大卡比兽玩偶"}
const PLACES:=["左侧","右侧","大型摆位"]
const POSITIONS:=[[7,9],[9,9],[8,10]]

static func bank(g)->Dictionary:
	if not g.save_data.has("js_mom"):
		g.save_data.js_mom={"balance":0,"saving":false,"index":0,"next_extra":2300,"parcels":[]}
	return g.save_data.js_mom

static func management(g,phone:=false):
	var a:=bank(g)
	var balance:=int(a.balance)
	var labels:=["停止代存" if a.saving else "请妈妈代存奖金"]
	if not phone:labels.append_array(["存入零用钱","取出存款"])
	g._pick("妈妈　存款 ¥%d"%balance,labels,func(i):
		if i==0:
			a.saving=not a.saving;g._persist()
			g._dialog(["以后每场训练家对战的奖金，我会帮你存四分之一。" if a.saving else "以后奖金就都由你随身带着。"],"妈妈")
		elif not phone and i in [1,2]:amount(g,i==1))

static func amount(g,deposit:bool):
	var a:=bank(g)
	var available:=mini(int(g.save_data.money),999999-int(a.balance)) if deposit else mini(int(a.balance),999999-int(g.save_data.money))
	if available<=0:g._dialog(["现在没有可转的金额。"],"妈妈");return
	var values: Array=[]
	for n in [100,1000,10000,available]:
		if n<=available and n not in values:values.append(n)
	var options:Array=values.map(func(n):return "¥%d"%n)
	options.append("输入其他金额")
	g._pick("存入多少钱？" if deposit else "取出多少钱？",options,func(i):
		if i<0 or i>=options.size():return
		if i<values.size():transfer(g,deposit,values[i]);return
		var popup:=ConfirmationDialog.new();popup.title="输入金额"
		var amount_box:=SpinBox.new();amount_box.min_value=1;amount_box.max_value=available;amount_box.value=1
		popup.add_child(amount_box);g.menu_layer.add_child(popup);g.panel_open+=1
		popup.confirmed.connect(func():transfer(g,deposit,int(amount_box.value)))
		popup.visibility_changed.connect(func():
			if not popup.visible:
				popup.queue_free();g.panel_open=maxi(0,g.panel_open-1))
		popup.popup_centered(Vector2i(300,150)))

static func transfer(g,deposit:bool,total:int):
	var a:=bank(g)
	if total<=0:return
	var delta:=total if deposit else -total
	if int(a.balance)+delta<0 or int(a.balance)+delta>999999 or int(g.save_data.money)-delta<0 or int(g.save_data.money)-delta>999999:return
	a.balance+=delta;g.save_data.money-=delta
	g._persist();g._dialog(["现在的存款是%d元。"%a.balance],"妈妈")

static func share_prize(g,prize:int)->int:
	if g.world.map_data.get("region","")!="johto" or not g.save_data.get("js_mom",{}).get("saving",false):return prize
	var a:=bank(g)
	var deposit:=mini(prize/4,999999-int(a.balance))
	a.balance+=deposit
	return prize-deposit

static func shopping(g):
	var a:Dictionary=g.save_data.get("js_mom",{})
	if a.is_empty() or not g.world.map_data.get("cycling",false):return
	var i:=int(a.index)
	var cost:=0
	var item:=""
	if i<SHOP.size() and int(a.balance)>=int(SHOP[i][0]):
		cost=SHOP[i][1];item=SHOP[i][2];a.index+=1
	else:
		while int(a.next_extra)<int(a.balance):a.next_extra+=2300
		if int(a.balance)!=int(a.next_extra):return
		var row:Array=EXTRA[g.rng.randi_range(0,EXTRA.size()-1)]
		cost=row[0];item=row[1];a.next_extra+=2300
	a.balance-=cost
	if DOLLS.has(item):
		g._flags().get_or_add("js_dolls_owned",{})[item]=true
		g._show_toast("妈妈打来电话：买到了%s！回家在电脑上布置吧。"%DOLLS[item])
	else:
		a.parcels.append(item)
		g._show_toast("妈妈打来电话：给你买的%s已经放进电脑了。"%item)
	g._persist()

static func parcels(g):
	var a:=bank(g)
	if a.parcels.is_empty():g._dialog(["电脑里没有妈妈寄存的物品。"]);return
	var items:Array=a.parcels.duplicate()
	g._pick("妈妈买来的物品",items,func(i):
		if i<0 or i>=items.size() or not items[i] in a.parcels:return
		var item:String=items[i];a.parcels.erase(item)
		g._give_item(item,1,"ball" if item.ends_with("球") else "other");g._persist()
		g._dialog(["取出了%s。"%item],"道具电脑"))

static func computer(g):
	g._pick("小悠的电脑",["宝可梦寄存系统","妈妈买来的物品","装饰房间"],func(i):
		if i==0:g._open_pc(false)
		elif i==1:parcels(g)
		elif i==2:decorate(g))

static func decorate(g):
	g._pick("把玩偶摆在哪里？",PLACES,func(i):
		if i<0 or i>2:return
		var placed:Dictionary=g._flags().get_or_add("js_dolls_placed",{})
		var keys:Array=[""]
		var options:Array=["收起这个位置的玩偶"]
		for key in DOLLS:
			if g._flags().get("js_dolls_owned",{}).has(key) and (i==2)==(key=="doll_big_snorlax"):
				keys.append(key);options.append(DOLLS[key])
		g._pick(PLACES[i],options,func(j):
			if j<0 or j>=keys.size():return
			var key:String=keys[j]
			for slot in placed.keys():
				if placed[slot]==key:placed.erase(slot)
			placed[str(i)]=key
			g.world.refresh_story_actors(g._flags());g._persist()
			g._dialog(["已经收起了。" if key=="" else "摆好了%s。"%DOLLS[key]])))

static func date(day:Dictionary)->int:return preload("res://core/crystal_phone.gd").current_day(day)

static func square_open(day:Dictionary,flags:Dictionary)->bool:
	return int(day.weekday)==1 and (day.hour<4 or day.hour>=18) and int(flags.get("js_moon_dance",-1))!=date(day)

static func roster(mid:String,rows:Array,flags:Dictionary,day:Dictionary)->Array:
	if mid==HOME:
		var result:=rows.duplicate()
		var placed:Dictionary=flags.get("js_dolls_placed",{})
		for i in 3:
			var key:String=placed.get(str(i),"")
			if DOLLS.has(key):
				result.append({"at":POSITIONS[i],"hgss_native":true,"name":DOLLS[key],"field_art":"crystal_"+key,"crystal_quest":"home_doll"})
		return result
	if mid!=SQUARE:return rows
	var others:=rows.filter(func(n):return n.name not in ["妖精","居民"])
	if flags.get("js_moon_dancing",false):
		for i in 2:
			var at:Array=[[8,12],[10,12]][i]
			others.append({"at":at,"hgss_native":true,"name":"皮皮","role":"cr_moon_dancer"+str(i),"field_art":"crystal_clefairy"})
	if flags.get("js_moon_rock",false):
		others.append({"at":[9,12],"hgss_native":true,"name":"月光下的岩石","gfx":"rock","crystal_quest":"moon_rock","field_art":"crystal_moon_rock"})
	return others

static func interact(g)->bool:
	var tile:Vector2i=g.world.player_pos+g.world._dir_vec()
	if g.world.map_data.id==HOME and tile==Vector2i(6,4):
		computer(g);return true
	if g.world.map_data.id==SQUARE and tile==Vector2i(9,12) and g._flags().get("js_moon_stone",false) and not g._flags().get("js_moon_rock",false):
		g._give_item("月之石",1,"other");g._flags().js_moon_stone=false;g._persist();g._dialog(["在刚才岩石的位置找到了一块月之石！"]);return true
	return false

static func smash(g):
	if not g._party_can_move("ROCK_SMASH"):
		g._dialog(["这块石头上有裂纹，伙伴的碎岩或许能击碎它。"]);return
	g._pick("用碎岩砸开石头？",["使用碎岩","离开"],func(i):
		if i==0:
			g._flags().js_moon_rock=false;g.world.refresh_story_actors(g._flags());g._persist()
			g._dialog(["石头碎开了。它下面似乎有东西在发光。"]))

static func field_step(g,day:Dictionary):
	if g.world.map_data.get("region","")!="johto":return
	if g.world.map_data.id==SQUARE and square_open(day,g._flags()) and g.world.player_pos==Vector2i(9,13):
		dance(g,day);return
	shopping(g)

static func dance(g,day:Dictionary):
	if not square_open(day,g._flags()) or g._flags().get("js_moon_dancing",false):return
	var f:Dictionary=g._flags()
	f.js_moon_dancing=true
	g.panel_open+=1;g.held_dir="";g.run_held=false
	g.world.refresh_story_actors(f)
	var first: String="cr_moon_dancer0"
	var second: String="cr_moon_dancer1"
	g.snd.play_sfx("confirm")
	g.world.play_actor_paths(first,"ULRRDL","")
	await g.world.play_actor_paths(second,"URULLD","")
	g.world.play_actor_paths(first,"RRRRR","")
	await g.world.play_actor_paths(second,"RRRRR","")
	f.erase("js_moon_dancing")
	f.js_moon_dance=date(day);f.js_moon_stone=true;f.js_moon_rock=true
	g.world.refresh_story_actors(f);g.panel_open=maxi(0,g.panel_open-1);g._persist()
	g._dialog(["两只皮皮一齐跃起，向东方跑远了。广场上留下了一块岩石。"])
