extends RefCounted
## 存档：单档跨地区。一个文件装下位置、队伍、图鉴标记、各地区进度。
## 用 JSON 起步，字段稳定后可以换成二进制，但结构不变。

const PATH := "user://save.json"
const VERSION := 2

static func empty() -> Dictionary:
	return {
		"version": VERSION,
		# 新档落在关都·真新镇的出生点（和 content/regions/kanto/region.json 的 start 一致）。
		# 之前这里写的是 [10, 8]，那是尼比市（道馆城市）中间，一开局就被扔到城里去了。
		"region": "kanto",
		"map": "kanto_main",
		"pos": [24, 217],
		"party": [],
		"money": 3000,
		"badges": [],
		"defeated": {},
		"flags": {},
		"dex_seen": [],
		"dex_caught": [],
		"play_time": 0.0,
	}

static func save(data: Dictionary) -> bool:
	data["version"] = VERSION
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return empty()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return empty()
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or not (parsed is Dictionary):
		return empty()
	var base := empty()
	for k in parsed.keys():
		base[k] = parsed[k]
	return base
