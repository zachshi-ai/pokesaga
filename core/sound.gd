extends Node
## 声音：BGM 按场景换曲（曲子是火红原版 MIDI 合成出来的），SFX 走短音效。
## 音频文件在 assets/audio/bgm/*.ogg、assets/audio/sfx/*.wav。

var bgm: AudioStreamPlayer
var sfx_pool: Array = []
var cur_key := ""
var music_on := true
var sfx_on := true
var _cache: Dictionary = {}
var _fade := 0.0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		music_on = false
		sfx_on = false
	bgm = AudioStreamPlayer.new()
	bgm.bus = "Master"
	bgm.volume_db = -8.0
	add_child(bgm)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -6.0
		add_child(p)
		sfx_pool.append(p)


func _load_stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return null
	var s: AudioStream = load(path)
	_cache[path] = s
	return s


## 按地图类型选曲：城里、道路、洞里、道馆、宝可梦中心各有各的曲子
func music_key_for(map_id: String, area: String, indoor: bool) -> String:
	var mid := map_id.to_lower()
	var area_l := area.to_lower()
	if mid.contains("silph") or mid.contains("rocket"):
		return "silph"
	if mid.contains("gym"):
		return "gym"
	if mid.contains("pokemoncenter") or mid.contains("pokemon_center"):
		return "center"
	if mid.contains("tower"):
		return "tower"
	if mid.contains("cave") or mid.contains("tunnel") or mid.contains("mansion") or mid.contains("seafoam") or mid.contains("victoryroad") or mid.contains("mt_moon"):
		return "cave"
	if mid.contains("sevii") or mid.contains("one_island") or mid.contains("two_island") or mid.contains("three_island") or mid.contains("four_island") or mid.contains("five_island") or mid.contains("six_island") or mid.contains("seven_island"):
		return "sevii"
	if area_l.contains("道路") or area_l.contains("号"):
		return "route"
	if indoor:
		return "city"
	return "town"


func play_music(key: String) -> void:
	if key == "" or key == cur_key:
		return
	var s := _load_stream("res://assets/audio/bgm/%s.ogg" % key)
	if s == null:
		return
	cur_key = key
	bgm.stream = s
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	bgm.volume_db = -8.0
	if music_on:
		bgm.play()


func stop_music() -> void:
	cur_key = ""
	bgm.stop()


func play_sfx(key: String) -> void:
	var s := _load_stream("res://assets/audio/sfx/%s.wav" % key)
	if s == null or not sfx_on:
		return
	for p in sfx_pool:
		if not (p as AudioStreamPlayer).playing:
			(p as AudioStreamPlayer).stream = s
			(p as AudioStreamPlayer).play()
			return
	(sfx_pool[0] as AudioStreamPlayer).stream = s
	(sfx_pool[0] as AudioStreamPlayer).play()


## 战斗换曲，回来再换回来
func battle_music(wild: bool) -> void:
	play_music("battle_wild" if wild else "battle_trainer")


func restore_music(key: String) -> void:
	play_music(key)
