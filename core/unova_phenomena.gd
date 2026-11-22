extends Node2D
## The field archives distinguish rustling grass, cave dust, flying shadows and rippling water per tile.
const Field := preload("res://core/unova_field.gd")
const Catch := preload("res://core/encounter.gd")
const WINGS := ["HEALTH_WING","MUSCLE_WING","RESIST_WING","GENIUS_WING","CLEVER_WING","SWIFT_WING"]
const GEMS := ["FIRE_GEM","WATER_GEM","ELECTRIC_GEM","GRASS_GEM","ICE_GEM","FIGHTING_GEM","POISON_GEM","GROUND_GEM","FLYING_GEM","PSYCHIC_GEM","BUG_GEM","ROCK_GEM","GHOST_GEM","DRAGON_GEM","DARK_GEM","STEEL_GEM","NORMAL_GEM"]
const STONES := ["SUN_STONE","MOON_STONE","FIRE_STONE","THUNDERSTONE","WATER_STONE","LEAF_STONE","SHINY_STONE","DUSK_STONE","DAWN_STONE","OVAL_STONE"]
const SHARDS := ["RED_SHARD","BLUE_SHARD","YELLOW_SHARD","GREEN_SHARD"]
var kind := 0
var phase := 0.0

func _process(delta: float) -> void:
	phase=fmod(phase+delta*3.0,1.0)
	queue_redraw()

func _draw() -> void:
	var swing:=roundf(sin(phase*TAU)*2.0)
	match kind:
		1:
			for x in [-4,0,4]:
				draw_line(Vector2(x,3),Vector2(x+swing,-3-abs(x)/2),Color("#a9d06e"),2)
			draw_line(Vector2(-5+swing,-2),Vector2(-7+swing,-4),Color("#eff5b6"),1)
		2:
			for x in [-4,0,4]:
				draw_circle(Vector2(x+swing,2-absi(x)/2),2+phase*2,Color("#b99c79"))
				draw_rect(Rect2(x+swing-1,-1-absi(x)/2,2,1),Color("#e7d5ad"))
		3:
			draw_set_transform(Vector2(swing,0),0,Vector2(1,.45))
			draw_circle(Vector2.ZERO,4.5,Color("#394f62"))
			draw_line(Vector2(-6,-2),Vector2(5+swing,0),Color("#4c6170"),2)
		4:
			draw_set_transform(Vector2.ZERO,0,Vector2(1,.45))
			draw_arc(Vector2.ZERO,2+phase*5,0,TAU,12,Color("#d3f4f5"),1)
			draw_arc(Vector2(1,1),4+phase*4,0,PI,10,Color("#86cad4"),1)

static func restore(g) -> void:
	var mark=g.world.get_node_or_null("UnovaSpot")
	var spot: Dictionary=g.save_data.get("unova_spot",{})
	if not spot.is_empty() and (spot.map!=g.world.map_data.get("id","") or spot.era!=Field.era(g._flags())):
		g.save_data.erase("unova_spot")
		spot={}
	if is_instance_valid(mark) and spot.is_empty():
		g.world.remove_child(mark)
		mark.queue_free()
	elif not spot.is_empty() and not is_instance_valid(mark):
		mark=load("res://core/unova_phenomena.gd").new()
		mark.name="UnovaSpot"
		mark.kind=int(spot.kind)
		mark.position=(Vector2(int(spot.at[0]),int(spot.at[1]))+Vector2(.5,.55))*g.world.TILE
		mark.z_index=7
		g.world.add_child(mark)

static func water_at(g, at: Vector2i) -> bool:
	var spot: Dictionary=g.save_data.get("unova_spot",{})
	return spot.get("map","")==g.world.map_data.id and int(spot.get("kind",0))==4 and Vector2i(int(spot.at[0]),int(spot.at[1]))==at

static func take(g) -> void:
	g.save_data.erase("unova_spot")
	restore(g)

static func prize(rng: RandomNumberGenerator, kind_id: int, zone: String, era: String) -> String:
	var roll:=rng.randi_range(0,999)
	if kind_id==3:return WINGS[rng.randi_range(0,5)] if roll<900 else "PRETTY_WING"
	if era=="b2" and (zone.begins_with("relic_passage") or (zone.begins_with("reversal_mountain_") and zone.trim_prefix("reversal_mountain_").to_int() in range(2,14))):return SHARDS[roll/250]
	if roll<100:return STONES[rng.randi_range(0,9)]
	if roll<950:return GEMS[rng.randi_range(0,16)]
	return "EVERSTONE"

static func step(g) -> bool:
	var map: Dictionary=g.world.map_data
	var flags: Dictionary=g._flags()
	if not flags.get(Field.flag_prefix(flags)+"badge_1",false):return false
	var grid: Array=map.get("physics",{}).get("phenomena",[])
	if grid.is_empty():return false
	var month:=int(Time.get_date_dict_from_system().month)
	var spot: Dictionary=g.save_data.get("unova_spot",{})
	var here: Vector2i=g.world.player_pos
	if not spot.is_empty():
		if spot.map!=map.id or spot.era!=Field.era(flags):take(g)
		elif here!=Vector2i(int(spot.at[0]),int(spot.at[1])):return false
		else:
			var k:=int(spot.kind)
			take(g)
			var item_chance:=60 if k==2 else 80 if k==3 else 0
			if item_chance and g.rng.randi_range(0,99)<item_chance:
				var item:=prize(g.rng,k,map.unova_zone,Field.era(flags))
				var side=load("res://core/unova_side.gd")
				side.give(g,item)
				g._persist()
				g._dialog(["找到了%s！"%side.item_name(item)])
				return true
			var pool: Array=Field.habitat(map,flags,"rippling_surf" if k==4 else "shaking_grass",month).pool
			var wild:=Catch.roll(pool,g.rng)
			if wild.is_empty():return false
			g._start_wild_battle(int(wild.species),int(wild.level),str(wild.get("form","")))
			return true
	var land:=Field.habitat(map,flags,"shaking_grass",month)
	var water:=Field.habitat(map,flags,"rippling_surf",month)
	if land.pool.is_empty() and water.pool.is_empty():return false
	var interval:=5 if int(land.get("phenomenon_setting",0))==2 else 20
	var n:=int(g.save_data.get("unova_phenomenon_steps",0))+1
	g.save_data.unova_phenomenon_steps=n%interval
	if n<interval or g.rng.randi_range(0,99)>=(15 if interval==5 else 10):return false
	var candidates: Array[Vector2i]=[]
	for y in range(maxi(0,here.y-5),mini(grid.size(),here.y+6)):
		for x in range(maxi(0,here.x-5),mini(len(grid[y]),here.x+6)):
			var k:=int(grid[y][x])
			var p:=Vector2i(x,y)
			if not k or p==here or (water.pool.is_empty() if k==4 else land.pool.is_empty()):continue
			if (k!=4 and g.world.blocked_by_terrain(p)) or not g.world.warp_at(p).is_empty():continue
			if g.world.npcs.any(func(actor):return actor.at==[x,y]):continue
			candidates.append(p)
	if not candidates.is_empty():
		var at: Vector2i=candidates[g.rng.randi_range(0,candidates.size()-1)]
		g.save_data.unova_spot={"map":map.id,"era":Field.era(flags),"at":[at.x,at.y],"kind":int(grid[at.y][at.x])}
		restore(g)
	return false
