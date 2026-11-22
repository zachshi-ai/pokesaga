extends RefCounted
## Coordinates are Emerald's map-local tiles, without the seven-tile engine border.
static var actor_catalog: Dictionary

static func visible(npc: Dictionary, flags: Dictionary) -> bool:
	if str(npc.get("source_gfx","")).begins_with("OBJ_EVENT_GFX_VAR_") and not npc.has("native_gfx"):return false
	var key := str(npc.get("source_flag","0"))
	return key=="0" or not flags.get(key,npc.get("initially_hidden",false))

static func behavior(map: Dictionary,p: Vector2i) -> int:
	var rows: Array=map.get("physics",{}).get("behavior",[])
	return int(rows[p.y][p.x]) if p.y>=0 and p.y<rows.size() and p.x>=0 and p.x<rows[p.y].size() else -1

static func draw(sprite: Sprite2D,npc: Dictionary,face: String,step:=0) -> void:
	if actor_catalog.is_empty():
		actor_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/actors.json"))
	var gfx:=str(npc.get("native_gfx",npc.get("source_gfx","")))
	var info: Dictionary=actor_catalog.get(gfx,{})
	if info.is_empty(): return
	var n:=int(info.frames)
	var pose:=0
	if not info.inanimate:
		pose=1 if face=="up" else (2 if face in ["left","right"] else 0)
		if step>0 and n>=9: pose=3+pose*2+(step-1)%2
	var tex:=AtlasTexture.new()
	tex.atlas=load("res://assets/hoenn_native/actors/%s.png"%info.sheet)
	tex.region=Rect2(mini(pose,n-1)*int(info.w),0,int(info.w),int(info.h))
	sprite.texture=tex
	sprite.flip_h=face=="right" and not info.inanimate

static func saved_position(world, old: Vector2i, was_surfing:=false) -> Vector2i:
	var map: Dictionary=world.map_data
	var size: Array=map.get("legacy_size",map.get("size",[]))
	var pos:=old
	if map.get("id","") not in ["littleroot_town","route101"] and map.has("legacy_size"):
		pos=Vector2i(roundi(float(old.x)*maxi(1,world.tile_size.x-1)/maxi(1,int(size[0])-1)),roundi(float(old.y)*maxi(1,world.tile_size.y-1)/maxi(1,int(size[1])-1)))
	var surf: bool=world.surfing
	world.surfing=was_surfing
	var closest:=Vector2i(map.spawn[0],map.spawn[1])
	var best:=2147483647
	for y in world.tile_size.y:
		for x in world.tile_size.x:
			var at:=Vector2i(x,y)
			var dist:=at.distance_squared_to(pos)
			if dist>=best or world.is_water(at)!=was_surfing or world._warp_cells.has(at):continue
			if world.can_enter(at,Vector2i.ZERO,true):
				closest=at
				best=dist
	world.surfing=surf
	return closest

static var travel_catalog: Dictionary

static func travel() -> Dictionary:
	if travel_catalog.is_empty():
		travel_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/travel.json"))
	return travel_catalog

static func destination(map: Dictionary, target: Dictionary, flags: Dictionary, hour: int) -> Dictionary:
	var dest:=target.duplicate()
	var mid:String=dest.map
	if map.id=="hoenn_125" and mid=="em_shoal_cave_low_tide_entrance_room" and (hour<3 or hour>=21 or (hour>=9 and hour<15)):
		dest.map="hoenn_shoal"
	if map.id=="em_route110_trick_house_entrance" and mid=="em_route110_trick_house_puzzle1":
		var stage:=clampi(1+int(flags.get("h_trick_cleared",0)),1,8)
		if stage>1:
			dest.map="em_route110_trick_house_puzzle%d"%stage
			dest.at=[0,21]
	return dest

static func trick_master(g, n: Dictionary) -> bool:
	if n.get("source_script","")!="Route110_TrickHouseEnd_EventScript_TrickMaster":return false
	preload("res://core/hoenn_side.gd").reward_trick(g)
	return true
