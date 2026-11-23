extends RefCounted

const Maison := preload("res://core/kalos_side_maison.gd")
const Frontier := preload("res://core/frontier_rules.gd")
const Hotel := preload("res://core/kalos_hotel.gd")
const ROOMS := {141:"lenah",126:"leyeah",140:"lewow",146:"sushi"}
const DINING := {"lenah":["一星餐厅",3000,15,"小蘑菇"],"leyeah":["二星餐厅",15000,20,"大蘑菇"],"lewow":["三星餐厅",100000,25,"芳香蘑菇"],"sushi":["回转寿司",500000,25,"巨大金珠"]}
const MODES := {"double":"双打","triple":"三打","rotation":"轮盘"}
static var courses: Dictionary

static func roster(map: Dictionary, flags: Dictionary, residents: Array) -> Array:
	var zone:=int(map.kalos_zone)
	if not (ROOMS.has(zone) or zone in [110,117,135]):return residents
	var spot: Array=map.kalos_anchors.guest4
	var rows:=residents.duplicate()
	var tag: String=ROOMS.get(zone,{110:"institute",117:"salon",135:"hotel"}.get(zone,""))
	var person: String=DINING[tag][0]+"领班" if DINING.has(tag) else {110:"对战考官",117:"多丽米亚修剪师",135:"酒店经理"}.get(zone,"")
	rows.append({"at":spot,"name":person,"gfx":"gentleman","kalos_service":tag,"facing":"down"})
	return rows

static func talk(g, npc: Dictionary) -> bool:
	if not npc.has("kalos_service"):return false
	var tag: String=npc.kalos_service
	if tag=="hotel":Hotel.desk(g)
	elif tag=="salon":preload("res://core/kalos_forms.gd").salon(g)
	elif tag=="institute":institute(g)
	else:dining(g,tag)
	return true

static func course(tag: String,style: String) -> Array:
	if courses.is_empty():courses=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_restaurants.json"))
	return courses[tag].get(style,[])

static func dining(g,tag: String) -> void:
	var details: Array=DINING[tag]
	if tag=="sushi" and not g._flags().get("ks_case1",false):
		g._dialog(["殿堂留名以后，去帅哥侦探事务所打个招呼，再回来预订。"],details[0]);return
	var ongoing: Dictionary=g.save_data.get("kalos_dining",{})
	if not ongoing.is_empty():
		if ongoing.tag!=tag:
			g._dialog(["你已经在%s订了套餐。"%DINING[ongoing.tag][0]]);return
		next_dish(g,ongoing)
		return
	var styles: Array=[]
	for style in MODES:
		if not course(tag,style).is_empty():styles.append(style)
	var price:=int(details[1])
	if tag!="sushi" and int(g.save_data.get("kalos_style",0))>=90:price=price*9/10
	var options:=styles.map(func(style):return MODES[style])
	options.append("先离开")
	g._pick("%s · 套餐 ¥%d"%[details[0],price],options,func(i):
		if i>=styles.size():return
		var style: String=styles[i]
		var count:=2 if style=="double" else 3
		if g.save_data.party.filter(func(mon):return int(mon.get("hp",0))>0).size()<count:
			g._dialog(["选这份套餐，需要 %d 只能出战的伙伴。"%count]);return
		if int(g.save_data.money)<price:g._dialog(["这份套餐的餐费是 %d 元。"%price]);return
		g.save_data.money-=price
		var visit:={"tag":tag,"style":style,"index":0,"mistakes":0}
		g.save_data.kalos_dining=visit
		g._persist()
		next_dish(g,visit))

static func next_dish(g,visit: Dictionary) -> void:
	var row: Array=course(visit.tag,visit.style)[int(visit.index)]
	var ready:=int(row[1])
	g._pick("第 %d 道菜 · 最佳享用时间为第 %d 回合"%[int(visit.index)+1,ready],["开始对战","稍后继续"],func(i):
		if i!=0:return
		var archive: Dictionary=load("res://core/kalos_campaign.gd").trainer_data()
		var id:=str(int(row[0]))
		var ui: Array=[]
		var before: int=g.save_data.party.filter(func(mon):return int(mon.get("hp",0))>0).size()
		g._start_battle({"name":archive.people[id][0],"battle":{"team":archive.teams[id],"double":visit.style=="double","battle_type":visit.style}},func(result):
			if result!="a":
				g.save_data.erase("kalos_dining");g._persist()
				if g._party_fainted():g._blackout()
				return
			var elapsed:=int(ui[0].battle.completed_turns)
			var after: int=g.save_data.party.filter(func(mon):return int(mon.get("hp",0))>0).size()
			visit.mistakes+=absi(elapsed-ready)+maxi(0,before-after)
			visit.index+=1
			if int(visit.index)<course(visit.tag,visit.style).size():
				g._persist();next_dish(g,visit);return
			var details: Array=DINING[visit.tag]
			var quantity:=maxi(1,int(details[2])-int(visit.mistakes))
			g._give_item(details[3],quantity,"other")
			g.save_data.get_or_add("kalos_restaurant_records",{})[visit.tag]=mini(int(g.save_data.get("kalos_restaurant_records",{}).get(visit.tag,9999)),int(visit.mistakes))
			g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+2)
			g.save_data.erase("kalos_dining");g._persist()
			g._dialog(["全套料理已上完，用餐赠礼为%s × %d。"%[details[3],quantity]],details[0]))
		ui.append(g.active_battle))

static func institute(g) -> void:
	if not g._flags().get("k_champion",false):
		g._dialog(["殿堂留名以后，欢迎回来参加五轮对战测验。"],"对战考官");return
	var current: Dictionary=g.save_data.get("kalos_institute",{})
	if not current.is_empty():exam_round(g,current);return
	var best:=int(g.save_data.get("kalos_institute_best",0))
	g._pick("对战研究所 · 最高 %d 分"%best,["单打测验","双打测验","离开"],func(i):
		if i<2:exam_team(g,i==1,[]))

static func exam_team(g,doubles: bool,selected: Array) -> void:
	var slots: Array=g.save_data.party.filter(func(mon):return Maison.allowed(mon,selected))
	var count:=4 if doubles else 3
	if slots.size()<count-selected.size():g._dialog(["需要报名 %d 只不同种类的宝可梦，携带道具也应各不相同。"%count]);return
	var options:=slots.map(func(mon):return mon.name)
	options.append("取消")
	g._pick("报名队员 %d / %d"%[selected.size()+1,count],options,func(i):
		if i>=slots.size():return
		var chosen:=selected.duplicate()
		chosen.append(slots[i])
		if chosen.size()<count:exam_team(g,doubles,chosen);return
		var exam:={"doubles":doubles,"index":0,"score":0,"wins":0,"team":chosen.map(func(mon):return Frontier.owner_team(mon,50))}
		g.save_data.kalos_institute=exam;g._persist();exam_round(g,exam))

static func exam_round(g,exam: Dictionary) -> void:
	g._pick("对战测验 · 第 %d / 5 场"%[int(exam.index)+1],["进入对战","稍后继续"],func(i):
		if i!=0:return
		var range_low:=int(exam.index)*10+1
		var groups: Array=Maison.data().rosters.filter(func(group):return int(group[2])<=range_low+30 and int(group[3])>=range_low)
		var group: Array=groups[g.rng.randi_range(0,groups.size()-1)]
		var foes:=Maison.fill(g,group[1],4 if exam.doubles else 3)
		var ui: Array=[]
		g._start_battle({"name":str(group[0][0]),"battle":{"platinum_battle":true,"tower":true,"double":exam.doubles,
			"enemy":foes,"player":exam.team.duplicate(true)}},func(result):
			var allies: Array=ui[0].player_team
			var enemy: Array=ui[0].enemy_team
			var points:=1000 if result=="a" else 0
			if result=="a":exam.wins+=1
			points+=80*enemy.filter(func(mon):return mon.fainted).size()-80*allies.filter(func(mon):return mon.fainted).size()
			points+=50*allies.filter(func(mon):return mon.hp==mon.max_hp).size()
			exam.score+=points
			exam.index+=1
			if int(exam.index)<5:g._persist();exam_round(g,exam);return
			var score:=maxi(0,int(exam.score));var stars:=clampi(score/1000+1,1,7)
			var bp: int=[0,3,5,7,9,11,13,15][stars]
			g.save_data.kalos_bp=int(g.save_data.get("kalos_bp",0))+bp
			g.save_data.kalos_institute_best=maxi(score,int(g.save_data.get("kalos_institute_best",0)))
			g.save_data.erase("kalos_institute");g._persist()
			g._dialog(["五场结束，你赢下 %d 场。成绩 %d 分，%d 星，获得 %d BP。"%[exam.wins,score,stars,bp]],"测验证书"))
		ui.append(g.active_battle))
