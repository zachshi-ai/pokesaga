extends RefCounted

const Party := preload("res://core/party.gd")
const Growth := preload("res://core/growth.gd")
const NAMES := {"abeens":"悠悠度假地","aplenny":"速速度假地","aphun":"怦怦度假地","evelup":"欢欢度假地","avue":"暖暖度假地"}
const COST := {"abeens":[[0,0],[15,30],[30,90]],"aplenny":[[15,15],[30,60],[45,135]],"aphun":[[30,30],[45,90],[60,150]],"evelup":[[45,45],[60,120],[75,225]],"avue":[[60,60],[75,150],[90,240]]}
const STAT := {"经验":"exp","体力":"hp","攻击":"atk","防御":"def","特攻":"spa","特防":"spd","速度":"spe"}
const SHARDS := ["红色碎片","蓝色碎片","绿色碎片","黄色碎片"]
const STONES := ["火之石","水之石","雷之石","叶之石","光之石","暗之石","觉醒之石","月之石","日之石","冰之石"]
const TREASURE := ["星星沙子","星星碎片","大珍珠","金珠","巨大金珠","银色王冠"]
const BEANS := ["普通豆","花纹豆","彩虹豆"]

static var guide: Dictionary
static func data() -> Dictionary:
	if guide.is_empty():guide=JSON.parse_string(FileAccess.get_file_as_string("res://content/alola_pelago.json"))
	return guide

static func state(save: Dictionary, now: int) -> Dictionary:
	var s: Dictionary=save.get_or_add("alola_pelago",{"last":now,"shaken":now-3600,"ranks":{"abeens":1},"beans":[0,0,0],"jobs":{},"boost":{}})
	advance(s,now)
	return s

static func advance(s: Dictionary, now: int) -> void:
	var elapsed:=maxi(0,now-int(s.last))
	if elapsed==0:return
	for isle in NAMES:
		var bonus:=mini(elapsed,int(s.boost.get(isle,0)))
		s.boost[isle]=maxi(0,int(s.boost.get(isle,0))-elapsed)
		var feed:Array=s.get_or_add("crates",{}).get_or_add(isle,[])
		var used:=elapsed
		while used>0 and not feed.is_empty():
			var eaten:=mini(used,int(feed[0]))
			used-=eaten;feed[0]=int(feed[0])-eaten
			if int(feed[0])==0:feed.pop_front()
		for job in s.jobs.get(isle,[]):
			job.work=mini(int(job.total),int(job.work)+elapsed+bonus)
	s.last=now

static func current(g) -> Dictionary:
	return state(g.save_data,int(Time.get_unix_time_from_system()))

static func open(g) -> void:
	if not g._flags().get("a_ride_charizard",false):
		g._dialog(["通过卡奇的考验并登记喷火龙后，就可以飞往宝可度假地。"])
		return
	var s:=current(g)
	var here:=str(g.world.map_data.id)
	var choices:Array=NAMES.values()
	var on_isle:=here.begins_with("alola_pelago_")
	if on_isle:choices.append("返回出发地点")
	g._pick("宝可度假地",choices,func(i):
		if i==NAMES.size():
			var back:Dictionary=s.get("return_to",{})
			if back.is_empty():
				var town:Dictionary=g.get_node("/root/Data").load_map("alola","alola_heahea")
				back={"region":"alola","map":town.id,"at":town.spawn,"alola_native":true}
			g._do_warp(back)
			g._persist()
			return
		if not on_isle:s.return_to={"region":"alola","map":here,"at":[g.world.player_pos.x,g.world.player_pos.y],"alola_native":true}
		var map:Dictionary=g.get_node("/root/Data").load_map("alola","alola_pelago_"+str(NAMES.keys()[i]))
		g._do_warp({"region":"alola","map":map.id,"at":map.spawn,"alola_native":true})
		g._persist())

static func residents(g,s:Dictionary) -> int:
	var total:=0
	for box in g.save_data.get("boxes",[]):
		if box is Dictionary:total+=Party.occupied(box.get("mons",[]))
	for isle in ["evelup","avue"]:
		for job in s.jobs.get(isle,[]):
			if job.has("mon"):total+=1
	return total

static func develop(g,isle:String) -> void:
	var s:=current(g)
	var rank:=int(s.ranks.get(isle,0))
	if rank>=3:return
	var price:Array=COST[isle][rank]
	var count:=residents(g,s)
	g._pick("%s升级到 Lv.%d　需要 %d 只箱中伙伴和 %d 颗普通豆"%[NAMES[isle],rank+1,price[0],price[1]],["开发","返回"],func(i):
		if i!=0:return
		if count<int(price[0]) or int(s.beans[0])<int(price[1]):
			g._dialog(["目前有 %d 只箱中伙伴、%d 颗普通豆。摇悠悠岛的豆树可以收集豆子。"%[count,s.beans[0]]],"莫恩")
			return
		s.beans[0]=int(s.beans[0])-int(price[1]);s.ranks[isle]=rank+1
		g._persist();g._show_toast("%s开发完成！"%NAMES[isle]))

static func shake(g) -> void:
	var s:=current(g)
	var rank:=int(s.ranks.abeens)
	var hours:=mini(24,maxi(0,int(s.last)-int(s.shaken))/3600)
	if hours==0:
		g._dialog(["新的宝可豆还在生长，约 %d 分钟后再来摇树。" % maxi(1,60-(int(s.last)-int(s.shaken))/60)],"莫恩")
		return
	var plain:=hours*(2+rank)
	var patterned:int=g.rng.randi_range(0,mini(4,hours+rank))
	var rainbow:=1 if g.rng.randf()<minf(.6,hours*.04*rank) else 0
	s.beans[0]=int(s.beans[0])+plain;s.beans[1]=int(s.beans[1])+patterned;s.beans[2]=int(s.beans[2])+rainbow
	s.shaken=int(s.last)-(int(s.last)-int(s.shaken))%3600
	g._persist();g._dialog(["收到了普通豆 ×%d、花纹豆 ×%d、彩虹豆 ×%d。"%[plain,patterned,rainbow]],"豆树")

static func visitors(g,s:Dictionary) -> void:
	var now:=int(s.last)
	var guest:Dictionary=s.get("visitor",{})
	if guest.is_empty() or now-int(guest.arrival)>172800:
		if now<int(s.get("next_visitor",0)):
			g._dialog(["岛上暂时没有新面孔。豆箱里的豆子会吸引附近的宝可梦。"],"莫恩");return
		var flags:Dictionary=g._flags()
		var stage:=4 if flags.get("a_credits",false) else 3 if flags.get("a_flute1",false) else 2 if flags.get("a_nihilego",false) else 1 if flags.get("a_sail",false) else 0
		var group: String="us" if str(flags.a_version).begins_with("ultra") else "sm"
		var pool:Array=data().visitors[group]
		var weights:=PackedFloat32Array()
		for row in pool:weights.append(float(row[1][stage]))
		var sid:=int(pool[g.rng.rand_weighted(weights)][0])
		var level:int=int([1,11,21,37,49][stage])+g.rng.randi_range(0,6)
		var mon:=Party.make(sid,level,preload("res://core/alola_field.gd").moves_for(sid,level,flags))
		Party.init_alola_ivs(mon,g.appearance_rng)
		guest={"arrival":now,"mon":mon,"stays":g.rng.randf()<(.8 if int(s.boost.get("abeens",0))>0 else .5)}
		s.visitor=guest
		preload("res://core/dex_variants.gd").record(g.save_data,mon,false);g._persist()
	if now-int(guest.arrival)<86400:
		g._dialog(["%s正在打量这座岛。明天来看看它愿不愿留下吧。"%guest.mon.name],"莫恩");return
	if not guest.stays:
		s.erase("visitor");s.next_visitor=now+14400;g._persist();g._dialog(["来访的宝可梦回到了野外。"],"莫恩");return
	g._pick("%s想留在你身边。"%guest.mon.name,["欢迎，去电脑箱里吧","以后再来"],func(i):
		if i!=0:return
		if not Party.store_in_boxes(g.save_data.get_or_add("boxes",[]),guest.mon):
			g._dialog(["箱子已经满了。"]);return
		preload("res://core/dex_variants.gd").record(g.save_data,guest.mon,true)
		s.erase("visitor");s.next_visitor=now+14400;g._persist();g._dialog(["%s成为了伙伴。"%guest.mon.name],"莫恩"))

static func bean_box(g,isle:String,exchange:bool) -> void:
	var s:=current(g);var options:Array=[]
	for i in range(1 if exchange else 0,3):
		if int(s.beans[i])>0:options.append(i)
	if options.is_empty():g._dialog(["手边没有这种宝可豆。到悠悠度假地摇一摇豆树吧。"]);return
	g._pick("兑换普通豆" if exchange else "投喂一颗宝可豆",options.map(func(n):return "%s ×%d"%[BEANS[n],s.beans[n]]),func(i):
		var n:int=options[i]
		if exchange:s.beans[0]=int(s.beans[0])+[1,3,7][n]
		else:
			var allowance:int=[20,30,50][int(s.ranks[isle])-1]
			var crate:Array=s.get_or_add("crates",{}).get_or_add(isle,[])
			var duration:int=[1200,3600,7200][n]
			if crate.size()>=allowance:g._dialog(["豆箱还没有放下这颗豆的空间。"]);return
			crate.append(duration)
			s.boost[isle]=int(s.boost.get(isle,0))+duration
		s.beans[n]=int(s.beans[n])-1;g._persist()
		g._show_toast("兑换完成。" if exchange else "豆子的效果还将持续 %d 分钟。"%(int(s.boost[isle])/60)))

static func add_job(s:Dictionary,isle:String,title:String,seconds:int,info:Dictionary) -> void:
	s.jobs.get_or_add(isle,[]).append({"name":title,"work":0,"total":seconds}.merged(info))

static func plant(g,s:Dictionary) -> void:
	var berries:Array=g.bag_items.filter(func(item):return item.get("category","")=="berry" and int(item.get("count",0))>0)
	if berries.is_empty():g._dialog(["背包里没有可以种植的树果。"]);return
	choose(g,"种下哪种树果？",berries.map(func(b):return "%s ×%d"%[b.name,b.count]),func(index):
		var item:Dictionary=berries[index];var key:String=item.get("berry","")
		var crop:Array=data().berries.get(key,[24,2,6])
		var hours:=int(crop[0])
		var yield_count:=int(crop[1])+roundi((int(crop[2])-int(crop[1]))*(int(s.ranks.aplenny)-1)/2.0)
		if not g.bag_items.has(item) or int(item.count)<=0:return
		g._consume_item(item.name)
		add_job(s,"aplenny",item.name,hours*3600,{"berry":key,"yield":yield_count})
		g._persist();g._show_toast("种下了%s。"%item.name))

static func expedition(g,s:Dictionary) -> void:
	var rank:=int(s.ranks.aphun)
	var ways:=["寻找碎片"]
	if rank>=2:ways.append_array(["寻找闪耀的石头","寻找各种道具"])
	if rank==3:ways.append("寻找珍贵的宝物")
	g._pick("派箱中的伙伴去哪里探险？",ways,func(i):
		var pool:Array=SHARDS.duplicate()
		if i==1:pool=STONES.duplicate()
		elif i==2:
			pool.append_array(STONES)
			if rank==3:pool.append_array(TREASURE)
		elif i==3:pool=TREASURE.duplicate()
		var rewards:Array=[]
		for j in range(rank+2):rewards.append(pool[g.rng.randi_range(0,pool.size()-1)])
		add_job(s,"aphun",ways[i],24*3600,{"rewards":rewards});g._persist();g._show_toast("伙伴们出发了。"))

static func choose(g,title:String,labels:Array,cb:Callable,page:=0) -> void:
	var start:=page*6
	var shown:=labels.slice(start,mini(start+6,labels.size()))
	var count:=shown.size()
	if start+count<labels.size():shown.append("下一页")
	if page>0:shown.append("上一页")
	g._pick(title,shown,func(i):
		if i<count:cb.call(i+start)
		elif shown[i]=="下一页":choose(g,title,labels,cb,page+1)
		else:choose(g,title,labels,cb,page-1))

static func enroll(g,s:Dictionary,isle:String,stat:String="",sessions:=1) -> void:
	var choices:Array=[];var labels:Array=[]
	for bi in g.save_data.get("boxes",[]).size():
		var box:Dictionary=g.save_data.boxes[bi]
		for i in box.get("mons",[]).size():
			var m=box.mons[i]
			if not m is Dictionary or m.is_empty() or m.get("is_egg",false):continue
			choices.append([bi,i]);labels.append("%s · %s Lv.%d"%[box.get("name","箱子"),m.name,m.level])
	if choices.is_empty():g._dialog(["先把一只伙伴寄放到电脑箱子里。"]);return
	choose(g,"选择箱中的伙伴",labels,func(i):
		var at:Array=choices[i];var box:Dictionary=g.save_data.boxes[at[0]];var mon:Dictionary=box.mons[at[1]]
		if mon.is_empty():return
		var info:={"mon":mon,"slot":at,"stat":stat,"rank":int(s.ranks[isle])}
		add_job(s,isle,mon.name,1800*sessions if isle=="evelup" else 48*3600,info)
		box.mons[at[1]]={};g._persist();g._show_toast("%s开始%s了。"%[mon.name,"锻炼" if isle=="evelup" else "泡温泉"]))

static func start(g,s:Dictionary,isle:String) -> void:
	var jobs:Array=s.jobs.get(isle,[])
	if jobs.size()>=(1 if isle=="aphun" else int(s.ranks[isle])*6):g._dialog(["位置已满，先领取成果或召回伙伴。"]);return
	match isle:
		"aplenny":plant(g,s)
		"aphun":expedition(g,s)
		"evelup":
			g._pick("选择训练饮料",STAT.keys(),func(i):
				var stat:String=STAT.values()[i]
				g._pick("每次训练需要 30 分钟",["1 次","4 次","12 次","63 次","99 次"],func(j):enroll(g,s,isle,stat,[1,4,12,63,99][j])))
		"avue":
			if not g._flags().has("as_egg_steps"):enroll(g,s,isle);return
			g._pick("让谁进入温泉？",["箱中的伙伴","寄放屋的伊布蛋"],func(i):
				if i==0:enroll(g,s,isle);return
				var steps:=35*256-int(g._flags().as_egg_steps)
				add_job(s,isle,"伊布的蛋",maxi(1,ceili(steps*60.0/16)),{"egg":true,"steps":steps})
				g._flags().erase("as_egg_steps");g._persist();g._show_toast("把蛋轻轻放进了温泉。"))

static func return_mon(g,job:Dictionary) -> bool:
	var at:Array=job.slot;var boxes:Array=g.save_data.boxes
	if int(at[0])<boxes.size():
		var slots:Array=boxes[int(at[0])].mons
		if int(at[1])<slots.size() and (slots[int(at[1])]==null or slots[int(at[1])].is_empty()):
			slots[int(at[1])]=job.mon;return true
	return Party.store_in_boxes(boxes,job.mon)

static func claim(g,s:Dictionary,isle:String,job:Dictionary) -> void:
	var pending:int=int(job.total)-int(job.work)
	if pending>0 and isle in ["aplenny","aphun"]:
		g._dialog(["还需要 %d 分钟。"%(ceili(pending/60.0))]);return
	if job.has("mon"):
		if not return_mon(g,job):
			g._dialog(["所有电脑箱都满了，伙伴会在度假地等你。"]);return
		var mon:Dictionary=job.mon
		if isle=="evelup":
			var reps:=int(job.work)/1800
			if job.stat=="exp":
				var before:=int(mon.level)
				Growth.add_exp(mon,reps*int([100,250,500][int(job.rank)-1]))
				if before<int(mon.level):g._learn_new_moves(mon,before,int(mon.level))
			else:
				var effort:Dictionary=mon.get_or_add("effort",{});var total:=0
				for n in effort.values():total+=int(n)
				var current_ev:=int(effort.get(job.stat,0))
				effort[job.stat]=current_ev+maxi(0,mini(252-current_ev,mini(510-total,reps*int([1,2,4][int(job.rank)-1]))))
			Party.recalc(mon,true)
		else:
			var hours:=int(job.work)/3600
			mon.friendship=clampi(int(mon.get("friendship",70))+mini(24,hours)*4-maxi(0,hours-24)*4,0,255)
	elif job.has("egg"):
		if pending<=0:load("res://core/alola_side.gd").give_mon(g,133,1)
		else:g._flags().as_egg_steps=35*256-int(job.steps)+int(job.work)*16/60
	elif job.has("berry"):
		for i in int(job["yield"]):g._give_bag_item(job.name,"berry","",job.berry)
	elif job.has("rewards"):
		for item in job.rewards:g._give_bag_item(item,"other")
	s.jobs[isle].erase(job);g._persist()
	var result:="伙伴已经回到电脑箱。"
	if job.has("berry"):result="收获了%s ×%d。"%[job.name,job["yield"]]
	elif job.has("rewards"):result="伙伴带回了"+"、".join(job.rewards)+"。"
	elif job.has("egg"):result="孵出了伊布！" if pending<=0 else "你接回了温暖的蛋。"
	g._dialog([result],"莫恩")

static func office(g,isle:String) -> void:
	if not NAMES.has(isle):return
	var s:=current(g);var rank:=int(s.ranks.get(isle,0))
	if rank==0:develop(g,isle);return
	var names:Array=[];var actions:Array=[]
	if isle=="abeens":
		names.append_array(["摇豆树","来访的宝可梦","给豆箱投豆","兑换宝可豆"])
		actions.append_array([func():shake(g),func():visitors(g,s),func():bean_box(g,isle,false),func():bean_box(g,isle,true)])
	else:
		names.append({"aplenny":"种树果","aphun":"派伙伴寻宝","evelup":"安排训练","avue":"去泡温泉"}[isle]);actions.append(func():start(g,s,isle))
		for task in s.jobs.get(isle,[]):
			var job:Dictionary=task;var mins:=ceili((int(job.total)-int(job.work))/60.0)
			names.append("%s · %s"%[job.name,"可以领取" if mins==0 else "还需 %d 分钟"%mins])
			actions.append(func():claim(g,s,isle,job))
		names.append("给豆箱投豆");actions.append(func():bean_box(g,isle,false))
	if rank<3:names.append("开发岛屿");actions.append(func():develop(g,isle))
	names.append("飞往其他岛屿");actions.append(func():open(g))
	g._persist()
	choose(g,"%s Lv.%d · 普通豆 %d"%( [NAMES[isle],rank,s.beans[0]] ),names,func(i):actions[i].call())
