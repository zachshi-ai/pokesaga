extends RefCounted
## The three café masters each keep their own daily battle. Hotel quests live in their guest rooms.
const SCREECH := "伽勒尔招式学习器16·刺耳声"
const TEARS := "伽勒尔招式学习器47·假哭"
const CHARM := "不晃捕捉护符"
const SWEETS := {"草莓糖饰":"STRAWBERRY","爱心糖饰":"LOVE","野莓糖饰":"BERRY","四叶糖饰":"CLOVER","花朵糖饰":"FLOWER"}
const GIFTS := [
 ["哞哞鲜奶",5,3,1],["熔岩饼干",3,3,3],["树果汁",3,3,3],["神奇糖果",5,5,10],
 ["森之羊羹",3,3,3],["心形甜点",3,3,3],["愤怒馒头",3,3,3],["飞云冰淇淋",3,3,3],
 ["泡沫奶油",8,6,4],["香袋",8,6,4],["密阿雷格雷派饼",3,3,3],["娑罗沙布蕾",3,3,3],
 ["大马拉萨达",3,3,3],["深灰米果",3,3,3],["经验糖果XS",6,0,0],["经验糖果S",10,8,0],
 ["经验糖果M",0,8,12],["经验糖果L",0,0,5],["草莓糖饰",20,2,2],["爱心糖饰",2,14,2],
 ["野莓糖饰",2,14,2],["四叶糖饰",2,2,14],["花朵糖饰",2,2,14]]
const Candy := preload("res://core/party.gd")
const Records := preload("res://core/dex_variants.gd")
const SUSPECTS := ["我进来的时候，桌上的树果还在。","我听见床边有很轻的脚步声。","窗户一直关着。看看屋里谁在嚼东西？"]
static var catalog:Dictionary

static func data()->Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_hotel.json"))
	return catalog

static func team(city:String,early:bool)->Array:
	if city=="motostoke":
		if early:return [{"species":415,"level":10,"moves":[230,16,522,450]}]
		return [{"species":684,"level":24,"moves":[178,584,496,589]},{"species":868,"level":24,"moves":[213,186,230,577]}]
	if city=="hammerlocke":return [{"species":685,"level":37,"moves":[583,496,270,412]},{"species":869,"level":37,"moves":[605,496,213,345]}]
	return [{"species":685,"level":47,"moves":[605,53,270,85]},{"species":869,"level":47,"moves":[605,105,94,345]}]

static func cafe(g,city:String)->void:
	var f:Dictionary=g._flags()
	var today:=Time.get_date_string_from_system()
	var key:="g_cafe_"+city
	if f.get(key,"")==today:g._dialog(["今天的对战已经结束了。明天再来喝杯茶吧。"],"咖啡店长");return
	var party:=team(city,not f.get("g_badge_2",false))
	g._pick("每天一场咖啡馆对战，赢了有点心。",["接受挑战","下次再来"],func(i):
		if i!=0:return
		g._start_battle({"name":"咖啡店长","battle":{"team":party,"double":party.size()>1}},func(outcome):
			if outcome!="a":return
			var gift:=choose_gift(city,g.rng)
			var category:="evo" if gift in ["泡沫奶油","香袋"] else "medicine" if gift=="神奇糖果" or gift.begins_with("经验糖果") or SWEETS.has(gift) else "heal"
			g._give_item(gift,1,category)
			f[key]=today;g._persist()
			g._dialog(["这是今天的小礼物，收下%s吧。"%gift],"咖啡店长")))

static func choose_gift(city:String,rng:RandomNumberGenerator)->String:
	var column:=1+["motostoke","hammerlocke","wyndon"].find(city)
	var total:=0
	for row in GIFTS:total+=int(row[column])
	var draw:=rng.randi_range(0,total-1)
	for row in GIFTS:
		draw-=int(row[column])
		if draw<0:return row[0]
	return ""

static func sweet(g,name:String)->void:
	var slots:Array=[];var labels:Array=[]
	for i in g.save_data.party.size():
		var m:Dictionary=g.save_data.party[i]
		if int(m.get("species_id",0))==868 and not m.get("egg",false):
			slots.append(i);labels.append(str(m.name))
	if slots.is_empty():g._dialog(["队伍里没有可以和你转圈的仙奶宝可梦。"]);return
	g._pick("把"+name+"交给哪只小仙奶，一起转圈？",labels,func(i):
		var m:Dictionary=g.save_data.party[slots[i]]
		if Candy.evolve(m,869,"ALCREMIE_"+str(SWEETS[name])):
			Records.record(g.save_data,m,true);g._consume_item(name);g._persist()
			g._dialog(["小仙奶转着圈，进化成了带着"+name+"的霜奶仙！"]))

static func morimoto(g)->void:
	var f:Dictionary=g._flags()
	var today:=Time.get_date_string_from_system()
	if not f.get("g_champion",false):g._dialog(["成为冠军以后，再来这里和我对战吧。"],"森本");return
	if f.get("g_morimoto","")==today:g._dialog(["今天打得很过瘾。明天再来吧。"],"森本");return
	var party:Array=[]
	for id in [864,853,874,887,839,143]:party.append({"species":id,"level":65})
	g._pick("要和森本进行双打吗？",["对战","下次再来"],func(i):
		if i:return
		g._start_battle({"name":"森本","battle":{"team":party,"double":true,"galar_power_spot":true,"galar_ace":143}},func(outcome):
			if outcome!="a":return
			if not f.has("g_morimoto"):
				if g._bag_count("圆形护符")==0:g._give_item("圆形护符",1,"key")
				f.ks_oval=true
			f.g_morimoto=today;g._persist();g._dialog(["这枚圆形护符会让寄放在培育屋的伙伴更容易留下蛋。"],"森本")))

static func director(g)->void:
	var f:Dictionary=g._flags()
	if not f.get("g_director_catch",false):
		if not g._bag_count(CHARM):g._give_item(CHARM,1,"key")
		f.g_director_catch=true;g._persist();g._dialog(["送给你一枚不晃捕捉护符。把它放在包里，在伽勒尔投球时更容易触发会心捕捉。"],"游戏总监");return
	var owned:Dictionary={}
	for id in g.save_data.get("dex",{}).get("caught",[]):owned[int(id)]=true
	var missing:int=data().dex.filter(func(id):return not owned.has(int(id))).size()
	if missing:g._dialog(["还差 %d 种就集齐伽勒尔图鉴了。"%missing],"游戏总监");return
	if not f.get("g_director_shiny",false):
		if not g._bag_count("闪耀护符"):g._give_item("闪耀护符",1,"key")
		f.g_director_shiny=true;f.ks_shiny=true;g._persist()
	g._dialog(["恭喜集齐伽勒尔图鉴！带着闪耀护符出发吧。"],"游戏总监")

static func award_tm(g,name:String)->void:
	if g._bag_count(name)==0:g._give_item(name,1,"tm");g._persist()
	g._dialog(["这张%s可以反复教给合适的伙伴。"%name])

static func use(g,name:String)->bool:
	if SWEETS.has(name):sweet(g,name);return true
	if name==CHARM:g._dialog(["放在包里就能提高伽勒尔会心捕捉的触发率。"]);return true
	if name not in [SCREECH,TEARS]:return false
	var id:=103 if name==SCREECH else 313
	var slots:Array=[];var labels:Array=[]
	for i in g.save_data.party.size():
		var m:Dictionary=g.save_data.party[i]
		if m.get("egg",false) or int(m.get("species_id",0)) not in data()[str(id)]:continue
		slots.append(i);labels.append(str(m.name))
	if slots.is_empty():g._dialog(["队伍里没有能学习这个招式的宝可梦。"])
	else:g._pick("让谁学习？",labels,func(i):g._tm_teach_one(id,slots[i],"刺耳声" if id==103 else "假哭",true))
	return true

static func talk(g,role:String)->void:
	var f:Dictionary=g._flags()
	if role in ["venue_fitting","venue_style_guest"] or role.begins_with("venue_salon_") or role.begins_with("venue_boutique_"):
		preload("res://core/galar_fashion.gd").talk(g,role);return
	if role.begins_with("venue_cafe_"):cafe(g,role.trim_prefix("venue_cafe_"));return
	if role.begins_with("venue_suspect_"):
		var i:=int(role.get_slice("_",2))
		if f.get("g_ionia_case",false):f["g_ionia_guest_"+str(i)]=true;g._persist()
		g._dialog([SUSPECTS[i]]);return
	match role:
		"venue_morimoto":morimoto(g)
		"venue_director":director(g)
		"venue_screech":award_tm(g,SCREECH)
		"venue_tears":award_tm(g,TEARS)
		"venue_detective":
			f.g_ionia_case=true;g._persist()
			g._dialog(["树果失踪案已经结案，多谢你。" if f.get("g_ionia_solved",false) else "客人的树果不见了。帮我问问屋里的三位客人，再去和你怀疑的家伙说话。"],"侦探")
		"venue_skwovet":
			if f.get("g_ionia_solved",false) or not f.get("g_ionia_guest_0",false) or not f.get("g_ionia_guest_1",false) or not f.get("g_ionia_guest_2",false):
				g._dialog(["它鼓着腮帮盯着你。"],"贪心栗鼠");return
			g._give_bag_item("广角镜","held","WIDE_LENS")
			f.g_ionia_solved=true;g._persist()
			g._dialog(["它的嘴里掉出了被偷走的树果！","谢谢你破了案，这枚广角镜给你。"],"侦探")
