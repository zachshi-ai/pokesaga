extends RefCounted
## Title Defense keeps a separate current run. The original championship and ending remain in the shared save.
const ROOMS := {"fighting":["哈拉",349],"rock":["丽姿",351],"ghost":["阿塞萝拉",350],"flying":["卡希丽",352]}
const CHALLENGERS := {"哈乌":[356,357,358],"格拉吉欧":[417,418,419],"库库伊":[477,478,479],"哈普乌":359,"布尔美丽":401,"龙葵":409,"马玛内":405,"小明":480,"扎奥博":410,"露莎米奈":644,"古兹马":647,"马睿因":481}
const FLAG := "a_title_active"

static func challengers(f: Dictionary, day: int, now: int) -> Array:
	var ultra: bool=str(f.a_version).begins_with("ultra")
	if int(f.get("a_defenses",0))==0:return ["哈乌"]
	if day==1:return ["露莎米奈" if ultra else "扎奥博"]
	var pool:=["哈乌","库库伊","哈普乌","布尔美丽","龙葵","马玛内","小明","古兹马" if ultra else "马睿因"]
	if not ultra or (f.get("as_rr_end",false) and int(f.get("as_rr_completed_at",now))<=now-30*86400):pool.append("格拉吉欧")
	return pool

static func gate(mid: String,f: Dictionary) -> String:
	if not f.get("a_credits",false):return ""
	if mid.begins_with("alola_e4_") or mid=="alola_champion_room":
		if not f.get(FLAG,false):return "先在联盟大厅登记这次卫冕。"
		if mid=="alola_champion_room":
			for room in ROOMS:
				if not f.get("a_title_"+room,false):return "本轮还要通过四位天王的挑战。"
	return ""

static func event(mid: String,f: Dictionary) -> Array:
	if not f.get("a_credits",false):return []
	var row: Dictionary
	var who: String
	var id: String
	var msg: String
	var steps: Array=[]
	if mid=="alola_league" and not f.get(FLAG,false):
		who="联盟向导";id="a_title_enter";msg="冠军，四天王都已就位。开始新一轮卫冕吧！"
		steps=[{"alola_defend":"start"}]
	elif mid.begins_with("alola_e4_") and f.get(FLAG,false):
		var room:=mid.trim_prefix("alola_e4_")
		if not ROOMS.has(room):return []
		var opponent:Array=["马睿因",490] if room=="fighting" and str(f.a_version).begins_with("ultra") else ROOMS[room]
		who=opponent[0];id="a_title_"+room;msg="欢迎回来，冠军！这次请面对我们磨炼过的新队伍。"
		steps=[{"battle":{"name":who,"alola_team":opponent[1]}},{"flag":id}]
	elif mid=="alola_champion_room" and f.get(FLAG,false) and gate(mid,f).is_empty():
		who=f.get("a_title_opponent","哈乌");id="a_title_challenger";msg="我已经准备好向阿罗拉冠军发起挑战了。来吧，小悠！"
		var source=CHALLENGERS[who]
		var cfg:={"name":who}
		cfg["alola_variants" if source is Array else "alola_team"]=source
		steps=[{"battle":cfg},{"alola_defend":"won"},{"alola_warp":"alola_home"}]
	else:return []
	row={"id":id,"who":who,"map":mid,"anchor":"story","require":["a_credits"],"steps":[{"who":who,"say":[msg]}]+steps}
	return [row]

static func clear(f: Dictionary) -> void:
	for room in ROOMS:
		f.erase("a_title_"+room)
		f.erase("story_a_title_"+room)
	f.erase(FLAG)
	f.erase("a_title_opponent")

static func act(g,what: String) -> void:
	var f: Dictionary=g._flags()
	if what=="start":
		var now:=int(Time.get_unix_time_from_system())
		if f.get("as_rr_end",false) and not f.has("as_rr_completed_at"):f.as_rr_completed_at=now
		var day:=int(Time.get_date_dict_from_system().day)
		var pool:=challengers(f,day,now)
		f.a_title_opponent=pool[g.rng.randi_range(0,pool.size()-1)]
		f[FLAG]=true
	else:
		f.a_title_last=f.get("a_title_opponent","哈乌")
		f.a_defenses=int(f.get("a_defenses",0))+1
		clear(f)
	g._persist()
