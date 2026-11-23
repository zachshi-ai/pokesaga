extends RefCounted
## Turffield Gym Challenge. Each visible group contains five Wooloo.
const LOBBY := "galar_turffield_pitch_room"
const MISSION := "galar_turffield_mission"
const PITCH := "galar_turffield_pitch"
const TM := "伽勒尔招式学习器10·魔法叶"
const UNIFORM := "草之套装"
const TRAINERS := ["","萨缪尔","马克","莉娅"]
const TEAMS := [
	[], [{"species":829,"level":16,"moves":[229,633,47]}],
	[{"species":406,"level":16,"moves":[72,74,78]},{"species":43,"level":17,"moves":[72,51,77]}],
	[{"species":761,"level":17,"moves":[229,230,75]},{"species":43,"level":17,"moves":[72,51,77]}]]
const MILO := [{"species":829,"level":19,"moves":[345,496,229],"ability":144},
	{"species":830,"level":20,"moves":[345,633,496],"ability":238}]

static func actor(at:Array,role:String,label:String,graphic:String,prop:=false)->Dictionary:
	var n:={"at":at,"role":role,"name":label}
	n["unova_prop" if prop else "field_art"]=graphic
	return n

static func state(pens:Array,index:int)->Dictionary:
	return {"stage":index,"tick":0,"flocks":pens[index].flocks.duplicate(true)}

static func dog_position(pen:Dictionary,index:int,tick:int,rest:bool)->Array:
	var origin:Array=pen.dogs[index]
	if rest:return [4+index,int(pen.trainer[1])]
	var swing:=[0,1,2,3,4,3,2,1]
	var dog_x:=int(origin[0])+int(swing[(tick/2+3*index)%8])*(-1 if index==0 else 1)
	return [dog_x,int(origin[1])-1]

static func actors(map:Dictionary,f:Dictionary)->Array:
	if map.id==LOBBY:
		return [actor([3,3],"g_gym_reception","道馆工作人员","clerk")]
	if map.id==PITCH and f.get("g_gym_mission",false):
		return [actor([14,11],"galar_milo","亚洛","breeder")]
	if map.id!=MISSION or not f.get("g_gym_registered",false) or f.get("g_gym_mission",false):return []
	var pens:Array=map.galar_pens
	var s:Dictionary=f.get("g_pasture",state(pens,0))
	var stage:=int(s.stage)
	var rows:Array=[]
	for i in range(stage,pens.size()):
		var gate:Array=pens[i].gate
		for x in range(int(gate[0])-2,int(gate[0])+3):
			rows.append(actor([x,gate[1]],"g_hay","干草垛","galar_straw_gate",true))
	var pen:Dictionary=pens[stage]
	for idx in s.flocks.size():
		if not s.flocks[idx].is_empty():
			rows.append(actor(s.flocks[idx],"g_flock_%d"%idx,"毛辫羊","galar_wooloo_flock",true))
	if stage:
		rows.append(actor(pen.trainer,"g_grass_trainer_%d"%stage,TRAINERS[stage],"breeder" if stage<3 else "aroma_lady"))
		for i in pen.dogs.size():
			var resting:bool=f.get("g_grass_win_%d"%stage,false)
			var xy:Array=s.dogs[i] if not resting and s.get("dogs",[]).size()>i else dog_position(pen,i,int(s.tick),resting)
			rows.append(actor(xy,"g_yamper","来电汪","galar_yamper",true))
	return rows

static func reset(f:Dictionary)->void:
	f.erase("g_pasture")
	for i in 4:f.erase("g_pen_%d"%(i+1))

static func deny(g,text:String)->bool:
	g.held_dir=""
	g.run_held=false
	g._dialog([text],"道馆工作人员")
	return true

static func warp(g,target:Dictionary)->bool:
	var f:Dictionary=g._flags()
	var dest:=str(target.map)
	var here:=str(g.world.map_data.id)
	if dest==LOBBY and not f.get("g_gym_ready",false):return deny(g,"先去草路镇的山坡，索妮亚在地画观景台等你。")
	if dest==MISSION:
		if not f.get("g_gym_registered",false):return deny(g,"请先在左侧柜台登记道馆任务。")
		if f.get("g_gym_mission",false) and here==LOBBY:
			g._do_warp({"map":PITCH,"region":"galar","at":[14,24]})
			return true
		if f.get("g_gym_mission",false) and here==PITCH:
			g._do_warp({"map":LOBBY,"region":"galar","at":[6,1]})
			return true
	if dest==PITCH and not f.get("g_gym_mission",false):return deny(g,"四座牧场的羊群全部到齐，选手通道才会开放。")
	if here==MISSION and dest!=MISSION and not f.get("g_gym_mission",false):
		reset(f)
	return false

static func inside(map:Dictionary,p:Vector2i,top:int)->bool:
	return p.x>=2 and p.x<=22 and p.y>=top+1 and p.y<=top+12 and int(map.tiles[p.y][p.x])==0

static func mat(p:Vector2i,gate:Vector2i)->bool:
	return p.y<=gate.y+2 and absi(p.x-gate.x)<=2

## The flock seeks a free lane to the mat when the herder is at its rear.
static func toward_mat(map:Dictionary,from:Vector2i,gate:Vector2i,occupied:Dictionary)->Vector2i:
	var queue:Array[Vector2i]=[from]
	var first:={from:from}
	var head:=0
	while head<queue.size():
		var at:=queue[head]
		head+=1
		var across:=Vector2i.LEFT if gate.x<=at.x else Vector2i.RIGHT
		for direction:Vector2i in [Vector2i.UP,across,-across,Vector2i.DOWN]:
			var to:=at+direction
			if not inside(map,to,gate.y) or first.has(to) or occupied.has(to):continue
			first[to]=to if at==from else first[at]
			if mat(to,gate):return first[to]
			queue.append(to)
	return from

static func step(g)->bool:
	var map:Dictionary=g.world.map_data
	var f:Dictionary=g._flags()
	if map.id!=MISSION or f.get("g_gym_mission",false) or not f.get("g_gym_registered",false):return false
	var pens:Array=map.galar_pens
	var s:Dictionary=f.get("g_pasture",state(pens,0))
	f.g_pasture=s
	var stage:=int(s.stage)
	var pen:Dictionary=pens[stage]
	var gate:=Vector2i(int(pen.gate[0]),int(pen.gate[1]))
	var player:Vector2i=g.world.player_pos
	var occupied:={player:true}
	for a:Array in s.flocks:
		if a.size():occupied[Vector2i(int(a[0]),int(a[1]))]=true
	var dogs:Array[Vector2i]=[]
	if stage:
		occupied[Vector2i(int(pen.trainer[0]),int(pen.trainer[1]))]=true
		var quiet:bool=f.get("g_grass_win_%d"%stage,false)
		var next_dogs:Array=[]
		for i in pen.dogs.size():
			var xy:=dog_position(pen,i,int(s.tick)+1,quiet)
			var dog:=Vector2i(int(xy[0]),int(xy[1]))
			if occupied.has(dog):
				xy=s.dogs[i] if s.get("dogs",[]).size()>i else dog_position(pen,i,int(s.tick),quiet)
				dog=Vector2i(int(xy[0]),int(xy[1]))
			next_dogs.append(xy)
			occupied[dog]=true
			if not quiet:dogs.append(dog)
		s.dogs=next_dogs
	s.tick=int(s.tick)+1
	var arrived:=false
	for i in s.flocks.size():
		var xy:Array=s.flocks[i]
		if xy.is_empty():continue
		var at:=Vector2i(int(xy[0]),int(xy[1]))
		var away:=at-player
		var to:=at
		if away.y<0 and away.y>=-3 and absi(away.x)<=2:
			to=toward_mat(map,at,gate,occupied)
		elif away.y==0 and absi(away.x) in [1,2]:
			to=at+Vector2i(signi(away.x),0)
		elif int(s.tick)%4==0:
			for dog in dogs:
				if at.distance_squared_to(dog)<=4:
					to=at+Vector2i(1 if at.x>=dog.x else -1,0)
					break
		if to==at or not inside(map,to,gate.y) or occupied.has(to):continue
		occupied.erase(at)
		if mat(to,gate):
			s.flocks[i]=[]
			arrived=true
		else:
			occupied[to]=true
			s.flocks[i]=[to.x,to.y]
	if arrived:
		var count:=0
		for xy:Array in s.flocks:
			if xy.is_empty():count+=5
		if count==20:
			f["g_pen_%d"%(stage+1)]=true
			if stage+1==pens.size():
				f.g_gym_mission=true
				f.erase("g_pasture")
				g._show_toast("20/20！最后的草垛倒下了，前往球员通道挑战亚洛！")
			else:
				f.g_pasture=state(pens,stage+1)
				g._show_toast("20/20！羊群冲开了草垛，进入下一片牧场。")
		else:g._show_toast("第 %d 片牧场　%d / 20 只已进圈"%[stage+1,count])
		g._persist()
	g.world.refresh_story_actors(f)
	return false

static func battle_rules(g,ui,npc:Dictionary)->void:
	var b=ui.battle
	b.galar_rules=true
	b.galar_power_spot=bool(g.world.map_data.get("galar_power_spot",false))
	b.galar_band=bool(g._flags().get("g_band",false))
	b.galar_ace=830 if npc.get("role","")=="galar_milo" else 0

static func talk(g,npc:Dictionary)->bool:
	var role:=str(npc.get("role",""))
	var f:Dictionary=g._flags()
	match role:
		"g_gym_reception":
			if not f.get("g_gym_ready",false) or not f.get("g_band",false):return deny(g,"请先完成开幕式，并到山坡与索妮亚见面。")
			if f.get("g_badge_1",false):return deny(g,"草之徽章在你手里了。谢谢你来照看毛辫羊！")
			if not f.get("g_gym_registered",false):
				f.g_gym_registered=true
				g._persist()
			return deny(g,"已为你登记。穿过北门，把每片牧场的二十只毛辫羊赶到有箭头的草垫。五只一群，从后面靠近，它们就会向前跑。从侧面靠近能改变路线。")
		"g_flock_0","g_flock_1","g_flock_2","g_flock_3":return deny(g,"咩——！绕到羊群后面，用方向键或触屏方向盘赶它们进圈。")
		"g_hay":return deny(g,"二十只毛辫羊都进圈之后，羊群就能冲开这排干草垛。")
		"g_yamper":return deny(g,"汪！赢过附近的道馆训练家，来电汪就会安静下来。")
		"galar_milo":
			if f.get("g_badge_1",false):
				g._dialog(["草之徽章记录着你和搭档的这次胜利！"],"亚洛")
				return true
			if not f.get("g_gym_mission",false) or not f.get("g_gym_registered",false):return deny(g,"先完成牧场的道馆任务。")
			g._dialog(["这片草坪有能量点！在战斗中按「特殊」，选择极巨化，再选招式。让我看看你们一路培养的默契吧！"],"亚洛").closed.connect(func():
				g._start_battle({"name":"道馆馆主 亚洛","role":role,"battle":{"team":MILO,"prize":3200}},func(result):
					if result=="a" and not f.get("g_badge_1",false):
						f.g_badge_1=true
						g._grant_badge("草之徽章")
						g._give_item(TM,1,"tm")
						g._give_item(UNIFORM,1,"key")
						g._persist()
						g._dialog(["这枚草之徽章是你的了。收下可重复使用的招式学习器「魔法叶」，还有我们队的草之套装！"],"亚洛")
					elif result=="b" and g._party_fainted():g._blackout()
				),CONNECT_ONE_SHOT)
			return true
	if role.begins_with("g_grass_trainer_"):
		var i:=role.trim_prefix("g_grass_trainer_").to_int()
		var key:="g_grass_win_%d"%i
		if f.get(key,false):return deny(g,"我会照看来电汪，让羊群安静通过！")
		g._start_battle({"name":"道馆训练家 "+TRAINERS[i],"battle":{"team":TEAMS[i],"prize":1536 if i==1 else 1632}},func(result):
			if result=="a":
				f[key]=true
				g.world.refresh_story_actors(f)
				g._persist()
			elif result=="b" and g._party_fainted():
				reset(f)
				g._blackout()
		)
		return true
	return false

## Sword/Shield TM10 compatibility by national dex number (PokéAPI version group 20).
const MAGICAL_LEAF_USERS := [1,2,3,35,36,103,122,151,173,176,182,251,252,253,254,280,281,282,315,407,420,421,459,460,468,470,475,548,549,640,700,708,709,743,753,754,761,762,763,764,810,811,812,829,830,856,857,858,869,876,893,898]

static func use_item(g,name:String)->bool:
	if name not in [TM,UNIFORM] or g._bag_count(name)<=0:return false
	if name==UNIFORM:
		var f:Dictionary=g._flags()
		var wear:=not bool(f.get("g_grass_uniform_worn",false))
		f.g_grass_uniform_worn=wear
		g.world.taken=f
		g.world._sync_player()
		g._persist()
		g._show_toast("小悠换上了草之套装。" if wear else "小悠换回了原来的衣服。")
		return true
	var slots:Array=[]
	var names:Array=[]
	for i in g.save_data.party.size():
		var mon:Dictionary=g.save_data.party[i]
		var species:=int(mon.get("species_id",0))
		if species in MAGICAL_LEAF_USERS or (species==678 and str(mon.get("sex",""))=="female"):
			slots.append(i)
			names.append(str(mon.name))
	if slots.is_empty():g._dialog(["队伍中没有可以学习魔法叶的宝可梦。"])
	else:g._pick("让谁学习魔法叶？",names,func(i):g._tm_teach_one(345,int(slots[i]),"魔法叶",true))
	return true
