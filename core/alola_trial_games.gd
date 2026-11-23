extends RefCounted
## The observatory platform uses the four rotatable 2×2 sections of its 3×3 grid.
const BLOCKS := [[0,1,4,3],[1,2,5,4],[3,4,7,6],[4,5,8,7]]
const GOALS := [[1,4,7],[3,4,5],[0,4,8]]
const LABELS := ["左上磁铁","右上磁铁","左下磁铁","右下磁铁"]
const BATTLE_PATH := "res://core/battle.gd"
const CampaignPath := "res://core/alola_campaign.gd"
static func circuit(g,stage:=0,occupied: Array=[0,3,6]) -> void:
	if stage>=GOALS.size():
		g._story_step()
		return
	var rows: Array=[]
	for y in 3:
		var row:=""
		for x in 3:row+="● " if y*3+x in occupied else "○ "
		rows.append(row)
	var pattern: String=["纵向中列","横向中排","左上到右下的斜线"][stage]
	g._pick("充电车　%d／3　排成%s\n%s"%[stage+1,pattern,"\n".join(rows)],LABELS,func(i):
		var next: Array=[]
		var block: Array=BLOCKS[i]
		for cell in occupied:
			var pos:=block.find(cell)
			next.append(block[(pos+1)%4] if pos>=0 else cell)
		next.sort()
		if next==GOALS[stage]:
			g._dialog(["电流接通了！"]).closed.connect(g._story_step,CONNECT_ONE_SHOT)
		else:circuit(g,stage,next),func():preload("res://core/hoenn_campaign.gd").abort_event(g))

static func royal(g) -> void:
	var fighters: Array=g._make_team().filter(func(m):return m.hp>0)
	if fighters.is_empty():
		preload("res://core/hoenn_campaign.gd").abort_event(g)
		g._dialog(["请带上能够战斗的伙伴再来报名。"])
		return
	var Battle=load(BATTLE_PATH)
	var allies: Array=[fighters[0]]
	var flags: Dictionary=g._flags()
	var which: int=maxi(0,load(CampaignPath).STARTERS.find(int(flags.a_starter)))
	for tid in [81,82+which,185]:
		var m: Dictionary=load(CampaignPath).trainer(tid,flags)[0]
		allies.append(Battle.make_combatant(m.species,m.level,m.moves,m.get("form","")))
	var engine=Battle.new(g.rng.randi())
	engine.start([allies[0]],[allies[1]])
	_royal_move(g,engine,allies)

static func _royal_move(g,b,mons: Array) -> void:
	var names: Array=[]
	var usable: Array=[]
	for i in mons[0].moves.size():
		if int(mons[0].pp[i])<=0:continue
		names.append(str(g.get_node("/root/Data").move_of(int(mons[0].moves[i])).name))
		usable.append(i)
	if usable.is_empty():names.append("挣扎");usable.append(-1)
	var hp: Array=[]
	for mon in mons:hp.append("%s %d/%d"%[mon.name,mon.hp,mon.max_hp])
	g._pick("皇家对战 · 选择招式\n"+"　".join(hp),names,func(i):
		var targets: Array=[]
		for idx in range(1,4):targets.append(mons[idx].name)
		g._pick("选择攻击目标",targets,func(j):_royal_turn(g,b,mons,usable[i],j+1)))

static func _royal_turn(g,b,mons: Array,move: int,target: int) -> void:
	var order: Array=[0,1,2,3]
	order.sort_custom(func(x,y):return mons[x].stats.spe>mons[y].stats.spe)
	var notes: Array=[]
	for idx in order:
		var aim: int=target if idx==0 else (idx+1+g.rng.randi_range(0,2))%4
		b.team_a=[mons[idx]]
		b.team_b=[mons[aim]]
		b.active_a=0
		b.active_b=0
		b.log.clear()
		var slot: int=move if idx==0 else g.rng.randi_range(0,mons[idx].moves.size()-1)
		b._take_action("a","move:"+str(slot))
		notes.append_array(b.log)
		if mons[aim].hp<=0 or mons[idx].hp<=0:
			notes.append("一名选手失去了全部战斗力。皇家蒙面人宣布表演赛结束！")
			g._dialog(notes,"皇家蒙面人").closed.connect(g._story_step,CONNECT_ONE_SHOT)
			return
	g._dialog(notes,"皇家对战").closed.connect(func():_royal_move(g,b,mons),CONNECT_ONE_SHOT)

static func z_lesson(g) -> void:
	var engine=load(BATTLE_PATH)
	var learner: Dictionary=engine.make_combatant(744,16,[33,44,28,316])
	learner.held="NORMALIUM_Z"
	var day: bool=str(g._flags().a_version).ends_with("sun")
	var target: Dictionary=engine.make_combatant(734 if day else 19,9,[33],"" if day else "RATTATA_ALOLA")
	var layer:=CanvasLayer.new()
	layer.layer=6
	g.add_child(layer)
	var ui=load("res://scenes/battle_ui.gd").new()
	ui.backdrop="grass"
	ui.alola_rules=true
	ui.alola_ring=true
	ui.alola_ultra=str(g._flags().a_version).begins_with("ultra")
	g.active_battle=ui
	g.held_dir=""
	layer.add_child(ui)
	ui.setup([learner],[target],g.rng.randi(),[],"库库伊的示范")
	g._set_hud_visible(false)
	ui.finished.connect(func(_result):
		var demonstrated: bool=ui.battle.alola_z_used.a
		g.active_battle=null
		layer.queue_free()
		g._set_hud_visible(true)
		if demonstrated:
			g._flags().a_z_practiced=true
			g._persist()
			g._story_step()
		else:
			preload("res://core/hoenn_campaign.gd").abort_event(g)
			g._dialog(["这次再试一次。点战斗、特殊行动、Z 招式，然后选岩狗狗的撞击。"],"库库伊"),CONNECT_ONE_SHOT)
