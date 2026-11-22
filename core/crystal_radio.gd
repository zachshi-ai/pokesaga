extends RefCounted
const LABELS:={"talk":"4.5　大木博士的宝可梦讲座","dex":"4.5　宝可梦图鉴节目","music":"7.5　宝可梦音乐","lucky":"8.5　幸运频道","buena":"10.5　小葵的口令","alph":"13.5　神秘电波","places":"16.5　名人与名胜","sing":"18.5　大家一起唱","flute":"20.0　宝可梦之笛","signal":"20.5　奇怪的电波"}
const SONGS:={"talk":"profoakspokemontalk","dex":"pokemoncenter","lucky":"gamecorner","buena":"buenaspassword","alph":"ruinsofalphradio","places":"viridiancity","sing":"bicycle","flute":"pokeflutechannel","signal":"lakeofragerocketradio"}
const ROUTES:=[29,46,30,32,34,35,37,38,39,42,43,44,45,36,31]
const PASSWORDS:=[["火球鼠","小锯鳄","菊草叶"],["美味之水","劲爽汽水","果汁牛奶"],["伤药","解毒药","麻痹药"],["精灵球","超级球","高级球"],["皮卡丘","小拉达","小拳石"],["咕咕","圆丝蛛","催眠貘"],["若叶镇","吉花市","桧皮镇"],["飞行","虫","草"],["撞击","叫声","掷泥"],["力量强化","防御强化","速度强化"],["宝可梦讲座","宝可梦音乐","幸运频道"]]
static var sites:Dictionary
static func local(g)->Array:
	if sites.is_empty():sites=JSON.parse_string(FileAccess.get_file_as_string("res://content/regions/johto/radio.json"))
	if g.world.map_data.get("region","")!="johto":return []
	return sites.get(g.world.map_data.id,[])

static func passwords(day:Dictionary)->Array:
	var seed_value:=preload("res://core/crystal_phone.gd").current_day(day)
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	var group:Array=PASSWORDS[rng.randi_range(0,PASSWORDS.size()-1)]
	return [group,group[rng.randi_range(0,group.size()-1)]]

static func stations(g,day:Dictionary)->Array:
	var area:=local(g)
	if area.is_empty():return []
	var channels:Array=[]
	if area[1]:
		channels=["dex" if day.hour>=4 and day.hour<10 else "talk","music","lucky","buena"]
		if area[0]=="RUINS_OF_ALPH":channels.append("alph")
		if area[0] in ["ROUTE_43","MAHOGANY_TOWN","LAKE_OF_RAGE"] and not g._flags().get("j_plant_clear",false):channels.append("signal")
	elif g._bag_count("收音机扩充卡")>0:channels=["places","sing","flute"]
	return channels

static func track(g,station:String,day:Dictionary)->String:
	if not station in stations(g,day):return ""
	if station in ["talk","dex","music","lucky","buena"] and g._flags().get("j_radio_takeover",false) and not g._flags().get("j_radio_free",false):return "rockettheme"
	if station=="music":return "pokemonmarch" if int(day.weekday)%2==0 else "pokemonlullaby"
	return SONGS[station]

static func playing(g)->String:
	var key:String=g.save_data.get("js_radio","")
	return "" if key=="" else track(g,key,Time.get_datetime_dict_from_system())

static func factor(g)->float:
	match playing(g):
		"pokemonmarch","ruinsofalphradio":return 2.0
		"pokemonlullaby":return 0.5
	return 1.0

static func radio(g):
	var day:=Time.get_datetime_dict_from_system()
	var ids:=stations(g,day)
	var labels:Array=ids.map(func(k):return LABELS[k])
	labels.append("关掉收音机")
	g._pick("宝可装置 · 调频",labels,func(i):
		if i<0 or i>=labels.size():return
		if i==ids.size():
			g.save_data.erase("js_radio");g._flags().j2_flute=false;g._update_music();g._persist()
		else:tune(g,ids[i],day))

static func tune(g,key:String,day:Dictionary):
	var song:=track(g,key,day)
	if song=="":return
	g.save_data.js_radio=key;g._flags().j2_flute=(key=="flute")
	g.snd.play_music("crystal_"+song);g._persist()
	if song=="rockettheme":
		g._dialog(["满金广播塔已被占领。火箭队正借着广播向曾经的首领喊话。"],"火箭队广播");return
	var content:Array=[]
	match key:
		"dex","talk":
			var route_number:int=ROUTES[g.rng.randi_range(0,ROUTES.size()-1)]
			var area:Dictionary=g.get_node("/root/Data").load_map("johto","johto_route_"+str(route_number))
			var pool:Array=area.encounters
			var broadcast_hour:String=["morn","day","nite"][g.rng.randi_range(0,2)]
			pool=area.get("encounters_by_time",{}).get(broadcast_hour,{}).get("pool",pool)
			var entry:Dictionary=pool[g.rng.randi_range(0,pool.size()-1)]
			var sp:Dictionary=g.get_node("/root/Data").species_of(entry.species)
			if key=="talk":content=["胡桃：博士，今天在哪儿可以观察宝可梦？","大木：试试%d号道路。有人在那里发现了%s！"%( [route_number,sp.name] )]
			else:content=["今日图鉴　No.%03d　%s"%[sp.id,sp.name],"调查记录：%d号道路的%s，常见等级为%d。"%[route_number,sp.name,entry.min]]
		"music":content=["今天播放宝可梦进行曲。精神抖擞的伙伴会被吸引过来。" if song=="pokemonmarch" else "今天播放宝可梦摇篮曲。周围的野生伙伴会安静下来。"]
		"lucky":
			var lucky:=preload("res://core/crystal_phone.gd").lottery_number(g,day)
			content=["本周号码是 %05d。请到满金广播塔一楼对照宝可梦的训练家编号。"%lucky]
		"buena":content=["今晚的口令是「%s」。来广播塔二楼找我吧。"%passwords(day)[1] if day.hour>=18 else "节目每天晚上六点开播。"]
		"alph":content=["……沙……沙……遗迹深处传来了反复变调的信号。"]
		"signal":content=["奇怪的音调从卡吉镇方向反复传来。湖里的鲤鱼王变得十分躁动。"]
		"places":
			var list:Array=["真新镇的大木博士正在研究宝可梦图鉴。","在华蓝市北边，有一条训练家们熟悉的桥。","到了红莲岛，可以在宝可梦中心歇脚。"]
			if g._flags().get("johto_champion",false):list.append("深灰道馆的小刚擅长岩石系，在深灰市等待挑战。")
			content=[list[g.rng.randi_range(0,list.size()-1)]]
		"sing":content=["大家一起唱！跟着节拍，和旅途中的宝可梦一起哼唱。"]
		"flute":content=["清亮的笛声响起来了。附近熟睡的宝可梦似乎动了动。"]
	g._dialog(content,LABELS[key])
