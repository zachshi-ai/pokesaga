extends Node2D
## 地图渲染与移动。
## 瓦片图集：assets/tiles.png（4 列 × 12 行，16×16）
##   0-15 独立瓦片；16-31 土路 autotile；32-47 水域 autotile
## 地图数据只用地形编号：0 草 1 树 2 水 3 路 4 花 5 石 6 墙 7 屋顶 8 门 9 栅栏 10 沙

const TILE := 16
const ATLAS_PATH := "res://assets/tiles_emerald.png"
const PLAYER_PATH := "res://assets/player_emerald.png"
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

	var sheet: Texture2D = load(PLAYER_PATH)
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
	_player_sprite.texture = sheet
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
	_prev_facing = facing
	map_data = data
	var em: String = String(data.get("emerald", ""))
	if em != "":
		_load_emerald_map(em)
		return
	# 切到自建图（开拓区这类）必须把原版地图的几张表清掉，
	# 否则 is_emerald() 还是 true，碰撞会去读上一张图的表
	emerald_collision = []
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
	var size_arr: Array = data.get("size", [20, 15])
	tile_size = Vector2i(int(size_arr[0]), int(size_arr[1]))
	tiles = data.get("tiles", [])
	npcs = data.get("npcs", []).duplicate(true)
	objects = (data.get("objects", []) as Array).duplicate(true)
	weather = String(data.get("weather", ""))
	var sp: Array = data.get("spawn", [1, 1])
	player_pos = Vector2i(int(sp[0]), int(sp[1]))
	facing = _prev_facing if _prev_facing != "" else "down"
	render_pos = Vector2(player_pos)
	walking = false
	_rebuild()
	_sync_player()

func _load_emerald_map(name: String) -> void:
	var meta_path := "res://content/emerald_maps/%s.json" % name
	var meta: Dictionary = {}
	if FileAccess.file_exists(meta_path):
		meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	emerald_collision = meta.get("collision", [])
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
	npcs = map_data.get("npcs", []).duplicate(true)
	objects = (map_data.get("objects", []) as Array).duplicate(true)
	weather = String(map_data.get("weather", ""))
	dark = bool(map_data.get("dark", false))
	_rebuild()
	_apply_cam_limits()
	_sync_player()

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
	# 非原版地图（开拓区这类自建图）只有 tiles 网格，没有方向阻挡
	if not is_emerald():
		if p.y < 0 or p.y >= tiles.size():
			return false
		var trow: Array = tiles[p.y]
		if p.x < 0 or p.x >= trow.size():
			return false
		var tv := int(trow[p.x])
		if tv == 1 or tv == 2 or tv == 6 or tv == 7:
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
		if int(row[p.x]) != 0:
			return false
		# 水面：只有冲浪时能进；上了岸就自动结束冲浪
		if is_water(p) and not surfing:
			return false
		# 深水只有潜下去才能进；漩涡没清掉过不去；岩壁和没填的坑洞一律挡
		if is_deep(p) and not diving:
			return false
		if is_whirl(p) and not whirl_cleared(p):
			return false
		if is_climb(p):
			return false
		# 坑洞挡人，但原版那种「跳下去到下一层」的坑本身就是传送门，不能挡
		if is_hole(p) and not hole_filled(p) and not _warp_cells.has(p):
			return false
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
	return int(row[p.x]) == 255 or int(row[p.x]) != 0


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


## 站定之后要不要被地形带着再走一步（冰面打滑 / 洋流）
func auto_step_dir() -> Vector2i:
	if is_ice(player_pos) and last_dir != Vector2i.ZERO and can_step(last_dir):
		return last_dir
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
	if ledge_bits(player_pos) != 0 and _ledge_allows(player_pos, dir):
		return not can_enter(target, dir)
	return false


func can_step(dir: Vector2i) -> bool:
	var target := player_pos + dir
	if target.x < 0 or target.y < 0 or target.x >= tile_size.x or target.y >= tile_size.y:
		return false
	# 坡沿是单行道：只准顺着坡的方向过去，反着走一律不行
	if ledge_bits(target) != 0 and not _ledge_allows(target, dir):
		return false
	if ledge_bits(target) != 0 and _ledge_allows(target, dir):
		return jump_landing(dir).x >= 0
	if can_enter(target, dir):
		return true
	return jump_landing(dir).x >= 0


func step(dir: Vector2i) -> bool:
	if walking:
		return false
	match dir:
		Vector2i(0, 1): facing = "down"
		Vector2i(0, -1): facing = "up"
		Vector2i(-1, 0): facing = "left"
		Vector2i(1, 0): facing = "right"
	if not can_step(dir):
		# 撞墙也要转身：原版顶着墙走，人是会转过脸来的
		_sync_player()
		return false
	last_dir = dir
	anim_from = Vector2(player_pos)
	var target := player_pos + dir
	var is_jump := false
	if hop_wanted(dir):
		# 土坡：跨过坡沿落到坡下的可行格
		player_pos = jump_landing(dir)
		is_jump = true
	else:
		player_pos = target
	# 一上岸就不再是冲浪状态（原版走到浅滩也算上岸）
	if surfing and not is_water(player_pos):
		surfing = false
	jumping = is_jump
	walking = true
	walk_timer = walk_carry
	walk_carry = 0.0
	frame_col = 1
	render_pos = anim_from
	_sync_player()
	# 走路时只认门；对话必须按 A，否则贴着 NPC 走过去会自动开口
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
		return "用冲浪下水了。"
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
	# 站在门格上按 A 也能进门（原版就是这样，不用走过去）
	_check_warp()
	if last_event.begins_with("warp:"):
		return
	_check_talk()

func _check_warp() -> void:
	for w in map_data.get("warps", []):
		var at: Array = w.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == player_pos:
			last_event = "warp:" + JSON.stringify(w.get("to", {}))
			pending_warp = w.get("to", {})
			return

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
func area_name() -> String:
	var areas = map_data.get("areas", [])
	if not (areas is Array):
		return String(map_data.get("name", ""))
	for a in areas:
		if not (a is Dictionary):
			continue
		if player_pos.y < int(a.get("y0", 0)) or player_pos.y >= int(a.get("y1", 0)):
			continue
		# 大地图一张图里横跨好几段路，靠 x 区间区分；老的小图没写 x 就当整行
		if a.has("x0") and (player_pos.x < int(a.get("x0", 0)) or player_pos.x >= int(a.get("x1", 9999))):
			continue
		return String(a.get("name", ""))
	return String(map_data.get("name", ""))

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
func _apply_cam_limits() -> void:
	if cam == null:
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
	if frame_col == 1:
		f = int(WALK_A.get(facing, 0))
	elif frame_col == 2:
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
	_player_sprite.position = Vector2(px + TILE / 2, py - lift)
	_player_sprite.offset = Vector2.ZERO
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

func _rebuild() -> void:
	for n in _tile_nodes:
		n.queue_free()
	_tile_nodes.clear()
	for n in _npc_nodes:
		n.queue_free()
	_npc_nodes.clear()

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

	for n in npcs:
		var at: Array = n.get("at", [0, 0])
		var s := Sprite2D.new()
		var gfx := String(n.get("gfx", ""))
		var tex: Texture2D = null
		if gfx != "" and ResourceLoader.exists("res://assets/npc/%s.png" % gfx):
			tex = load("res://assets/npc/%s.png" % gfx)
		if tex == null:
			tex = _npc_texture(String(n.get("name", "")))
		s.texture = tex
		s.hframes = 1
		s.vframes = 1
		s.centered = true
		s.frame = 0
		s.modulate = Color(1.0, 1.0, 1.0)
		var sh := Sprite2D.new()
		sh.texture = _shadow_tex
		var nz: int = Z_ACTOR + int(at[1]) * 2
		sh.z_index = nz - 1
		sh.position = Vector2(int(at[0]) * TILE + TILE / 2, int(at[1]) * TILE + TILE - 2)
		add_child(sh)
		_npc_nodes.append(sh)
		# 同上：脚底对齐格子下沿
		s.position = Vector2(int(at[0]) * TILE + TILE / 2, int(at[1]) * TILE)
		s.offset = Vector2.ZERO
		s.z_index = nz
		add_child(s)
		_npc_nodes.append(s)
	_draw_objects()
	apply_light()

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


func _draw_objects() -> void:
	for n in _obj_nodes:
		n.queue_free()
	_obj_nodes.clear()
	for o in objects:
		var flag := String(o.get("flag", ""))
		var key := _object_key(o)
		if taken.get(key, false) or (flag != "" and taken.get(flag, false)):
			continue
		var at: Array = o.get("at", [0, 0])
		# 告示牌不额外画立牌：原版地图里牌子本来就画在图块上了，
		# 再叠一个精灵就成了"满地立牌"。这里只保留可交互的透明点。
		if String(o.get("kind", "")) == "sign":
			continue
		var tex := _object_texture(o)
		if tex == null:
			continue
		var sp := Sprite2D.new()
		var kind0 := String(o.get("kind", ""))
		# 贴图比格子高的（球、树）以前按"底边对齐"往上顶了整整一格，
		# 看着像浮在上一行，人站过去却按不到。这里让贴图严格落在自己这一格里。
		sp.texture = tex
		sp.centered = false
		# 球的高光/影子在贴图上沿，直接摆会浮到上一行、看着在脑袋顶上飞；
		# 只取最下面一格像素，让它老实待在自己这格里
		var th := tex.get_height()
		if th > TILE:
			sp.region_enabled = true
			sp.region_rect = Rect2(0, th - TILE, tex.get_width(), TILE)
		sp.position = Vector2(int(at[0]) * TILE, int(at[1]) * TILE)
		# 物件与本行前景同层再高 1：既不被同一行的树冠盖住，
		# 又低于站在它正下方那格的人（人的 z 是行号*2）
		# 比站在同一行的人低一层：人走到球上时人压在球上，不会被球糊住
		sp.z_index = Z_ACTOR + int(at[1]) * 2 - 1
		add_child(sp)
		_obj_nodes.append(sp)


func _object_key(o: Dictionary) -> String:
	var at: Array = o.get("at", [0, 0])
	return "%s:%d,%d" % [String(map_data.get("id", "")), int(at[0]), int(at[1])]


## 这一格上有没有能按 A 的东西
func object_at(p: Vector2i) -> Dictionary:
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
	if o.is_empty():
		return false
	var at: Array = o.get("at", [0, 0])
	var from := Vector2i(int(at[0]), int(at[1]))
	var to := from + dir
	if to.x < 0 or to.y < 0 or to.x >= tile_size.x or to.y >= tile_size.y:
		return false
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
	if night > 0.01:
		var t: float = clampf(night, 0.0, 1.0)
		base = Color(1.0 - 0.30 * t, 1.0 - 0.28 * t, 1.0 - 0.12 * t)
	match weather:
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
		_add_fg_rows(load(path), Vector2.ZERO, 0)


## 前景层按「行」切开放，每行跟着它所在的 y 排序。
## 整张前景压在一个大 z 上会带来两个老问题：站在树后看不见人（对），
## 但站在树前也被树盖住（错）；大图上人物 z 涨过前景后，又变成人踩在树上。
func _add_fg_rows(tex: Texture2D, origin: Vector2, base_row: int) -> void:
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0:
		return
	var row_h := TILE
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
		sp.position = origin + Vector2(0, top)
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
	var dur: float = jump_dur if jumping else (run_dur if running else walk_dur)
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
	player_pos = pos
	render_pos = Vector2(pos)
	anim_from = Vector2(pos)
	walking = false
	walk_timer = 0.0
	walk_carry = 0.0
	frame_col = 0
	pending_warp = {}
	_sync_player()

func _process(_delta: float) -> void:
	# 这个 HUD 只在调试时用，正常游戏里是空的；避免每帧拼字符串
	if hud and hud.visible:
		hud.text = "%s  (%d,%d)" % [String(map_data.get("name", "")), player_pos.x, player_pos.y]
