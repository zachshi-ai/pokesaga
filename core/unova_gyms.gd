extends RefCounted

const RIDE_NAMES := {"coaster":"过山车","lift":"升降台","cannon":"大炮","lily":"睡莲","dragon":"龙首平台","cocoon":"茧道","ice":"冰面转盘","wind":"风道","curtain":"帷幕"}
const TRACK_COLORS := ["","红色","蓝色","紫色","绿色"]

static func flag(map: Dictionary,row: Dictionary) -> String:
	return "%s_switch_%d"%[map.id,int(row.index)]

static func is_rail(map: Dictionary) -> bool:
	return map.get("id","")=="unova_bw_gym_nimbasa"

static func switch_at(g,at: Vector2i) -> bool:
	var map: Dictionary=g.world.map_data
	if not is_rail(map):return false
	for row in map.get("unova_mechanisms",[]):
		var cell: Array=row.get("switch_at",[])
		if cell.size()!=2 or at!=Vector2i(int(cell[0]),int(cell[1])):continue
		var key:=flag(map,row)
		if g._flags().get(key,false):return false
		g._flags()[key]=true
		g.snd.play_sfx("confirm")
		g._show_toast("%s按钮亮起，轨道转向下一站。"%TRACK_COLORS[clampi(int(row.index),0,4)])
		g._persist()
		return true
	return false

static func station(g,target: Dictionary) -> Dictionary:
	var map: Dictionary=g.world.map_data
	if target.get("map","")!=map.get("id",""):return {}
	var position: Vector2i=g.world.player_pos
	for row in map.get("unova_mechanisms",[]):
		var a:=Vector2i(int(row.from[0]),int(row.from[1]))
		var b:=Vector2i(int(row.to[0]),int(row.to[1]))
		var end:=Vector2i(int(target.at[0]),int(target.at[1]))
		if (position==a and end==b) or (position==b and end==a):return row
	return {}

static func ride(g,row: Dictionary,target: Dictionary) -> void:
	if g._escort_active:return
	var map: Dictionary=g.world.map_data
	var point: Array=target.at
	var forward: bool=point==row.to
	if is_rail(map) and forward and row.has("switch_at") and not g._flags().get(flag(map,row),false):
		g.held_dir=""
		g.run_held=false
		g._dialog(["轨道还没转过来。走到站台的%s按钮上再来乘车。"%TRACK_COLORS[clampi(int(row.index),0,4)]],"过山车")
		return
	g._escort_active=true
	g.held_dir=""
	g.run_held=false
	g.panel_open+=1
	g._set_hud_visible(false)
	g.world.warp_to(g.world.player_pos)
	var start: Vector2=g.world.render_pos
	var end:=Vector2(int(point[0]),int(point[1]))
	var name: String=RIDE_NAMES.get(row.kind,"移动平台")
	g.snd.play_sfx("door")
	g._show_toast(name)
	var tween: Tween=g.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var move:=func(fraction: float):
		g.world.render_pos=start.lerp(end,fraction)
		g.world.jump_lift=sin(fraction*PI)*(35.0 if row.kind=="cannon" else 3.0 if row.kind=="coaster" else 0.0)
		g.world._sync_player()
	tween.tween_method(move,0.0,1.0,clampf(start.distance_to(end)*0.035,0.35,1.45))
	await tween.finished
	g.world.jump_lift=0
	g.world.warp_to(Vector2i(end))
	g.panel_open-=1
	g._escort_active=false
	g._set_hud_visible(true)
	g._persist()

# The three floor rows and six bookcases use Black's event tiles (zone 7 and 18).
const CURTAIN_Y := [36,26,16]
const SOLUTION_X := [15,9,12]
const BOOKS := [[6,18],[5,10],[6,2],[12,18],[12,10]]
const NOTES := [
	"书里夹着馆主的便条：刚进道馆时，你最先遇见的是哪只宝可梦？",
	"探探鼠会直立着望风。下一条谜面说，有个家伙体内燃着火，前进时从头上冒烟。",
	"原来是蒸汽机车！下一本书谈到一种在锅中加热、甜甜的宝可梦点心。",
	"宝芬的书页间画着路线。照着步数走，终点在右边中间的书架。",
	"书架后藏着按钮。你按下按钮，通往馆主房间的楼梯露了出来。"
]
const STUDENTS := {"u2_badge_1":[171,172],"u2_badge_2":[178,179],"u2_badge_4":[207,208,209]}

static func step(g) -> bool:
	var at: Vector2i=g.world.player_pos
	if switch_at(g,at):return true
	if g.world.map_data.id!="unova_bw_gym_striaton" or g._flags().get("u1_badge_1",false):return false
	var row:=CURTAIN_Y.find(at.y)
	if row<0 or at.x not in [9,12,15]:return false
	var clicks:=int(g._flags().get("u1_curtains",0))
	if row!=clicks:return false
	if at.x!=SOLUTION_X[row]:
		g._show_toast("这块踏板没有克制帷幕上的属性。")
		return true
	g._flags().u1_curtains=clicks+1
	g.snd.play_sfx("confirm")
	g._show_toast(["水克火，第一道帷幕打开了。","草克水，第二道帷幕打开了。","火克草，最后一道帷幕打开了。"][row])
	g._persist()
	return true

static func shelf(g,at: Vector2i) -> bool:
	if g.world.map_data.id!="unova_bw_gym_nacrene":return false
	var step_index:=int(g._flags().get("u1_library_books",0))
	var shelf_index:=-1
	for i in BOOKS.size():
		if at.y==BOOKS[i][1] and ((at.x>=4 and at.x<=7)==(BOOKS[i][0]<=7)) and (at.x in range(4,8) or at.x in range(11,15)):
			shelf_index=i
			break
	if shelf_index<0:return false
	if shelf_index==step_index:
		var reader: String={2:"u1_trainer_88",4:"u1_trainer_87"}.get(step_index,"")
		if reader!="" and not g._flags().get(reader,false):
			g._dialog(["有人正在看这本书。先和旁边的训练家说说话。"],"书架")
			return true
		g._flags().u1_library_books=step_index+1
		g._persist()
		g._dialog([NOTES[shelf_index]],"馆长的藏书")
	else:
		g._dialog([NOTES[shelf_index] if shelf_index<step_index else "这本书的书签还夹在后面。先从入口左边那本讲初遇的书找起。"],"书架")
	return true

static func message(event_id: String,flags: Dictionary) -> String:
	if event_id=="u1_badge_1" and not flags.get(event_id,false) and int(flags.get("u1_curtains",0))<3:
		return "请依次踩中克制帷幕属性的踏板。绿叶是草，红色火苗是火，蓝色水滴是水。"
	for tid in STUDENTS.get(event_id,[]):
		if not flags.get("u2_trainer_%d"%tid,false):
			return {"u2_badge_1":"先和训练场上的两位学生分别对战，然后来找黑连。","u2_badge_2":"鼓声和吉他声太响了。先和两位乐手对战，霍米加才能听清你说话。","u2_badge_4":"请沿伸展台依次挑战三位模特，让聚光灯照亮最后的舞台。"}[event_id]
	return ""

static func gate(src: Dictionary, target: Dictionary, flags: Dictionary) -> String:
	if src.get("id","")=="unova_bw_gym_nacrene" and target.get("map","")=="unova_bw_zone_19" and int(flags.get("u1_library_books",0))<5 and not flags.get("u1_badge_2",false):
		return "书架下的通道还没有打开。循着馆长写在书里的便条调查五个书架。"
	return ""
