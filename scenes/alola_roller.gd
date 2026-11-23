extends Control
## Post-trial Roller keeps the direction of each Charjabug as each four-cell panel turns.
signal closed
const UI=preload("res://core/field_ui.gd")
const Rules=preload("res://core/alola_trial_games.gd")
const LEVELS=["入门","普通","困难","超级困难"]
const ARROWS=["↑","→","↓","←"]
const TARGETS=[[[1,2],[4,2],[7,2]],[[3,1],[4,1],[5,1]],[[0,1],[4,2],[8,3]],[[2,2],[4,3],[6,0]]]
const PATHS=[[2,0,1],[0,3,3],[2,2,2,3],[1,0,1,3]]
var game
var level:=0
var insects:Array
var presses:=0
var message:=""
func start(g,which:int) -> void:
	game=g;level=which;set_anchors_and_offsets_preset(PRESET_FULL_RECT);reset()
func rotate(state:Array,corner:int,step:int) -> Array:
	var result:Array=[];var block:Array=Rules.BLOCKS[corner]
	for bug in state:
		var pos:=block.find(bug[0])
		result.append([block[posmod(pos+step,4)],posmod(int(bug[1])+step,4)] if pos>=0 else bug.duplicate())
	result.sort_custom(func(a,b):return int(a[0])<int(b[0]))
	return result
func reset() -> void:
	insects=TARGETS[level].duplicate(true)
	var reverse:Array=PATHS[level].duplicate();reverse.reverse()
	for corner in reverse:insects=rotate(insects,corner,-1)
	presses=0;message="";render()
func selected(corner:int) -> void:
	insects=rotate(insects,corner,1);presses+=1
	if insects==TARGETS[level]:
		var f:Dictionary=game._flags()
		f.a_roller_rank=maxi(int(f.get("a_roller_rank",0)),level+1)
		if level==3 and not f.get("a_roller_prize",false):
			game._give_item("PP极限提升剂",1,"medicine");f.a_roller_prize=true;message="通电成功！获得 PP极限提升剂。"
		else:message="通电成功！"
		game._persist()
	elif presses==4:message="四次机会用完了，再试一次。"
	render()
func render() -> void:
	for child in get_children():remove_child(child);child.queue_free()
	var paper:=UI.sheet(self,Color("#eff4df"))
	UI.place(paper,UI.label("虫电宝充电盘 · "+LEVELS[level],18),16,5,295,31)
	UI.place(paper,UI.button("离开",finish),395,4,69,36)
	UI.place(paper,UI.label("转动磁铁，让虫电宝的位置和朝向与目标一致。",13),17,41,445,27)
	UI.place(paper,UI.label("充电盘",14),46,68,130,23);UI.place(paper,UI.label("目标",14),218,68,110,23)
	for i in 9:
		for j in 2:
			var state:Array=insects if j==0 else TARGETS[level]
			var idx:=state.find_custom(func(b):return int(b[0])==i)
			var rect:=ColorRect.new();rect.color=Color("#5a867c") if j==0 else Color("#94aa9a")
			UI.place(paper,rect,17+j*173+(i%3)*48,94+(i/3)*42,45,39)
			if idx>=0:
				var arrow:=UI.label(ARROWS[int(state[idx][1])],18,Color("#fff8d4"));arrow.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
				if j==0:
					var pic:=UI.portrait(737);UI.place(rect,pic,0,0,32,35);UI.place(rect,arrow,27,0,16,37)
				else:UI.place(rect,arrow,0,0,45,39)
	for i in 4:
		var b:=UI.button(Rules.LABELS[i],selected.bind(i));b.disabled=not message.is_empty()
		UI.place(paper,b,345+(i%2)*61,102+(i/2)*52,59,47)
	UI.place(paper,UI.label(message if message!="" else "剩余 %d 次"%(4-presses),14),18,229,445,32)
	UI.place(paper,UI.button("重新开始",reset),17,267,137,40)
	if insects==TARGETS[level] and level<3:
		UI.place(paper,UI.button("下一关",func():level+=1;reset(),true),273,267,187,40)
func finish() -> void:
	closed.emit();queue_free()
func handle_back() -> void:finish()
