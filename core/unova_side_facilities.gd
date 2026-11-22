extends RefCounted

const Party := preload("res://core/party.gd")
const Battle := preload("res://core/battle.gd")
const Frontier := preload("res://core/sinnoh_frontier.gd")
const Field := preload("res://core/unova_field.gd")
const NAMES := {"subway":"对战地铁","pwt":"宝可梦世界锦标赛","tower":"黑色摩天楼"}
const LEADERS := ["黑连","霍米加","亚堤","小菊儿","菊老大","风露","夏卡","西子伊","白露","伯特","寇恩","天桐","芦荟","哈奇库","青绿","阿渡","大吾","米可利","竹兰","阿戴克","小刚","小霞","马志士","莉佳","娜姿","夏伯","坂木","阿速","阿笔","小茜","小松","阿四","阿蜜","柳伯","小椿","阿杏","杜鹃","藤树","铁旋","亚莎","千里","娜琪","小枫","小南","亚当","瓢太","菜种","梅丽莎","阿李","吉宪","东瓜","小菘","电次","赤红"]
const EXCHANGE := {"PROTEIN":1,"CALCIUM":1,"IRON":1,"ZINC":1,"CARBOS":1,"HP_UP":1,"POWER_BRACER":16,"POWER_BELT":16,"POWER_LENS":16,"POWER_BAND":16,"POWER_ANKLET":16,"POWER_WEIGHT":16,"FOCUS_SASH":48,"CHOICE_SCARF":48,"CHOICE_BAND":48,"CHOICE_SPECS":48,"LIFE_ORB":48,"RARE_CANDY":48}
static var db: Dictionary

static func data() -> Dictionary:
	if db.is_empty():db=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_side_activities.json"))
	return db

static func side():
	return load("res://core/unova_side.gd")

static func open(g,kind: String) -> void:
	if kind=="pwt":
		load("res://core/unova_side_pwt.gd").open(g)
		return
	var era:=Field.era(g._flags())
	var key:="unova_facility_"+era+"_"+kind
	var existing: Dictionary=g.save_data.get(key,{})
	if not existing.is_empty():
		menu(g,existing)
		return
	var modes: Array
	if kind=="subway":modes=["单打列车","双打列车"]
	else:modes=["进入第 %d 区"%mini(10,int(g.save_data.get("unova_tower_area",0))+1)]
	if kind=="subway":
		for mode in ["单打列车","双打列车"]:
			if int(g.save_data.get("us_record_"+era+mode,0))>=21:modes.append("超级"+mode)
	var labels:=modes.duplicate()
	if kind!="tower":labels.append("兑换奖品（%d BP）"%int(g.save_data.get("unova_bp",0)))
	labels.append("离开")
	g._pick(NAMES[kind],labels,func(i):
		if i==labels.size()-1:return
		if i>=modes.size():exchange(g);return
		var mode: String=modes[i]
		if kind=="tower":
			if not g._has_party():return
			enroll(g,key,kind,mode,g.save_data.party.filter(func(m):return m is Dictionary and not m.is_empty() and int(m.get("hp",0))>0))
		else:Frontier.pick(g,"选择参赛宝可梦",g.save_data.party,4 if "双打" in mode else 3,[],func(chosen):enroll(g,key,kind,mode,chosen)))

static func enroll(g,key: String,kind: String,mode: String,chosen: Array) -> void:
	var squad: Array=[]
	for source in chosen:
		var mon:=Battle.make_combatant(int(source.species_id),int(source.level) if kind=="tower" else 50,source.moves,str(source.get("form","")))
		for k in ["ability","held","berry","shiny","shiny_kind","name"]:mon[k]=source.get(k,mon.get(k,""))
		squad.append(mon)
	var area:=mini(10,int(g.save_data.get("unova_tower_area",0))+1)
	var run:={"key":key,"kind":kind,"mode":mode,"team":squad,"round":0,"area":area,"previous":[],"record":"us_record_"+Field.era(g._flags())+mode}
	run.start=int(g.save_data.get("us_streak_"+run.record,0)) if kind=="subway" else 0
	g.save_data[key]=run
	g._persist()
	menu(g,run)

static func menu(g,run: Dictionary) -> void:
	var kind:=str(run.kind)
	var prompt: String="%s · %s"%[NAMES[kind],run.mode]
	if kind=="tower":prompt+=" · "+("寻找守门训练家" if int(run.round)==0 else "挑战区域首领")
	elif kind=="subway":prompt+=" · %d 连胜"%(int(run.start)+int(run.round))
	else:prompt+=" · "+["第一轮","半决赛","决赛"][int(run.round)]
	g._pick(prompt,["开始对战","暂时休息","退出挑战"],func(i):
		if i==0:next_battle(g,run)
		elif i==2:g._pick("结束本次挑战？",["继续","结束"],func(n):
			if n==1:finish(g,run,false)
			else:menu(g,run)))

static func enemy_set(key: String,row: Array,level: int) -> Dictionary:
	var mon:=Battle.make_combatant(int(row[0]),level,row[1])
	var item:=str(row[2])
	mon.held="" if item=="NONE" else item
	if item.ends_with("_BERRY"):mon.berry=item.trim_suffix("_BERRY").to_lower()
	mon.nature=row[3]
	return mon

static func next_battle(g,run: Dictionary) -> void:
	var kind:=str(run.kind)
	var mode:=str(run.mode)
	var stage:=int(run.round)
	var group:="battle_subway" if kind=="subway" else "black_tower"
	var rows: Array=data()[group].trainers
	var round_number:=int(run.start)+stage+1
	var count:=4 if "双打" in mode else 3
	var level:=50
	var who: String
	var foes: Array=[]
	if kind=="tower" and int(run.area)==10 and stage==1:
		who="蕃石郎"
		for source in load("res://core/unova_side_quests.gd").special().teams.boss_trainer_benga_2:
			var mon:=Battle.make_combatant(int(source.species),int(source.level),source.moves)
			mon.held=source.held
			foes.append(mon)
	else:
		var lower:=0
		var upper:=rows.size()-1
		if kind=="subway":
			lower=110 if "超级" in mode else mini(60,(round_number-1)/7*20)
			upper=299 if "超级" in mode else mini(109,lower+39)
		else:
			lower=mini(500,(int(run.area)-1)*45)
			upper=mini(rows.size()-1,lower+55)
			level=43+int(run.area)*3
		var allowed: Array=[]
		for i in range(lower,upper+1):
			if rows[i][1].size()>=count and not run.previous.has(i):allowed.append(i)
		if allowed.is_empty():return
		var index:=int(allowed.pick_random())
		if kind=="subway" and round_number==(49 if "超级" in mode else 21):
			if count==3:index=308 if "超级" in mode else 307
			else:index=310 if "超级" in mode else 309
		var trainer: Array=rows[index]
		if kind=="subway" and index in [307,308,309,310]:who="北尚" if count==3 else "南厦"
		else:who=str(trainer[0]).get_slice("_",str(trainer[0]).count("_")).capitalize()
		var pool: Array=trainer[1].duplicate()
		pool.shuffle()
		var used: Array=[]
		for set_id in pool:
			var row: Array=data()[group].sets[int(set_id)]
			if int(row[0]) in used:continue
			used.append(int(row[0]))
			foes.append(enemy_set(group,row,level))
			if foes.size()==count:break
		run.previous.append(index)
	g._start_battle({"name":who,"battle":{"platinum_battle":true,"tower":true,"double":count==4,"player":run.team,"enemy":foes}},func(result):
		if result!="a":finish(g,run,false);return
		run.round=int(run.round)+1
		var wins:=int(run.start)+int(run.round)
		g.save_data[run.record]=maxi(int(g.save_data.get(run.record,0)),wins)
		if kind!="tower":Frontier.heal(g,run.team)
		if int(run.round)>=(7 if kind=="subway" else 2):finish(g,run,true)
		else:g._persist();menu(g,run))

static func finish(g,run: Dictionary,win: bool) -> void:
	g.save_data.erase(run.key)
	var text:="本次挑战结束。"
	if run.kind=="subway":g.save_data["us_streak_"+run.record]=int(run.start)+int(run.round) if win else 0
	if win and run.kind=="tower":
		var area:=int(run.area)
		g.save_data.unova_tower_area=maxi(area,int(g.save_data.get("unova_tower_area",0)))
		if area==10:side().mark(g,"us_tower_complete")
		text="第 %d 区已突破。"%area+("回算木镇见蕃石郎吧。" if area==10 else "下一区的电梯已经开放。")
	elif win:
		var bp:=3
		if run.kind=="subway":
			bp=10 if int(run.start)+int(run.round) in [21,49] else 3+mini(7,int(run.start)/7)
		g.save_data.unova_bp=int(g.save_data.get("unova_bp",0))+bp
		text="全场获胜！获得 %d BP。"%bp
	g._persist()
	g._dialog([text],NAMES[run.kind])

static func exchange(g) -> void:
	var bp:=int(g.save_data.get("unova_bp",0))
	var keys:=EXCHANGE.keys()
	var labels:=keys.map(func(key):return "%s　%d BP"%[side().item_name(key),int(EXCHANGE[key])])
	labels.append("离开")
	g._pick("工分兑换 · %d BP"%bp,labels,func(i):
		if i>=keys.size():return
		var key: String=keys[i]
		if bp<int(EXCHANGE[key]):g._dialog(["对战点数不足。"]);return
		g.save_data.unova_bp=bp-int(EXCHANGE[key])
		side().give(g,key)
		g._persist()
		g._dialog(["换得了%s。"%side().item_name(key)]))
