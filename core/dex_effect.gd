extends Control
## Preview effects are drawn over the actual normal or shiny sprite.
const TYPE_COLORS := {
	"normal":"b0a99b", "fire":"f17347", "water":"3899e5", "electric":"e1af27",
	"grass":"70b251", "ice":"69c8da", "fighting":"cf6753", "poison":"ae67b9",
	"ground":"bd8f58", "flying":"88a5df", "psychic":"ed7199", "bug":"9cb343",
	"rock":"bda869", "ghost":"7b65a8", "dragon":"656fc7", "dark":"706574",
	"steel":"849ba8", "fairy":"e995ba", "stellar":"71b7b4"
}

var shine := "none"
var tera := ""
var giant := false
var time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(shine != "none" or not tera.is_empty() or giant)

func _process(delta: float) -> void:
	time = fmod(time+delta, 12.0)
	queue_redraw()

func _draw() -> void:
	if giant:
		for i in 3:
			var angle := time + i*2.1
			var center := Vector2(size.x*(0.5+0.33*cos(angle)), size.y*(0.16+0.04*sin(angle)))
			draw_arc(center, 8, 2.8, 6.7, 16, Color("#d65c80"), 2, true)
	if not tera.is_empty():
		var tint := Color(str(TYPE_COLORS.get(tera,"78bbc6")))
		var c := Vector2(size.x*0.5, size.y*0.15)
		for i in 3:
			var p := c + Vector2((i-1)*9, abs(i-1)*6)
			var h := 14.0 if i==1 else 10.0
			var jewel := PackedVector2Array([p+Vector2(0,-h),p+Vector2(5,-h*0.25),p+Vector2(3,4),p+Vector2(-3,4),p+Vector2(-5,-h*0.25)])
			draw_colored_polygon(jewel,tint)
			draw_line(p+Vector2(0,-h+1),p+Vector2(-2,1),Color.WHITE,1.4,true)
	if shine == "none":
		return
	var positions := [Vector2(0.16,0.22),Vector2(0.82,0.29),Vector2(0.78,0.68),Vector2(0.2,0.75),Vector2(0.09,0.49)]
	for i in positions.size():
		var pulse := sin(time*3.4+i*1.35)
		var center: Vector2 = positions[i]*size+Vector2(0,pulse*2.5)
		var radius := 3.8+2.0*pulse
		if shine == "square":
			var rect := Rect2(center-Vector2.ONE*radius,Vector2.ONE*2*radius)
			draw_rect(rect.grow(1), Color("#226b73"), false, 2)
			draw_rect(rect, Color("#acfcfa"), false, 1.5)
		else:
			var points := PackedVector2Array()
			for j in 8:
				points.append(center + Vector2.UP.rotated(j*PI/4.0)*(radius*1.4 if j%2==0 else radius*0.43))
			draw_colored_polygon(points,Color("#ffd863"))
			points.append(points[0])
			draw_polyline(points,Color("#9b7425"),0.9,true)
