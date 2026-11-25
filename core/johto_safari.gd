extends RefCounted

const GATE := "hgss_safari_zone_entrance_interior"
const YARD := "hgss_safari_zone_entrance_exterior"
const PREFIX := "hgss_safari_zone_"
const FIRST := [1,8,2,6,4,7]
const NAMES := ["","草原","草丛","稀树草原","山峰","岩滩","湿地","森林","沼泽","泥泽","荒地","山地","沙漠"]
const SLOTS := ["西北","正北","东北","西南","正南 · 入园处","东南"]
const BAOBA := Vector2i(7,12)
const TERMINAL := Vector2i(9,6)
const WAIT := 3.0*3600.0

static func area(mid: String) -> int:
	if not mid.begins_with(PREFIX):return 0
	var suffix:=mid.trim_prefix(PREFIX)
	var id:=suffix.to_int()
	return id if suffix.is_valid_int() and id>=1 and id<=12 else 0

static func layout(flags: Dictionary) -> Array:
	var current: Array=flags.get("j_safari_layout",FIRST)
	if current.size()!=6:return FIRST.duplicate()
	var result: Array=[]
	var seen := {}
	for id in current:
		if int(id)<1 or int(id)>12 or seen.has(int(id)):return FIRST.duplicate()
		seen[int(id)]=true
		result.append(int(id))
	return result

static func id_for(id: int) -> String:
	return YARD if id==0 else PREFIX+"%02d"%id

static func field(data: Dictionary,flags: Dictionary) -> Dictionary:
	var mid: String=data.get("id","")
	var id:=area(mid)
	if id==0 and mid!=YARD:return data
	var slots:=layout(flags)
	if slots==FIRST and (mid==YARD or slots.has(id)):return data
	var index:=slots.find(id)
	if mid!=YARD and index<0:
		# A transfer-item visit to an unplaced template can always return to the entrance.
		slots[4]=id
		index=4
	var pos:=Vector2i(1,2) if mid==YARD else Vector2i(index%3,floori(index/3.0))
	var result:=data.duplicate()
	var warps: Array=[]
	for warp in data.warps:
		if not warp.get("edge",false):warps.append(warp)
	var dirs:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
	for side in 4:
		var dir: Vector2i=dirs[side]
		var next:=pos+dir
		var yard:=next==Vector2i(1,2)
		if not yard and not Rect2i(0,0,3,2).has_point(next):continue
		var other: int=0 if yard else int(slots[next.y*3+next.x])
		# Land files 658 and 659 have a seven-wide E/W opening. All other
		# native entrances span local cells 12..19; use the common width.
		var stop:=19 if dir.x and (id in [7,8] or other in [7,8]) else 20
		for n in range(12,stop):
			var p:=Vector2i(0 if dir.x<0 else 31 if dir.x>0 else n,0 if dir.y<0 else 31 if dir.y>0 else n)
			var q:=Vector2i(posmod(p.x+dir.x,32),posmod(p.y+dir.y,32))
			warps.append({"at":[p.x,p.y],"trigger":["up","right","down","left"][side],"edge":true,
				"to":{"region":"johto","map":id_for(other),"at":[q.x,q.y],"hgss":true}})
	result.warps=warps
	return result

static func open(flags: Dictionary) -> bool:
	return flags.get("j_lighthouse_cured",false)

static func first_meeting(g) -> bool:
	var f: Dictionary=g._flags()
	if f.get("j_baoba_contact",false) or open(f):return false
	f.j_baoba_contact=true
	g._persist()
	g._dialog(["我是巴奥巴，正在湛蓝市以西筹备狩猎地带。我们交换电话吧，开园时我会通知你。"],"巴奥巴")
	g.world.refresh_story_actors(f)
	return true

static func route_step(g) -> bool:
	var p: Vector2i=g.world.player_pos
	return g.world.map_data.id=="johto_route_39" and p.x==22 and p.y>=11 and p.y<=13 and first_meeting(g)

static func clock(g,delta:float) -> void:
	var flags: Dictionary=g.save_data.get("flags",{})
	if not flags.has("j_safari_wait"):return
	var left: float=maxf(0.0,float(flags.j_safari_wait)-delta)
	if left>0.0:
		flags.j_safari_wait=left
		return
	flags.erase("j_safari_wait")
	flags.j_safari_customizer=true
	g._show_toast("巴奥巴来电：区域配置机准备好了。到狩猎地带门口来吧！")
	g._persist()

static func submit(g,id:int) -> bool:
	for mon in g.save_data.party:
		if int(mon.get("species_id",0))==id and mon.get("johto_safari_caught",false):return true
	return false

static func interact(g) -> bool:
	var tile: Vector2i=g.world.player_pos+g.world._dir_vec()
	if g.world.map_data.id=="johto_route_39" and tile==Vector2i(19,12):return first_meeting(g)
	if g.world.map_data.id!=GATE:return false
	var f: Dictionary=g._flags()
	if tile==TERMINAL:
		if not f.get("j_safari_customizer",false):g._dialog(["区域配置机目前锁着。"],"区域配置机")
		else:edit(g)
		return true
	if tile!=BAOBA:return false
	if not open(f):g._dialog(["园区还在准备。听说浅葱灯塔的电龙病了。"],"巴奥巴")
	elif not f.get("j_safari_test1",false):
		g._pick("巴奥巴：要试试园长的考验吗？",["接受考验","以后再来"],func(i):
			if i==0:
				f.j_safari_test1=true;g._persist()
				g._dialog(["到山峰捕捉一只小拳石，带在队伍里给我看看。"],"巴奥巴"))
	elif f.get("j_safari_tests_done",false):g._dialog(["你已经通过两次考验。去配置机挑一组想探索的地形吧。"],"巴奥巴")
	elif f.get("j_safari_customizer",false):
		if submit(g,27):
			f.j_safari_tests_done=true;g._persist()
			g._dialog(["是你在园内捕捉的穿山鼠！你通过了第二次考验。"],"巴奥巴")
		else:g._dialog(["用区域配置机把沙漠放进园区，在里面捉一只穿山鼠，再带来给我看。"],"巴奥巴")
	elif f.has("j_safari_wait"):g._dialog(["我在准备区域配置机。等我给你打电话吧。"],"巴奥巴")
	elif submit(g,74):
		f.j_safari_wait=WAIT;g._persist()
		g._dialog(["这只小拳石确实来自园内。第一关通过！有新考验我会联系你。"],"巴奥巴")
	else:g._dialog(["请把你自己在狩猎地带捕捉的小拳石放进队伍。"],"巴奥巴")
	return true

static func edit(g) -> void:
	var current:=layout(g._flags())
	var labels: Array=[]
	for i in 6:labels.append("%s　%s"%[SLOTS[i],NAMES[int(current[i])]])
	g._pick("区域配置机 · 选择要更换的位置",labels,func(slot):
		var choices: Array=[]
		for id in range(1,13):
			var occupied:=current.find(id)
			choices.append(NAMES[id]+("　· "+str(SLOTS[occupied]) if occupied>=0 else ""))
		g._pick("为%s选择地形"%SLOTS[slot],choices,func(choice):
			var id: int=choice+1
			var other:=current.find(id)
			if other>=0:current[other]=current[slot]
			current[slot]=id
			g._flags().j_safari_layout=current
			g._persist()
			g._show_toast("%s已配置为%s。"%[SLOTS[slot],NAMES[id]])))
