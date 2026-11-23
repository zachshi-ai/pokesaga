extends Control
## Effects laid over the native field while Shauna and AZ finish their stories.
var elapsed:=0.0
const BURSTS:=[
	[.2,Vector2(.28,.31),Color("#ffba84")],
	[.85,Vector2(.67,.23),Color("#a7ddff")],
	[1.25,Vector2(.46,.18),Color("#ffd881")],
	[1.85,Vector2(.73,.35),Color("#ecb9ee")],
	[2.05,Vector2(.23,.18),Color("#c1eda7")]
]

func _process(delta:float)->void:
	elapsed+=delta
	queue_redraw()

func _draw()->void:
	var veil:=clampf(minf(elapsed*2.5,(3.35-elapsed)*2.5),0,1)*.44
	draw_rect(Rect2(Vector2.ZERO,size),Color(.08,.13,.24,veil))
	var unit:=clampf(size.y/140.0,1,4)
	for burst in BURSTS:
		var t:float=elapsed-float(burst[0])
		if t<0 or t>1.12:continue
		var center:Vector2=burst[1]*size
		var color:Color=burst[2]
		if t<.16:
			var shell:=center+Vector2(0,(.16-t)*size.y*.8)
			draw_rect(Rect2(shell.round(),Vector2(unit,unit*3)),Color("#fff0ba"))
			continue
		t=(t-.16)/.96
		var radius:float=(1-pow(1-t,2))*.16*size.y
		for ring in [1.0,.62]:
			for i in 16:
				var dir:=Vector2.from_angle(TAU*i/16.0+ring*.32)
				var p:Vector2=center+dir*radius*float(ring)+Vector2.DOWN*t*t*size.y*.08
				var light:=Color(color,clampf((1-t)*2.5,0,1))
				draw_rect(Rect2(p.round(),Vector2.ONE*unit),light)

static func play(g,kind:String) -> void:
	g.panel_open+=1
	g._escort_active=true
	g.held_dir=""
	g.run_held=false
	g._set_hud_visible(false)
	if kind=="fireworks":
		var fireworks=load("res://core/kalos_scenes.gd").new()
		g.menu_layer.add_child(fireworks)
		fireworks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fireworks.mouse_filter=Control.MOUSE_FILTER_IGNORE
		await g.get_tree().create_timer(3.35).timeout
		fireworks.queue_free()
	else:
		# The eternal-flower form descends to AZ, separate from the five wild flower colours.
		var feet:=Vector2(g.world.player_pos*16+Vector2i(8,8))
		for npc in g.world.npcs:
			if npc.get("name","")=="ＡＺ":
				feet=Vector2(int(npc.at[0])*16+8,int(npc.at[1])*16+6)
				break
		var flower:=Sprite2D.new()
		flower.texture=preload("res://assets/mon/forms/670_floette_eternal.png")
		flower.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		flower.scale=Vector2.ONE*.45
		flower.z_index=1800
		g.world.add_child(flower)
		flower.position=feet+Vector2(28,-100)
		var flight: Tween=g.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		flight.tween_property(flower,"position",feet+Vector2(-5,-57),.75)
		flight.tween_property(flower,"position",feet+Vector2(15,-15),.85)
		flight.tween_interval(1.0)
		await flight.finished
		flower.queue_free()
	g.panel_open-=1
	g._escort_active=false
	g._set_hud_visible(true)
	g._story_step()
