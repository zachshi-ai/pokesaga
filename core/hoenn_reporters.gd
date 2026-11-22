extends RefCounted
const ROUTES := ["111","118","120"]

static func visible(n: Dictionary,f: Dictionary) -> int:
	var sc:=str(n.get("source_script",""))
	if not sc.begins_with("GabbyAndTy_EventScript_"):return -1
	var flag:=str(n.get("source_flag",""))
	var round:=int(f.get("h_reporter_wins",0))
	var idx:=round%3
	var group:=mini(2 if idx==2 else 3,1+floori(float(round)/3))
	return int(flag=="FLAG_HIDE_ROUTE_%s_GABBY_AND_TY_%d"%[ROUTES[idx],group])

static func talk(g,n: Dictionary) -> bool:
	if not str(n.get("source_script","")).begins_with("GabbyAndTy_EventScript_"):return false
	var f: Dictionary=g._flags()
	if visible(n,f)!=1:return false
	var ready:=0
	for m in g.save_data.party:
		if m is Dictionary and not m.is_empty() and int(m.get("hp",0))>0:ready+=1
	if ready<2:g._dialog(["我们要录一场双打比赛，请带来两只可以战斗的伙伴。"],"电视台记者");return true
	var round:=int(f.get("h_reporter_wins",0))
	var team: Array=load("res://core/hoenn_campaign.gd").data().teams["GABBY_AND_TY_%d"%mini(6,round+1)]
	g._pick("采访开始前，可以录下你的一场双打比赛吗？",["对战","以后再来"],func(i):
		if i!=0:return
		g._start_battle({"name":"电视台记者玛莉和达伊","battle":{"double":true,"team":team}},func(outcome):
			if outcome!="a":
				if outcome=="b" and g._party_fainted():g._blackout()
				return
			f.h_reporter_wins=mini(255,round+1)
			g.world.refresh_story_actors(f)
			g._persist()
			var words:=["伙伴","努力","冒险","胜利","不接受采访"]
			g._pick("用一个词来形容刚才的比赛？",words,func(j):
				if j==4:return
				f.h_reporter_quote=words[j]
				g._persist()
				g._dialog(["谢谢你！这段采访很快就会在电视上播出。"],"记者玛莉"))))
	return true
