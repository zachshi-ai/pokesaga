extends RefCounted

const FR := preload("res://core/frlg_sidequests.gd")
const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")
const INCENSE := {360:["LAX_INCENSE",202],298:["SEA_INCENSE",183],439:["ODD_INCENSE",122],438:["ROCK_INCENSE",185],446:["FULL_INCENSE",143],458:["WAVE_INCENSE",226],406:["ROSE_INCENSE",315],440:["LUCK_INCENSE",113],433:["PURE_INCENSE",358]}
const SPECIAL_DATES := [112,214,303,401,501,611,707,821,907,928,1121,1214]
const STATS := ["hp","atk","def","spe","spa","spd"]
static var table: Dictionary

static func data() -> Dictionary:
	if table.is_empty():
		table=JSON.parse_string(FileAccess.get_file_as_string("res://content/sinnoh_breeding.json"))
		# JSON numbers reload as floats. Array.has uses strict Variant types.
		for row in table.values():
			row[0]=row[0].map(func(k):return int(k))
			row[3]=row[3].map(func(k):return int(k))
	return table

static func compatibility(a: Dictionary,b: Dictionary,player_id: int) -> int:
	var ia := int(a.species_id)
	var ib := int(b.species_id)
	var ga: Array=data().get(str(ia),[[]])[0]
	var gb: Array=data().get(str(ib),[[]])[0]
	if ga.is_empty() or gb.is_empty() or 15 in ga or 15 in gb or (ia==132 and ib==132):return 0
	var foreign := int(a.get("ot_id",player_id))!=int(b.get("ot_id",player_id))
	if ia==132 or ib==132:return 50 if foreign else 20
	if a.get("sex","")==b.get("sex","") or not a.get("sex","") in ["male","female"] or not b.get("sex","") in ["male","female"]:return 0
	if not ga.any(func(k):return gb.has(k)):return 0
	if ia==ib:return 70 if foreign else 50
	return 50 if foreign else 20

static func preview(entry: Dictionary) -> Dictionary:
	var mon: Dictionary=entry.mon.duplicate(true)
	if int(mon.level)>=100:return mon
	var level:=int(mon.level)
	var curve:=str(Data.species_of(int(mon.species_id)).get("growth","medium_fast"))
	mon.exp=mini(Growth.exp_for_level(100,curve),int(mon.get("exp",Growth.exp_for_level(level,curve)))+int(entry.steps))
	while level<100 and int(mon.exp)>=Growth.exp_for_level(level+1,curve):level+=1
	mon.level=level
	return mon

static func add_move(moves: Array,move: int) -> void:
	if move<=0 or moves.has(move):return
	if moves.size()>=4:moves.pop_front()
	moves.append(move)

static func egg_mon(g,side,a: Dictionary,b: Dictionary) -> Dictionary:
	var mother: Dictionary=a if a.get("sex","")=="female" else b
	if int(a.species_id)==132 or int(b.species_id)==132:mother=b if int(a.species_id)==132 else a
	var father: Dictionary=b if is_same(mother,a) else a
	var seed_parent:=mother
	var sid:=int(data()[str(int(mother.species_id))][1])
	if sid==29 and g.rng.randi_range(0,1)==1:sid=32
	if sid==314 and g.rng.randi_range(0,1)==1:sid=313
	if sid==490:sid=489
	if INCENSE.has(sid) and not INCENSE[sid][0] in [a.get("held",""),b.get("held","")]:sid=int(INCENSE[sid][1])
	if int(father.species_id)==132 and mother.get("sex","")!="female":
		father=mother
		mother=b if is_same(father,a) else a
	var form: String=seed_parent.get("form","") if sid in [412,422] else ""
	var moves: Array=side.moves_for(sid,1,form).map(func(k):return int(k))
	var paternal_moves: Array=father.moves.map(func(k):return int(k))
	var maternal_moves: Array=mother.moves.map(func(k):return int(k))
	var egg_moves: Array=data()[str(sid)][3]
	for move in paternal_moves:
		if int(move) in egg_moves:add_move(moves,int(move))
	for move in paternal_moves:
		for machine in side.data().machines.values():
			if int(machine.move)==int(move) and machine.species.any(func(k):return int(k)==sid):
				add_move(moves,int(move))
				break
	var levels: Array=side.learnset(sid,form)
	if levels.is_empty():levels=Data.species_of(sid).get("learnset",[])
	var level_moves: Array=levels.map(func(row):return int(row[1]))
	for move in paternal_moves:
		if move in maternal_moves and int(move) in level_moves:add_move(moves,int(move))
	if sid==172 and "LIGHT_BALL" in [a.get("held",""),b.get("held","")]:add_move(moves,344)
	var mon:=Party.make(sid,1,moves,form)
	mon.berry=""
	mon.ot_id=g.save_data.js_trainer_id
	mon.origin="随意镇培育屋"
	Party.set_shiny_kind(mon,Party.roll_shiny(g.appearance_rng))
	var nature_parent: Dictionary=a if int(a.species_id)==132 else (b if int(b.species_id)==132 else mother)
	const NATURES:=["勤奋","怕寂寞","勇敢","固执","顽皮","大胆","坦率","悠闲","淘气","乐天","胆小","急躁","认真","爽朗","天真","内敛","慢吞吞","冷静","害羞","马虎","温和","温顺","自大","慎重","浮躁"]
	mon.nature=nature_parent.get("nature","坦率") if nature_parent.get("held","")=="EVERSTONE" and g.rng.randi_range(0,1)==0 else NATURES[g.rng.randi_range(0,24)]
	mon.ivs={}
	for key in STATS:mon.ivs[key]=g.rng.randi_range(0,31)
	var pool:=STATS.duplicate()
	for i in 3:
		var stat: String=pool.pop_at(g.rng.randi_range(0,pool.size()-1))
		var parent: Dictionary=a if g.rng.randi_range(0,1)==0 else b
		mon.ivs[stat]=int(parent.get("ivs",{}).get(stat,31))
	return mon

static func tick(g,side) -> bool:
	var entries: Array=g.save_data.get("s_day_care",[])
	if entries.is_empty() and g.save_data.get("sinnoh_eggs",[]).is_empty():return false
	for entry in entries:entry.steps=int(entry.steps)+1
	if entries.size()==2 and not g.save_data.has("s_daycare_egg") and (int(entries[1].steps)&255)==255:
		var score:=compatibility(entries[0].mon,entries[1].mon,int(g.save_data.js_trainer_id))
		if score>g.rng.randi_range(0,65535)*100/65535:
			g.save_data.s_daycare_egg=egg_mon(g,side,entries[0].mon,entries[1].mon)
			g._flags().s_daycare_egg_waiting=true
			g.world.refresh_story_actors(g._flags())
			g._persist()
	var date:=Time.get_date_dict_from_system()
	var limit:=230 if int(date.month)*100+int(date.day) in SPECIAL_DATES else 255
	var clock:=int(g.save_data.get("s_daycare_hatch_clock",0))+1
	g.save_data.s_daycare_hatch_clock=clock%limit
	return clock>=limit

static func ready(egg: Dictionary,cycle: bool,pace: int) -> bool:
	if not cycle:return false
	if int(egg.cycles)==0:return true
	egg.cycles=maxi(0,int(egg.cycles)-pace)
	return false

static func report(g) -> String:
	var rows: Array=[]
	for entry in g.save_data.get("s_day_care",[]):
		var mon:=preview(entry)
		rows.append("%s　Lv.%d"%[mon.name,mon.level])
	if g.save_data.has("s_daycare_egg"):rows.append("发现了一枚蛋！")
	return "／".join(rows) if not rows.is_empty() else "培育屋还没有托管伙伴。"

static func deposit(g,slot: int) -> void:
	var rows: Array=g.save_data.get_or_add("s_day_care",[])
	var party: Array=g.save_data.party
	if rows.size()>=2 or slot<0 or slot>=party.size() or party[slot].is_empty():return
	var mon: Dictionary=party[slot]
	if not party.any(func(m):return m is Dictionary and not is_same(m,mon) and int(m.get("hp",0))>0):
		FR.say(g,"请留下一只能够战斗的伙伴。","培育屋婆婆")
		return
	if not g.save_data.has("js_trainer_id"):g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
	if not mon.has("sex"):
		var ratio:=int(Data.species_of(int(mon.species_id)).get("gender",255))
		if ratio<255:mon.sex="female" if ratio==254 or g.rng.randi_range(0,253)<ratio else "male"
	rows.append({"mon":mon,"steps":0})
	party[slot]={}
	g.save_data.party=Party.compact(party)
	g._flags().s_daycare_used=true
	g.world.refresh_story_actors(g._flags())
	g._persist()
	FR.say(g,"把%s交给我吧。散步回来再看看！"%mon.name,"培育屋婆婆")

static func withdraw(g,side,slot: int) -> void:
	var rows: Array=g.save_data.get("s_day_care",[])
	if slot<0 or slot>=rows.size() or g.save_data.has("s_daycare_egg"):return
	var entry: Dictionary=rows[slot]
	var mon:=preview(entry)
	var old_level:=int(entry.mon.level)
	var fee:=100*(1+int(mon.level)-old_level)
	if Party.occupied(g.save_data.party)+g.save_data.get("sinnoh_eggs",[]).size()>=Party.MAX_SIZE:
		FR.say(g,"你的队伍满了，给它留一个位置吧。","培育屋婆婆")
		return
	if int(g.save_data.get("money",0))<fee:
		FR.say(g,"照顾费是 %d 元，凑齐了再来吧。"%fee,"培育屋婆婆")
		return
	for move in Growth.moves_learned(mon,old_level,int(mon.level),side.learnset(int(mon.species_id),mon.get("form",""))):
		if not mon.moves.any(func(k):return int(k)==int(move)):
			if mon.moves.size()>=4:mon.moves.pop_front();mon.pp.pop_front()
			mon.moves.append(move)
			mon.pp.append(int(Data.move_of(int(move)).get("pp",10)))
	if int(mon.level)>old_level:Party.recalc(mon,true)
	if not Party.insert_into(g.save_data.party,mon,Party.MAX_SIZE):return
	rows.remove_at(slot)
	g.save_data.money=int(g.save_data.money)-fee
	g._persist()
	FR.say(g,"%s回到了队伍。照顾费共 %d 元。"%[mon.name,fee],"培育屋婆婆")

static func collect(g,side) -> void:
	if not g.save_data.has("s_daycare_egg"):return
	if Party.occupied(g.save_data.party)+g.save_data.get("sinnoh_eggs",[]).size()>=Party.MAX_SIZE:
		FR.say(g,"队伍里没有放蛋的位置了，我替你留着。","培育屋爷爷")
		return
	var mon: Dictionary=g.save_data.s_daycare_egg
	var eggs: Array=g.save_data.get_or_add("sinnoh_eggs",[])
	eggs.append({"species":int(mon.species_id),"cycles":int(data()[str(int(mon.species_id))][2]),"mon":mon})
	g._give_item("神奥的蛋",1,"key")
	g.save_data.erase("s_daycare_egg")
	g.save_data.s_daycare_hatch_clock=0
	side.change(g,"s_daycare_egg_waiting",false)
	FR.say(g,"这枚蛋就交给你了。带着它一起走走吧。","培育屋爷爷")

static func man(g,side) -> void:
	var rows: Array=g.save_data.get("s_day_care",[])
	if g.save_data.has("s_daycare_egg"):
		g._pick("你的伙伴带来了一枚蛋，要领走吗？",["领取蛋","放弃这枚蛋"],func(i):
			if i==0:collect(g,side)
			else:g._pick("确定不领取这枚蛋吗？",["还是领取","确定放弃"],func(n):
				if n==0:collect(g,side)
				else:
					g.save_data.erase("s_daycare_egg")
					g.save_data.s_daycare_hatch_clock=0
					side.change(g,"s_daycare_egg_waiting",false)))
		return
	var text:="我会帮你观察伙伴们相处得怎么样。"
	if rows.size()==1:text="%s过得很好！"%rows[0].mon.name
	if rows.size()==2:
		var score:=compatibility(rows[0].mon,rows[1].mon,int(g.save_data.js_trainer_id))
		text={0:"它们更喜欢跟其他伙伴玩。",20:"它们好像不太亲近。",50:"它们相处得不错。",70:"它们非常亲密！"}[score]
	FR.say(g,text,"培育屋爷爷")

static func lady(g,side) -> void:
	var rows: Array=g.save_data.get("s_day_care",[])
	if g.save_data.has("s_daycare_egg"):
		FR.say(g,"老爷爷在外面找你，好像发现了什么！","培育屋婆婆")
		return
	var options: Array=[]
	if rows.size()<2:options.append("寄放伙伴")
	for entry in rows:
		var mon:=preview(entry)
		options.append("接回%s　Lv.%d（%d 元）"%[mon.name,mon.level,100*(1+int(mon.level)-int(entry.mon.level))])
	options.append("离开")
	g._pick("随意镇培育屋",options,func(i):
		if i==options.size()-1:return
		if options[i]=="寄放伙伴":
			FR.pick_party(g,"寄放哪一只？",func(_m):return true,func(slot):deposit(g,slot))
		else:
			var slot: int=i-(1 if rows.size()<2 else 0)
			g._pick(options[i],["支付并接回","稍后"],func(n):
				if n==0:withdraw(g,side,slot)))

static func talk(g,side,script: String) -> bool:
	match script:
		"DayCareCommon_Lady":lady(g,side)
		"DayCareCommon_Man":man(g,side)
		"PokemonDayCare_GymGuide":
			var apps: Array=g.save_data.get_or_add("s_apps",[])
			if not apps.has("培育屋查看器"):
				apps.append("培育屋查看器")
				g._persist()
				FR.say(g,"我给你的宝可表安装了培育屋查看器，可以随时查看伙伴和蛋。","培育屋访客")
			else:FR.say(g,report(g),"培育屋访客")
		_:return false
	return true
