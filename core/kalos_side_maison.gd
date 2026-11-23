extends RefCounted
## Maison teams fight as copies; temporary HP, PP and transformations never replace a party member.
const Battle := preload("res://core/battle.gd")
const Party := preload("res://core/party.gd")
const Frontier := preload("res://core/frontier_rules.gd")
const SideItems := preload("res://core/unova_side.gd")
const MODE := ["单打","双打","三打","轮盘","多人"]
const STYLE := ["single","double","triple","rotation","double"]
const COUNT := [3,4,6,4,2]
const BOSSES := ["妮塔","露美丹","拉珠妮","露玛修"]
const BANNED := [150,151,249,250,251,382,383,384,385,386,483,484,487,489,490,491,492,493,494,643,644,646,647,648,649,716,717,718,719,720,721]
static var archive: Dictionary

static func data() -> Dictionary:
	if archive.is_empty():archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_maison.json"))
	return archive

static func side():
	return load("res://core/kalos_side.gd")

static func open(g) -> void:
	var run: Dictionary=g.save_data.get("kalos_maison",{})
	if not run.is_empty():menu(g,run);return
	var options:=MODE.duplicate()
	var codes:=[0,1,2,3,4]
	for i in MODE.size():
		if g._flags().get("ks_maison_super_%d"%i,false):
			options.append("超级"+MODE[i]);codes.append(i+5)
	options.append("查看最高连胜")
	options.append("离开")
	g._pick("奇楠市 · 对战屋",options,func(i):
		if i==options.size()-1:return
		if i==options.size()-2:
			var records: Array=[]
			for k in codes:records.append("%s　%d 连胜"%[MODE[k%5] if k<5 else "超级"+MODE[k%5],int(g.save_data.get("kalos_maison_best",{}).get(str(k),0))])
			g._dialog(records,"对战屋");return
		pick(g,codes[i],[]))

static func allowed(mon: Dictionary,chosen: Array) -> bool:
	if mon.is_empty() or mon.get("is_egg",false) or int(mon.species_id) in BANNED:return false
	if mon.get("held","")=="SOUL_DEW":return false
	for other in chosen:
		if int(other.species_id)==int(mon.species_id):return false
		var item:=str(mon.get("held",""));var berry:=str(mon.get("berry",""))
		if item!="" and item==other.get("held","") or berry!="" and berry==other.get("berry",""):return false
	return true

static func pick(g,code: int,selected: Array) -> void:
	var style:=code%5
	var options: Array=[];var eligible: Array=[]
	for mon in g.save_data.party:
		if mon is Dictionary and allowed(mon,selected):
			eligible.append(mon);options.append("%s　Lv.%d"%[mon.name,int(mon.level)])
	options.append("取消报名")
	g._pick("选择第 %d / %d 只 · 种类和持有物须不同"%[selected.size()+1,COUNT[style]],options,func(i):
		if i>=eligible.size():return
		var chosen:=selected.duplicate();chosen.append(eligible[i])
		if chosen.size()<int(COUNT[style]):pick(g,code,chosen);return
		var squad: Array=chosen.map(func(m):return Frontier.owner_team(m,mini(50,int(m.level))))
		if style==4:
			var mates:=["莎娜","提耶鲁诺","多罗巴"]
			g._pick("本地搭档",mates+["取消"],func(j):
				if j>=mates.size():return
				for row in data().partners[j]:squad.append(opponent(row))
				enroll(g,code,squad))
		else:enroll(g,code,squad))

static func enroll(g,code: int,squad: Array) -> void:
	var run:={"code":code,"team":squad,"wins":0}
	g.save_data.kalos_maison=run
	g._persist();menu(g,run)

static func menu(g,run: Dictionary) -> void:
	var code:=int(run.code)
	g._pick("%s%s · %d 连胜 · %d BP"%["超级" if code>=5 else "",MODE[code%5],int(run.wins),int(g.save_data.get("kalos_bp",0))],["开始下一场","暂时休息","结束挑战"],func(i):
		if i==0:fight(g,run)
		elif i==2:g._pick("结束这轮连胜？",["留下记录","继续挑战"],func(n):
			if n==0:g.save_data.erase("kalos_maison");g._persist()
			else:menu(g,run)))

static func opponent(row: Array) -> Dictionary:
	var mon:=Battle.make_combatant(int(row[0]),50,row[1].map(func(i):return int(i)))
	var key:=str(row[2])
	if key.ends_with("_BERRY"):mon.berry=key.trim_suffix("_BERRY").to_lower()
	elif key not in ["","NONE","—"]:mon.held=key
	mon.nature=row[3]
	if row.size()>5:
		var evs: Array=row[5]
		for i in 6:mon.get_or_add("effort",{})[["hp","atk","def","spa","spd","spe"][i]]=int(evs[i])
		Party.recalc(mon);mon.hp=mon.max_hp
	return mon

static func fill(g,roster: Array,n: int) -> Array:
	var foes: Array=[]
	var pool:=roster.duplicate()
	while not pool.is_empty() and foes.size()<n:
		var row: Array=data().sets[int(pool.pop_at(g.rng.randi_range(0,pool.size()-1)))]
		var mon:=opponent(row)
		if allowed_opponent(mon,foes):foes.append(mon)
	return foes

static func allowed_opponent(mon: Dictionary,others: Array) -> bool:
	for o in others:
		if int(o.species_id)==int(mon.species_id):return false
		if mon.get("held","")!="" and mon.held==o.get("held",""):return false
		if mon.get("berry","")!="" and mon.berry==o.get("berry",""):return false
	return true

static func fight(g,run: Dictionary) -> void:
	var code:=int(run.code);var round_no:=int(run.wins)+1;var style:=code%5
	var super_course:=code>=5
	var target:=50 if super_course else 20
	var foes: Array=[]
	var who: String
	if round_no==target:
		var boss:=mini(3,style)
		foes=data().bosses[boss*2+int(super_course)].map(opponent)
		who="对战女仆 "+str(BOSSES[boss])
		if style==4:
			who="对战女仆姐妹"
			foes=foes.slice(0,2)+data().bosses[int(super_course)].slice(0,2).map(opponent)
	else:
		var bounds: Array
		if super_course:
			bounds=[111,160] if round_no<=10 else [141,180] if round_no<=20 else [161,200] if round_no<=30 else [181,220] if round_no<=40 else [201,300]
		else:bounds=[1,50] if round_no<=5 else [33,70] if round_no<=10 else [51,90] if round_no<=15 else [71,110]
		var options: Array=data().rosters.filter(func(group):return int(group[2])<=int(bounds[1]) and int(group[3])>=int(bounds[0]))
		var group: Array=options[g.rng.randi_range(0,options.size()-1)]
		who=group[0][g.rng.randi_range(0,group[0].size()-1)]
		foes=fill(g,group[1],4 if style==4 else int(COUNT[style]))
	var mine: Array=run.team.duplicate(true)
	g._start_battle({"name":who,"battle":{"platinum_battle":true,"tower":true,"player":mine,"enemy":foes,"double":style in [1,4],"battle_type":STYLE[style]}},func(result):
		g._flags().ks_maison_played=true
		if result!="a":
			g.save_data.erase("kalos_maison");g.world.refresh_story_actors(g._flags());g._persist()
			g._dialog(["本次挑战结束。记录为 %d 连胜。"%int(run.wins)],"对战屋");return
		run.wins=round_no
		var best: Dictionary=g.save_data.get_or_add("kalos_maison_best",{})
		best[str(code)]=maxi(int(best.get(str(code),0)),round_no)
		var bp:=1 if round_no<=10 else 2
		if super_course:bp=mini(7,2+(round_no-1)/10)
		if round_no==target:bp=50 if super_course else 20
		if super_course and round_no>50:bp=7
		g.save_data.kalos_bp=int(g.save_data.get("kalos_bp",0))+bp
		if not super_course and round_no==target:
			g._flags()["ks_maison_super_%d"%style]=true
			g.save_data.erase("kalos_maison")
		g.world.refresh_story_actors(g._flags());g._persist()
		if not super_course and round_no==target:g._dialog(["打赢了对战女仆！超级%s已开放，获得 %d BP。"%[MODE[style],bp]],"对战屋")
		else:menu(g,run))

static func exchange(g) -> void:
	var rows: Array=data().shop
	var labels: Array=[]
	for row in rows:
		var key:=str(row[0])
		var name: String=preload("res://core/kalos_field.gd").machine_name(g,int(key.trim_prefix("TM")),false) if key.begins_with("TM") else str(side().data().items.get(key,SideItems.item_name(key)))
		labels.append("%s　%d BP"%[name,int(row[1])])
	labels.append("返回")
	g._pick("奖品兑换 · %d BP"%int(g.save_data.get("kalos_bp",0)),labels,func(i):
		if i>=rows.size():return
		var cost:=int(rows[i][1]);var key:=str(rows[i][0])
		if int(g.save_data.get("kalos_bp",0))<cost:g._dialog(["对战点数不足。"]);return
		if key.begins_with("TM"):
			var field=preload("res://core/kalos_field.gd")
			var n:=int(key.trim_prefix("TM"))
			if g._bag_count(field.machine_name(g,n,false))>0:g._dialog(["已经持有这枚学习器。"]);return
			field.give_machine(g,n,false)
		elif SideItems.data().items.has(key):SideItems.give(g,key)
		elif key=="ABILITY_CAPSULE":g._give_item(side().data().items[key],1,"other")
		elif key in ["SACHET","WHIPPED_DREAM"]:g._give_item(side().data().items[key],1,"evo")
		else:g._give_bag_item(side().data().items[key],"held",key)
		g.save_data.kalos_bp-=cost;g._persist()
		g._dialog(["兑换成功。"]))

static func chateau(g) -> void:
	var db: Dictionary=side().data().chateau
	var wins:=int(g.save_data.get("kalos_chateau_wins",0))
	var level:=0
	var cutoffs:=[0,5,20,40,140,295]
	for i in cutoffs.size():
		if wins>=int(cutoffs[i]):level=i
	var title: String=["男爵","子爵","伯爵","侯爵","公爵","大公"][level]
	var pick_list: Array=db.guests.filter(func(v):return int(v[2])<=level)
	var guest: Array=pick_list[g.rng.randi_range(0,pick_list.size()-1)]
	g._pick("对战城堡 · %s　已赢 %d 场"%[title,wins],["拜会"+str(guest[1]),"离开"],func(i):
		if i!=0:return
		preload("res://core/kalos_side_quests.gd").battle(g,guest[1],int(guest[0]),func():
			g.save_data.kalos_chateau_wins=wins+1;g._persist()
			g._dialog(["城堡记录下了这次胜利。"],title)))
