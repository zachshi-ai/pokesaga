extends RefCounted
## 存档：单档跨地区。一个文件装下位置、队伍、图鉴标记、各地区进度。
## 用 JSON 起步，字段稳定后可以换成二进制，但结构不变。

const PATH := "user://save.json"
const VERSION := 2
static var slot := PATH

static func use_test_slot() -> void:
	slot = "user://selftest-%s-%s.json" % [OS.get_process_id(), Time.get_ticks_usec()]

static func clear_test_slot() -> void:
	if slot != PATH:
		for suffix in ["", ".previous", ".tmp", ".previous.tmp"]:
			if FileAccess.file_exists(slot + suffix):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(slot + suffix))
	slot = PATH


static func empty() -> Dictionary:
	return {
		"version": VERSION,
		# 新档落在关都·真新镇的出生点（和 content/regions/kanto/region.json 的 start 一致）。
		"region": "kanto",
		"map": "pallet_town_players_house_2f",
		"pos": [3, 6],
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
	var temp_path := slot + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(slot)) == OK

static func new_game() -> bool:
	if FileAccess.file_exists(slot):
		var path := ProjectSettings.globalize_path(slot)
		if DirAccess.copy_absolute(path, path + ".previous.tmp") != OK:
			return false
		if DirAccess.rename_absolute(path + ".previous.tmp", path + ".previous") != OK:
			return false
	return save(empty())

## Used by the title screen. An invalid save stays on disk until the player confirms replacement.
static func existing() -> Dictionary:
	if not FileAccess.file_exists(slot):
		return {}
	var f := FileAccess.open(slot, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or not parsed.get("region") is String or not parsed.get("map") is String:
		return {}
	var base := empty()
	base.merge(parsed, true)
	if not parsed.has("pos"):
		base["pos"] = []
	return base

static func load_game() -> Dictionary:
	var data := existing()
	return empty() if data.is_empty() else data
