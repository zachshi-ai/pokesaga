extends RefCounted
const LOBBY := "galar_battle_tower"
const ROOM := "galar_battle_tower_field"
const RENTALS := ["基础队","技巧队","强攻队","雨天队","空间队"]
const LEON := ["leonbeginnertier","leonpokeballtier","leongreatballtier","leonultraballtier","leonmasterballtier"]
const PROMOTIONS := [6,10,15,21,33]
const Party := preload("res://core/party.gd")
static var book:Dictionary

static func data()->Dictionary:
	if book.is_empty():book=JSON.parse_string(FileAccess.get_file_as_string("res://content/galar_tower_teams.json"))
	return book

static func build_member(row:Array)->Dictionary:
	var moves:Array=row[1].duplicate()
	if moves.is_empty():moves=preload("res://core/galar_moves.gd").moves_for(int(row[0]),50)
	var m:Dictionary=Party.make(int(row[0]),50,moves)
	m.held=row[2]
	if str(row[2]).ends_with("BERRY"):m.berry=str(row[2]).trim_suffix("BERRY").trim_suffix("_")
	if int(row[3]):m.ability=int(row[3])
	return m

static func switch_map(source:String,target:Dictionary,f:Dictionary)->Dictionary:
	if f.get("g_champion",false) and source=="galar_wyndon" and target.get("map","")=="galar_rose":
		return {"region":"galar","map":LOBBY,"at":[14,16]}
	return target

static func walk_gate(mid:String,f:Dictionary)->String:
	if mid in [LOBBY,ROOM] and not f.get("g_champion",false):return "先获得伽勒尔冠军资格。"
	if mid==ROOM and not f.has("g_tower_run"):return "先到接待处选择挑战组别和参赛队伍。"
	return ""

static func rental(g)->void:
	g._pick("借用哪一队？",RENTALS,func(i):
		g._flags().g_tower_rental=i
		g._persist()
		g._dialog(["登记了%s。到接待处选择其中的成员上场。"%RENTALS[i]]))

static func enter(g)->void:
	g._pick("对战塔报名",["单打 · 3只","双打 · 4只"],func(mode):
		var rented:Array=data().rentals[int(g._flags().get("g_tower_rental",0))]
		var options:Array=["自己的队伍","租借的"+RENTALS[int(g._flags().get("g_tower_rental",0))]]
		g._pick("从哪支队伍选人？",options,func(i):
			var candidates:Array=[]
			if i==1:
				for row in rented:candidates.append(build_member(row))
			else:
				for member in g.save_data.party:
					if not member is Dictionary or member.is_empty() or member.get("egg",false):continue
					var original:Dictionary=member.duplicate(true)
					original.level=50
					Party.recalc(original)
					original.hp=original.max_hp;original.status=""
					for j in original.moves.size():
						if j<original.pp.size():original.pp[j]=int(g.get_node("/root/Data").move_of(int(original.moves[j])).get("pp",5))
					candidates.append(original)
			if candidates.size()<3+mode:
				g._dialog(["队伍人数不足，可以先借用一套队伍。"])
			else:select_members(g,candidates,[],mode)))

static func select_members(g,candidates:Array,selected:Array,mode:int)->void:
	var labels:Array=candidates.map(func(m):return str(m.name))
	g._pick("选择第%d只　共%d只"%[selected.size()+1,3+mode],labels,func(i):
		var m:Dictionary=candidates[i]
		if selected.any(func(v):return v.species_id==m.species_id or v.get("held","")!="" and v.held==m.get("held","")):
			g._dialog(["同一种宝可梦或同一携带道具不能重复报名。"]);return
		var rest:=candidates.duplicate();rest.remove_at(i)
		var team:=selected.duplicate();team.append(m)
		if team.size()<3+mode:select_members(g,rest,team,mode);return
		g._flags().g_tower_run={"mode":mode,"team":team}
		g._do_warp({"region":"galar","map":ROOM,"at":[12,16]}))

static func lineup(g,count:int,wins:int)->Dictionary:
	var leader:=PROMOTIONS.find(wins+1)
	if wins>=33 and (wins+1)%10==0:leader=4
	var names:Array=data().opponents.keys().filter(func(n):return not str(n).begins_with("leon"))
	var name:String=LEON[leader] if leader>=0 else str(names[g.rng.randi_range(0,names.size()-1)])
	var bag:Array=data().opponents[name].duplicate();var choices:Array=[];var species:Dictionary={}
	while not bag.is_empty() and choices.size()<count-(1 if leader>=0 else 0):
		var slot:int=g.rng.randi_range(0,bag.size()-1)
		var row:Array=data().sets[int(bag[slot])];bag.remove_at(slot)
		if species.has(int(row[0])) or leader>=0 and int(row[0])==6:continue
		species[int(row[0])]=true;choices.append(build_member(row))
	if leader>=0:
		for key in data().opponents[name]:
			var row:Array=data().sets[int(key)]
			if int(row[0])==6:
				var ace:=build_member(row);ace.gmax_factor=true;choices.append(ace);break
	return {"trainer":"丹帝" if leader>=0 else name.capitalize(),"team":choices,"leader":leader>=0}

static func fight(g)->void:
	var f:Dictionary=g._flags()
	if not f.has("g_tower_run"):g._dialog(["请先在大厅报名。"]);return
	var run:Dictionary=f.g_tower_run;var mode:int=run.mode;var key:="g_tower_"+("doubles" if mode else "singles")
	var wins:=int(f.get(key,0));var foe:=lineup(g,3+mode,wins)
	var battle={"platinum_battle":true,"player":run.team.duplicate(true),"enemy":foe.team,"double":mode==1,"tower":true,"galar_power_spot":true,"galar_gmax":foe.leader,"galar_ace":6 if foe.leader else 0,"prize":0}
	g._start_battle({"name":foe.trainer,"battle":battle},func(result):
		f.erase("g_tower_run")
		if result=="a":
			f[key]=wins+1
			g.save_data.battle_points=int(g.save_data.get("battle_points",0))+2
		g._do_warp({"region":"galar","map":LOBBY,"at":[14,4]})
		g._dialog(["获胜！本组累计 %d 胜，获得 2 BP。"%[wins+1] if result=="a" else "本次挑战结束。随时可以重新报名。"]))

static func talk(g,role:String)->void:
	match role:
		"venue_tower_rental":rental(g)
		"venue_tower_sign":enter(g)
		"venue_tower_fight":fight(g)
		"venue_tower_bp":
			g._pick("现有 %d BP"%int(g.save_data.get("battle_points",0)),["神奇糖果　20 BP","能力增强剂　2 BP"],func(i):
				var price: int=[20,2][i]
				if int(g.save_data.get("battle_points",0))<price:g._dialog(["BP 不足。"]);return
				g.save_data.battle_points-=price;g._give_item(["神奇糖果","攻击增强剂"][i],1,"medicine");g._persist())
