extends RefCounted
## Battle Tree copies each entry; HP, PP, temporary held items and forms stay inside the facility.
const Battle:=preload("res://core/battle.gd")
const Maison:=preload("res://core/kalos_side_maison.gd")
const Frontier:=preload("res://core/frontier_rules.gd")
const Party:=preload("res://core/party.gd")
const LABELS:=["单打","双打","多人对战"]
const COUNTS:=[3,4,2]
const GUESTS:={"Red":"赤红","Blue":"青绿","Anabel":"莉拉","Wally":"满充","Cynthia":"竹兰","Colress":"阿克罗玛","Grimsley":"越橘","Sina":"吉娜","Dexio":"德克希欧","Kukui":"库库伊","Lillie":"莉莉艾","Guzma":"古兹马","Mallow":"玛奥","Plumeria":"布尔美丽","Kiawe":"卡奇","Rada":"培育家拉达","Sophocles":"马玛内"}
static var archive: Dictionary

static func data() -> Dictionary:
	if archive.is_empty():archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_side_tree.json"))
	return archive

static func pool(g) -> Array:
	return data().usum if str(g._flags().a_version).begins_with("ultra") else data().sm

static func combatant(ref: int) -> Dictionary:
	var row: Array=data().sets[ref]
	var mon:=Maison.opponent(row)
	if row[4]!="":Party.set_form(mon,str(row[4]))
	return mon

static func squad(g,roster: Array,count: int) -> Array:
	var refs:=roster.duplicate()
	var result: Array=[]
	while not refs.is_empty() and result.size()<count:
		var mon:=combatant(int(refs.pop_at(g.rng.randi_range(0,refs.size()-1))))
		if Maison.allowed_opponent(mon,result):result.append(mon)
	return result

static func rentals(g) -> Array:
	var source: Array=pool(g)
	return squad(g,source[g.rng.randi_range(0,39)][1],3)

static func open(g) -> void:
	var run: Dictionary=g.save_data.get("alola_tree",{})
	if not run.is_empty():menu(g,run);return
	var choices:=LABELS.duplicate()
	var codes:=[0,1,2]
	for n in 3:
		if g._flags().get("as_tree_super_"+str(n),false):
			choices.append("超级"+str(LABELS[n]));codes.append(n+3)
	choices.append_array(["查看连胜纪录","离开"])
	g._pick("对战树",choices,func(i):
		if i==choices.size()-1:return
		if i==choices.size()-2:
			var records: Array=[]
			for j in codes.size():records.append("%s　%d 胜"%[choices[j],g.save_data.get("alola_tree_best",{}).get(str(codes[j]),0)])
			g._dialog(records,"对战树");return
		pick(g,codes[i],[]))

static func pick(g,code: int,chosen: Array) -> void:
	var choices: Array=[]
	var mons: Array=[]
	var unrestricted: bool=code<3 and str(g._flags().a_version).begins_with("ultra")
	for m in g.save_data.party:
		if m.is_empty() or m.get("is_egg",false):continue
		var sid:=int(m.species_id)
		if not unrestricted and (sid in Maison.BANNED or sid in [789,790,791,792,800,801,802,807]):continue
		if not Maison.allowed_opponent(m,chosen):continue
		mons.append(m);choices.append("%s　Lv.%d"%[m.name,int(m.level)])
	choices.append("取消报名")
	g._pick("选择第 %d／%d 位伙伴"%[chosen.size()+1,COUNTS[code%3]],choices,func(i):
		if i==mons.size():return
		var next:=chosen.duplicate()
		next.append(mons[i])
		if next.size()<int(COUNTS[code%3]):pick(g,code,next);return
		var team: Array=next.map(func(m):return Frontier.owner_team(m,int(m.level) if unrestricted else mini(int(m.level),50)))
		var run:={"mode":code,"wins":0,"team":team}
		if code%3==2:partner(g,run)
		else:start(g,run))

static func partner(g,run: Dictionary) -> void:
	var names:=["培育家拉达"]
	var teams: Array=[squad(g,pool(g)[80][1],2)]
	if g._flags().get("as_tree_lillie",false):
		names.append("莉莉艾");teams.append(squad(g,pool(g)[206][1],2))
	for name in g.save_data.get("alola_scouts",{}):
		names.append(GUESTS.get(name,name));teams.append(g.save_data.alola_scouts[name])
	names.append("取消")
	g._pick("选择对战搭档",names,func(i):
		if i<teams.size():
			run.partner=teams[i]
			start(g,run))

static func start(g,run: Dictionary) -> void:
	g.save_data.alola_tree=run
	g._persist()
	menu(g,run)

static func menu(g,run: Dictionary) -> void:
	g._pick("对战树 · %d 连胜 · %d BP"%[run.wins,int(g.save_data.get("bp",0))],["开始下一场","暂时休息","结束这轮连胜"],func(i):
		if i==0:fight(g,run)
		elif i==2:
			g._pick("确定结束这轮挑战？",["结束","保留连胜"],func(j):
				if j==0:g.save_data.erase("alola_tree");g._persist()))

static func select_opponent(g,run: Dictionary,second: bool) -> Array:
	var trainers:=pool(g)
	var round_no:=int(run.wins)+1
	var style:=int(run.mode)%3
	var advanced:=int(run.mode)>=3
	var boss:=round_no==(50 if advanced else 20)
	if boss:
		var blue:=style==1 or second
		return trainers[(190 if advanced else 203)+int(blue)]
	if advanced and round_no%10==0:
		var guests: Array=range(192,203)
		if not g._flags().get("as_ub5",false) and not str(g._flags().a_version).begins_with("ultra"):guests.erase(193)
		return trainers[guests[g.rng.randi_range(0,guests.size()-1)]]
	var lower:=mini(130,40+20*((round_no-1)/10)) if advanced else 0
	var upper:=mini(189,lower+59) if advanced else mini(99,29+((round_no-1)/5)*20)
	return trainers[g.rng.randi_range(lower,upper)]

static func partner_row(m: Dictionary) -> Dictionary:
	return {"species":m.species_id,"level":m.level,"moves":m.moves,"form":m.get("form",""),"held":m.get("held",""),"ability":m.get("ability",0)}

static func fight(g,run: Dictionary) -> void:
	var style:=int(run.mode)%3
	var group:=select_opponent(g,run,false)
	var foes:=squad(g,group[1],COUNTS[style])
	var invite:=foes.duplicate(true).slice(0,2)
	var cfg:={"platinum_battle":true,"tower":true,"player":run.team.duplicate(true),"enemy":foes,"double":style!=0}
	var name: String=GUESTS.get(group[0],group[0])
	if style==2:
		var other:=select_opponent(g,run,true)
		name+="、"+str(GUESTS.get(other[0],other[0]))
		for m in foes:m.trainer_group="first"
		var other_party:=squad(g,other[1],2)
		for m in other_party:m.trainer_group="second"
		foes.append_array(other_party)
		cfg.ally="alola";cfg.ally_team=run.partner.map(partner_row)
	g._start_battle({"name":name,"battle":cfg},func(outcome):
		if outcome!="a":
			g.save_data.erase("alola_tree");g._persist()
			g._dialog(["本次挑战结束，连胜纪录为 %d。"%run.wins],"对战树");return
		run.wins=int(run.wins)+1
		var best: Dictionary=g.save_data.get_or_add("alola_tree_best",{})
		best[str(run.mode)]=maxi(int(run.wins),int(best.get(str(run.mode),0)))
		var legend_win: bool=int(run.wins)==(20 if int(run.mode)<3 else 50)
		var reward: int=20 if legend_win and int(run.mode)<3 else 50 if legend_win else mini(7,2+(int(run.wins)-1)/10) if int(run.mode)>=3 else (1 if int(run.wins)<=10 else 2)
		g.save_data.bp=int(g.save_data.get("bp",0))+reward
		if legend_win and style in [0,2] and not g._flags().get("as_tree_stones",false):
			for stone in [["妙蛙花进化石","VENUSAURITE"],["喷火龙进化石Ｘ","CHARIZARDITE_X"],["喷火龙进化石Ｙ","CHARIZARDITE_Y"],["水箭龟进化石","BLASTOISINITE"]]:g._give_bag_item(stone[0],"held",stone[1])
			g._flags().as_tree_stones=true
		if legend_win and int(run.mode)<3:
			g._flags()["as_tree_super_"+str(style)]=true
			g.save_data.erase("alola_tree");g._persist()
			g._dialog(["２０连胜！超级赛已开放。获得 %d BP。"%reward],"对战树");return
		g._persist()
		g._pick("第 %d 胜　获得 %d BP"%[run.wins,reward],["继续挑战","邀请对手成为搭档（10 BP）","暂时休息"],func(i):
			if i==0:menu(g,run)
			elif i==1:
				if int(g.save_data.bp)<10:g._dialog(["需要１０点 BP 才能邀请对手。"]);return
				g.save_data.bp-=10;g.save_data.get_or_add("alola_scouts",{})[group[0]]=invite
				g._persist();g._dialog(["已登记在多人对战的搭档名单中。"])))

static func exchange(g) -> void:
	var offers: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_side_bp.json"))
	var table: Array=offers["usum" if str(g._flags().a_version).begins_with("ultra") else "sm"]
	if table.is_empty():return
	var labels: Array=[]
	for row in table:labels.append("%s　%d BP"%[row[0],row[2]])
	labels.append("离开")
	g._pick("对战树 · 持有 %d BP"%int(g.save_data.get("bp",0)),labels,func(i):
		if i>=table.size():return
		var row: Array=table[i]
		if int(g.save_data.get("bp",0))<int(row[2]):g._dialog(["对战点数不足。"]);return
		g.save_data.bp-=int(row[2])
		g._give_bag_item(str(row[0]),"held",str(row[1]))
		g._persist();g._show_toast("兑换了"+str(row[0])))
