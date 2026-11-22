extends RefCounted
const PARK := "johto_national_park"
const GATES := ["johto_route_35_national_park_gate","johto_route_36_national_park_gate"]
const ROWS := [[20,10,7,18],[20,13,7,18],[10,11,9,18],[10,14,9,18],[5,12,12,15],[5,15,12,15],[10,48,10,16],[10,46,10,17],[5,123,13,14],[5,127,13,14]]
const OTHERS := [[300,285,226],[286,251,237],[357,349,368],[332,324,321],[318,295,285],[366,329,314],[341,301,264],[326,292,282],[270,282,251],[267,254,259]]
const PRIZES := ["日之石","不变之石","文柚果","橙橙果"]

static func active(g) -> bool: return not g.save_data.get("js_contest",{}).is_empty()

static func roster(mid: String,rows: Array) -> Array:
	if not mid in GATES:return rows
	# Crystal has several attendance variants of the same official on top of
	# each other. Bind just one visible official at HGSS's actual park doorway.
	var out:=rows.filter(func(n):return n.get("gfx","")!="officer" and n.get("name","")!="巡警")
	var south:=mid==GATES[0]
	out.append({"name":"捕虫大会工作人员","gfx":"officer","at":[0,2],"crystal_quest":"bug_officer","native_anchor":{"at":[24,3] if south else [1,6],"facing":"down"}})
	return out

static func enroll(g,day: Dictionary):
	if active(g):
		g._pick("提前结束捕虫大会，参加评选？",["参加评选","继续捕虫"],func(i):
			if i==0: finish(g))
		return
	var date:="%04d-%02d-%02d" % [day.year,day.month,day.day]
	if day.weekday not in [2,4,6] or g._flags().get("js_contest_date","")==date:
		g._dialog(["捕虫大会在星期二、四、六举行，每天限参加一次。"],"工作人员")
		return
	var lead:=first_slot(g)
	if lead<0 or int(g.save_data.party[lead].get("hp",0))<=0:
		g._dialog(["请把一只还能战斗的宝可梦放在队伍首位。"],"工作人员")
		return
	g._pick("用首位伙伴参加捕虫大会？限时二十分钟，提供二十个竞赛球。",["报名参赛","先离开"],func(i):
		if i!=0:return
		var entry: Dictionary={}
		for warp in g.world.map_data.warps:
			if warp.to.map==PARK: entry=warp.to;break
		if entry.is_empty():return
		var indices:=range(OTHERS.size())
		var rivals: Array=[]
		for n in 5:
			var scores: Array=OTHERS[indices.pop_at(g.rng.randi_range(0,indices.size()-1))]
			rivals.append(int(scores[g.rng.randi_range(0,2)])+g.rng.randi_range(0,7))
		g.save_data.js_contest={"balls":20,"until":int(Time.get_unix_time_from_system())+1200,"kept":{},"rivals":rivals,"slot":lead,"return":g.world.map_data.id}
		g.save_data.party[lead]["crystal_contest_partner"]=true
		g._flags().js_contest_date=date
		g._do_warp(entry)
		g._persist()
		g._dialog(["去草丛找虫宝可梦吧。只能留下一个，回来找我就可以提前评选。"],"工作人员"))

static func first_slot(g) -> int:
	for i in g.save_data.party.size():
		if g.save_data.party[i] is Dictionary and not g.save_data.party[i].is_empty():return i
	return -1

static func partner_slot(g)->int:
	for i in g.save_data.party.size():
		if g.save_data.party[i] is Dictionary and g.save_data.party[i].get("crystal_contest_partner",false):return i
	return -1

static func departure(g,dest: Dictionary) -> bool:
	if not active(g) or g.world.map_data.id!=PARK or dest.get("map","")==PARK: return false
	g.held_dir=""
	g._pick("离开公园会结束本场捕虫大会。",["离开并评选","继续捕虫"],func(i):
		if i==0:finish(g))
	return true

static func expired(g) -> bool:
	return active(g) and (int(g.save_data.js_contest.balls)<=0 or Time.get_unix_time_from_system()>=float(g.save_data.js_contest.until))

static func field_step(g):
	if g.world.map_data.id==PARK and expired(g):finish(g)

static func encounter(g) -> bool:
	if g.world.map_data.id!=PARK or not active(g):return false
	if expired(g):
		finish(g)
		return true
	var roll: int=g.rng.randi_range(1,100)
	for row in ROWS:
		roll-=int(row[0])
		if roll<=0:
			g._start_wild_battle(int(row[1]),g.rng.randi_range(row[2],row[3]))
			break
	return true

static func score(mon: Dictionary) -> int:
	if mon.is_empty():return 0
	var points:=4*int(mon.max_hp)+int(mon.hp)/8+int(mon.get("contest_dv",0))
	for stat in ["atk","def","spe","spa","spd"]:points+=int(mon.stats[stat])
	return points+int(mon.get("berry","")!="" or mon.get("held","")!="")

static func caught(g,mon: Dictionary):
	var run: Dictionary=g.save_data.js_contest
	g.DexVariants.record(g.save_data,mon,false)
	mon.contest_dv=g.rng.randi_range(0,15)
	if run.kept.is_empty():
		run.kept=mon
		g._persist()
		if expired(g): finish(g)
		else: g._dialog(["本场保留了%s。还剩%d个竞赛球。"%[mon.name,run.balls]],"捕虫大会")
		return
	var old: Dictionary=run.kept
	g._pick("本场只保留一只宝可梦",["保留%s　Lv.%d"%[old.name,old.level],"改留%s　Lv.%d"%[mon.name,mon.level]],func(i):
		if i==1:run.kept=mon
		g._persist()
		if expired(g):finish(g))

static func finish(g):
	if not active(g):return
	var run: Dictionary=g.save_data.js_contest
	var kept: Dictionary=run.kept
	var points:=score(kept)
	var place:=1
	for rival in run.rivals:
		if rival>=points:place+=1
	for p in g.save_data.party:
		if p is Dictionary:p.erase("crystal_contest_partner")
	for box in g.save_data.get("boxes",[]):
		for p in box.get("mons",[]):
			if p is Dictionary:p.erase("crystal_contest_partner")
	g.save_data.erase("js_contest")
	var destination: Dictionary=g.get_node("/root/Data").load_map("johto",GATES[1])
	g._do_warp({"region":"johto","map":GATES[1],"at":destination.spawn,"hgss":true})
	var result: Array=["本次成绩为%d分，排名第%d。"%[points,place]]
	if not kept.is_empty():
		g._store_mon(kept)
		result.append("你带走了%s。"%kept.name)
	var item: String=PRIZES[mini(3,place-1)]
	if place>2:
		var berry_key: String="sitrus" if place==3 else "oran"
		g._give_bag_item(item,"berry","",berry_key)
	else: g._give_item(item,1,"other")
	g._flags().js_contest_best=maxi(points,int(g._flags().get("js_contest_best",0)))
	result.append("获得了%s！"%item)
	g._persist()
	g._dialog(result,"捕虫大会")
