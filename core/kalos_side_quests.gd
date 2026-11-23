extends RefCounted
const FR := preload("res://core/frlg_sidequests.gd")
const Dex := preload("res://core/dex_variants.gd")
const Party := preload("res://core/party.gd")
const FOSSILS := {"颚之化石":696,"鳍之化石":698,"秘密琥珀":142,"根状化石":345,"爪子化石":347,"贝壳化石":138,"甲壳化石":140,"盾甲化石":410,"头盖化石":408,"背盖化石":564,"羽毛化石":566}
const ROADS := [2,3,4,5,6,7,8,10,11,12,14,15,16,18,19,20,21,22]
const BIRDS := {650:144,653:145,656:146}
const TEAMS_PATH := "res://content/kalos_trainers.json"
static var trainers: Dictionary

static func side():
	return load("res://core/kalos_side.gd")

static func team(id: int,flags: Dictionary={}) -> Array:
	if trainers.is_empty():trainers=JSON.parse_string(FileAccess.get_file_as_string(TEAMS_PATH))
	var table: Dictionary=trainers.y if flags.get("k_version","x")=="y" and trainers.y.has(str(id)) else trainers.teams
	return table.get(str(id),[]).duplicate(true)

static func battle(g,who: String,id: int,win: Callable) -> void:
	var foes:=team(id,g._flags())
	if foes.is_empty() or not g._has_party():g._dialog(["先带上可出战的伙伴，再来挑战。"],who);return
	g._start_battle({"name":who,"battle":{"team":foes}},func(outcome):
		if outcome=="a":win.call()
		elif g._party_fainted():g._blackout())

static func bird_id(flags: Dictionary) -> int:
	return int(BIRDS.get(int(flags.get("k_starter",650)),144))

static func say(g,r: Dictionary,text: String) -> void:
	var milestone: int={"case2":5,"mimi":5,"gang2":5,"suit2":5,"essentia3":5,"farewell":20}.get(r.id,0)
	if milestone>0 and not g._flags().get("ks_"+str(r.id),false):
		g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+milestone)
	side().save_event(g,r)
	g._dialog([text],r.name)

static func interact(g,r: Dictionary) -> void:
	var f: Dictionary=g._flags()
	match str(r.action):
		"scene":
			say(g,r,str(r.txt))
		"case_fight":
			battle(g,r.name,int(r.team),func():say(g,r,str(r.txt)))
		"ticket":
			g._give_item("帅哥券",1,"key")
			say(g,r,"捡到了一张帅哥券。带回帅哥事务所交给帅哥吧。")
		"ticket_return":
			if g._bag_count("帅哥券")<5:
				g._dialog(["目前收集了 %d / 5 张。还要去洋红广场的宝可梦中心、棱镜塔、药草店、大酒店和美术馆找找。"%g._bag_count("帅哥券")],"帅哥")
				return
			for i in 5:g._consume_item("帅哥券")
			say(g,r,str(r.txt))
		"mimi":
			g._pick("小弥正偷偷看着你。",["跳舞","微笑","模仿它叫","追过去","离开"],func(i):
				if i in [0,1,2]:say(g,r,"小弥收起警惕，轻轻碰了碰你的手。帅哥邀请它和玛琪艾儿搬进事务所。")
				elif i==3:g._dialog(["小弥缩进黑暗里。慢一点，让它愿意自己走过来。"]))
		"rematch":
			var today:=Time.get_date_dict_from_system()
			var stamp:=Time.get_date_string_from_system()
			if not int(today.weekday) in [2,4,6] or g.save_data.get("kalos_essentia_date","")==stamp:
				g._dialog(["事务所今天还有委托。每周二、四、六，你可以来这里和强化服对战。"],r.name);return
			battle(g,r.name,int(r.team),func():g.save_data.kalos_essentia_date=stamp;g._persist();g._dialog(["小弥也记住了你们的配合。"],r.name))
		"train":
			if g._bag_count("ＴＭＶ自由票")==0:g._give_item("ＴＭＶ自由票",1,"key")
			f.k_train_pass=true
			say(g,r,"恭喜你成为卡洛斯冠军。凭这张ＴＭＶ自由票，随时可以乘车来往密阿雷和奇楠市。")
		"rival":
			var stamp:=Time.get_date_string_from_system()
			if g.save_data.get("kalos_rival_date","")==stamp:g._dialog(["明天还在这里见吧。"],r.name);return
			var ix: int=[650,653,656].find(int(f.get("k_starter",650)))
			battle(g,r.name,599+maxi(0,ix),func():
				g.save_data.kalos_rival_date=stamp
				if not f.get("ks_rival",false):
					side().give_stone(g,"ABSOLITE")
					say(g,r,"阿勃梭鲁进化石是送你的。博士在百刻市的日晷旁等你，快去找他吧。")
				else:g._persist();g._dialog(["今天也打得漂亮。"],r.name))
		"sundial":
			say(g,r,"请把超级环放到日晷上。今后每天晚上八点到九点，升级后的环能感应藏在卡洛斯的超级石。回密阿雷时也留意全息影像通讯器，有人想见你。")
		"stone","dusk":
			if r.get("condition","")=="seen_92":
				var seen: Array=g.save_data.get("dex",{}).get("seen",[])
				if not seen.any(func(id):return int(id) in [92,93,94]):
					g._dialog(["旅行时遇见过鬼斯、鬼斯通或耿鬼吗？见过它们之后再来找我。"],r.name);return
			side().give_stone(g,r.key)
			say(g,r,("%s。"%r.txt if r.action=="stone" else "超级环和地上的光点共鸣了。")+"获得了%s！"%side().stone_name(r.key))
		"emporium":emporium(g)
		"revive":revive(g,r.name)
		"fossil_rock":mine(g)
		"legend":
			var species:=int(r.get("species",bird_id(f)))
			g._pick("它留意到了小悠。",["走近","离开"],func(i):
				if i!=0 or not g._has_party():return
				g._start_wild_battle(species,int(r.level),"",func(outcome):
					if outcome=="caught":
						if species==150:side().give_stone(g,"MEWTWONITE_"+side().version(f).to_upper())
						side().save_event(g,r)
						if species==150:g._dialog(["超梦身后留下了一块%s。"%side().stone_name("MEWTWONITE_"+side().version(f).to_upper())])
					elif outcome=="b" and g._party_fainted():g._blackout(),"none"))
		"gift_mon","torchic":
			g._pick(str(r.get("txt","这是卡洛斯开幕时的特别配送。要领取携带火焰鸡进化石的加速火稚鸡吗？")),["接受","下次再来"],func(i):
				if i!=0:return
				var mon: Dictionary=side().roster_mon(g,int(r.get("species",255)),int(r.get("level",10)))
				if r.action=="torchic":mon.held="BLAZIKENITE";mon.ability=3
				var destination: String=g._store_mon(mon)
				say(g,r,"%s%s。"%[mon.name,"加入了队伍" if destination=="party" else "已送入电脑"]))
		"trade":trade(g,r)
		"radar","dowsing":
			var name: String="宝可追踪" if r.action=="radar" else "探宝器"
			if g._bag_count(name)==0:g._give_item(name,1,"key")
			if r.action=="radar":g.save_data.get_or_add("kalos_radar",{"charge":50,"chain":0})
			say(g,r,"获得了%s。"%name+("在普通草丛中使用，会指出摇动草丛的位置。" if r.action=="radar" else "在路上使用，天线会指向附近的隐藏道具。"))
		"rod":
			if g._bag_count(r.key)==0:g._give_item(r.key,1,"key")
			f["k_"+str(r.id)]=true
			say(g,r,"收下这支%s。站在水边面朝水，从背包使用就能钓鱼。"%r.key)
		"machine","tm_shop","tm_clock","tm_quiz","museum":preload("res://core/kalos_side_machines.gd").interact(g,r)
		"herbs":
			g._pick("药草店",["元气粉　500元","元气根　800元","万能粉　450元","复活草　2800元","离开"],func(i):
				if i>=4:return
				var cost:=int([500,800,450,2800][i])
				if int(g.save_data.money)<cost:g._dialog(["钱不够。"]);return
				g.save_data.money-=cost
				var name:=str(["元气粉","元气根","万能粉","复活草"][i])
				g._give_item(name,1,"heal");g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+1);g._persist();g._dialog(["收下了%s。"%name]))
		"charms":charms(g)

static func charms(g) -> void:
	var f: Dictionary=g._flags()
	var caught: Dictionary={};var seen: Dictionary={}
	for id in g.save_data.get("dex",{}).get("caught",[]):caught[int(id)]=true;seen[int(id)]=true
	for id in g.save_data.get("dex",{}).get("seen",[]):seen[int(id)]=true
	var groups: Dictionary=side().data().dex
	for spec in [["oval","圆形护符","kalos"],["shiny","闪耀护符","national"]]:
		var flag: String="ks_"+str(spec[0])
		if f.get(flag,false):continue
		var owned: Dictionary=seen if spec[0]=="oval" else caught
		var missing: Array=groups[spec[2]].filter(func(id):return not owned.has(int(id)))
		if missing.is_empty():
			if g._bag_count(spec[1])==0:g._give_item(spec[1],1,"key")
			side().mark(g,flag)
			g._dialog(["图鉴完成了！这是给你的%s。"%spec[1]],"布拉塔诺博士");return
	g._dialog(["完成卡洛斯图鉴可领奖圆形护符，集齐全国图鉴可领奖闪耀护符。"],"博士的助手")

static func emporium(g) -> void:
	var f: Dictionary=g._flags()
	var keys:=["VENUSAURITE","CHARIZARDITE_"+str(side().version(f)).to_upper(),"BLASTOISINITE"]
	var chosen: int=[1,4,7].find(int(f.get("ks_kanto_species",0)))
	if chosen>=0:keys.remove_at(chosen)
	keys=keys.filter(func(k):return not f.get("ks_shop_"+k,false))
	if keys.is_empty():g._dialog(["这三枚初始伙伴的超级石都找到主人了。"]);return
	var style:=int(g.save_data.get("kalos_style",0))
	var price: int=10000 if style>=255 else 50000 if style>=100 else 100000 if style>=50 else 300000 if style>=25 else 500000 if style>=10 else 1000000
	var labels: Array=keys.map(func(k):return side().stone_name(k)+"　%d元"%price)
	labels.append("离开")
	g._pick("密阿雷石头馆 · 收藏家",labels,func(i):
		if i>=keys.size():return
		if int(g.save_data.money)<price:g._dialog(["你的钱还不够。在密阿雷帮助别人、参观美术馆或消费，收藏家会重新估价。"]);return
		var key: String=keys[i]
		g.save_data.money-=price
		side().give_stone(g,key);side().mark(g,"ks_shop_"+key)
		g._dialog(["收下了%s。"%side().stone_name(key)]))

static func revive(g,who: String) -> void:
	var keys:=FOSSILS.keys().filter(func(k):return g._bag_count(k)>0)
	if keys.is_empty():g._dialog(["把闪耀洞窟的化石交给我，可以让古代的宝可梦重新醒来。"],who);return
	var options:=keys.duplicate();options.append("下次再来")
	g._pick("想复原哪块化石？",options,func(i):
		if i>=keys.size() or g._bag_count(keys[i])<1:return
		var key: String=keys[i]
		var mon: Dictionary=side().roster_mon(g,int(FOSSILS[key]),20)
		g._consume_item(key);g._store_mon(mon);g._persist()
		g._dialog(["复原成功！%s 从沉睡中醒来了。"%mon.name],who))

static func mine(g) -> void:
	if not g._party_has_move("ROCK_SMASH"):
		g._dialog(["有裂缝的岩石，用碎岩或许能打碎。"]);return
	if g._flags().get("ks_quarry_used",false):
		g._dialog(["这里只剩石屑。离开洞窟再回来找找吧。"]);return
	g._flags().ks_quarry_used=true
	var claims:=["秘密琥珀"]
	if g._flags().get("k_champion",false):
		claims.append_array(["头盖化石","盾甲化石","背盖化石","羽毛化石"])
		claims.append_array(["根状化石","爪子化石"] if side().version(g._flags())=="x" else ["甲壳化石","贝壳化石"])
	var name: String=claims[g.rng.randi_range(0,claims.size()-1)]
	g._give_item(name,1,"other");g._persist()
	g._dialog(["岩石碎开，从石屑中找到了%s。"%name])

static func trade(g,r: Dictionary) -> void:
	var id:=int(r.species)
	if id==0:id=int({650:656,653:650,656:653}.get(int(g._flags().get("k_starter",650)),656))
	var wanted:=int(r.wanted)
	var db=g.get_node("/root/Data")
	var ask: String="一只伙伴" if wanted==0 else str(db.species_of(wanted).name)
	FR.pick_party(g,"用%s交换%s？"%[ask,db.species_of(id).name],func(mon):
		return not mon.get("is_egg",false) and not mon.has("fused_part") and (wanted==0 or int(mon.species_id)==wanted),func(slot):
		var original: Dictionary=g.save_data.party[slot]
		g._pick("让%s和对方交换？"%original.name,["交换","取消"],func(i):
			if i!=0 or not is_same(g.save_data.party[slot],original) or g._flags().get("ks_"+str(r.id),false):return
			var mon: Dictionary=side().roster_mon(g,id,int(r.level))
			if r.held!="":mon.held=r.held
			if id==280:mon.ability=28;mon.nature="内敛"
			mon.ot_id=37110 if id==280 else 41000+id
			mon.ot_name=r.name
			g.save_data.party[slot]=mon
			Dex.record(g.save_data,mon,true)
			say(g,r,"%s收到了%s。"%["小悠",mon.name])))

static func roam(g) -> bool:
	var f: Dictionary=g._flags()
	if not str(g.world.map_data.id).begins_with("kalos_glitter"):f.erase("ks_quarry_used")
	if not f.get("k_champion",false) or f.get("ks_bird_nested",false):return false
	var mid:=str(g.world.map_data.id)
	if not g.world.wild_tile_here() or not mid.trim_prefix("kalos_").is_valid_int():return false
	var visits:=int(f.get("ks_bird_visits",0))
	if visits>0 and int(mid.trim_prefix("kalos_"))!=int(f.get("ks_bird_road",0)):return false
	if g.rng.randf()>.04:return false
	var id:=bird_id(f)
	var mon: Dictionary=side().roster_mon(g,id,70)
	Dex.record(g.save_data,mon,false)
	f.ks_bird_visits=visits+1
	var roads:=ROADS.duplicate()
	roads.erase(int(mid.trim_prefix("kalos_")))
	f.ks_bird_road=roads[g.rng.randi_range(0,roads.size()-1)]
	if int(f.ks_bird_visits)>=11:f.ks_bird_nested=true;g.world.refresh_story_actors(f)
	g._persist()
	g._dialog(["%s掠过草丛，还没来得及出招就已经远去。"%mon.name,"它最后朝海神之穴飞去了！" if f.get("ks_bird_nested",false) else "图鉴收到新的位置报告：%d号道路。"%int(f.ks_bird_road)])
	return true

static func use_item(g,name: String) -> bool:
	match name:
		"宝可追踪":preload("res://core/kalos_side_explore.gd").use_radar(g)
		"探宝器":preload("res://core/kalos_side_explore.gd").dowse(g)
		"折价券":g._dialog(["在白檀市或密阿雷时装店结账时使用，一次半价。"])
		"莲叶童子喷壶":
			if str(g.world.map_data.id)=="kalos_berry_fields":
				var crops: Dictionary=g.save_data.get_or_add("kalos_garden",{})
				g._pick("给哪一垄浇水？",["第一垄","第二垄","第三垄","第四垄","第五垄","第六垄","取消"],func(i):
					if i<6:preload("res://core/kalos_side_orchard.gd").row_menu(g,i,crops))
			else:g._dialog(["去7号道路的树果园给种下的树果浇水吧。"])
		"特性胶囊":
			FR.pick_party(g,"给哪只宝可梦使用特性胶囊？",func(mon):
				var a: Array=preload("res://core/kalos_side_explore.gd").data().abilities.get(str(int(mon.species_id)),[])
				return a.size()>=2 and int(a[1])>0 and int(mon.get("ability",0)) in [int(a[0]),int(a[1])] and int(a[0])!=int(a[1]),func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				var a: Array=preload("res://core/kalos_side_explore.gd").data().abilities[str(int(mon.species_id))]
				var n:=int(a[1]) if int(mon.ability)==int(a[0]) else int(a[0])
				if g._bag_count(name)<1:return
				g._consume_item(name);mon.ability=n;mon.ability_name=g.get_node("/root/Data").abilities.get(n,{}).get("name","")
				g._persist();g._dialog(["%s的特性变成了%s。"%[mon.name,mon.ability_name]]))
		"ＴＭＶ自由票":g._dialog(["凭票在密阿雷车站与奇楠市之间搭乘高速列车。"])
		"帅哥券":g._dialog(["已收集 %d / 5 张。集齐后到帅哥事务所。"%g._bag_count(name)])
		"卡洛斯的蛋":g._dialog(["把蛋带在身边多走走，看起来就快有动静了。"])
		"圆形护符":g._dialog(["带在身上时，培育屋会更容易发现蛋。"])
		"闪耀护符":g._dialog(["它会使你更容易遇见不同颜色的野生宝可梦。"])
		_:return false
	return true
