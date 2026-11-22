extends RefCounted

const ROAD := "hoenn_110"
const NORTH := "em_route110_seaside_cycling_road_north_entrance"
const SOUTH := "em_route110_seaside_cycling_road_south_entrance"
const MACH := "ITEM_MACH_BIKE"
const TIMER := "emerald_cycling_attempt"
const TRACK := "h_cycling_lane"
const RECORD := "h_cycling_record"

static func transfer(g,next_map: Dictionary,target: Dictionary) -> void:
	var origin: String=g.world.map_data.get("id","")
	var dest: String=next_map.get("id","")
	if origin!=ROAD and origin not in [NORTH,SOUTH] and dest not in [NORTH,SOUTH,ROAD]:return
	if g.has_meta(TIMER):g.remove_meta(TIMER)
	var at: Array=target.get("at",[])
	# Each gatehouse has an ordinary street exit and a separate exit onto the bridge.
	if dest in [NORTH,SOUTH]:
		g._flags()[TRACK]=at.size()==2 and int(at[0])>=12
		return
	if dest==ROAD and origin in [NORTH,SOUTH] and at.size()==2:
		var bridge: bool=Vector2i(int(at[0]),int(at[1])) in [Vector2i(18,17),Vector2i(19,89)]
		g._flags()[TRACK]=bridge
		if bridge and origin==NORTH and g.world.bike and g._flags().get("h_bike","")==MACH:
			g.set_meta(TIMER,{"started":Time.get_ticks_usec(),"hits":0,"speed":0,"last_step":0})
		return
	g._flags().erase(TRACK)

static func blocks_dismount(g) -> bool:
	if g.world.bike and g._flags().get(TRACK,false) and g.world.map_data.id in [ROAD,NORTH,SOUTH]:
		g._show_toast("自行车道上请保持骑行。")
		return true
	return false

static func bump(g) -> void:
	if g.has_meta(TIMER) and g.world.bike and g.world.map_data.id==ROAD:
		var attempt: Dictionary=g.get_meta(TIMER)
		attempt.hits=mini(100,int(attempt.hits)+1)
		attempt.speed=0

static func field_step(g) -> bool:
	var map: String=g.world.map_data.get("id","")
	var pos: Vector2i=g.world.player_pos
	if map in [NORTH,SOUTH]:
		if pos==Vector2i(5,4):g._flags().erase(TRACK)
		elif pos==Vector2i(7,4):
			if not g.world.bike:
				g.world.warp_to(Vector2i(6,4))
				g.held_dir=""
				g._dialog(["这条路只供自行车通行。请先骑上自行车。"],"自行车道管理员")
				return true
			g._flags()[TRACK]=true
	elif map==ROAD and g.has_meta(TIMER) and g.world.bike:
		var attempt: Dictionary=g.get_meta(TIMER)
		var now:=Time.get_ticks_usec()
		if now-int(attempt.last_step)>400000:attempt.speed=0
		if g.world.walking and g.world.pending_warp.is_empty():
			g.world._step_duration=[16,8,4][int(attempt.speed)]/60.0
			attempt.speed=mini(2,int(attempt.speed)+1)
			attempt.last_step=now
		if pos not in [Vector2i(28,92),Vector2i(29,92)]:return false
		var run: Dictionary=g.get_meta(TIMER)
		g.remove_meta(TIMER)
		var frames:=maxi(1,int((Time.get_ticks_usec()-int(run.started))*60/1000000))
		var hits:=int(run.hits)
		var record: Dictionary=g._flags().get(RECORD,{})
		if record.is_empty() or int(record.frames)>frames:
			g._flags()[RECORD]={"frames":frames,"hits":hits}
		g.held_dir=""
		g._persist()
		g._dialog([summary(frames,hits),reaction(score(frames,hits))],"自行车道裁判")
		return true
	return false

static func score(frames: int,hits: int) -> int:
	var safety:=0
	for threshold in [1,4,10,20,100]:
		if hits<threshold:safety+=1
	var seconds:=frames/60
	var speed:=0
	for threshold in [11,16,21,41,60]:
		if seconds<threshold:speed+=1
	return safety+speed

static func summary(frames: int,hits: int) -> String:
	var duration:="1 分钟以上" if frames>=3600 else "%d.%02d 秒"%[frames/60,frames%60*100/60]
	return "碰撞　%s　　用时　%s"%["99 次以上" if hits>=100 else "%d 次"%hits,duration]

static func reaction(points: int) -> String:
	if points==10:return "太精彩了！你对自行车的热爱，让我发自内心地感动。"
	if points>=7:return "技术真好！下次也要避开障碍，试试再快一点。"
	if points>=4:return "还有进步的余地。记得享受骑自行车本身的乐趣。"
	if points>=1:return "刚才可真惊险。先练稳转弯，再试一次吧。"
	return "看得我捏了一把汗。要不要回风野的车店再练练？"

static func interact(g,row: Dictionary) -> bool:
	var script: String=row.get("source_script","")
	match script:
		"Route110_EventScript_CyclingRoadResultsSign":
			var record: Dictionary=g._flags().get(RECORD,{})
			g._dialog(["还没有骑行纪录。" if record.is_empty() else "最快纪录\n"+summary(int(record.frames),int(record.hits))],"海滨自行车道")
		"Route110_EventScript_ChallengeGuy":
			var message:="从紫堇市这头骑音速自行车南下，我会记录你用的时间和碰撞次数。"
			if g.world.bike and g._flags().get("h_bike","")=="ITEM_ACRO_BIKE":message="越野自行车也能骑这条路。计时赛需要音速自行车。"
			elif g.world.bike and g._flags().get(RECORD,{}):message="我在这里等你再次挑战。争取刷新最快纪录吧！"
			g._dialog([message],"自行车道裁判")
		"Route110_SeasideCyclingRoadSouthEntrance_EventScript_Clerk","Route110_SeasideCyclingRoadNorthEntrance_EventScript_Clerk":
			g._dialog(["这是海滨自行车道。骑音速自行车从北入口出发，南端的裁判会统计用时和碰撞。"],"自行车道管理员")
		_:return false
	return true
