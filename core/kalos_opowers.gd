extends RefCounted
## Local X/Y PSS O-Powers. Energy and proficiency are saved; current effects end on reloading.
const NAMES:={"hp":"HP 回复力","capture":"捕获力","atk":"攻击力","def":"防御力","spa":"特攻力","spd":"特防力","spe":"速度力","acc":"命中力","critical":"要害力","exp":"经验值力","money":"奖金力","friend":"亲密度力","encounter":"相遇力","stealth":"隐身力","pp":"PP 回复力","bargain":"打折力","hatch":"孵蛋力"}
const STATS:=["atk","def","spa","spd","spe","acc","critical"]
const GROUPS:=[["hp","pp","capture","exp","money","bargain"],STATS,["encounter","stealth","friend","hatch"]]
const GIFTS:={"kalos_zone_71":["atk","def"],"kalos_zone_18":["spa"],"kalos_zone_52":["spd"],"kalos_zone_162":["money"],"kalos_zone_26":["spe"],"kalos_center_shalour":["critical"],"kalos_center_coumarine":["friend"],"kalos_center_laverre":["encounter"],"kalos_center_dendemille":["acc"],"kalos_center_anistar":["exp"],"kalos_zone_42":["stealth"],"kalos_center_snowbelle":["pp"],"kalos_hotel":["bargain"],"kalos_zone_125":["hatch"]}
const RATES:={"exp":[1.2,1.5,2.0],"capture":[1.5,2.0,2.5],"money":[1.5,2.0,3.0],"bargain":[.9,.75,.5],"encounter":[1.5,2.0,3.0],"stealth":[2.0/3,.5,1.0/3],"hatch":[1.25,1.5,2.0]}
static var time:Callable=func():return int(Time.get_unix_time_from_system())
static var ticks:Callable=func():return Time.get_ticks_msec()

static func known(f:Dictionary,key:String)->bool:
	if key in ["hp","capture"]:return bool(f.get("k_starter",0))
	return f.get("k_o_got_"+key,false)

static func roster(map:Dictionary,flags:Dictionary,rows:Array)->Array:
	var gifts:Array=GIFTS.get(str(map.id),[])
	if gifts.is_empty() or not flags.get("k_starter",0) or gifts.all(func(k):return known(flags,k)):return rows
	if "hatch" in gifts:
		if not flags.get("k_o_stylish",false) or not NAMES.keys().all(func(k):return k=="hatch" or known(flags,k)):return rows
	var taken:Array=rows.map(func(r):return r.at)
	for slot in ["guest5","guest4","guest3","side12"]:
		var at:Array=map.kalos_anchors.get(slot,[])
		if at.size()==2 and at not in taken:
			return rows+[{"at":at,"name":"欧斯先生","kalos_actor":"欧斯先生","facing":"down","o_gifts":gifts}]
	return rows

static func talk(g,row:Dictionary)->bool:
	if not row.has("o_gifts"):return false
	var gifts:Array=row.o_gifts
	for key in gifts:g._flags()["k_o_got_"+key]=true
	g.world.refresh_story_actors(g._flags())
	g._persist()
	g._dialog(["我来送你新的Ｏ力量！","学会了%s。打开 START → 工具 → Ｏ力量，就能为自己发动。"% "、".join(gifts.map(func(k):return NAMES[k]))],"欧斯先生")
	return true

static func cost(key:String,level:int)->int:
	if key in STATS:return [3,5,8][level-1]
	return (4 if key in ["capture","money","exp"] else 2)+level-1

static func grade(f:Dictionary,key:String)->int:
	var use_counts:Array=f.get("k_o_practice",{}).get(key,[0,0])
	return 3 if int(use_counts[1])>=30 else 2 if int(use_counts[0])>=15 else 1

static func recharge(save:Dictionary)->Dictionary:
	var now:=int(time.call())
	var battery:Dictionary=save.get_or_add("kalos_o_energy",{"units":10,"updated":now,"date":"","steps":0})
	var day:=Time.get_date_string_from_system()
	var interval:int=60 if int(battery.steps)>4000 else 120 if int(battery.steps)>3000 else 180 if int(battery.steps)>2000 else 240
	if battery.date!=day:
		battery.date=day
		battery.steps=0
		interval=240
	var passed:=maxi(0,now-int(battery.updated))
	if battery.units>=10 or int(battery.updated)>now:battery.updated=now
	elif passed>=interval:
		battery.units=mini(10,int(battery.units)+passed/interval)
		battery.updated=now if int(battery.units)==10 else now-passed%interval
	return battery

static func runtime(g)->Dictionary:
	if not g.has_meta("kalos_o_runtime"):g.set_meta("kalos_o_runtime",{})
	return g.get_meta("kalos_o_runtime")

static func rank(g,key:String)->int:
	var powers:=runtime(g)
	var row:Array=powers.get(key,[])
	if row.is_empty():return 0
	if int(row[1])>0 and int(ticks.call())>=int(row[1]):
		powers.erase(key)
		return 0
	return int(row[0])

static func factor(g,key:String)->float:
	var level:=rank(g,key)
	return float(RATES[key][level-1]) if level and RATES.has(key) else 1.0

static func details(key:String,lv:int)->String:
	if key in STATS:return "下一场战斗为首发提升 %d 级%s。"%[lv,"要害率" if key=="critical" else NAMES[key].trim_suffix("力")]
	if key=="hp":return "立即为首发恢复 %d HP。"%[20,50,200][lv-1]
	if key=="pp":return "立即为首发所有招式%s。"%("回满 PP" if lv==3 else "各恢复 %d PP"%[5,10][lv-1])
	if key=="friend":return "三分钟内，每次增长亲密度时额外增加 %d 点。"%lv
	var effect:Dictionary={"exp":"获得经验","capture":"捕获率","money":"对战奖金","bargain":"商店售价","encounter":"野生遭遇率","stealth":"野生遭遇率","hatch":"孵蛋速度"}
	return "三分钟内，%s变为 %.2f 倍。"%[effect[key],RATES[key][lv-1]]

static func use_power(g,key:String,lv:int)->String:
	if not NAMES.has(key) or not known(g._flags(),key) or lv<1 or lv>grade(g._flags(),key):return "这个等级尚未解锁。"
	var battery:=recharge(g.save_data)
	var required:=cost(key,lv)
	if int(battery.units)<required:return "能量不足，还需要 %d 格。"%(required-int(battery.units))
	var lead:Dictionary={}
	for m in g.save_data.party:
		if m is Dictionary and not m.is_empty():lead=m;break
	if key in ["hp","pp"] and lead.is_empty():return "队伍中没有宝可梦。"
	if key=="hp":
		if int(lead.hp)<=0 or int(lead.hp)>=int(lead.max_hp):return "目前的首发无法接受 HP 回复。"
		lead.hp=mini(int(lead.max_hp),int(lead.hp)+int([20,50,200][lv-1]))
		lead.hp_text="%d/%d"%[int(lead.hp),int(lead.max_hp)]
	elif key=="pp":
		var changed:=false
		for i in lead.moves.size():
			var maximum:=int(g.get_node("/root/Data").move_of(int(lead.moves[i])).get("pp",1))
			var value:=mini(maximum,int(lead.pp[i])+int([5,10,999][lv-1]))
			if int(lead.pp[i])<value:lead.pp[i]=value;changed=true
		if not changed:return "首发的招式 PP 已满。"
	else:
		var powers:=runtime(g)
		if key=="stealth":powers.erase("encounter")
		if key=="encounter":powers.erase("stealth")
		powers[key]=[lv,-1 if key in STATS else int(ticks.call())+180000]
	battery.units=int(battery.units)-required
	var counts:Array=g._flags().get_or_add("k_o_practice",{}).get_or_add(key,[0,0])
	if lv<=2:counts[lv-1]=int(counts[lv-1])+1
	g._persist()
	var new_level:=grade(g._flags(),key)
	return "%s Lv.%d 发动！%s%s"%[NAMES[key],lv,details(key,lv)," 已解锁 Lv.%d。"%new_level if new_level>lv and ((lv==1 and int(counts[0])==15) or (lv==2 and int(counts[1])==30)) else ""]

static func menu(g)->void:
	var battery:=recharge(g.save_data)
	g._pick("Ｏ力量　能量 %d / 10"%int(battery.units),["恢复与收获","对战能力","野外冒险"],func(i):group(g,GROUPS[i]))

static func group(g,keys:Array)->void:
	var available:=keys.filter(func(k):return known(g._flags(),k))
	if available.is_empty():g._dialog(["还未获得这类Ｏ力量。留意各地旅馆和宝可梦中心的欧斯先生。"]);return
	g._pick("选择Ｏ力量",available.map(func(k):return NAMES[k]+("　生效中" if rank(g,k)>0 else "")),func(i):choose(g,available[i]),func():menu(g))

static func choose(g,key:String)->void:
	var levels:=range(1,grade(g._flags(),key)+1)
	g._pick("%s　能量 %d / 10"%[NAMES[key],int(recharge(g.save_data).units)],levels.map(func(n):return "Lv.%d　消耗 %d 格　%s"%[n,cost(key,n),details(key,n)]),func(i):
		g._dialog([use_power(g,key,i+1)],NAMES[key]),func():menu(g))

static func walk(g)->void:
	if not g._flags().get("k_starter",0):return
	var battery:=recharge(g.save_data)
	battery.steps=int(battery.steps)+1
	if int(battery.steps)%128==0 and g.rng.randi_range(0,1)==1:
		var friend_rank:=rank(g,"friend")
		for m in g.save_data.party:
			if m is Dictionary and not m.is_empty():m.friendship=mini(255,int(m.get("friendship",70))+1+friend_rank)

static func enter_battle(g,battle)->void:
	var powers:=runtime(g)
	var began:=int(ticks.call())
	battle.set_meta("kalos_o_began",began)
	for key in powers.keys():
		var lv:=rank(g,key)
		if not lv:continue
		if key in STATS:
			battle.kalos_o_stages.append([key,lv])
			powers.erase(key)
	battle.kalos_o_capture=factor(g,"capture")

static func leave_battle(g,battle)->void:
	if not battle.has_meta("kalos_o_began"):return
	var elapsed:=maxi(0,int(ticks.call())-int(battle.get_meta("kalos_o_began")))
	for row in runtime(g).values():
		if int(row[1])>0:row[1]=int(row[1])+elapsed

static func hatch_steps(g,state:Dictionary,warmth:int)->int:
	var amount:=float(state.get("o_egg_credit",0.0))+float(warmth)*factor(g,"hatch")
	state.o_egg_credit=amount-floor(amount)
	return int(amount)
