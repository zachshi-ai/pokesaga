extends RefCounted
## 剧情引擎：事件写在 content/story/<region>.json，代码里不写死任何一段对话。
##
## 每条事件 = 触发条件 + 前提条件 + 一串步骤。
##   触发：map_enter（进入地图）/ talk（跟某个 NPC 说话）/ badge（拿到某枚徽章）
##   前提：flags_all / flags_none / has_party / party_empty
##   步骤：say（对话）/ flag（置标记）/ give_mon（给宝可梦）/ give_item（给道具）/ heal（治疗）
##
## 剧情只管"发生什么"，谁触发、怎么播都由外层决定。

const DIR := "res://content/story/"

var events: Array = []        # 本地区全部事件
var region_id := ""

func load_region(rid: String) -> bool:
	region_id = rid
	events = []
	var path := DIR + rid + ".json"
	if not FileAccess.file_exists(path):
		return false
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	if raw == null or not (raw is Dictionary):
		return false
	var list = (raw as Dictionary).get("events", [])
	if list is Array:
		events = list
	return true

## 找第一条满足条件的未完成事件
func take(kind: String, ctx: Dictionary, flags: Dictionary, has_party: bool) -> Dictionary:
	for ev in events:
		if not (ev is Dictionary):
			continue
		if _finished(ev, flags):
			continue
		if not _trigger_match(ev, kind, ctx):
			continue
		if not _require_match(ev, flags, has_party):
			continue
		return ev
	return {}

func _finished(ev: Dictionary, flags: Dictionary) -> bool:
	var id := String(ev.get("id", ""))
	if id == "":
		return true
	if not bool(ev.get("once", true)):
		return false
	return bool(flags.get("story_" + id, false))

func _trigger_match(ev: Dictionary, kind: String, ctx: Dictionary) -> bool:
	var tr: Dictionary = ev.get("trigger", {})
	if String(tr.get("type", "")) != kind:
		return false
	match kind:
		"map_enter":
			var m := String(tr.get("map", ""))
			return m == "" or m == String(ctx.get("map", ""))
		"talk":
			var who := String(tr.get("npc", ""))
			if who != "" and who != String(ctx.get("npc", "")):
				return false
			var tm := String(tr.get("map", ""))
			return tm == "" or tm == String(ctx.get("map", ""))
		"badge":
			return String(tr.get("badge", "")) == String(ctx.get("badge", ""))
		"step":
			# 同一张大图里也分段触发（真新镇 → 1 号道路不用切图）
			var sm := String(tr.get("map", ""))
			if sm != "" and sm != String(ctx.get("map", "")):
				return false
			var area = tr.get("area", [])
			if not (area is Array) or (area as Array).size() != 4:
				return false
			var px := int(ctx.get("x", -1))
			var py := int(ctx.get("y", -1))
			return px >= int(area[0]) and py >= int(area[1]) and px < int(area[2]) and py < int(area[3])
	return false

func _require_match(ev: Dictionary, flags: Dictionary, has_party: bool) -> bool:
	var rq = ev.get("require", {})
	if not (rq is Dictionary):
		return true
	var r: Dictionary = rq
	for k in r.get("flags_all", []):
		if not bool(flags.get(String(k), false)):
			return false
	for k in r.get("flags_none", []):
		if bool(flags.get(String(k), false)):
			return false
	if r.has("has_party") and bool(r["has_party"]) != has_party:
		return false
	return true

## 事件播完：记下完成标记，保证 once 的事件不会再放一遍
func mark_finished(ev: Dictionary, flags: Dictionary) -> void:
	var id := String(ev.get("id", ""))
	if id != "":
		flags["story_" + id] = true
