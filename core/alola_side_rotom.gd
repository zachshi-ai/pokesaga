extends RefCounted
const POWERS := {"捕捉碰碰":"catch","经验碰碰":"exp","零花钱碰碰":"money","孵蛋碰碰":"hatch","相遇碰碰":"encounter","亲密碰碰":"friendship","优惠碰碰":"bargain","隐身碰碰":"stealth","回复碰碰":"heal","招式碰碰":"pp"}
static func lottery(g) -> void:
	var now:=int(Time.get_unix_time_from_system())
	var record: Dictionary=g.save_data.get_or_add("alola_roto",{})
	if now<int(record.get("next",0)):
		g._dialog(["我的眼睛还没亮起来洛托！约 %d 分钟后再来。"%ceili((int(record.next)-now)/60.0)],"洛托姆")
		return
	var names:=POWERS.keys()
	var name: String=names[g.rng.randi_range(0,names.size()-1)]
	var n: int=g.rng.randi_range(1,3)
	record.next=now+g.rng.randi_range(600,1200)
	g._give_item(name,n,"key")
	g._persist()
	g._dialog(["中了%s ×%d！打开背包即可使用洛托。"%[name,n]],"洛托姆")

static func use(g,label: String) -> bool:
	if not str(g._flags().get("a_version","")).begins_with("ultra"):return false
	if label=="洛托姆图鉴":
		g._pick("洛托姆图鉴",["触碰洛托姆的眼睛","查看有效的力量","收起"],func(i):
			if i==0:lottery(g)
			elif i==1:
				var info: Array=[]
				var now:=int(Time.get_unix_time_from_system())
				for power in POWERS:
					var seconds:=int(g.save_data.get("alola_roto",{}).get(POWERS[power],0))-now
					if seconds>0:info.append("%s：还可用 %d 分钟"%( [power,ceili(seconds/60.0)] ))
				g._dialog(["目前没有发动的力量。"] if info.is_empty() else info,"洛托姆"))
		return true
	if not POWERS.has(label) or g._bag_count(label)==0:return false
	var key: String=POWERS[label]
	g._pick("使用%s？"%label,["使用","取消"],func(i):
		if i!=0:return
		var record: Dictionary=g.save_data.get_or_add("alola_roto",{})
		var now:=int(Time.get_unix_time_from_system())
		if int(record.get(key,0))>now:
			g._dialog(["这项洛托姆力量仍然有效。"]);return
		if key in ["heal","pp"]:
			for mon in g.save_data.party:
				if not mon is Dictionary or mon.is_empty():continue
				if key=="pp":mon.pp=mon.moves.map(func(mid):return int(g.get_node("/root/Data").move_of(int(mid)).pp))
				elif int(mon.hp)>0:mon.hp=mon.max_hp;mon.hp_text="%d/%d"%[mon.hp,mon.max_hp]
		else:
			record[key]=now+(1200 if key in ["friendship","stealth"] else 600)
			if key=="stealth":record.erase("encounter")
			if key=="encounter":record.erase("stealth")
		g._consume_item(label);g._persist();g._show_toast(label+"发挥了作用！"))
	return true
