extends "res://tools/test_emerald_frontier.gd"
## Isolated fixtures for optional events, timing, field/menu actions and captured item effects.
var Side
var Quest
var Maison
var Nursery
var Orchard
var Explore
var Party
var Field

func clear() -> void:
	g._close_all_dialogs()
	for attempt in 12:
		if g.panel_open <= 0:break
		g._on_back()
		g._close_all_dialogs()

func invoke(id: String) -> void:
	clear()
	var row: Dictionary=Side.by_id[id]
	for flag in row.requires:
		if not g._flags().has(flag):g._flags()[flag]=true
	var m: Dictionary=g.get_node("/root/Data").load_map("kalos",row.map)
	g.world.load_map(m);g.world.refresh_story_actors(g._flags())
	var npc: Dictionary={}
	for n in g.world.npcs:
		if n.get("kalos_side","")==id:npc=n;break
	check(not npc.is_empty(),"field actor "+id)
	if npc.is_empty():return
	for delta in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
		var pos=Vector2i(int(npc.at[0]),int(npc.at[1]))+Vector2i(delta)
		if g.world.is_blocked(pos):continue
		g.world.warp_to(pos);g.world.finish_walk()
		g.world.facing={Vector2i.DOWN:"up",Vector2i.LEFT:"right",Vector2i.RIGHT:"left",Vector2i.UP:"down"}[delta]
		g._on_action();return
	check(false,"reachable actor "+id)

func fields() -> void:
	var db=g.get_node("/root/Data")
	var missing: Dictionary={}
	for row in Side.data().events:
		var map: Dictionary=db.load_map("kalos",row.map)
		if map.is_empty():
			missing[row.map]=true;continue
		var at: Array=map.get("kalos_anchors",{}).get(row.anchor,[])
		check(at.size()==2,"anchor "+row.id)
		var flags:={"k_version":"x","k_starter":650}
		for required in row.requires:flags[required]=true
		if row.get("version","")!="":flags.k_version=row.version
		check(Side.eligible(row,flags,20),"eligible "+row.id)
		for required in row.requires:
			var before:=flags.duplicate();before.erase(required)
			check(not Side.eligible(row,before,20),"required "+row.id+" "+required)
		for until in row.until:
			var after:=flags.duplicate();after[until]=true
			check(not Side.eligible(row,after,20),"done "+row.id+" "+until)
		if row.action=="dusk":
			check(not Side.eligible(row,flags,19) and not Side.eligible(row,flags,21),"evening only "+row.key)
			if row.get("version","")!="":
				flags.k_version="x" if flags.k_version=="y" else "y"
				check(not Side.eligible(row,flags,20),"exclusive "+row.key)
		if row.action in ["case_fight","rematch"]:check(not Quest.team(int(row.team)).is_empty(),"original party "+row.id)
	check(missing.is_empty(),"source map names "+str(missing))
	check(Side.data().stones.size()==28,"all 28 X/Y mega stones")
	var sources: Dictionary={}
	for f in Side.data().tm_sources:sources[int(f)]=true
	for n in [4,13,24,39,83,86,98,99]:sources[n]=true
	for entry in Maison.data().shop:
		if str(entry[0]).begins_with("TM"):sources[int(str(entry[0]).trim_prefix("TM"))]=true
	check(sources.size()==100,"100 machine sources")

func gifts() -> void:
	g._flags().k_fossil=true
	invoke("aerodactylite")
	check(g._bag_count(Side.stone_name("AERODACTYLITE"))==1,"aerodactylite obtained at fossil lab")
	g._give_item("鳍之化石",1,"key")
	invoke("fossils");button("鳍之化石")
	check(g._bag_count("鳍之化石")==0 and g.save_data.party.any(func(m):return m.get("species_id",0)==698 and m.level==20),"revived Amaura Lv.20")
	invoke("hm1")
	check(g._bag_count(Field.machine_name(g,1,true))==1 and g._flags().k_hm_1,"usable Cut learning machine")
	invoke("lapras");button("接受")
	check(g.save_data.party.any(func(m):return m.get("species_id",0)==131 and m.level==30),"Route 12 Lapras Lv.30")
	invoke("blaziken");button("接受")
	check(g.save_data.party.any(func(m):return m.get("species_id",0)==255 and m.get("held","")=="BLAZIKENITE" and m.ability==3),"event Torchic holds correct stone and ability")
	invoke("train")
	check(g._flags().k_train_pass and g._bag_count("ＴＭＶ自由票")==1,"TMV pass opens return rail")
	invoke("case1")
	for i in range(1,6):invoke("ticket%d"%i)
	check(g._bag_count("帅哥券")==5,"five physical detective tickets")
	invoke("case2")
	check(g._bag_count("帅哥券")==0 and g._flags().ks_case2,"Looker receives all tickets and advances once")
	check(not Side.eligible(Side.by_id.case1,g._flags()),"Looker moved on")
	invoke("mimi");button("追过去")
	check(not g._flags().get("ks_mimi",false),"Mimi escapes the chase")
	invoke("mimi");button("跳舞")
	check(g._flags().get("ks_mimi",false),"Mimi trusts a gentle gesture")

func facility() -> void:
	var d=Maison.data()
	check(d.sets.size()==1072 and d.rosters.size()==66 and d.shop.size()==63,"full Maison rosters")
	for i in 8:check(d.bosses[i].size()==[3,3,4,4,6,6,4,4][i],"original chatelaine "+str(i))
	for i in 3:check(d.partners[i].size()==2,"original local multi partner")
	for group in d.rosters:
		var squad=Maison.fill(g,group[1],6)
		check(squad.size()==6 and squad.all(func(m):return m.level==50 and not m.moves.is_empty()),"legal six from roster "+str(group[0][0]))
	var first: Dictionary=Party.make(445,90,[89,337]);first.held="LIFE_ORB"
	var same_item: Dictionary=Party.make(9,90,[57]);same_item.held="LIFE_ORB"
	check(not Maison.allowed(first,[first]) and not Maison.allowed(same_item,[first]),"species and item clauses")
	check(not Maison.allowed(Party.make(150,70,[94]),[]),"restricted legend denied")
	g.save_data.party=[first,Party.make(6,90,[53,337]),Party.make(9,90,[57,58])]
	invoke("maison");button("单打");button("烈咬陆鲨");button("喷火龙");button("水箭龟")
	check(g.save_data.has("kalos_maison"),"registered temporary squad")
	if not g.save_data.has("kalos_maison"):return
	check(g.save_data.kalos_maison.team.all(func(m):return m.level==50),"Maison team level ceiling")
	button("开始下一场")
	check(is_instance_valid(g.active_battle),"Maison opens battle")
	if is_instance_valid(g.active_battle):
		var w=play_battle()
		check(w=="a" and g._flags().get("ks_maison_played",false) and g.save_data.get("kalos_bp",0)==1,"played first Maison fight and earned BP")
	check(g.save_data.party[0].level==90 and g.save_data.party[0].held=="LIFE_ORB","real partner data retained")

func extra() -> void:
	check(Explore.data().safari.size()==18,"all Safari types")
	for i in 18:check(Explore.data().safari[i].size()==3,"three original encounter slots "+str(i))
	invoke("safari");button("可尔妮")
	var initial: Array=g.save_data.kalos_safari_cards["1"].duplicate()
	invoke("safari");button("可尔妮")
	check(g.save_data.kalos_safari_cards["1"]==initial,"persistent friend card")
	var mon=Explore.safari_mon(g,initial[0])
	check(mon.level==30 and mon.ivs.values().count(31)>=2,"Safari level and minimum perfect IVs")
	invoke("berries");invoke("soil0");button("1　空地");button("橙橙果")
	check(g.save_data.kalos_garden["0"].berry=="oran","first planting")
	invoke("soil0");button("1　橙橙果");button("用莲叶童子喷壶")
	var crop: Dictionary=g.save_data.kalos_garden["0"]
	check(crop.water.size()==1 and Orchard.phase(crop,int(crop.at)+24*3600)=="成熟","water interaction and offline maturity")
	invoke("compost");button("橙橙果");button("橙橙果");button("橙橙果")
	check(g._bag_count("变异肥")==3,"compost uses three berries of the same color")
	check(Orchard.yield_count(["blue",24,4,15],{"water":["播种","长高"],"mulch":"速效肥"})==8,"boost mulch improves watering yield")
	var a=Party.make(650,10,[33]);a.sex="female";a.held="DESTINY_KNOT"
	var b=Party.make(132,10,[144]);b.sex="genderless";b.held="EVERSTONE";b.nature="固执"
	check(Nursery.chance(g,a,b)>0 and Nursery.chance(g,b,b)==0,"gen VI egg and Ditto compatibility")
	var egg=Nursery.egg(g,a,b)
	check(int(egg.mon.species_id)==650 and int(egg.mon.level)==1 and egg.mon.nature=="固执" and egg.mon.ivs.size()==6,"Kalos native inheritance")
	check(Quest.bird_id({"k_starter":650})==144 and Quest.bird_id({"k_starter":653})==145 and Quest.bird_id({"k_starter":656})==146,"roaming bird follows the original starter")

func city() -> void:
	var City=load("res://core/kalos_side_city.gd")
	var Battle=load("res://core/battle.gd")
	var b=Battle.new()
	check(b.effectiveness("electric",["ground"])==0 and b.effectiveness("fire",["grass"])==2,"standard type chart")
	b.inverse_record={"score":0,"fainted":false}
	check(b.effectiveness("electric",["ground"])==2 and b.effectiveness("fire",["grass","steel"])==.25,"inverse immunities and dual types")
	check(Side.data().inverse.size()==37,"all original Inver sets")
	var prev=g._bag_count("密阿雷格雷派饼")
	City.galette(g,2)
	check(g._bag_count("密阿雷格雷派饼")==prev,"out of stock before baking")
	clear()
	g.save_data.money=200000
	City.galette(g,3);button("买一块")
	var milk=g._bag_count("哞哞鲜奶")
	check(milk>0 and g._bag_count("密阿雷格雷派饼")==prev+1,"fresh galette and milk")
	clear();City.galette(g,3);button("买一块")
	check(g._bag_count("哞哞鲜奶")==milk,"daily milk")
	invoke("coupon")
	var money=g.save_data.money
	invoke("boutique_santalune");button("丰缘头饰 · 宝蓝");button("使用折价券")
	check(g._bag_count("折价券")==0 and g.save_data.money==money-900 and g._flags().ks_cap=="blue","one-use price reduction and worn headwear")
	check("kalos_cap_blue_walk" in g.world._player_sprite.texture.resource_path,"overworld palette switches to purchased trim")
	invoke("trick_cosmic")
	check(not g._flags().get("ks_trick_cosmic",false),"hotel trick blocks before city lessons")
	for trick in ["parallel","dash","backflip","spin","cosmic"]:invoke("trick_"+trick)
	check(g._flags().get("ks_trick_cosmic",false) and g._flags().ks_skate_mode=="cosmic","four lessons and lost hotel trick")
	invoke("tree_oran")
	var count=g._bag_count("橙橙果")
	invoke("tree_oran")
	check(g._bag_count("橙橙果")==count and g.save_data.kalos_berry_trees.has("tree_oran"),"roadside berry tree seven-day lock")
	clear()

func run() -> void:
	Side=load("res://core/kalos_side.gd")
	Quest=load("res://core/kalos_side_quests.gd")
	Maison=load("res://core/kalos_side_maison.gd")
	Nursery=load("res://core/kalos_side_nursery.gd")
	Orchard=load("res://core/kalos_side_orchard.gd")
	Explore=load("res://core/kalos_side_explore.gd")
	Party=load("res://core/party.gd")
	Field=load("res://core/kalos_field.gd")
	Save.use_test_slot()
	g=load("res://scenes/boot.tscn").instantiate()
	root.add_child(g)
	await process_frame
	await preload("regional_start.gd").enter(g,"kalos","boxed","x")
	g._close_all_dialogs()
	g.save_data.party=[Party.make(25,50,[85,98])]
	fields();gifts();facility();extra();city()
	print("KALOS SIDE ", "PASS" if failures.is_empty() else "FAIL", " checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
