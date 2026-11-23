extends RefCounted
## The seven later Gym Challenges. Puzzle state and rewards belong to this save/version.
const DB := "res://content/galar_gyms.json"
const COLORS := {"red":"红","yellow":"黄","blue":"蓝"}
const QUIZ := [
	["妖精属性的弱点是什么？",["毒属性","钢属性"],[0,1],"atk","攻击和特攻"],
	["上一位道馆训练家叫什么？",["安妮特","特蕾莎"],[0],"spe","速度"],
	["我每天早上都吃什么？",["咖喱","煎蛋卷"],[1],"def","防御和特防"],
	["你知道大家怎么称呼我吗？",["魔法师","魔术师"],[0],"spe","速度"],
	["我最喜欢什么颜色？",["粉红色","紫色"],[1],"def","防御和特防"],
	["你猜我几岁？",["16岁","88岁"],[0],"atk","攻击和特攻"]]
static var book:Dictionary
static func data()->Dictionary:
	if book.is_empty():
		book=JSON.parse_string(FileAccess.get_file_as_string(DB))
		for move in book.machine_compatibility:
			book.machine_compatibility[move]=PackedInt32Array(book.machine_compatibility[move])
	return book
static func section(n:int,f:Dictionary)->Dictionary:
	return data().gyms[str(n)]["shield" if str(f.get("g_version","sword"))=="shield" else "sword"]
static func key(n:int,suffix:String)->String:return "g_gym_%d_%s"%[n,suffix]
static func id(n:int,part:String)->String:return "galar_gym_%d_%s"%[n,part]
static func ok(f:Dictionary,n:int)->bool:return bool(f.get(key(n,"ready"),false)) and bool(f.get("g_badge_%d"%(n-1),false))
static func local(f:Dictionary,n:int)->Dictionary:
	return f.get(key(n,"field"),{})
static func edit(g,n:int)->Dictionary:
	return g._flags().get_or_add(key(n,"field"),{})
static func changed(g)->void:
	g.world.refresh_story_actors(g._flags())
	g._persist()
static func as_cell(xy:Array)->Vector2i:return Vector2i(int(xy[0]),int(xy[1]))
static func actor(xy:Array,role:String,label:String,graphic:String,prop:=false)->Dictionary:
	var row:={"at":xy,"role":"g_fac_"+role,"name":label}
	row["unova_prop" if prop else "field_art"]=graphic
	return row
static func trained(f:Dictionary,n:int,i:int)->bool:
	return bool(f.get(key(n,"trainer_"+str(i)),false))
static func current_map(g)->Dictionary:return g.world.map_data.get("galar_facility",{})
static func cleared(f:Dictionary,n:int)->bool:return bool(f.get(key(n,"mission"),false))
static func gate_open(n:int,gate:Dictionary,f:Dictionary,s:Dictionary)->bool:
	if cleared(f,n) or gate.has("checkpoint"):return true
	if gate.has("color"):return bool(s.get(gate.color,false))==bool(gate.open_on)
	if n==3:return int(s.get("points",0))>=5
	return trained(f,n,int(gate.stage)-1)

static func actors(map:Dictionary,f:Dictionary)->Array:
	var m:Dictionary=map.get("galar_facility",{})
	if m.is_empty():return []
	var n:=int(m.number)
	var cfg:=section(n,f)
	if m.part=="pitch":
		if not cleared(f,n) or f.get("g_badge_%d"%n,false):return []
		return [actor([14,11],"leader",cfg.leader,"breeder")]
	if not ok(f,n) or cleared(f,n):return []
	var list:Array=[]
	var s:=local(f,n)
	for i in m.get("trainers",[]).size():
		var person:Dictionary=cfg.trainers[i]
		var item:=actor(m.trainers[i],"trainer_%d"%i,person.name,("aroma_lady" if n==5 else "rocker" if n==7 else "cooltrainer_m"))
		list.append(item)
	for gate:Dictionary in m.get("gates",[]):
		if gate_open(n,gate,f,s):
			if n==2:
				var back:=int(gate.x)+(3 if int(gate.x)<13 else -3)
				var stream:=actor([back,int(gate.y)-1],"return","回流水幕","galar_gym_water",true)
				stream.pass_through=true
				list.append(stream)
			continue
		for x in range(int(gate.x)-1,int(gate.x)+2):
			list.append(actor([x,gate.y],"barrier","水幕" if n==2 else "拦路护栏","galar_gym_water" if n==2 else "galar_gym_rail",true))
	for i in m.get("valves",[]).size():
		var v:Array=m.valves[i];var color:=str(v[2])
		list.append(actor([v[0],v[1]],"valve_%d"%i,COLORS[color]+"色阀门","galar_gym_"+color+("_on" if s.get(color,false) else "_off"),true))
	for i in m.get("cups",[]).size():
		var at:Array=m.cups[i].at
		list.append(actor(at,"cup_%d"%i,"旋转座椅","galar_gym_cup%d"%int(s.get("cup_"+str(i),0)),true))
	for i in m.get("pens",[]).size():
		if not s.get("empty_"+str(i),false):
			list.append(actor(m.pens[i],"wild_%d"%i,["六尾","烧火蚣","烛光灵"][i],["galar_gym_vulpix","galar_gym_sizzlipede","galar_gym_litwick"][i],true))
	if n==6:
		for xy:Array in s.get("revealed",[]):
			# A revealed pit still triggers a fall when walked on; rendering it as a nonblocking object is handled by the field.
			var hole:=actor(xy,"hole","陷坑","galar_gym_pit",true)
			hole["pass_through"]=true
			list.append(hole)
	return list

static func deny(g,words:String)->bool:
	g.held_dir="";g.run_held=false
	g._dialog([words],"道馆工作人员")
	return true
static func warp(g,target:Dictionary)->bool:
	var name:=str(target.get("map",""))
	var here:=current_map(g)
	var f:Dictionary=g._flags()
	if not name.begins_with("galar_gym_"):
		if not here.is_empty() and here.part=="mission" and not cleared(f,int(here.number)):
			f.erase(key(int(here.number),"field"))
		return false
	var n:=int(name.get_slice("_",2))
	if not data().gyms.has(str(n)):return false
	if not ok(f,n):return deny(g,"尚未取得本次挑战资格。跟随当地的道馆挑战剧情，再来登记。")
	if name==id(n,"mission") and not cleared(f,n) and not f.get(key(n,"briefed"),false):
		var briefs={2:"转动红色、黄色和蓝色阀门。每次转动，同色管道会交换出水方向。",3:"和场内的训练家争夺五分！击倒野生宝可梦得一分，捕捉得两分。对手先将它击倒就不得分。",4:"站在旋转座椅的左侧或右侧按 A 转动，再站到南边按 A 登上座椅。对准轨道拐弯处的红色弹簧。",5:"这是舞台选拔！战斗时请回答问题，答对会提高能力，答错会降低能力。",6:"探测器距离陷坑越近，振动越强。找到安全的落脚处，穿过三段标记线。",7:"沿商店街去地下舞台。呐喊队会在沿途设下路障，这里也没有极巨化能量点。",8:"请带上至少两只有战斗力的伙伴。三位龙之训练家轮流以双打考验你对天气的运用。"}
		f[key(n,"briefed")]=true
		g.held_dir="";g.run_held=false
		g._dialog([briefs[n]],"道馆工作人员").closed.connect(func():g._do_warp(target),CONNECT_ONE_SHOT)
		return true
	if name==id(n,"pitch") and not cleared(f,n):
		if here.get("part","")!="mission" or int(here.get("number",0))!=n:return deny(g,"完成本馆的道馆任务后才能进入对战场。")
		var s:=local(f,n)
		if n==2 and int(s.get("valves_seen",0))!=15:return deny(g,"四处阀门都要操作过，才能关闭挡路的水幕。")
		if n==3 and int(s.get("points",0))<5:return deny(g,"捕捉得两分，击倒得一分。先积满五分。")
		if n==4 and int(s.get("rides",0))!=7:return deny(g,"三段旋转座椅赛道尚未全部通过。")
		if n==6 and int(s.get("checkpoint",0))<3:return deny(g,"请先穿过三片陷阱区。")
		if n in [4,5,7,8]:
			for i in section(n,f).trainers.size():
				if not trained(f,n,i):return deny(g,"前方还有训练家等候挑战。")
		f[key(n,"mission")]=true
		g._persist()
	if name==id(n,"mission") and cleared(f,n):
		if here.get("part","")=="pitch":
			var map:Dictionary=g.get_node("/root/Data").load_map("galar",name)
			g._do_warp(map.warps[0].to)
		else:g._do_warp({"region":"galar","map":id(n,"pitch"),"at":[14,24]})
		return true
	return false

static func step(g)->bool:
	var m:=current_map(g)
	if m.get("part","")!="mission" or int(m.get("number",0))!=6 or cleared(g._flags(),6):return false
	var at:Vector2i=g.world.player_pos;var s:=edit(g,6)
	for door:Dictionary in m.gates:
		if at.y==int(door.y) and absi(at.x-int(door.x))<=1:
			s.checkpoint=maxi(int(s.get("checkpoint",0)),int(door.checkpoint))
			g._show_toast("记录了新的探测起点。")
			g._persist()
	var distance:=999
	var traps:Array=m.traps_shield if g._flags().get("g_version","sword")=="shield" else m.traps
	for p:Array in traps:distance=mini(distance,absi(at.x-int(p[0]))+absi(at.y-int(p[1])))
	if distance==0:
		var holes:Array=s.get_or_add("revealed",[])
		var xy:=[at.x,at.y]
		if not holes.has(xy):holes.append(xy)
		g.held_dir="";g.run_held=false
		g.world.warp_to(as_cell(m.checkpoints[int(s.get("checkpoint",0))]))
		g._show_toast("脚下塌了！从上一处标记重新探路。")
		changed(g)
		return true
	if distance<3 and at.y>7:
		if OS.has_feature("mobile"):Input.vibrate_handheld(70 if distance==1 else 30)
		g._show_toast("探测器强烈振动！留意四周。" if distance==1 else "探测器轻轻振动。")
	return false

static func cup(g,m:Dictionary,i:int)->bool:
	var s:=edit(g,4);var station:Dictionary=m.cups[i];var at:=as_cell(station.at)
	var delta:Vector2i=g.world.player_pos-at;var k:="cup_"+str(i)
	if delta.x!=0:
		s[k]=posmod(int(s.get(k,0))+(1 if delta.x<0 else -1),4)
		changed(g);g._show_toast("座椅转向%s。站到南侧按 A 出发。"%["北","东","南","西"][int(s[k])])
		return true
	if delta.y<0:return deny(g,"从两侧转动座椅，从南侧进入座位。")
	var hit:=int(s.get(k,0))==int(station.goal)
	var landing:=as_cell(station.landing) if hit else at+Vector2i.DOWN
	var course:Array=station.track if hit else []
	if not hit:
		var dir:Vector2i=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT][int(s.get(k,0))]
		var bounce:=at+dir*2
		course=[[bounce.x,bounce.y],[landing.x,landing.y]]
	g.held_dir=""
	g.run_held=false
	g.world.warp_to(landing)
	if hit:
		s.rides=int(s.get("rides",0))|(1<<i)
		changed(g)
	var car:=Sprite2D.new()
	car.texture=load("res://assets/emerald/field/galar_gym_cup%d.png"%int(s.get(k,0)))
	car.scale=Vector2.ONE*g.world._field_actor_scale()
	car.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	g.world.add_child(car)
	var render:=func(point:Vector2):
		g.world._render_story_step(point)
		car.position=point*g.world.TILE+Vector2(g.world.TILE/2.0,g.world.TILE-4)
		car.z_index=g.world.Z_ACTOR+int(point.y)*2-1
	var previous:=Vector2(at)
	render.call(previous)
	var tween=g.create_tween()
	g.panel_open+=1
	for p:Array in course:
		var end:=Vector2(as_cell(p))
		tween.tween_method(render,previous,end,clampf(previous.distance_to(end)*0.047,0.09,0.46))
		previous=end
	tween.tween_callback(func():
		car.queue_free()
		g.world.warp_to(landing)
		g.panel_open=maxi(0,g.panel_open-1)
		if not hit:g._show_toast("旋转座椅撞上挡板，弹回了起点。")
	)
	return true

static func wild(g,n:int,i:int)->bool:
	var s:=edit(g,n);var cfg:=section(n,g._flags());var wild_ids:=[37,850,607]
	if s.get("empty_"+str(i),false):return true
	var scorecard:={"won":false}
	var competitors:Array=[]
	for row in cfg.trainers[i].team:
		var competitor:Dictionary=battle_competitor(g,row)
		competitor.scorecard=scorecard
		competitors.append(competitor)
	g._start_wild_battle(wild_ids[i],25 if i==1 else 24,"",func(result):
		if result=="b":return
		var po:=2 if result=="caught" else 1 if result=="a" and not scorecard.won else 0
		if result=="fled":return
		s["empty_"+str(i)]=true
		s.points=int(s.get("points",0))+po
		if int(s.points)<5 and [0,1,2].all(func(j):return s.get("empty_"+str(j),false)):
			for j in 3:s.erase("empty_"+str(j))
		changed(g)
		g._show_toast("捕捉赛　%d / 5 分。%s"%[int(s.points),"可以上场挑战卡芜了！" if int(s.points)>=5 else "去下一片草丛找宝可梦。"])
	)
	if is_instance_valid(g.active_battle):
		g.active_battle.battle.galar_competitor=competitors.pop_front()
		g.active_battle.battle.galar_rival_reserves=competitors
	return true

static func battle_competitor(g,row:Dictionary)->Dictionary:
	var b=load("res://core/battle.gd")
	var mon:Dictionary=b.make_combatant(int(row.species),int(row.level),row.moves,str(row.get("form","")))
	return b.normalize_team([mon])[0]

static func trainer(g,n:int,i:int)->bool:
	var f:Dictionary=g._flags();var cfg:=section(n,f);var person:Dictionary=cfg.trainers[i]
	if n==3:return deny(g,"捕获野生宝可梦得两分，击倒得一分。我也会出招和你争分！")
	if trained(f,n,i):return deny(g,"挑战结束，前面请通行。")
	if n==8 and g._make_team().filter(func(mon):return int(mon.hp)>0).size()<2:return deny(g,"双打需要两只可以战斗的伙伴。")
	var battle:={"team":person.team,"double":n==8 or person.get("double",false),"prize":int(person.team[-1].level)*96}
	if n==5:battle.galar_quiz=[i]
	g._start_battle({"name":"道馆训练家 "+str(person.name),"battle":battle},func(result):
		if result=="a":
			f[key(n,"trainer_"+str(i))]=true
			changed(g)
		elif result=="b" and g._party_fainted():g._blackout()
	)
	return true

static func item_name(g,cfg:Dictionary)->String:
	return "伽勒尔招式学习器%02d·%s"%[int(cfg.tm),str(g.get_node("/root/Data").move_of(int(cfg.move)).name)]

static func leader(g,n:int)->bool:
	var f:Dictionary=g._flags();var cfg:=section(n,f)
	if not ok(f,n) or not cleared(f,n):return deny(g,"还没有完成本次道馆任务。")
	if f.get("g_badge_%d"%n,false):return true
	if cfg.get("double",false) and g._make_team().filter(func(mon):return int(mon.hp)>0).size()<2:return deny(g,"奇巴纳的比赛采用双打，请准备两只伙伴。")
	var ace:Dictionary=cfg.team[-1]
	var battle:={"team":cfg.team,"prize":int(ace.level)*160,"double":cfg.get("double",false),"galar_power_spot":n!=7,
		"galar_ace":0 if n==7 else int(ace.species),"galar_gmax":ace.get("gmax",false)}
	if n==5:battle.galar_quiz=[3,4,5]
	g._start_battle({"name":"道馆馆主 "+str(cfg.leader),"battle":battle},func(result):
		if result=="a" and not f.get("g_badge_%d"%n,false):
			f["g_badge_%d"%n]=true
			g._grant_badge(cfg.badge)
			g._give_item(item_name(g,cfg),1,"tm")
			g._give_item(cfg.uniform,1,"key")
			changed(g)
			g._dialog(["收下%s、招式学习器和%s。训练家，下一场再见！"%[cfg.badge,cfg.uniform]],cfg.leader)
		elif result=="b" and g._party_fainted():g._blackout()
	)
	return true

static func talk(g,npc:Dictionary)->bool:
	var role:=str(npc.get("role",""))
	if not role.begins_with("g_fac_"):return false
	var m:=current_map(g);var n:=int(m.get("number",0));var s:=edit(g,n);role=role.trim_prefix("g_fac_")
	if role=="leader":return leader(g,n)
	if role=="barrier":return deny(g,"先完成这座场馆的机关或训练家挑战。")
	if role.begins_with("trainer_"):return trainer(g,n,role.get_slice("_",1).to_int())
	var i:=int(role.get_slice("_",1))
	if role.begins_with("valve_"):
		var c:=str(m.valves[i][2]);s[c]=not bool(s.get(c,false))
		s.valves_seen=int(s.get("valves_seen",0))|(1<<i)
		changed(g);g._show_toast("%s色水管切换了出水方向。"%COLORS[c]);return true
	if role.begins_with("cup_"):return cup(g,m,i)
	if role.begins_with("wild_"):return wild(g,n,i)
	return false

static func use_item(g,name:String)->bool:
	if (not UNIFORM_NAMES.has(name) and not name.begins_with("伽勒尔招式学习器")) or g._bag_count(name)<1:return false
	for n in range(2,9):
		for version_id in ["sword","shield"]:
			var cfg:Dictionary=data().gyms[str(n)][version_id]
			if name==cfg.uniform:
				var f:Dictionary=g._flags()
				f.g_gym_uniform="" if f.get("g_gym_uniform","")==name else name
				f.g_grass_uniform_worn=false
				g.world.taken=f;g.world._sync_player();g._persist()
				g._show_toast("小悠换上了"+name+"。" if f.g_gym_uniform!="" else "小悠换回了原来的衣服。")
				return true
			if name!=item_name(g,cfg):continue
			var slots:Array=[];var labels:Array=[]
			for i in g.save_data.party.size():
				var mon:Dictionary=g.save_data.party[i]
				if int(mon.get("species_id",0)) in data().machine_compatibility[str(int(cfg.move))]:
					slots.append(i);labels.append(str(mon.name))
			var move_name:=str(g.get_node("/root/Data").move_of(int(cfg.move)).name)
			if slots.is_empty():g._dialog(["队伍中没有可以学习%s的宝可梦。"%move_name])
			else:g._pick("让谁学习%s？"%move_name,labels,func(i):g._tm_teach_one(int(cfg.move),int(slots[i]),move_name,true))
			return true
	return false

static func rival_attack(b)->void:
	var rival:Dictionary=b.galar_competitor;var wild:Dictionary=b.cur_b()
	var choices:Array=range(rival.moves.size()).filter(func(i):return int(rival.pp[i])>0)
	if choices.is_empty():return
	var i:=int(choices[b.rng.randi_range(0,choices.size()-1)])
	var mv:Dictionary=Engine.get_main_loop().root.get_node("Data").move_of(int(rival.moves[i]))
	rival.pp[i]=int(rival.pp[i])-1
	var hp:=int(wild.hp)
	b.log.append("竞赛对手的%s使用了%s！"%[rival.name,mv.name])
	if str(mv.category)=="status":
		var effect:String=b._apply_effect(rival,wild,mv,0)
		if effect!="":b.log.append(effect)
		return
	if int(mv.accuracy)>0 and b.rng.randi_range(1,100)>int(mv.accuracy):return
	var damage_points:int=b.damage(rival,wild,mv)
	b._set_hp(wild,maxi(0,hp-damage_points))
	if int(wild.hp)==0:
		wild.fainted=true;rival.scorecard.won=true
		b.log.append("对手抢先击倒了野生宝可梦。")
	else:b.log.append("竞赛对手造成了 %d 点伤害。"%damage_points)

static func ask_quiz(ui)->bool:
	if ui.galar_quiz_index>=ui.galar_quiz.size() or int(ui.battle.completed_turns)<ui.galar_quiz_index:return false
	var q:Array=QUIZ[int(ui.galar_quiz[ui.galar_quiz_index])]
	var list=ui._list_sheet("FairyQuiz",str(q[0]),q[1].size())
	# The question must be answered before the turn resumes, including with physical Back.
	list.get_parent().get_parent().get_node("Return").visible=false
	ui.galar_quiz_index+=1
	for i in q[1].size():
		var answer:=func():
			var delta:=2 if i in q[2] else -2
			var target:Dictionary=ui.battle.cur_a();var logs:Array=[]
			var stats: Array=["atk","spa"] if q[3]=="atk" else ["def","spd"] if q[3]=="def" else ["spe"]
			for k in stats:ui.battle._apply_stage(target,k,delta,logs)
			ui._close_sheet()
			ui._open_commands("fight",("答对了！" if delta>0 else "答错了！")+str(q[4])+("提高了。" if delta>0 else "降低了。"))
		ui._row(list,str(q[1][i]),answer)
	return true

const UNIFORM_NAMES := {"水之套装":"water","火之套装":"fire","格斗之套装":"fighting","幽灵之套装":"ghost","妖精之套装":"fairy","岩石之套装":"rock","冰之套装":"ice","恶之套装":"dark","龙之套装":"dragon"}
static var uniform_cache:Dictionary={}
static func uniform_texture(name:String,afloat:bool,current:Texture2D)->Texture2D:
	if not UNIFORM_NAMES.has(name):return current
	var path:="res://assets/galar/league_gyms/uniform_%s_%s.png"%[UNIFORM_NAMES[name],"surf" if afloat else "walk"]
	if not uniform_cache.has(path):uniform_cache[path]=load(path)
	return uniform_cache[path]
