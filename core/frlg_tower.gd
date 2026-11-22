extends RefCounted
## Eight-floor timed courses use the original FireRed lineup and level scaling.
const MODES := ["single","double","knockout","mixed"]
const NAMES := ["单打","双打","三连战","混合"]
const PRIZES := [["升级数据","UP_GRADE"],["龙之鳞片","DRAGON_SCALE"],["金属膜","METAL_COAT"],["王者之证","KINGS_ROCK"]]
const PARTY := preload("res://core/party.gd")

static func floor_of(mid: String) -> int:
	if mid.begins_with("trainer_tower_") and mid.ends_with("f"):return int(mid.trim_prefix("trainer_tower_").trim_suffix("f"))
	return 0

static func course(g) -> Dictionary:
	return g._flags().get("fr_tower",{})

static func clock(g,delta: float) -> void:
	if g.save_data.is_empty() or not g.save_data.get("flags",{}).has("fr_tower"):return
	var active: Dictionary=course(g)
	if not active.is_empty():active.elapsed=float(active.get("elapsed",0.0))+delta

static func roster(mid: String,flags: Dictionary,rows: Array,source: Dictionary) -> Array:
	var n:=floor_of(mid)
	if n==0:return rows
	var active: Dictionary=flags.get("fr_tower",{})
	if active.is_empty() or int(active.floor)<n:return []
	var floor_data: Dictionary=source[active.mode][n-1]
	var cleared: bool=int(active.floor)>n
	var positions: Array
	match floor_data.kind:
		"double":positions=[[10,12],[11,12] if cleared else [10,13]]
		"knockout":positions=[[10,16],[10,10],[14,13]]
		_:positions=[[15,13]]
	var actors: Array=[]
	for i in floor_data.actors.size():
		var trainer: Array=floor_data.actors[i]
		var art: String="fr_tower_"+str(trainer[1])
		var face:=2
		if floor_data.kind=="double" and cleared:face=0
		if floor_data.kind=="knockout":face=[1,0,2][i]
		actors.append({"at":positions[i],"name":trainer[0],"gfx":art,"field_art":art,"field_pose":face,
			"side":["tower_done" if cleared else "tower_fight",trainer[0]],"side_flag":""})
	return actors

static func step(g,source: Dictionary) -> bool:
	if g.world.map_data.id=="trainer_tower_lobby" and g._flags().get("fr_tower_lobby_exit",false) and g.world.player_pos.y>=11:
		g._flags().erase("fr_tower_lobby_exit")
		g.world.refresh_story_actors(g._flags())
	var state:=course(g)
	var n:=floor_of(g.world.map_data.id)
	if state.is_empty() or n==0 or n!=int(state.floor):return false
	var kind: String=source[state.mode][n-1].kind
	var pos: Vector2i=g.world.player_pos
	if (kind=="double" and pos in [Vector2i(9,12),Vector2i(9,13)]) or (kind!="double" and pos==Vector2i(10,13)):
		talk(g,["tower_fight","挑战者"],source)
		return true
	return false

static func talk(g,a: Array,data: Dictionary) -> void:
	match a[0]:
		"tower_desk":
			var men: Array=NAMES.duplicate()
			men.append("查看各组最快纪录")
			g._pick("选择训练家之塔挑战",men,func(i):
				if i==4:
					var lines: Array=[]
					for j in MODES.size():
						var t: float=g._flags().get("fr_tower_best_"+MODES[j],0)
						lines.append("%s　%s"%[NAMES[j],time_string(t) if t>0 else "暂无纪录"])
					g._dialog(lines,"接待员")
					return
				var healthy=g.save_data.party.filter(func(mon):return mon is Dictionary and int(mon.get("hp",0))>0)
				if healthy.is_empty() or (i in [1,3] and healthy.size()<2):
					g._dialog(["参赛需要能战斗的伙伴，含双打的赛道需要至少两只。"],"接待员")
					return
				g._flags().fr_tower={"mode":MODES[i],"floor":1,"bout":0,"elapsed":0.0}
				g._persist()
				g._dialog(["挑战开始！从北边楼梯上楼，击败当层的对手后再往上走。"],"接待员"))
		"tower_done":g._dialog(["已经交过手了。祝你接下来的挑战顺利！"],a[1])
		"tower_fight":
			var state:=course(g)
			if state.is_empty() or int(state.floor)!=floor_of(g.world.map_data.id):return
			var fd: Dictionary=data[state.mode][int(state.floor)-1]
			var fight: Dictionary=fd.fights[int(state.bout)]
			var lv:=1
			for m in g.save_data.party:
				if m is Dictionary:lv=maxi(lv,int(m.get("level",1)))
			var team: Array=fight.team.duplicate(true)
			for mon in team:mon.level=lv
			var npc:={"name":fight.name,"battle":{"team":team,"double":fd.kind=="double","tower":true,"prize":0}}
			g._start_battle(npc,func(result):
				if result=="a":
					state.bout=int(state.bout)+1
					if int(state.bout)>=fd.fights.size():
						state.floor=int(state.floor)+1
						state.bout=0
					g.world.refresh_story_actors(g._flags())
					g._persist()
					if state.bout==0:g._dialog(["本层通过，可以上楼了。"],"训练家之塔")
					else:
						var between=g._dialog(["下一位训练家接着上场！"],"训练家之塔")
						between.closed.connect(func():talk(g,a,data))
				else:
					g._flags().erase("fr_tower")
					g._do_warp({"region":"sevii","map":"trainer_tower_lobby","at":[9,8]})
					g._heal_party()
					g._persist()
					g._dialog(["本次挑战结束。可以重新报名。"],"接待员"))
		"tower_owner":
			var state:=course(g)
			if state.is_empty() or int(state.floor)!=9:
				g._dialog(["完成八层挑战后来找我吧。"],"塔主")
				return
			var mode: String=state.mode
			var index:=MODES.find(mode)
			var key:="fr_tower_best_"+mode
			var t: float=state.elapsed
			var best: float=g._flags().get(key,0)
			g._flags()[key]=t if best<=0 else minf(t,best)
			var text:="八层通关！本次%s用时%s。"%[NAMES[index],time_string(t)]
			if not g._flags().get("fr_tower_prize_"+mode,false):
				var item: Array=PRIZES[index]
				g._give_bag_item(item[0],"held",item[1])
				g._flags()["fr_tower_prize_"+mode]=true
				text+=" 首次通关奖品是%s。"%item[0]
			g._flags().erase("fr_tower")
			g._persist()
			g._dialog([text],"塔主")

static func time_string(seconds: float) -> String:
	return "%02d分%02d秒" % [int(seconds)/60,int(seconds)%60]

static func gate(g,target: Dictionary) -> String:
	var from: String=g.world.map_data.id
	var to: String=target.get("map","")
	if to=="trainer_tower_lobby" and target.get("at",[0])[0]==17:g._flags().fr_tower_lobby_exit=true
	if not from.begins_with("trainer_tower_"):return ""
	var src:=floor_of(from)
	var dest:=9 if to=="trainer_tower_roof" else floor_of(to)
	var state:=course(g)
	if dest>src and (state.is_empty() or int(state.floor)<dest):return "请先在大厅报名并击败当前楼层的对手。"
	if not state.is_empty() and not to.begins_with("trainer_tower_"):
		g._flags().erase("fr_tower")
	return ""
