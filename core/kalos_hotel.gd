extends RefCounted

const PAY := [[2000,1000,650],[10000,1500,750],[20000,3000,900],[50000,5000,950]]
const ORDERS := [["烤","蒸","煮","煎"],["香草","柠檬","咖喱","蜂蜜"],["鲤鱼王形","皮卡丘形","宝贝球形","树果形"],["蛋卷","布丁","薄饼","焗饭"]]
const JOBS := ["客房送餐","整理床铺","寻找失物"]
const FLOORS := [136,137,138]
# The first three points are on the footboards in the north-west, north-east
# and south-west rooms. The last three are accessible floor tiles for lost property.
const TARGET := [[10,15],[36,15],[10,31],[21,7],[33,29],[9,22]]

static func today() -> String:return Time.get_date_string_from_system()

static func desk(g) -> void:
	var job: Dictionary=g.save_data.get("kalos_hotel_shift",{})
	if not job.is_empty():
		if job.day==today():
			if int(job.job)==0:show_order(g,job)
			else:g._dialog(["你的工作在 %d 层。%s"%[int(job.floor)+2,"走到每张客床旁按 A 整理。" if int(job.job)==1 else "沿走廊轻步寻找，站在闪光点旁按 A 拾取。"]],"酒店经理")
			return
		g.save_data.erase("kalos_hotel_shift")
	g._pick("酒店前台",JOBS+["住宿　¥100000","离开"],func(i):
		if i==3:stay(g)
		elif i<3:start(g,i))

static func start(g,kind: int) -> void:
	var done: Dictionary=g.save_data.get_or_add("kalos_hotel_days",{})
	if done.get(str(kind),"")==today():g._dialog(["今天这项工作已经做完了。"]);return
	var perfect:=int(g.save_data.get("kalos_hotel_perfect",0))
	var level:=3 if perfect>=30 else 2 if perfect>=15 else 1 if perfect>=5 else 0
	var shift:={"job":kind,"day":today(),"level":level,"done":[],"round":0,"errors":0,"floor":g.rng.randi_range(0,2),
		"started":int(Time.get_unix_time_from_system()),"scuffed":[]}
	var order: Array=[]
	for group in ORDERS:order.append(g.rng.randi_range(0,group.size()-1))
	shift.order=order
	g.save_data.kalos_hotel_shift=shift
	mark_stations(g,shift)
	g._persist()
	if kind==0:show_order(g,shift)
	else:g._dialog(["请前往酒店 %d 层，%s。"%[int(shift.floor)+2,"在客房依次整理床铺" if kind==1 else "轻步寻找客人丢下的东西"]],"酒店经理")

static func show_order(g,shift: Dictionary) -> void:
	var words: Array=[]
	for i in ORDERS.size():words.append(ORDERS[i][int(shift.order[i])])
	var dialog=g._dialog(["请给我一份「%s」。麻烦把这份点单告诉厨师。"%("".join(words))],"客人")
	dialog.closed.connect(func():order_word(g,shift,0,true),CONNECT_ONE_SHOT)

static func order_word(g,shift: Dictionary,step: int,ok: bool) -> void:
	g._pick("向厨师复述 · %d / 4"%(step+1),ORDERS[step],func(i):
		var matches: bool=ok and i==int(shift.order[step])
		if step<3:order_word(g,shift,step+1,matches);return
		if not matches:shift.errors+=1
		shift.round+=1
		if int(shift.round)>int(shift.level):finish(g,shift);return
		for col in ORDERS.size():shift.order[col]=g.rng.randi_range(0,3)
		g._persist()
		show_order(g,shift))

static func objects(map: Dictionary) -> Array:
	if int(map.kalos_zone) not in FLOORS:return []
	var result: Array=[]
	for i in TARGET.size():
		result.append({"kind":"hotel_work","at":TARGET[i],"station":i})
	return result

static func mark_stations(g,shift: Dictionary) -> void:
	var flags: Dictionary=g._flags()
	flags.erase("k_hotel_targets")
	if not shift.is_empty() and int(shift.job)>0:
		var start:=0 if int(shift.job)==1 else 3
		var count:=mini(3,1+int(shift.level))
		var pending: Array=[]
		for i in range(start,start+count):
			if i not in shift.done:pending.append(i)
		flags.k_hotel_targets={"zone":FLOORS[int(shift.floor)],"day":shift.day,"pending":pending}
	g.world.taken=flags
	g.world._draw_objects()

static func visible(map: Dictionary,obj: Dictionary,flags: Dictionary) -> bool:
	var targets: Dictionary=flags.get("k_hotel_targets",{})
	return targets.get("day","")==today() and int(map.get("kalos_zone",-1))==int(targets.get("zone",-2)) and int(obj.station) in targets.get("pending",[])

static func station(g,obj: Dictionary) -> bool:
	if obj.get("kind","")!="hotel_work":return false
	var shift: Dictionary=g.save_data.get("kalos_hotel_shift",{})
	if shift.is_empty() or shift.day!=today() or int(shift.job)==0 or FLOORS[int(shift.floor)]!=int(g.world.map_data.kalos_zone):return false
	var i:=int(obj.station)
	var count:=mini(3,1+int(shift.level))
	var points: Array=[0,1,2] if int(shift.job)==1 else [3,4,5]
	points=points.slice(0,count)
	if i not in points or shift.done.has(i):return false
	shift.done.append(i)
	mark_stations(g,shift)
	if int(shift.job)==2 and i in shift.scuffed:shift.errors+=1
	if shift.done.size()==count:
		if int(shift.job)==1 and int(Time.get_unix_time_from_system())-int(shift.started)>150:shift.errors+=1
		finish(g,shift)
	else:
		g._persist()
		g._show_toast("%s　%d / %d"%["床铺已整理" if int(shift.job)==1 else "找到失物",shift.done.size(),count])
	return true

static func step(g) -> void:
	var shift: Dictionary=g.save_data.get("kalos_hotel_shift",{})
	if shift.is_empty() or int(shift.job)!=2 or not (g.run_held or g.world.bike):return
	if FLOORS[int(shift.floor)]!=int(g.world.map_data.get("kalos_zone",-1)):return
	for i in range(3,6):
		var coords: Array=TARGET[i]
		if g.world.player_pos==Vector2i(int(coords[0]),int(coords[1])) and i not in shift.scuffed:
			shift.scuffed.append(i)
			g._show_toast("不小心踩到了失物。")

static func finish(g,shift: Dictionary) -> void:
	var grade:=mini(2,int(shift.errors))
	if int(shift.job)==0 and int(shift.level)==0 and grade>0:grade=2
	var pay:=int(PAY[int(shift.level)][grade])
	g.save_data.get_or_add("kalos_hotel_days",{})[str(int(shift.job))]=today()
	if grade==0:
		g.save_data.kalos_hotel_perfect=int(g.save_data.get("kalos_hotel_perfect",0))+1
		g.save_data.kalos_style=mini(255,int(g.save_data.get("kalos_style",0))+1)
	g.save_data.money+=pay
	g.save_data.erase("kalos_hotel_shift")
	mark_stations(g,{})
	g._persist()
	g._dialog(["%s完成了。今天的工资是 %d 元。"%[JOBS[int(shift.job)],pay]],"酒店经理")

static func stay(g) -> void:
	if g.save_data.get("kalos_hotel_stay","")==today():g._dialog(["今天已经入住过。"]);return
	if int(g.save_data.money)<100000:g._dialog(["一晚的房费是十万元。"]);return
	g._pick("以 ¥100000 入住套房？",["入住","取消"],func(i):
		if i!=0:return
		g.save_data.money-=100000
		g._heal_party()
		for mon in g.save_data.party:
			if not mon.is_empty():
				mon.affection=mini(255,int(mon.get("affection",0))+30)
				mon.fullness=255
		g.save_data.kalos_hotel_stay=today()
		g._persist()
		g._dialog(["一觉醒来，伙伴们都休息好了。"]))
