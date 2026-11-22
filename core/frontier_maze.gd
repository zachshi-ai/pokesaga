extends RefCounted
## Each floor uses sixteen original 8×8 Battle Pyramid squares.
const FLOOR := "em_battle_frontier_battle_pyramid_floor"
const SIDE := 32
const FIELDS := ["behavior","collision","elevation"]
const DIRS := [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]
static var squares: Dictionary

static func square(id: int) -> Dictionary:
	if not squares.has(id):
		var map: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/maps/em_battle_pyramid_square%02d.json"%id))
		map.lower=Marshalls.base64_to_raw(map.hoenn_art.t).decompress(128,FileAccess.COMPRESSION_DEFLATE)
		map.upper=Marshalls.base64_to_raw(map.hoenn_art.a).decompress(128,FileAccess.COMPRESSION_DEFLATE) if map.hoenn_art.has("a") else PackedByteArray()
		squares[id]=map
	return squares[id]

static func apply(base: Dictionary, run: Dictionary) -> Dictionary:
	if base.id!=FLOOR or run.get("kind","")!="pyramid" or not run.has("floor_seed"):return base
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(run.floor_seed)
	var m:=base.duplicate(true)
	m.size=[SIDE,SIDE]
	m.npcs=[]
	m.objects=[]
	m.physics={"size":[SIDE,SIDE]}
	for f in FIELDS:
		m.physics[f]=[]
		for y in SIDE:
			var values: Array=[]
			values.resize(SIDE)
			m.physics[f].append(values)
	var lower:=PackedByteArray()
	var upper:=PackedByteArray()
	lower.resize(SIDE*SIDE*2)
	upper.resize(lower.size())
	var exits: Array=[]
	var potentials: Array=[]
	var floor_tile:=0
	var exit_tile:=0
	for tile_y in 4:
		for tile_x in 4:
			var src:=square(rng.randi_range(1,16))
			for y in 8:
				for x in 8:
					var xx:=tile_x*8+x
					var yy:=tile_y*8+y
					for f in FIELDS:m.physics[f][yy][xx]=int(src.physics[f][y][x])
					var tile: int=src.lower.decode_u16((y*8+x)*2)
					lower.encode_u16((yy*SIDE+xx)*2,tile)
					if not src.upper.is_empty():upper.encode_u16((yy*SIDE+xx)*2,src.upper.decode_u16((y*8+x)*2))
					if src.physics.behavior[y][x]==13:
						exits.append(Vector2i(xx,yy))
						exit_tile=tile
					elif floor_tile==0 and int(src.physics.collision[y][x])==0 and int(src.physics.behavior[y][x])==0:floor_tile=tile
			var sample: Array=src.npcs
			var actor: Dictionary=sample[rng.randi_range(0,sample.size()-1)].duplicate(true)
			actor.at=[int(actor.at[0])+tile_x*8,int(actor.at[1])+tile_y*8]
			potentials.append(actor)
	var start: Vector2i=exits[0]
	var seen: Dictionary={start:0}
	var q: Array=[start]
	var cursor:=0
	while cursor<q.size():
		var p: Vector2i=q[cursor]
		cursor+=1
		for d: Vector2i in DIRS:
			var t:=p+d
			if t.x<0 or t.y<0 or t.x>=SIDE or t.y>=SIDE or seen.has(t) or int(m.physics.collision[t.y][t.x])!=0:continue
			seen[t]=int(seen[p])+1
			q.append(t)
	var dest: Vector2i=q.back()
	for cell: Vector2i in exits:
		m.physics.behavior[cell.y][cell.x]=0
		lower.encode_u16((cell.y*SIDE+cell.x)*2,floor_tile)
	m.physics.behavior[dest.y][dest.x]=13
	lower.encode_u16((dest.y*SIDE+dest.x)*2,exit_tile)
	m.hoenn_art={"s":m.size,"p":[],"source":"pokeemerald","t":Marshalls.raw_to_base64(lower.compress(FileAccess.COMPRESSION_DEFLATE)),"a":Marshalls.raw_to_base64(upper.compress(FileAccess.COMPRESSION_DEFLATE))}
	m.spawn=[start.x,start.y]
	m.pyramid_exit=[dest.x,dest.y]
	m.name="对战金字塔 · 第 %d 层" % (int(run.wins)%7+1)
	for n in potentials:
		var pos:=Vector2i(n.at[0],n.at[1])
		var key:="%d,%d" % [pos.x,pos.y]
		if pos==start or pos==dest or key in run.get("cleared",[]) or not seen.has(pos):continue
		# Interactions are adjacent. Keep corridors traversable.
		if DIRS.filter(func(d):return seen.has(pos+d)).size()<3:continue
		n.erase("battle")
		n.erase("source_trainer")
		n.erase("native_gfx")
		n.erase("source_flag")
		n.frontier_key=key
		m.npcs.append(n)
	return m
