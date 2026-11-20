extends RefCounted
## 存档：单档跨地区。一个文件装下位置、队伍、图鉴标记、各地区进度。
## 用 JSON 起步，字段稳定后可以换成二进制，但结构不变。

const PATH := "user://save.json"
const VERSION := 2
static var slot := PATH

static func use_test_slot() -> void:
	slot = "user://selftest-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]

static func clear_test_slot() -> void:
	if slot != PATH and FileAccess.file_exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot))
	slot = PATH


static func empty() -> Dictionary:
	return {
		"version": VERSION,
		# 新档落在关都·真新镇的出生点（和 content/regions/kanto/region.json 的 start 一致）。
		"region": "kanto",
		"map": "kanto_main",
		"pos": [],
		"party": [],
		"money": 3000,
		"badges": [],
		"defeated": {},
		"flags": {},
		"dex_seen": [],
		"dex_caught": [],
		"dex_variants": {},
		"play_time": 0.0,
	}

static func save(data: Dictionary) -> bool:
	data["version"] = VERSION
	var f := FileAccess.open(slot, FileAccess.WRITE)
	if f == null:
		push_error("存档写入失败")
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true

static func load_game() -> Dictionary:
	if not FileAccess.file_exists(slot):
		return empty()
	var f := FileAccess.open(slot, FileAccess.READ)
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
