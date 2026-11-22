extends Control
## Stir by circling the bowl with a finger, or use the large direction buttons.
signal finished(seconds: float, mistakes: int)
const CENTER := Vector2(240,116)
var elapsed:=0.0
var last_stir:=0.0
var revolutions:=0.0
var mistakes:=0
var last_angle:=0.0
var dragging:=false
var direction:=1
var switch_at:=4.0
var next_check:=3.0
var swirl:=0.0
var active:=false
var info:=Label.new()

func start() -> void:
	active=true
	mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(info);info.position=Vector2(8,6);info.size=Vector2(464,40)
	info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;info.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	for i in 2:
		var sign_dir := 1 if i==1 else -1
		var b:=Button.new();b.text="顺时针 ↻" if i==1 else "↺ 逆时针"
		b.position=Vector2(62+i*185,205);b.size=Vector2(171,49)
		b.pressed.connect(func():stir(sign_dir*0.7))
		add_child(b)

func _gui_input(event: InputEvent) -> void:
	var pos: Vector2
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		pos=event.position
		dragging=event.pressed and pos.distance_to(CENTER)<90
		if dragging:last_angle=(pos-CENTER).angle()
	elif dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		pos=event.position
		if pos.distance_to(CENTER)<18 or pos.distance_to(CENTER)>96:return
		var angle: float=(pos-CENTER).angle()
		stir(wrapf(angle-last_angle,-PI,PI));last_angle=angle

func stir(delta: float) -> void:
	if not active or absf(delta)<0.012:return
	swirl+=delta
	if signf(delta)==signi(direction):
		revolutions+=minf(absf(delta),0.9)/TAU
	else:
		if elapsed-last_stir>0.22:mistakes+=1
	last_stir=elapsed
	queue_redraw()

func _process(dt: float) -> void:
	if not active:return
	elapsed+=dt
	if elapsed>=next_check:
		if elapsed-last_stir>2.6:mistakes+=1
		next_check+=3.0
	if revolutions>=switch_at:
		direction=-direction;switch_at+=3.0
	info.text="宝芬料理屋　　%s 搅拌　　%d%%"%["顺时针 ↻" if direction==1 else "逆时针 ↺",mini(100,int(revolutions*100/13))]
	if revolutions>=13 or elapsed>=65:
		active=false
		finished.emit(clampf(elapsed,25,65),mistakes)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#302733"))
	draw_circle(CENTER+Vector2(0,4),78,Color("#9c847e"))
	draw_circle(CENTER,74,Color("#f6e2c6"))
	draw_circle(CENTER,64,Color("#ac6356").lerp(Color("#e5b67e"),clampf(revolutions/13.0,0,1)))
	for i in 5:
		draw_arc(CENTER,18+i*9,swirl+i*0.75,swirl+i*0.75+2.65,28,Color("#f2d3a2"),3)
	var tip:=CENTER+Vector2.from_angle(swirl)*40
	draw_line(tip,tip+Vector2(35,-37),Color("#7d4b39"),7,true)
