extends Node2D
## 地图渲染与移动。
## 瓦片图集：assets/tiles.png（4 列 × 12 行，16×16）
##   0-15 独立瓦片；16-31 土路 autotile；32-47 水域 autotile
## 地图数据只用地形编号：0 草 1 树 2 水 3 路 4 花 5 石 6 墙 7 屋顶 8 门 9 栅栏 10 沙

const HoennMechanisms := preload("res://core/hoenn_mechanisms.gd")
var hoenn_local := {}

const EmeraldField := preload("res://core/emerald_field.gd")
const JohtoCast := preload("res://core/johto_gba_cast.gd")
const TILE := 16
const ATLAS_PATH := "res://assets/tiles_emerald.png"
const PLAYER_PATH := "res://assets/player_emerald.png"
const PLAYER_WALK := preload(PLAYER_PATH)
const PLAYER_SURF := preload("res://assets/player_surf.png")
const SHADOW_PATH := "res://assets/shadow.png"

const PATH_BASE := 32
const WATER_BASE := 16

# 地形编号 -> 图集里的独立瓦片索引（可给多个，渲染时按坐标挑一个，消除网格感）
const SOLO := {
	0: [0],    # 草
	1: [1],    # 树
	2: [2],    # 水
	3: [3],    # 路
	4: [4],    # 花
	5: [5],    # 石头
	6: [6],    # 墙
	7: [7],    # 屋顶
	8: [8],    # 门
	9: [9],    # 栅栏
	10: [10],  # 沙
	11: [11], # 高草
	12: [12], # 路牌
	13: [13], # 室内地板
	14: [14], # 室内地毯
	15: [15], # 室内墙
}

var map_data: Dictionary = {}
var tile_size := Vector2i(20, 15)
var tiles: Array = []
var player_pos := Vector2i(0, 0)
var facing := "down"
var npcs: Array = []
## 地图上的可交互物件：告示牌、道具球、树果树、翻过的土、隐藏道具
var objects: Array = []
var taken: Dictionary = {}          # 已拿走的物件（存档里记的 flag）
var _hoenn_storm_phase := -1
var weather := ""                   # rain / snow / sandstorm / fog / ash ...
var night := 0.0                    # 0 白天 1 深夜，只影响画面染色与遇敌
var bike := false                   # 骑车时走路速度翻倍
var last_event := ""
## 上一条 talk 事件对应的是哪个 NPC（按坐标存的，同名 NPC 不会串）
var last_npc: Dictionary = {}
var walking := false
var walk_timer := 0.0
var frame_col := 0
# 走路是插值出来的：逻辑位置 player_pos 立刻变，渲染位置 render_pos 在两格之间滑过去。
# 之前直接把 sprite 移到新格中心，看着就是一格一格地闪。
# 原版一张图 16 帧走一格 = 1 像素/帧。速度和步幅必须挂在同一个节拍上，
# 否则脚在原地倒腾、人整体平移，就是"滑雪"。
const WALK_FRAMES := 16
const RUN_FRAMES := 8
var walk_dur := 16.0 / 60.0
var run_dur := 8.0 / 60.0
## 从矮台阶跳下来：滞空比走路久一点，图上再抬几像素，看着才是「跳」不是「滑」
var jump_dur := 0.30
var jumping := false
var jump_lift := 0.0
var running := false
var render_pos := Vector2.ZERO
var anim_from := Vector2.ZERO
# 上一格没走完的时间余量：不留着的话，每格的节拍会一点点往后漂，
# 走起来像踩在棉花上
var walk_carry := 0.0
# Warp events are keyed by their exact source tile in the current map.
const WARP_DIR := {"up":Vector2i.UP, "down":Vector2i.DOWN, "left":Vector2i.LEFT, "right":Vector2i.RIGHT}
var _passages: Dictionary = {}
var _directional_passages: Dictionary = {}
var _step_duration := 16.0 / 60.0
var pending_warp: Dictionary = {}
signal warp_ready(to: Dictionary)

var _atlas: Texture2D
var _frames: Array = []          # 瓦片切片
var _npc_textures: Array = []    # 六套 NPC 角色
var _decal_trees: Array = []     # 跨格树冠贴花
var _decal_bushes: Array = []
var _decal_grass: Array = []
var _decor_nodes: Array = []
var _decal_shade: Texture2D
var _tile_nodes: Array = []
var _player_sprite: Sprite2D
var _player_shadow: Sprite2D
var _shadow_tex: Texture2D
var _npc_nodes: Array = []
var _obj_nodes: Array = []
var _night_tint: CanvasModulate
var _weather_fx: CPUParticles2D
var _weather_rect: ColorRect
var dark := false                    # 需要闪光的洞窟
var _dark_rect: ColorRect
var cam: Camera2D
var hud: Label
var hint: Label

func _ready() -> void:
	_atlas = load(ATLAS_PATH)
	var cols: int = int(_atlas.get_width() / TILE)
	var total: int = int(_atlas.get_height() / TILE) * cols
	for i in total:
		var at := AtlasTexture.new()
		at.atlas = _atlas
		at.region = Rect2((i % cols) * TILE, (i / cols) * TILE, TILE, TILE)
		_frames.append(at)

	for i in 6:
		var path := "res://assets/npc_%d.png" % i
		if ResourceLoader.exists(path):
			_npc_textures.append(load(path))
	for i in 6:
		var p2 := "res://assets/decal_tree_%d.png" % i
		if ResourceLoader.exists(p2):
			_decal_trees.append(load(p2))
	for i in 3:
		var pb := "res://assets/decal_bush_%d.png" % i
		if ResourceLoader.exists(pb):
			_decal_bushes.append(load(pb))
		var pg := "res://assets/decal_grass_%d.png" % i
		if ResourceLoader.exists(pg):
			_decal_grass.append(load(pg))
	if ResourceLoader.exists("res://assets/decal_shade.png"):
		_decal_shade = load("res://assets/decal_shade.png")
	_shadow_tex = load(SHADOW_PATH)
	_player_shadow = Sprite2D.new()
	_player_shadow.texture = _shadow_tex
	_player_shadow.z_index = 8
	add_child(_player_shadow)
	_player_sprite = Sprite2D.new()
	_player_sprite.texture = PLAYER_WALK
	_player_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_player_sprite.hframes = 9
	_player_sprite.vframes = 1
	_player_sprite.frame = 0
	add_child(_player_sprite)

	cam = Camera2D.new()
	# 原版视野是 15x10 格，之前 zoom=1 会显示 30x20 格，看着就是"一切都小了一半"
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()

## 原版地图：由 tools/render_emerald_maps.py 从 rom 数据整张渲染好，
## 这里只贴图 + 读碰撞表，不再按 16 类地形去拼，房子和道路就是原版的样子。
var emerald_png_path := ""
var emerald_collision: Array = []
var emerald_counter: Array = []
var emerald_ledge: Array = []
var emerald_slide: Array = []      # 冰面：踩上去会被推着走的方向
var emerald_current: Array = []    # 水流方向
var emerald_waterfall: Array = []  # 瀑布格
var emerald_button: Array = []
var _warp_cells: Dictionary = {}   # 有传送的门格：坑洞/楼梯落点不该挡人
var emerald_hole: Array = []       # 坑洞：石头推进去会填平
var emerald_deep: Array = []       # 深水：要潜水才能进
var emerald_whirl: Array = []      # 漩涡：要漩涡招式清掉
var emerald_climb: Array = []      # 岩壁：要攀岩翻过去
# 渲染层级：人物按 y 排（100 + y*2），前景/图层压到 3000 以上
const Z_ACTOR := 100
const Z_FG := 1500
const Z_DARK := 1600
const Z_FX := 1700
var emerald_elevation: Array = []  # Native FRLG height: 1 water, 3 land, 15 layered crossing.
var last_elevation := 0
var emerald_water: Array = []
## 冲浪：站在水上时才算
var surfing := false
var diving := false            # 潜水状态：深水格只有潜下去才进得去
var last_dir := Vector2i(0, 1) # 上一步的方向，冰面要顺着它滑
var emerald_dir: Array = []
var emerald_grass: Array = []
## 洞里、塔里这种整片地面都可能出野怪的原版地图（GSC 的 encounter 是"走到哪都可能"）
var emerald_wild_any := false
var emerald_chunks: Array = []

## 换图时朝向要跟着人走：原版进门是朝上走进来的，进屋后还是朝上；
## 出门是朝下走出去的，落地也是朝下。以前这里一律重置成 down，进屋会莫名转身。
var _prev_facing := ""

func load_map(data: Dictionary) -> void:
	if data.get("id","")==preload("res://core/emerald_lilycove_lady.gd").MAP and get_parent() and get_parent().has_method("_flags"):
		data=data.duplicate()
		data.npcs=data.npcs.duplicate(true)
		preload("res://core/emerald_lilycove_lady.gd").prepare(get_parent(),data)
	if data.get("id","")==preload("res://core/frontier_maze.gd").FLOOR:
		data=preload("res://core/frontier_maze.gd").apply(data,taken.get("h_frontier_run",{}))
	_prev_facing = facing
	var puzzle: Dictionary=data.get("mechanisms",{})
	var local_save: Dictionary=taken.get("hoenn_room_state",{})
	if puzzle.has("gates") or puzzle.has("switches") or puzzle.has("stairs") or puzzle.has("power_switches"):
		if local_save.get("map","")!=data.id:
			local_save={"map":data.id,"state":{}}
		hoenn_local=local_save.state
		taken.hoenn_room_state=local_save
	else:
		hoenn_local={}
		taken.erase("hoenn_room_state")
	map_data = data
	_passages.clear()
	_directional_passages.clear()
	for w in preload("res://core/world_passages.gd").active(data):
		var p := Vector2i(int(w.at[0]), int(w.at[1]))
		if data.has("emerald_original") and WARP_DIR.has(w.get("trigger","")):
			_directional_passages[[p,WARP_DIR[w.trigger]]]=w
		if not _passages.has(p):
			_passages[p] = w
	pending_warp = {}
	last_event = ""
	jumping = false
	jump_lift = 0.0
	walk_carry = 0.0
	walk_timer = 0.0
	frame_col = 0
	var em: String = String(data.get("emerald", ""))
	if em != "":
		_load_emerald_map(em)
		return
	# 切到自建图（开拓区这类）必须把原版地图的几张表清掉，
	# 否则 is_emerald() 还是 true，碰撞会去读上一张图的表
	emerald_collision = []
	emerald_elevation = []
	last_elevation = 0
	emerald_grass = []
	emerald_counter = []
	emerald_ledge = []
	emerald_water = []
	emerald_slide = []
	emerald_current = []
	emerald_waterfall = []
	emerald_button = []
	emerald_hole = []
	emerald_deep = []
	emerald_whirl = []
	emerald_climb = []
	surfing = false
	emerald_dir = []
	emerald_chunks = []
	emerald_wild_any = false
	diving = false
	dark = bool(data.get("dark", false))
	var size_arr: Array = data.get("size", [20, 15])
	tile_size = Vector2i(int(size_arr[0]), int(size_arr[1]))
	tiles = data.get("tiles", [])
	npcs = preload("res://core/frlg_actors.gd").roster(data, taken)
	objects = (data.get("objects", []) as Array).duplicate(true)
	weather = String(data.get("weather", ""))
	var sp: Array = data.get("spawn", [1, 1])
	player_pos = Vector2i(int(sp[0]), int(sp[1]))
	facing = _prev_facing if _prev_facing != "" else "down"
	render_pos = Vector2(player_pos)
	walking = false
	_rebuild()
	_apply_cam_limits()
	_sync_player()

func _load_emerald_map(name: String) -> void:
	var meta_path := "res://content/emerald_maps/%s.json" % name
	var meta: Dictionary = {}
	if map_data.has("emerald_original"):
		meta=map_data.physics
	elif map_data.has("hgss"):
		meta = preload("res://core/hgss_field.gd").grids(map_data.hgss)
	elif FileAccess.file_exists(meta_path):
		meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	emerald_collision = meta.get("collision", [])
	emerald_elevation = meta.get("elevation", [])
	last_elevation = 0
	emerald_grass = meta.get("grass", [])
	emerald_wild_any = bool(meta.get("wild_any", false))
	emerald_counter = meta.get("counter", [])
	emerald_ledge = meta.get("ledge", [])
	emerald_water = meta.get("water", [])
	emerald_slide = meta.get("slide", [])
	emerald_current = meta.get("current", [])
	emerald_waterfall = meta.get("waterfall", [])
	_warp_cells = {}
	for w in map_data.get("warps", []):
		var wa: Array = w.get("at", [0, 0])
		_warp_cells[Vector2i(int(wa[0]), int(wa[1]))] = true
	emerald_button = meta.get("button", [])
	emerald_hole = meta.get("hole", [])
	emerald_deep = meta.get("deep", [])
	emerald_whirl = meta.get("whirl", [])
	emerald_climb = meta.get("climb", [])
	emerald_dir = meta.get("dirblock", [])
	emerald_chunks = meta.get("chunks", [])
	var sz: Array = meta.get("size", [20, 20])
	tile_size = Vector2i(int(sz[0]), int(sz[1]))
	tiles = []
	emerald_png_path = "res://content/emerald_maps/%s.png" % name
	var sp: Array = map_data.get("spawn", [1, 1])
	player_pos = Vector2i(int(sp[0]), int(sp[1]))
	facing = _prev_facing if _prev_facing != "" else "down"
	# 渲染位置必须跟上，否则相机停在原点，画面会偏到角落
	render_pos = Vector2(player_pos)
	walking = false
	npcs = preload("res://core/frlg_actors.gd").roster(map_data, taken)
	if map_data.has("mechanisms"):HoennMechanisms.adjust_actors(self,npcs)
	objects = (map_data.get("objects", []) as Array).duplicate(true)
	if map_data.id=="hoenn_130" and not taken.get("h_mirage_today",false):objects=objects.filter(func(o):return o.get("kind","")!="berry_tree")
	if map_data.has("hgss") and map_data.hgss.header in ["MAP_ICE_PATH_B1F","MAP_ICE_PATH_B2F"]:
		objects=objects.filter(func(o):return (not o.has("ice_rock") or not taken.get("ice:rock:"+str(o.ice_rock),false)) and (not o.has("ice_rest") or taken.get("ice:pit:%d"%int(o.ice_rest),false)))
	if map_data.get("region","")=="kanto":
		objects=preload("res://core/kanto_campaign.gd").victory_rocks(map_data.id,objects,taken)
	weather = String(map_data.get("weather", ""))
	dark = bool(map_data.get("dark", false))
	_rebuild()
	_apply_cam_limits()
	_sync_player()

func field_biome() -> String:
	return str(EmeraldField.plan_for(map_data).get("biome", map_data.get("biome", "")))

func is_emerald() -> bool:
	return emerald_collision.size() > 0

## 这一步算不算"踩在有野怪的地方"
func wild_tile_here() -> bool:
	if tile_at(player_pos) == 11:
		return true
	if emerald_wild_any and is_emerald():
		return not is_blocked(player_pos) and not is_water(player_pos)
	return false

func tile_at(p: Vector2i) -> int:
	# 原版地图：草地/高草从预渲染时导出的 grass 网格取，其余当作普通地面
	if is_emerald():
		if p.y < 0 or p.y >= emerald_grass.size():
			return 1
		var grow: Array = emerald_grass[p.y]
		if p.x < 0 or p.x >= grow.size():
			return 1
		return 11 if int(grow[p.x]) == 1 else 0
	if p.y < 0 or p.y >= tiles.size():
		return 1
	var row: Array = tiles[p.y]
	if p.x < 0 or p.x >= row.size():
		return 1
	return int(row[p.x])

## 只看地形/碰撞，不看 NPC 站立
func blocked_by_terrain(p: Vector2i) -> bool:
	if is_emerald():
		if p.y < 0 or p.y >= emerald_collision.size():
			return true
		var row: Array = emerald_collision[p.y]
		if p.x < 0 or p.x >= row.size():
			return true
		return int(row[p.x]) != 0
	var t := tile_at(p)
	return t == 1 or t == 2 or t == 6 or t == 7

func is_blocked(p: Vector2i) -> bool:
	if is_emerald():
		if p.y < 0 or p.y >= emerald_collision.size():
			return true
		var row: Array = emerald_collision[p.y]
		if p.x < 0 or p.x >= row.size():
			return true
		if int(row[p.x]) != 0:
			return true
		for n in npcs:
			var at: Array = n.get("at", [0, 0])
			if Vector2i(int(at[0]), int(at[1])) == p:
				return true
		return false
	var t := tile_at(p)
	if t == 1 or t == 2 or t == 6 or t == 7:
		return true
	for n in npcs:
		var at: Array = n.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == p:
			return true
	return false

## 方向阻挡：1 北 / 2 南 / 4 东 / 8 西，表示"从这个方向进不来"
func dir_mask(p: Vector2i) -> int:
	if p.y < 0 or p.y >= emerald_dir.size():
		return 0
	var row: Array = emerald_dir[p.y]
	if p.x < 0 or p.x >= row.size():
		return 0
	return int(row[p.x])

## 方向阻挡：斜着走时两个分量任何一边被挡，都算进不去
func _mask_blocks(p: Vector2i, dir: Vector2i) -> bool:
	var m := dir_mask(p)
	if m == 0:
		return false
	if dir.x > 0 and m & 4 != 0:
		return true
	if dir.x < 0 and m & 8 != 0:
		return true
	if dir.y > 0 and m & 2 != 0:
		return true
	if dir.y < 0 and m & 1 != 0:
		return true
	return false


func _dir_bit(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1):
		return 1
	if dir == Vector2i(0, 1):
		return 2
	if dir == Vector2i(1, 0):
		return 4
	return 8

## 从 dir 方向走进 p 这一格行不行（方向性阻挡只挡对应方向）
func can_enter(p: Vector2i, dir: Vector2i, ignore_mask: bool = false) -> bool:
	if not preload("res://core/hoenn_base_effects.gd").allows(self,p,dir):return false
	if map_data.has("emerald_original") and not preload("res://core/hoenn_items.gd").can_enter(self,p,dir): return false
	if map_data.get("hgss",{}).get("header","")=="MAP_OLIVINE_LIGHTHOUSE_LIGHT_ROOM" and p==Vector2i(8,12) and not taken.get("j_sick_amphy",false): return false
	# 非原版地图（开拓区这类自建图）只有 tiles 网格，没有方向阻挡
	if not is_emerald():
		if p.y < 0 or p.y >= tiles.size():
			return false
		var trow: Array = tiles[p.y]
		if p.x < 0 or p.x >= trow.size():
			return false
		var tv := int(trow[p.x])
		if tv in [1, 6, 7] or (tv == 2 and not surfing):
			return false
		for n in npcs:
			var nat: Array = n.get("at", [0, 0])
			if Vector2i(int(nat[0]), int(nat[1])) == p:
				return false
		return true
	if p.y < 0 or p.y >= emerald_collision.size():
		return false
	var row: Array = emerald_collision[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	var has_cleared := _is_cleared(p)
	if not has_cleared:
		# 城都碰撞层把水面标为步行障碍；学会冲浪后只放行真正的水格。
		if int(row[p.x]) != 0 and not (emerald_elevation.is_empty() and surfing and is_water(p)):
			return false
		# 水面：只有冲浪时能进；上了岸就自动结束冲浪
		if is_water(p) and not surfing and map_data.get("map_type","")!="MAP_TYPE_UNDERWATER":
			return false
		# 深水只有潜下去才能进；漩涡没清掉过不去；岩壁和没填的坑洞一律挡
		if is_deep(p) and not diving and not map_data.has("emerald_original"):
			return false
		if is_whirl(p) and not whirl_cleared(p):
			return false
		if is_climb(p):
			return false
		# 坑洞挡人，但原版那种「跳下去到下一层」的坑本身就是传送门，不能挡
		if is_hole(p) and not hole_filled(p) and not _warp_cells.has(p):
			return false
		if not ignore_mask and not emerald_elevation.is_empty():
			var origin := p - dir
			if _mask_blocks(origin, -dir) or not _heights_connect(origin, p):
				return false
		if map_data.has("mechanisms") and not HoennMechanisms.gate(self,p,dir,false): return false
		if not ignore_mask and _mask_blocks(p, dir):
			return false
	if _blocked_by_object(p):
		return false
	for n in npcs:
		var at: Array = n.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == p:
			return false
	return true

## 这一格上的障碍物是否已经被清掉（砍了树、碎了岩、推走石头）
func _is_cleared(p: Vector2i) -> bool:
	for o in objects:
		var k := String(o.get("kind", ""))
		if k != "cut" and k != "rock" and k != "boulder":
			continue
		var at: Array = o.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) != p:
			continue
		if taken.get(_object_key(o), false):
			return true
	return false


## 树、石头、可推的岩块在没处理掉之前是不能走上去的
func _blocked_by_object(p: Vector2i) -> bool:
	for o in objects:
		var k := String(o.get("kind", ""))
		# FRLG bg_events mark text on existing map blocks (even walk-through holes).
		# Solid signposts already have collision in their native layout.
		if k == "sign" and (not emerald_elevation.is_empty() or (map_data.get("region", "") == "johto" and o.has("source_script"))):
			continue
		# 树果树 / 道具球 / 告示牌在原版里都占一格，人不该踩过去
		# 道具球不再挡路：踩上去就自动捡（以前把球也当墙，人永远走不到它那格，
		# 看着有球、碰不到，就是这个原因）
		if k != "cut" and k != "rock" and k != "boulder" and k != "sign" and k != "berry_tree":
			continue
		var at: Array = o.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) != p:
			continue
		var key := _object_key(o)
		if taken.get(key, false):
			continue
		return true
	return false


func elevation_at(p: Vector2i) -> int:
	if p.y < 0 or p.y >= emerald_elevation.size():
		return 0
	var row: Array = emerald_elevation[p.y]
	return int(row[p.x]) if p.x >= 0 and p.x < row.size() else 0

func _heights_connect(origin: Vector2i, target: Vector2i) -> bool:
	var src := elevation_at(origin)
	var dest := elevation_at(target)
	if src == 15:
		src = last_elevation
	if src == 0 or dest in [0, 15] or src == dest:
		return true
	return surfing and ((src == 3 and dest == 1 and is_water(target)) or (src == 1 and dest == 3 and not is_water(target)))

## 土坡：位掩码 1 上 / 2 下 / 4 右 / 8 左 / 16 右上 / 32 左上 / 64 右下 / 128 左下
func ledge_bits(p: Vector2i) -> int:
	if p.y < 0 or p.y >= emerald_ledge.size():
		return 0
	var row: Array = emerald_ledge[p.y]
	if p.x < 0 or p.x >= row.size():
		return 0
	return int(row[p.x])

## 这一格是不是水面（没有 water 表就当作不是）
func is_water(p: Vector2i) -> bool:
	if not is_emerald():
		return tile_at(p) == 2
	if emerald_water.is_empty():
		return false
	if p.y < 0 or p.y >= emerald_water.size():
		return false
	var row: Array = emerald_water[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 1

const LEDGE_BITS := {
	Vector2i(0, -1): 1, Vector2i(0, 1): 2, Vector2i(1, 0): 4, Vector2i(-1, 0): 8,
	Vector2i(1, -1): 16, Vector2i(-1, -1): 32, Vector2i(1, 1): 64, Vector2i(-1, 1): 128,
}

func _ledge_allows(p: Vector2i, dir: Vector2i) -> bool:
	var bits := ledge_bits(p)
	if bits == 0:
		return false
	var m: int = int(LEDGE_BITS.get(dir, 0))
	return m != 0 and bits & m != 0


## 冰面 / 水流：这一格会把站在上面的人推向哪个方向
func _push_dir_of(grid: Array, p: Vector2i) -> Vector2i:
	if grid.is_empty() or p.y < 0 or p.y >= grid.size():
		return Vector2i.ZERO
	var row: Array = grid[p.y]
	if p.x < 0 or p.x >= row.size():
		return Vector2i.ZERO
	var b: int = int(row[p.x])
	if b == 0:
		return Vector2i.ZERO
	for d in LEDGE_BITS:
		if b & int(LEDGE_BITS[d]) != 0:
			return d
	return Vector2i.ZERO


func waterfall_landing(origin: Vector2i) -> Vector2i:
	var top := origin
	while is_waterfall(top + Vector2i.UP):
		if not can_enter(top + Vector2i.UP,Vector2i.UP): return origin
		top += Vector2i.UP
	if top != origin and can_enter(top + Vector2i.UP,Vector2i.UP): top += Vector2i.UP
	return top

## 这一格是不是瀑布
func is_waterfall(p: Vector2i) -> bool:
	if emerald_waterfall.is_empty() or p.y < 0 or p.y >= emerald_waterfall.size():
		return false
	var row: Array = emerald_waterfall[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 1


## 这一格是不是「怪力开关」：原版把石头推上去机关就触发
func is_button(p: Vector2i) -> bool:
	if emerald_button.is_empty() or p.y < 0 or p.y >= emerald_button.size():
		return false
	var row: Array = emerald_button[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 1


## 通用地形查询：坑洞 / 深水 / 漩涡 / 岩壁 / 冰面
func _flag_at(grid: Array, p: Vector2i) -> bool:
	if grid.is_empty() or p.y < 0 or p.y >= grid.size():
		return false
	var row: Array = grid[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 1


func is_hole(p: Vector2i) -> bool:
	return _flag_at(emerald_hole, p)


func is_deep(p: Vector2i) -> bool:
	return _flag_at(emerald_deep, p)


func is_whirl(p: Vector2i) -> bool:
	return _flag_at(emerald_whirl, p)


func is_climb(p: Vector2i) -> bool:
	return _flag_at(emerald_climb, p)


## 冰面：踩上去会顺着走的方向一直滑，直到撞墙或者离开冰面
func is_ice(p: Vector2i) -> bool:
	if emerald_slide.is_empty() or p.y < 0 or p.y >= emerald_slide.size():
		return false
	var row: Array = emerald_slide[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 255


## 坑洞填平之后就是普通地面
func _hole_key(p: Vector2i) -> String:
	return "hole:%s:%d,%d" % [String(map_data.get("id", "")), p.x, p.y]


func hole_filled(p: Vector2i) -> bool:
	return taken.get(_hole_key(p), false)


func fill_hole(p: Vector2i) -> void:
	taken[_hole_key(p)] = true


## 漩涡清掉之后就是普通水面
func _whirl_key(p: Vector2i) -> String:
	return "whirl:%s:%d,%d" % [String(map_data.get("id", "")), p.x, p.y]


func whirl_cleared(p: Vector2i) -> bool:
	return taken.get(_whirl_key(p), false)


func clear_whirl(p: Vector2i) -> void:
	taken[_whirl_key(p)] = true
	if not map_data.has("hgss") or not is_whirl(p): return
	# A native current covers several adjacent cells. One use clears that current.
	var pending: Array[Vector2i] = [p]
	var checked := {p:true}
	while not pending.is_empty():
		var current: Vector2i = pending.pop_back()
		for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next := current+delta
			if is_whirl(next) and not checked.has(next):
				checked[next]=true
				taken[_whirl_key(next)]=true
				pending.append(next)


## 站定之后要不要被地形带着再走一步（冰面打滑 / 洋流）
func auto_step_dir() -> Vector2i:
	if map_data.get("mechanisms",{}).has("base") and preload("res://core/hoenn_base_effects.gd").at(self,player_pos).get("surface")==71 and can_step(Vector2i.DOWN):return Vector2i.DOWN
	if is_ice(player_pos):
		return last_dir if last_dir != Vector2i.ZERO and can_step(last_dir) else Vector2i.ZERO
	var d := _push_dir_of(emerald_slide, player_pos)
	if d != Vector2i.ZERO and can_step(d):
		return d
	d = _push_dir_of(emerald_current, player_pos)
	if d != Vector2i.ZERO and can_step(d):
		return d
	return Vector2i.ZERO

## 土坡落点：越过坡沿，落到前方最近的可行格（最多 3 格）
## 原版是固定跨两格；关都那批坡只有一格宽，按固定两格算会掉进墙里
func jump_landing(dir: Vector2i) -> Vector2i:
	var here := player_pos
	var target := here + dir
	if not emerald_elevation.is_empty():
		var land := here + dir * 2
		if _ledge_allows(target, dir) and can_enter(land, dir, true):
			return land
		return Vector2i(-1, -1)
	var ok := false
	# 坡有两种画法：坡沿在脚下（关都），或坡沿在前面一格（丰缘）
	if ledge_bits(target) != 0 and _ledge_allows(target, dir):
		ok = true
	if ledge_bits(here) != 0 and _ledge_allows(here, dir):
		ok = true
	if not ok:
		return Vector2i(-1, -1)
	# 斜向的坡是原版特有的一格斜跨，正视的坡要跨两格；
	# 坡下的第一格常常被坡本身的图块占着，再往前找，最多到 5 格
	var spans := [1, 2] if (dir.x != 0 and dir.y != 0) else [2, 3, 4, 5]
	for k in spans:
		var land: Vector2i = here + dir * k
		if land.x < 0 or land.y < 0 or land.x >= tile_size.x or land.y >= tile_size.y:
			continue
		if can_enter(land, dir, true):
			return land
	return Vector2i(-1, -1)


## 该不该跳：坡沿在前面一格（丰缘），或坡沿就在脚下（关都）
func hop_wanted(dir: Vector2i) -> bool:
	var target := player_pos + dir
	if ledge_bits(target) != 0 and _ledge_allows(target, dir):
		return true
	if emerald_elevation.is_empty() and ledge_bits(player_pos) != 0 and _ledge_allows(player_pos, dir):
		return not can_enter(target, dir)
	return false


func can_step(dir: Vector2i) -> bool:
	if not _warp_from(player_pos, dir).is_empty():
		return true
	var target := player_pos + dir
	if target.x < 0 or target.y < 0 or target.x >= tile_size.x or target.y >= tile_size.y:
		return false
	# 坡沿是单行道：只准顺着坡的方向过去，反着走一律不行
	var ledge := ledge_bits(target)
	if ledge != 0 and not _ledge_allows(target, dir):
		# Crystal 的单向坡唇是 LAND_TILE，玩家可以沿坡唇横走（26 号道路的通路）。
		# 仍然禁止从坡底逆向上坡，其他地区保留原来的阻挡规则。
		var along_lip := (dir.x != 0 and ledge in [1, 2]) or (dir.y != 0 and ledge in [4, 8])
		if map_data.get("region", "") != "johto" or not along_lip:
			return false
	if ledge_bits(target) != 0 and _ledge_allows(target, dir):
		return jump_landing(dir).x >= 0
	if can_enter(target, dir):
		return true
	return jump_landing(dir).x >= 0


func warp_at(cell: Vector2i) -> Dictionary:
	return _passages.get(cell, {})

# FRLG checks arrows and lateral stairs underfoot on a direction press,
# animated house doors ahead when facing north, and other warps on arrival.
func _warp_from(cell: Vector2i, dir: Vector2i) -> Dictionary:
	var here: Dictionary = _directional_passages.get([cell,dir],_passages.get(cell, {}))
	if WARP_DIR.get(here.get("trigger", ""), Vector2i.ZERO) == dir and dir != Vector2i.ZERO:
		return here
	if dir == Vector2i.UP:
		if cell + dir == quest_door_tile and not quest_door_open:
			return {}
		var front: Dictionary = _passages.get(cell + dir, {})
		if front.has("trainer_gate") and not HoennMechanisms.open_door(taken,front.trainer_gate): return {}
		if front.get("trigger", "") == "door":
			return front
	return {}

func step(dir: Vector2i) -> bool:
	if walking or hoenn_local.get("decor_busy",false):
		return false
	if map_data.has("emerald_original") and not emerald_current.is_empty():
		var current := _push_dir_of(emerald_current,player_pos)
		if current!=Vector2i.ZERO and dir!=current and can_step(current): return false
	match dir:
		Vector2i(0, 1): facing = "down"
		Vector2i(0, -1): facing = "up"
		Vector2i(-1, 0): facing = "left"
		Vector2i(1, 0): facing = "right"
	# Rapid water only permits a downstream step. Waterfall ascends through the field action.
	if dir != Vector2i.DOWN and (is_waterfall(player_pos + dir) or is_waterfall(player_pos)):
		_sync_player()
		return false
	var passage := _warp_from(player_pos, dir)
	if passage.is_empty() and not can_step(dir):
		# 撞墙也要转身：原版顶着墙走，人是会转过脸来的
		_sync_player()
		return false
	if map_data.has("mechanisms") and passage.is_empty(): HoennMechanisms.gate(self,player_pos+dir,dir,true)
	if not emerald_elevation.is_empty() and elevation_at(player_pos) != 15:
		last_elevation = elevation_at(player_pos)
	last_dir = dir
	anim_from = Vector2(player_pos)
	var target := player_pos + dir
	var is_jump := false
	if not passage.is_empty():
		player_pos = Vector2i(int(passage.at[0]), int(passage.at[1]))
	elif hop_wanted(dir):
		# 土坡：跨过坡沿落到坡下的可行格
		player_pos = jump_landing(dir)
		is_jump = true
	else:
		player_pos = target
	# 一上岸就不再是冲浪状态（原版走到浅滩也算上岸）
	if surfing and not is_water(player_pos):
		surfing = false
	jumping = is_jump
	_step_duration = jump_dur if jumping else (run_dur if running and passage.is_empty() else walk_dur)
	walking = true
	walk_timer = walk_carry
	walk_carry = 0.0
	frame_col = 1
	render_pos = anim_from
	_sync_player()
	# 走路时只认门；对话必须按 A，否则贴着 NPC 走过去会自动开口
	if not passage.is_empty():
		_queue_passage(passage)
	else:
		_check_warp()
	return true

## 潜水：对着深水按 A 下潜 / 上浮
func toggle_dive() -> String:
	if not diving:
		if not is_deep(player_pos + _dir_vec()):
			return ""
		diving = true
		surfing = true
		return "潜进深水里了。"
	diving = false
	return "浮了上来。"


## 攀岩：对着岩壁往上翻两格
func climb_up() -> bool:
	var face := player_pos + _dir_vec()
	if not is_climb(face):
		return false
	if map_data.has("hgss"):
		var direction := _dir_vec()
		var field: Dictionary = map_data.hgss
		var behavior := preload("res://core/hgss_field.gd").word(field,face) & 255
		if (behavior==75 and direction.x!=0) or (behavior==76 and direction.y!=0): return false
		var landing := face
		while (preload("res://core/hgss_field.gd").word(field,landing)&255)==behavior:
			landing+=direction
		if not can_enter(landing,direction): return false
		warp_to(landing)
		return true
	# 先踩上岩壁这一格（它是障碍，普通移动进不去，攀岩可以），再往上翻一格
	player_pos = face
	for i in 2:
		var nxt := player_pos + Vector2i(0, -1)
		if nxt.y < 0 or nxt.x < 0 or nxt.x >= tile_size.x or nxt.y >= tile_size.y:
			break
		if is_climb(nxt):
			break
		if not can_enter(nxt, Vector2i(0, -1)):
			break
		player_pos = nxt
	render_pos = Vector2(player_pos)
	_sync_player()
	return true


## 朝水面按 A 上水；已经在海上按 A 下岸
func toggle_surf() -> String:
	var face := player_pos + _dir_vec()
	if not surfing:
		if not is_water(face):
			return ""
		surfing = true
		if not can_enter(face, _dir_vec()) or not step(_dir_vec()):
			surfing = false
			return "这里不能下水。"
		return "用冲浪下水了。"
	if is_water(player_pos):
		if is_water(face) or not can_enter(face, _dir_vec()) or not step(_dir_vec()):
			return "靠近能站立的岸边才能上岸。"
	surfing = false
	return "回到岸上。"

## 立刻结束当前这一步（传送、自检时用，避免卡在半格）
func finish_walk() -> void:
	pending_warp = {}
	walk_carry = 0.0
	walking = false
	jumping = false
	jump_lift = 0.0
	walk_timer = 0.0
	frame_col = 0
	render_pos = Vector2(player_pos)
	_sync_player()

## 原地按 A：不移动，只检查正前方有没有可交互对象
func step_interact() -> void:
	last_event = ""
	if walking:
		return
	var panel := warp_at(player_pos + _dir_vec())
	if panel.get("trigger", "") == "panel":
		_queue_passage(panel)
		return
	# Older authored maps also allow A on a standing warp.
	var row := warp_at(player_pos)
	if not row.is_empty() and not row.has("trigger"):
		_queue_passage(row)
		return
	_check_talk()

func _queue_passage(row: Dictionary) -> void:
	pending_warp = row.to
	if map_data.has("emerald_original"):
		pending_warp=preload("res://core/hoenn_field.gd").destination(map_data,pending_warp,taken,Time.get_time_dict_from_system().hour)
	last_event = "warp:" + JSON.stringify(row.to)

func _check_warp() -> void:
	var row := warp_at(player_pos)
	if not row.is_empty() and row.get("trigger", "step") == "step":
		_queue_passage(row)

## 只有按下 A 才检查对话目标，走路不会自动触发
var last_obj: Dictionary = {}

func _check_talk() -> void:
	var dir_vec := _dir_vec()
	var face := player_pos + dir_vec
	var npc := _npc_at(face)
	# 隔着柜台也能说话：原版柜台（宝可梦中心、商店）就是这样，
	# 人站不上去，但能跟柜台后面的 NPC 对话。往前一格被挡时再看一格。
	if npc.is_empty() and is_desk(face):
		npc = _npc_at(face + dir_vec)
	if not npc.is_empty():
		var index := npcs.find(npc)
		if index>=0 and index*2+1<_npc_nodes.size():
			var sprite: Sprite2D = _npc_nodes[index*2+1]
			var identity := str(sprite.get_meta("johto_identity",""))
			if not identity.is_empty() and not npc.has("apricorn"):
				var turn: String = {"left":"right","right":"left","up":"down","down":"up"}[facing]
				JohtoCast.draw(sprite,identity,turn)
		if map_data.has("emerald_original") and npc.has("source_gfx") and index>=0 and index*2+1<_npc_nodes.size():
			var turn: String={"up":"down","down":"up","left":"right","right":"left"}[facing]
			preload("res://core/hoenn_field.gd").draw(_npc_nodes[index*2+1],npc,turn)
		last_npc = npc
		last_event = "talk:" + String(npc.get("name", ""))
		return
	# 面前没有人的话，看看是不是告示牌 / 道具球 / 树果树 / 翻过的土
	var o := object_at(face)
	if not o.is_empty():
		last_obj = o
		last_event = "obj:" + String(o.get("kind", ""))
		return
	# 脚下踩着的隐藏道具（原版用探宝器，这里站着按 A 也能翻出来）
	var under := object_at(player_pos)
	if not under.is_empty():
		last_obj = under
		last_event = "obj:" + String(under.get("kind", ""))

## 拼过的大地图按位置报具体地名：站在真新镇就不该显示"真新镇～尼比市"
func area_at(pos: Vector2i) -> Dictionary:
	for area in map_data.get("areas", []):
		if pos.y < int(area.get("y0",0)) or pos.y >= int(area.get("y1",0)):
			continue
		if area.has("x0") and (pos.x < int(area.x0) or pos.x >= int(area.x1)):
			continue
		return area
	return {}

func area_name() -> String:
	return str(area_at(player_pos).get("name",map_data.get("name","")))

## HUD 用的一行地名
func display_name() -> String:
	var sub := area_name()
	var full := String(map_data.get("name", ""))
	if sub == "" or sub == full:
		return full
	var region := String(map_data.get("region", ""))
	if region == "kanto":
		return "关都·" + sub
	return full

func _npc_at(p: Vector2i) -> Dictionary:
	for n in npcs:
		var at: Array = n.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == p:
			return n
	return {}

## 柜台 / 桌子：挡人，但南北两侧都是地面，站着能看过去、隔着说话。
## 火红的柜台只有一部分标了 MB_COUNTER，剩下的（带电脑那几格）是靠碰撞位挡的，
## 所以这里按形状判：被挡、且上下一格都能走，就当柜台处理。
func is_desk(p: Vector2i) -> bool:
	if not blocked_by_terrain(p):
		return false
	if is_counter(p):
		return true
	# 只按地形判：NPC 站在柜台后面属于正常情况，不能因为那儿站着人就不把它当柜台
	return not blocked_by_terrain(p + Vector2i(0, -1)) and not blocked_by_terrain(p + Vector2i(0, 1))

## 柜台格：能挡人，但可以隔着一张柜台跟后面的人说话
func is_counter(p: Vector2i) -> bool:
	if p.y < 0 or p.y >= emerald_counter.size():
		return false
	var row: Array = emerald_counter[p.y]
	if p.x < 0 or p.x >= row.size():
		return false
	return int(row[p.x]) == 1

func _dir_vec() -> Vector2i:
	match facing:
		"up": return Vector2i(0, -1)
		"down": return Vector2i(0, 1)
		"left": return Vector2i(-1, 0)
		_: return Vector2i(1, 0)

## 相机别越过地图边界，否则边缘会露出黑底
func _field_actor_scale() -> float:
	if map_data.has("hgss"): return 1.0
	# One Crystal block projects two native walking tiles onto one world cell.
	return 0.5 if str(map_data.get("emerald","")).begins_with("johto_") else 1.0

func _apply_cam_limits() -> void:
	if cam == null:
		return
	cam.zoom = Vector2(3,3) if map_data.get("region","") == "johto" and tile_size.x <= 6 and tile_size.y <= 6 else Vector2(2,2)
	if map_data.has("hgss"):
		var viewport_size := Vector2i(Vector2(480,320)/cam.zoom)
		var bounds := preload("res://core/hgss_field.gd").camera_bounds(map_data,viewport_size)
		cam.limit_left=bounds.position.x
		cam.limit_top=bounds.position.y
		cam.limit_right=bounds.end.x
		cam.limit_bottom=bounds.end.y
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = tile_size.x * TILE
	cam.limit_bottom = tile_size.y * TILE

## 原版图集是横排九帧，顺序不是「每方向三帧」，而是：
## 0 朝南站 / 1 朝北站 / 2 朝西站 / 3,4 朝南走 / 5,6 朝北走 / 7,8 朝西走，
## 朝东一律用朝西镜像。之前按 3x3 分块取帧，走起来会串到别的方向上去。
const FACE_FRAME := {"down": 0, "up": 1, "left": 2, "right": 2}
const WALK_A := {"down": 3, "up": 5, "left": 7, "right": 7}
const WALK_B := {"down": 4, "up": 6, "left": 8, "right": 8}

## 调试/自检用：当前精灵帧号与是否水平翻转
func debug_sprite() -> Dictionary:
	return {"frame": int(_player_sprite.frame), "flip": bool(_player_sprite.flip_h)}

## 操作区占了下半屏，镜头要往人物下方看一点，人物才会落在上半屏中间
var view_shift := 0.0

func _sync_player() -> void:
	if _player_sprite == null:
		return
	var f: int = int(FACE_FRAME.get(facing, 0))
	var afloat := surfing and is_water(player_pos)
	var sheet := PLAYER_SURF if afloat else PLAYER_WALK
	if _player_sprite.texture != sheet:
		_player_sprite.texture = sheet
		_player_sprite.hframes = 3 if afloat else 9
	if not afloat and frame_col == 1:
		f = int(WALK_A.get(facing, 0))
	elif not afloat and frame_col == 2:
		f = int(WALK_B.get(facing, 0))
	_player_sprite.frame = f
	_player_sprite.flip_h = facing == "right"
	# 取整到物理像素：不取整的话像素图会每帧落在半像素上，
	# 描边时粗时细、看着像在抖
	var px: float = round(render_pos.x * TILE)
	var py: float = round(render_pos.y * TILE)
	var lift: float = round(jump_lift)
	# 16x32 的人物图要「脚踩格子下沿」，不是「身子居中」：
	# 居中会让脚多踩下半格，看起来就像站在下面那张桌子上
	var actor_scale := _field_actor_scale()
	_player_sprite.scale = Vector2.ONE * actor_scale
	_player_shadow.scale = _player_sprite.scale
	_player_sprite.position = Vector2(px + TILE / 2, py + TILE * (1.0 - actor_scale) - lift)
	_player_sprite.offset = Vector2(0, 4 if afloat else 0)
	_player_shadow.visible = not afloat
	_player_sprite.z_index = Z_ACTOR + int(render_pos.y) * 2
	_player_shadow.position = Vector2(px + TILE / 2, py + TILE - 2)
	_player_shadow.z_index = Z_ACTOR + int(render_pos.y) * 2 - 1
	if cam:
		# 相机按屏幕像素取整（zoom=2 时 1 屏幕像素 = 0.5 世界像素），
		# 否则背景每帧落在半像素上，整幅画面在轻微地抖
		var z: float = maxf(cam.zoom.x, 0.001)
		cam.position = Vector2(
			round((px + TILE / 2) * z) / z,
			round((py + TILE / 2 + view_shift) * z) / z)

func _mask_at(p: Vector2i, kind: int) -> int:
	var mask := 0
	if tile_at(p + Vector2i(0, -1)) == kind: mask |= 1
	if tile_at(p + Vector2i(1, 0)) == kind: mask |= 2
	if tile_at(p + Vector2i(0, 1)) == kind: mask |= 4
	if tile_at(p + Vector2i(-1, 0)) == kind: mask |= 8
	return mask

## 按名字稳定分配一套 NPC 角色，同一个人每次进来长得一样
const NpcAppearance := preload("res://core/npc_appearance.gd")
const NPC_ROLES := [
	["护士", "nurse"], ["馆主", "brock"], ["水手", "sailor"], ["港口", "sailor"],
	["商人", "man"], ["老板", "man"], ["老伯", "old_man"], ["老人", "old_man"],
	["爷爷", "old_man"], ["少女", "lass"], ["女孩", "lass"], ["少年", "youngster"],
	["小子", "youngster"], ["捕虫", "bug_catcher"], ["登山", "hiker"],
	["训练家", "cooltrainer_m"], ["游客", "camper"], ["旅人", "camper"],
	["登记员", "clerk"], ["前台", "teala"], ["师傅", "man"], ["工", "man"],
	["博士", "expert_m"], ["研究员", "expert_m"], ["居民", "woman"], ["女孩", "lass"], ["男孩", "boy"],
]

func _npc_texture(name: String) -> Texture2D:
	for pair in NPC_ROLES:
		if name.contains(String(pair[0])):
			var path := "res://assets/npc/%s.png" % String(pair[1])
			if ResourceLoader.exists(path):
				var tex: Texture2D = load(path)
				if tex != null:
					return tex
	# 匹配不到时退回一张单帧人物图，绝不能返回玩家的九帧行走图，
	# 否则一张图里有九个人，看着就是"一堆奇怪的小人"
	var fallback := "res://assets/npc/man.png"
	if ResourceLoader.exists(fallback):
		return load(fallback)
	if _npc_textures.is_empty():
		return _player_sprite.texture
	var h := 0
	for i in name.length():
		h = (h * 31 + name.unicode_at(i)) % 100000
	return _npc_textures[h % _npc_textures.size()]

func _texture_for(p: Vector2i, t: int) -> Texture2D:
	if t == 3:
		return _frames[PATH_BASE + _mask_at(p, 3)]
	if t == 2:
		return _frames[WATER_BASE + _mask_at(p, 2)]
	var list: Array = SOLO.get(t, [0])
	if list.size() == 1:
		return _frames[int(list[0])]
	# 整数哈希散开：避免用 x*7+y*13 这类线性式，否则会散出斜条纹
	var h: int = (p.x * 73856093) ^ (p.y * 19349663) ^ ((p.x * p.y) * 83492791)
	h = absi(h)
	return _frames[int(list[h % list.size()])]

const MANSION_FLAG := "mansion_secret_switch"
var mansion_switches: Array[Vector2i] = []
var quest_door_open := false
var quest_door_tile := Vector2i(-2,-2)
var quest_door_flag := ""

func _quest_passage_open(flags: Dictionary) -> bool:
	if quest_door_flag == "ember_ruby_requested":
		return flags.get("got_ember_ruby",false) or flags.get("delivered_ember_ruby",false) or (flags.get("beat_ember_grunt_1",false) and flags.get("beat_ember_grunt_2",false))
	return flags.get(quest_door_flag,false)

func set_mansion_switch(active: bool) -> void:
	if mansion_switches.is_empty():
		return
	taken[MANSION_FLAG] = active
	_rebuild()

func _rebuild(story_flags: Variant = null) -> void:
	for n in _tile_nodes:
		n.queue_free()
	_tile_nodes.clear()

	if map_data.has("hgss"):
		mansion_switches.clear()
		quest_door_flag = ""
		quest_door_tile = Vector2i(-2,-2)
		preload("res://core/hgss_field.gd").draw(self)
		preload("res://core/hgss_azalea.gd").draw(self)
		_draw_npcs()
		_draw_objects()
		apply_light()
		return
	var plan := EmeraldField.plan_for(map_data)
	var mansion: Dictionary = plan.get("mansion",{})
	mansion_switches.clear()
	for xy in mansion.get("statues",[]):
		mansion_switches.append(Vector2i(int(xy[0]),int(xy[1])))
	var overrides: Array = []
	if map_data.has("mechanisms"):
		emerald_collision=map_data.physics.collision.duplicate(true)
		overrides=HoennMechanisms.overrides(self,taken if story_flags==null else story_flags)
		emerald_slide=map_data.physics.get("slide",[]).duplicate(true)
		if map_data.mechanisms.has("hill"):
			var course: Dictionary=preload("res://core/hoenn_hill.gd").course(self)
			emerald_ledge=course.ledge
			emerald_slide=course.slide
		if map_data.mechanisms.has("stairs") and not emerald_slide.is_empty():
			for tile in overrides: emerald_slide[int(tile[1])][int(tile[0])]=0
	if not mansion_switches.is_empty() and taken.has(MANSION_FLAG):
		overrides = mansion.on if taken[MANSION_FLAG] else mansion.off
	var quest_door: Dictionary = plan.get("quest_door",{})
	quest_door_flag = quest_door.get("flag","")
	quest_door_tile = Vector2i(-2,-2)
	quest_door_open = false
	if not quest_door.is_empty():
		quest_door_open = _quest_passage_open(taken if story_flags == null else story_flags)
		var state: Array = quest_door.open if quest_door_open else quest_door.closed
		quest_door_tile = Vector2i(int(state[0]),int(state[1]))
		overrides.append(state)
	if map_data.get("source_id","")=="MAP_JAGGED_PASS":
		var progress: Dictionary = taken if story_flags==null else story_flags
		var states: Dictionary = preload("res://core/hoenn_campaign.gd").data().jagged
		overrides.append_array(states.open if progress.get("h_magma_gate",false) else states.closed)
	if map_data.get("region","") in ["kanto","sevii"]:
		overrides = overrides.duplicate()
		overrides.append_array(preload("res://core/kanto_campaign.gd").tiles(map_data.id,taken if story_flags==null else story_flags))
	for row in overrides:
		emerald_collision[int(row[1])][int(row[0])] = int(row[4])
	if not plan.is_empty():
		var field := EmeraldField.new()
		add_child(field)
		field.setup(self, plan, overrides)
		if map_data.has("mechanisms"): HoennMechanisms.draw(field,self)
		_tile_nodes.append(field)
	else:
		_build_legacy_ground()

	if map_data.get("id","") == preload("res://core/johto_campaign.gd").SWITCH_ROOM:
		preload("res://core/johto_campaign.gd").draw_shutters(self,taken if story_flags==null else story_flags)
	if map_data.get("id","")=="johto_ilex_forest" and taken.get("j_forest_path_clear",false):
		var clear_tile := Sprite2D.new()
		clear_tile.texture = load("res://assets/field/crystal_ilex_cut.png")
		clear_tile.centered = false
		clear_tile.scale = Vector2(0.5,0.5)
		clear_tile.position = Vector2(4,12)*TILE
		clear_tile.z_index = 1
		add_child(clear_tile)
		_tile_nodes.append(clear_tile)
	_draw_npcs()
	_draw_objects()
	apply_light()

func refresh_story_actors(flags: Dictionary) -> void:
	var updated := preload("res://core/frlg_actors.gd").roster(map_data,flags)
	for row in npcs:
		if row.get("form_items",false): updated.append(row)
	npcs = updated
	if map_data.has("mechanisms"):
		HoennMechanisms.adjust_actors(self,npcs)
		_rebuild(flags)
		return
	if map_data.get("id","") == preload("res://core/johto_campaign.gd").SWITCH_ROOM:
		_rebuild(flags)
	elif (not quest_door_flag.is_empty() and _quest_passage_open(flags) != quest_door_open) or (map_data.get("region","") in ["kanto","sevii"] and not preload("res://core/kanto_campaign.gd").field_rules(map_data.id).is_empty()):
		_rebuild(flags)
	else:
		_draw_npcs()

func _draw_npcs() -> void:
	for node in _npc_nodes:
		node.hide()
		node.queue_free()
	_npc_nodes.clear()
	for n in npcs:
		var at: Array = n.get("at", [0, 0])
		var s := Sprite2D.new()
		var johto: bool = map_data.get("region","")=="johto"
		var identity := JohtoCast.character(n) if johto else ""
		var tex: Texture2D
		if n.has("source_gfx") and map_data.has("emerald_original"):
			preload("res://core/hoenn_field.gd").draw(s,n,n.get("facing","down"))
			tex=s.texture
		elif not identity.is_empty():
			s.set_meta("johto_identity",identity)
			JohtoCast.draw(s,identity,JohtoCast.facing(n.get("hgss_facing","down")))
			tex=s.texture
		elif johto and (n.get("name","")=="道具球" or n.has("gives_mon")):
			tex = EmeraldField.prop_texture("pickup")
		elif not n.has("starter_balls"):
			tex = NpcAppearance.texture_for(n)
		if tex == null and not n.has("starter_balls"):
			var gfx := String(n.get("gfx", ""))
			var legacy := "res://assets/npc/%s.png" % gfx
			tex = load(legacy) if gfx != "" and ResourceLoader.exists(legacy) else _npc_texture(str(n.get("name", "")))
		s.texture = tex
		s.scale = Vector2.ONE * _field_actor_scale()
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var sh := Sprite2D.new()
		sh.scale = s.scale
		sh.texture = _shadow_tex
		sh.visible = not n.get("in_water_pose",false) and tex!=null and not (n.has("apricorn") or n.has("gives_mon") or n.get("name","")=="道具球")
		var nz: int = Z_ACTOR + int(at[1]) * 2
		if n.get("source_gfx","")=="OBJ_EVENT_GFX_TRUCK": nz-=1
		sh.z_index = nz - 1
		sh.position = Vector2(int(at[0]) * TILE + TILE / 2, int(at[1]) * TILE + TILE - 2)
		add_child(sh)
		_npc_nodes.append(sh)
		# 同上：脚底对齐格子下沿
		var foot := Vector2(int(at[0]) * TILE + TILE / 2, (int(at[1]) + 1) * TILE)
		s.position = foot
		if tex: s.position.y -= tex.get_height()*s.scale.y*0.5
		if map_data.get("source_id","")=="MAP_INSIDE_OF_TRUCK" and n.get("source_gfx","")=="OBJ_EVENT_GFX_MOVING_BOX":
			s.position+=preload("res://core/hoenn_truck.gd").REST[int(n.local_id)-1]
			sh.visible=false
		if n.has("starter_balls"):
			var offsets := [Vector2(-6,-23),Vector2(6,-23),Vector2(0,-18)]
			for i in int(n.starter_balls):
				var ball := Sprite2D.new()
				ball.texture=EmeraldField.prop_texture("pickup")
				ball.position=offsets[i]
				s.add_child(ball)
		s.z_index = nz
		add_child(s)
		_npc_nodes.append(s)

## NPC and player move on the same clock so the following player stays one step behind.
func play_actor_paths(role: String, npc_path: String, player_path: String) -> void:
	var index := npcs.find_custom(func(n): return n.get("role","") == role)
	if index < 0: return
	var row: Dictionary = npcs[index]
	var sprite: Sprite2D = _npc_nodes[index*2+1]
	var shadow: Sprite2D = _npc_nodes[index*2]
	var npc_position := Vector2i(int(row.at[0]),int(row.at[1]))
	var johto_identity := str(sprite.get_meta("johto_identity",""))
	var emerald: bool = map_data.has("emerald_original") and row.has("source_gfx")
	if johto_identity.is_empty() and not emerald:
		sprite.texture = preload("res://assets/npc/fr_oak_walk.png")
		sprite.hframes = 9
	var actor_face := "down"
	var directions := {"L":Vector2i.LEFT,"R":Vector2i.RIGHT,"U":Vector2i.UP,"D":Vector2i.DOWN}
	var faces := {"L":"left","R":"right","U":"up","D":"down"}
	for i in maxi(npc_path.length(),player_path.length()):
		var tween := create_tween().set_parallel()
		if i<npc_path.length():
			var delta: Vector2i = directions[npc_path[i]]
			npc_position+=delta
			actor_face = faces[npc_path[i]]
			if emerald: preload("res://core/hoenn_field.gd").draw(sprite,row,actor_face,1+i%2)
			elif johto_identity.is_empty():
				sprite.flip_h = actor_face == "right"
				sprite.frame = (WALK_A if i%2 == 0 else WALK_B)[actor_face]
			else: JohtoCast.draw(sprite,johto_identity,actor_face,1+i%2)
			row.at=[npc_position.x,npc_position.y]
			sprite.z_index=Z_ACTOR+npc_position.y*2
			shadow.z_index=sprite.z_index-1
			tween.tween_property(sprite,"position",sprite.position+Vector2(delta)*TILE,0.11)
			tween.tween_property(shadow,"position",shadow.position+Vector2(delta)*TILE,0.11)
		if i<player_path.length():
			facing=faces[player_path[i]]
			frame_col=1+i%2
			player_pos+=Vector2i(directions[player_path[i]])
			tween.tween_method(_render_story_step,render_pos,Vector2(player_pos),0.11)
		await tween.finished
		if emerald: preload("res://core/hoenn_field.gd").draw(sprite,row,actor_face)
		elif johto_identity.is_empty(): sprite.frame = FACE_FRAME[actor_face]
		else: JohtoCast.draw(sprite,johto_identity,actor_face)
	frame_col=0
	_sync_player()

func _render_story_step(position_tiles: Vector2) -> void:
	render_pos=position_tiles
	_sync_player()

func _build_legacy_ground() -> void:
	if is_emerald():
		# 拼过的大地图按块贴，单张纹理不超过手机上限
		if not emerald_chunks.is_empty():
			for c in emerald_chunks:
				var sp := Sprite2D.new()
				sp.texture = load("res://content/emerald_maps/%s" % String(c.get("png", "")))
				sp.centered = false
				var at: Array = c.get("at", [0, 0])
				sp.position = Vector2(int(at[0]) * TILE, int(at[1]) * TILE)
				sp.z_index = 0
				add_child(sp)
				_tile_nodes.append(sp)
		else:
			var big := Sprite2D.new()
			big.texture = load(emerald_png_path)
			big.scale = Vector2(tile_size * TILE) / big.texture.get_size()
			big.centered = false
			big.position = Vector2.ZERO
			big.z_index = 0
			add_child(big)
			_tile_nodes.append(big)
	# 人物之上的那层（屋顶、墙头、树冠、招牌）。原版是 BG1，
	# 精灵夹在 BG1 与 BG2 之间，所以这层必须盖在角色上面。
	_add_overlay()

	for y in tiles.size():
		var row: Array = tiles[y]
		for x in row.size():
			var t: int = int(row[x])
			var s := Sprite2D.new()
			s.texture = _texture_for(Vector2i(x, y), t)
			s.centered = false
			s.position = Vector2(x * TILE, y * TILE)
			add_child(s)
			_tile_nodes.append(s)


func _object_texture(o: Dictionary) -> Texture2D:
	var kind := String(o.get("kind", ""))
	var name := kind
	match kind:
		"item":
			name = "ball"
		"berry_tree":
			name = "tree"
		"soil":
			name = "soil"
		"sign":
			name = "sign"
		"cut":
			name = "cut_tree"
		"rock":
			name = "rock"
		"boulder":
			name = "boulder"
	var path := "res://assets/props/%s.png" % name
	if ResourceLoader.exists(path):
		return load(path)
	return null


# Coordinates are the object's footprint. Taller shrubs extend upward from that cell.
const FIELD_INTERACTIVE := {
	"item": "pickup", "cut": "cut_tree", "rock": "rock", "boulder": "boulder",
	"berry_tree": "berry_tree", "soil": "soil"
}

func _draw_objects() -> void:
	for n in _obj_nodes:
		n.queue_free()
	_obj_nodes.clear()
	var has_emerald := map_data.has("hgss") or not EmeraldField.plan_for(map_data).is_empty()
	for o in objects:
		var flag := String(o.get("flag", ""))
		var key := _object_key(o)
		if taken.get(key, false) or (flag != "" and taken.get(flag, false)) or o.get("baked",false):
			continue
		var kind := String(o.get("kind", ""))
		# The field plan already contains signs, wall maps and bedroom furniture.
		if o.get("native_fixture",false) or kind == "sign" or (kind == "wall_map" and map_data.get("id") == "pallet_town_players_house_2f"):
			continue
		var at: Array = o.get("at", [0, 0])
		var base := Vector2(int(at[0]) * TILE, int(at[1]) * TILE)
		var art_kind := str(FIELD_INTERACTIVE.get(kind, "")) if has_emerald else ""
		var texture := EmeraldField.prop_texture(art_kind) if not art_kind.is_empty() else _object_texture(o)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = false
		sprite.position = base
		if not art_kind.is_empty():
			var size := texture.get_size()
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.position += Vector2((TILE-size.x)/2, TILE-size.y)
		elif texture.get_height() > TILE:
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0,texture.get_height()-TILE,texture.get_width(),TILE)
		sprite.z_index = Z_ACTOR + int(at[1]) * 2 - 1
		add_child(sprite)
		_obj_nodes.append(sprite)


func _object_key(o: Dictionary) -> String:
	var at: Array = o.get("legacy_at", o.get("at", [0, 0]))
	return "%s:%d,%d" % [String(o.get("legacy_map",map_data.get("id",""))), int(at[0]), int(at[1])]


## 这一格上有没有能按 A 的东西
func object_at(p: Vector2i) -> Dictionary:
	if map_data.get("region","")=="kanto":
		var switch := preload("res://core/kanto_campaign.gd").control(map_data.id,p)
		if not switch.is_empty(): return switch
	if p in mansion_switches:
		return {"kind":"mansion_switch","at":[p.x,p.y]}
	for o in objects:
		var at: Array = o.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == p:
			var key := _object_key(o)
			var flag := String(o.get("flag", ""))
			if taken.get(key, false) or (flag != "" and taken.get(flag, false)):
				continue
			var copy: Dictionary = o.duplicate(true)
			copy["_key"] = key
			return copy
	return {}


## 拿真实对象（不是副本），推石头这种要改它
func object_ref(p: Vector2i) -> Dictionary:
	for o in objects:
		var at: Array = o.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == p:
			return o
	return {}


## 怪力：把石头往 dir 方向推一格。推不动就返回 false，调用方负责说话
func push_object(o: Dictionary, dir: Vector2i) -> bool:
	if o.is_empty() or o.has("ice_rest") or taken.has("placed:"+str(o.get("rock_id",""))):
		return false
	var at: Array = o.get("at", [0, 0])
	var from := Vector2i(int(at[0]), int(at[1]))
	var to := from + dir
	if to.x < 0 or to.y < 0 or to.x >= tile_size.x or to.y >= tile_size.y:
		return false
	if o.has("ice_rock"):
		var pit:=warp_at(to)
		if pit.has("ice_pit"):
			var filled:="ice:pit:%d"%int(pit.ice_pit)
			if taken.get(filled,false): return false
			taken[filled]=true
			taken["ice:rock:"+str(o.ice_rock)]=true
			o["dropped"]=true
			objects.erase(o)
			_draw_objects()
			return true
	if map_data.get("id","")=="victoryroad_3f" and to==Vector2i(34,18):
		taken["victory_rock_dropped"]=true
		o["dropped"]=true
		objects.erase(o)
		_draw_objects()
		return true
	# 推坑里就填坑：石头卡进洞里，那格从此能走
	if is_hole(to) and not hole_filled(to):
		fill_hole(to)
		o["filled_hole"] = true
		taken[_object_key(o)] = true
		_draw_objects()
		return true
	# 推水里就沉底：石头没了，水面还是水面（原版就是这么处理的）
	if is_water(to):
		o["sunk"] = true
		taken[_object_key(o)] = true
		_draw_objects()
		return true
	# 目标格必须站得下：不是墙、不是水、没人、没有别的物件
	if not can_enter(to, dir, true):
		return false
	if not object_ref(to).is_empty():
		return false
	o["at"] = [to.x, to.y]
	# 原来那格已经不是障碍了，重画一遍物件层
	_draw_objects()
	return true


func mark_taken(o: Dictionary) -> void:
	var key := String(o.get("_key", ""))
	if key == "":
		key = _object_key(o)
	if key != "":
		taken[key] = true
	var flag := String(o.get("flag", ""))
	if flag != "":
		taken[flag] = true
	_rebuild()


## 天气 / 昼夜染色：不加的话夜里跟白天一样亮
func apply_light() -> void:
	if _night_tint == null:
		_night_tint = CanvasModulate.new()
		add_child(_night_tint)
	var base := Color(1, 1, 1)
	# FireRed maps use the palette assigned to their tileset throughout the day.
	var lit_room: bool = map_data.get("hgss",{}).get("art",{}).get("indoors",false)
	if night > 0.01 and not lit_room and EmeraldField.plan_for(map_data).get("source","") != "pokefirered":
		var t: float = clampf(night, 0.0, 1.0)
		base = Color(1.0 - 0.30 * t, 1.0 - 0.28 * t, 1.0 - 0.12 * t)
	match weather:
		"harsh_sun": base=base.lerp(Color(1,0.83,0.59),0.48)
		"rain", "thunderstorm":
			base = base.darkened(0.18).lerp(Color(0.78, 0.86, 1.0), 0.25)
		"snow":
			base = base.lerp(Color(0.92, 0.96, 1.0), 0.35)
		"sandstorm":
			base = base.lerp(Color(1.0, 0.86, 0.62), 0.45)
		"fog":
			base = base.lerp(Color(0.85, 0.88, 0.9), 0.5)
		"volcanic_ash":
			base = base.lerp(Color(0.7, 0.66, 0.62), 0.4)
		"shade":
			base = base.darkened(0.12)
	_night_tint.color = base
	_sync_weather_fx()
	_sync_dark()


func _sync_dark() -> void:
	if not is_inside_tree():
		return
	if _dark_rect == null:
		_dark_rect = ColorRect.new()
		_dark_rect.color = Color(0, 0, 0, 0.94)
		_dark_rect.z_index = Z_DARK
		_dark_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_dark_rect)
	var vp := get_viewport_rect().size
	_dark_rect.size = vp * 4.0
	_dark_rect.position = Vector2(-vp.x * 1.5, -vp.y * 1.5)
	_dark_rect.visible = dark


func _sync_weather_fx() -> void:
	if not is_inside_tree():
		return
	var want := weather in ["rain", "thunderstorm", "snow", "sandstorm", "volcanic_ash"]
	if _weather_fx == null:
		_weather_fx = CPUParticles2D.new()
		_weather_fx.emitting = false
		_weather_fx.amount = 90
		_weather_fx.lifetime = 1.4
		_weather_fx.z_index = Z_FX
		_weather_fx.local_coords = false
		add_child(_weather_fx)
	if not want:
		_weather_fx.emitting = false
		return
	var vp := get_viewport_rect().size
	_weather_fx.position = cam.position if cam else Vector2.ZERO
	_weather_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_weather_fx.emission_rect_extents = Vector2(vp.x * 0.7, 4)
	_weather_fx.direction = Vector2(0.2, 1)
	_weather_fx.spread = 6.0
	_weather_fx.gravity = Vector2(30, 420)
	match weather:
		"snow":
			_weather_fx.color = Color(1, 1, 1, 0.85)
			_weather_fx.gravity = Vector2(20, 90)
			_weather_fx.initial_velocity_min = 20
			_weather_fx.initial_velocity_max = 50
			_weather_fx.scale_amount_min = 1.5
			_weather_fx.scale_amount_max = 2.5
		"sandstorm":
			_weather_fx.color = Color(0.92, 0.82, 0.6, 0.8)
			_weather_fx.gravity = Vector2(420, 120)
			_weather_fx.direction = Vector2(1, 0.3)
		"volcanic_ash":
			_weather_fx.color = Color(0.75, 0.7, 0.68, 0.8)
			_weather_fx.gravity = Vector2(10, 60)
		_:
			_weather_fx.color = Color(0.75, 0.85, 1.0, 0.7)
			_weather_fx.gravity = Vector2(40, 600)
			_weather_fx.initial_velocity_min = 260
			_weather_fx.initial_velocity_max = 360
			_weather_fx.scale_amount_min = 0.6
			_weather_fx.scale_amount_max = 1.0
	_weather_fx.emitting = true


func _add_overlay() -> void:
	if OS.get_environment("FG_OFF") == "1":
		return
	if not emerald_chunks.is_empty():
		for c in emerald_chunks:
			var fg := "res://content/emerald_maps/%s" % String(c.get("png", "")).replace(".png", "_fg.png")
			if not ResourceLoader.exists(fg):
				continue
			var at: Array = c.get("at", [0, 0])
			_add_fg_rows(load(fg), Vector2(int(at[0]) * TILE, int(at[1]) * TILE), int(at[1]))
		return
	var path := emerald_png_path.replace(".png", "_fg.png")
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		_add_fg_rows(tex, Vector2.ZERO, 0, roundi(tex.get_height() / float(tile_size.y)))


## 前景层按「行」切开放，每行跟着它所在的 y 排序。
## 整张前景压在一个大 z 上会带来两个老问题：站在树后看不见人（对），
## 但站在树前也被树盖住（错）；大图上人物 z 涨过前景后，又变成人踩在树上。
func _add_fg_rows(tex: Texture2D, origin: Vector2, base_row: int, row_h := TILE) -> void:
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var rows := int(ceil(float(h) / float(row_h)))
	for r in rows:
		var top := r * row_h
		var height := mini(row_h, h - top)
		# 只保留这一行真正有内容的像素，空行不建节点
		var empty := true
		for yy in range(top, top + height, 2):
			for xx in range(0, w, 4):
				if img.get_pixel(xx, yy).a > 0.02:
					empty = false
					break
			if not empty:
				break
		if empty:
			continue
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(0, top, w, height)
		var sp := Sprite2D.new()
		sp.texture = at
		sp.centered = false
		sp.scale = Vector2.ONE * float(TILE) / row_h
		sp.position = origin + Vector2(0, r * TILE)
		# 与人物同一套排序，行号大（更靠南）才盖住人
		sp.z_index = Z_ACTOR + (base_row + r) * 2 + 1
		if OS.get_environment("FG_TINT") == "1":
			sp.modulate = Color(1, 0, 1, 0.6)
		add_child(sp)
		_tile_nodes.append(sp)


## 贴花层：在网格之上撒不规则的树冠、灌木、草簇，专门用来打散方格的机械感。
## 位置带亚像素抖动，尺寸也随机，跟瓦片不对齐，所以看不出格子。
func _decorate() -> void:
	for n in _decor_nodes:
		n.queue_free()
	_decor_nodes.clear()
	if _decal_trees.is_empty():
		return
	# 人物之上的那层（屋顶、墙头、树冠、招牌）。原版是 BG1，
	# 精灵夹在 BG1 与 BG2 之间，所以这层必须盖在角色上面。
	_add_overlay()

	for y in tiles.size():
		var row: Array = tiles[y]
		for x in row.size():
			var t: int = int(row[x])
			var h: int = absi((x * 374761393) ^ (y * 668265263))
			var jx := float(h % 11) - 5.0
			var jy := float((h / 11) % 9) - 4.0
			if t == 1 and _decal_trees.size() > 0:
				# 树块上撒树冠，越靠里越密，边缘稀一点，形成自然的疏密
				var edge := _is_tree(x - 1, y) and _is_tree(x + 1, y) and _is_tree(x, y - 1) and _is_tree(x, y + 1)
				var chance := 0.92 if edge else 0.34
				if float(h % 100) / 100.0 < chance:
					var sp := Sprite2D.new()
					sp.texture = _decal_trees[h % _decal_trees.size()]
					sp.centered = true
					sp.position = Vector2(x * TILE + TILE / 2 + jx, y * TILE + TILE / 2 + jy - 4)
					# 大小与明暗都抖一下，才有前后层次
					var sc := 0.74 + float((h / 17) % 46) / 100.0
					sp.scale = Vector2(sc, sc)
					var lum := 0.82 + float((h / 29) % 30) / 100.0
					sp.modulate = Color(lum, lum, lum * 0.98)
					# 树冠跟人物用同一套 y 排序：站在树的南边才被树挡住，
					# 站在北边就走在前头。写死一个大数字会让大图上的人又跑到树上。
					# 树冠要盖住站在它北边的人
					sp.z_index = Z_ACTOR + y * 2 + 1
					add_child(sp)
					_decor_nodes.append(sp)
			elif (t == 0 or t == 11 or t == 4) and _decal_grass.size() > 0:
				# 挨着树的草地铺一层投影，把林缘从草地里"压"出来
				if _decal_shade != null and _is_tree(x, y - 1):
					var sh := Sprite2D.new()
					sh.texture = _decal_shade
					sh.centered = false
					sh.position = Vector2(x * TILE, y * TILE)
					sh.z_index = 3
					sh.modulate = Color(1, 1, 1, 0.9)
					add_child(sh)
					_decor_nodes.append(sh)
				if float((h / 7) % 100) / 100.0 < (0.34 if t == 11 else 0.16):
					var sp2 := Sprite2D.new()
					sp2.texture = _decal_grass[h % _decal_grass.size()]
					sp2.centered = true
					sp2.position = Vector2(x * TILE + TILE / 2 + jx * 0.5, y * TILE + TILE / 2 + jy * 0.5)
					sp2.z_index = 4
					add_child(sp2)
					_decor_nodes.append(sp2)
				elif float((h / 13) % 100) / 100.0 < 0.05 and _decal_bushes.size() > 0:
					var sp3 := Sprite2D.new()
					sp3.texture = _decal_bushes[h % _decal_bushes.size()]
					sp3.centered = true
					sp3.position = Vector2(x * TILE + TILE / 2 + jx, y * TILE + TILE / 2 + jy)
					sp3.z_index = 5
					add_child(sp3)
					_decor_nodes.append(sp3)

func _is_tree(x: int, y: int) -> bool:
	if y < 0 or y >= tiles.size():
		return true
	var row: Array = tiles[y]
	if x < 0 or x >= row.size():
		return true
	return int(row[x]) == 1

## 走一格的时间由这里推进。放在输入轮询之前调用，
## 走完的当帧就能接上下一步，不会每格都顿一帧。
func tick_walk(delta: float) -> void:
	if not walking:
		return
	var dur := _step_duration
	walk_timer += delta
	if walk_timer >= dur:
		walk_carry = 0.0 if jumping else minf(walk_timer - dur, dur * 0.5)
		walking = false
		jumping = false
		jump_lift = 0.0
		walk_timer = 0.0
		frame_col = 0
		render_pos = Vector2(player_pos)
		_sync_player()
		if map_data.has("mechanisms") and pending_warp.is_empty():HoennMechanisms.landed(self)
		if not pending_warp.is_empty():
			var to: Dictionary = pending_warp
			pending_warp = {}
			warp_ready.emit(to)
		return
	var t: float = walk_timer / dur
	# 位移量化成整格内的整数像素步进：一格 16 像素，一格 16 帧，
	# 正好 1 像素/帧。不量化的话浮点位置会在两帧之间来回凑整，
	# 出现"这一帧不动、下一帧跳两下"的抖动，看着就是打滑。
	var span: Vector2 = Vector2(player_pos) - anim_from
	var pix: int = int(floor(t * 16.0 + 0.0001))
	if pix > 16:
		pix = 16
	render_pos = anim_from + span * (float(pix) / 16.0)
	# 跳跃：整格位移之外再抬一段弧线，落地时归零
	jump_lift = sin(PI * t) * 6.0 if jumping else 0.0
	# 原版一步之内是四拍：抬这只腿 → 并腿 → 抬那只腿 → 并腿（3,0,4,0）。
	# 之前整格只有一个中间帧，脚不动人却平移，看着就是贴纸在滑。
	if jumping:
		frame_col = 0
	elif t < 0.25:
		frame_col = 1
	elif t < 0.5:
		frame_col = 0
	elif t < 0.75:
		frame_col = 2
	else:
		frame_col = 0
	_sync_player()

## 传送落点：先把渲染位置和状态一起对齐，否则会先看到人在旧位置闪一下
func warp_to(pos: Vector2i) -> void:
	if elevation_at(pos) not in [0, 15]:
		last_elevation = elevation_at(pos)
	player_pos = pos
	render_pos = Vector2(pos)
	anim_from = Vector2(pos)
	jumping = false
	jump_lift = 0.0
	last_dir = Vector2i.ZERO
	last_event = ""
	walking = false
	walk_timer = 0.0
	walk_carry = 0.0
	frame_col = 0
	pending_warp = {}
	_sync_player()

func arrive(target: Dictionary) -> void:
	var pos := Vector2i(int(target.at[0]), int(target.at[1]))
	if map_data.has("emerald_original") and not target.get("hoenn_native",false) and map_data.has("legacy_size"):
		pos=preload("res://core/hoenn_field.gd").saved_position(self,pos)
	if map_data.has("hgss") and not target.get("hgss",false):
		pos=preload("res://core/hgss_field.gd").position(map_data,pos)
	facing = str(target.get("facing", facing))
	if not is_water(pos):
		surfing = false
		diving = false
	if map_data.has("emerald_original"):
		diving=preload("res://core/hoenn_items.gd").underwater(map_data)
		surfing=not diving and is_water(pos)
	warp_to(pos)
	if target.has("arrival_from"):
		anim_from = Vector2(target.arrival_from[0], target.arrival_from[1])
		render_pos = anim_from
		_step_duration = walk_dur * maxf(1.0, anim_from.distance_to(Vector2(pos)))
		walking = true
		_sync_player()

func _process(_delta: float) -> void:
	if map_data.get("source_id","")=="MAP_SOOTOPOLIS_CITY" and taken.get("h_kyogre",false) and not taken.get("h_peace",false):
		var phase := int(Time.get_ticks_msec()/3400.0)%2
		if phase!=_hoenn_storm_phase:
			_hoenn_storm_phase=phase
			weather="thunderstorm" if phase==0 else "harsh_sun"
			apply_light()
	elif _hoenn_storm_phase!=-1:
		_hoenn_storm_phase=-1
		weather=str(map_data.get("weather",""))
		apply_light()
	# 这个 HUD 只在调试时用，正常游戏里是空的；避免每帧拼字符串
	if hud and hud.visible:
		hud.text = "%s  (%d,%d)" % [String(map_data.get("name", "")), player_pos.x, player_pos.y]
