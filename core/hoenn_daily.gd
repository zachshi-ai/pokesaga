extends RefCounted
const COMMON := ["cheri","chesto","pecha","rawst","aspear","leppa","oran","persim","lum","sitrus"]
const MASTER := ["pomeg","kelpsy","qualot","hondew","grepa","tamato","cornn","magost","rabuta","nomel"]
const SAYINGS := {"精彩|战斗":"spelon","挑战|华丽大赛":"pamtre","压倒性的|拉帝亚斯":"watmel","帅气|拉帝欧斯":"durin","超级|干劲":"belue"}
const WORDS := ["精彩","挑战","压倒性的","帅气","超级","快乐"]
const ENDINGS := ["战斗","华丽大赛","拉帝亚斯","拉帝欧斯","干劲","旅行"]
const DAILY := {
	"Route123_BerryMastersHouse_EventScript_BerryMaster":"master",
	"Route123_BerryMastersHouse_EventScript_BerryMastersWife":"wife",
	"Route104_PrettyPetalFlowerShop_EventScript_RandomBerryGirl":"florist",
	"Route114_EventScript_Man":"route114",
	"SootopolisCity_EventScript_Kiri":"kiri",
	"LilycoveCity_DepartmentStore_1F_EventScript_LotteryClerk":"loto",
}

static func date_number() -> int:
	return floori(float(Time.get_unix_time_from_datetime_dict(Time.get_date_dict_from_system()))/86400.0)

static func wild_news(g) -> void:
	if not g.world.map_data.has("emerald_original") or not g._flags().get("h_champion",false):return
	var today:=date_number()
	var f: Dictionary=g._flags()
	if int(f.get("h_blender_news",-1))>=today or g.rng.randi_range(1,4)!=4:return
	f.h_blender_news=today+4
	f.h_blender_broadcast=false

static func blender_active(f: Dictionary) -> bool:
	return int(f.get("h_blender_news",-1))==date_number() and f.get("h_blender_broadcast",false)

static func television(g,script: String) -> bool:
	if script=="EmeraldRoamingTV" and preload("res://core/emerald_lilycove_lady.gd").television(g):return true
	var f: Dictionary=g._flags()
	if script!="EmeraldRoamingTV" or not f.has("h_roaming_species") or not f.has("h_blender_news"):return false
	var days:=int(f.h_blender_news)-date_number()
	if days<0 or days>4:return false
	f.h_blender_broadcast=true
	g._persist()
	g._dialog(["混合名人今天在水静市华丽大赛大厅，带上你的树果去见他吧！" if days==0 else "丰缘新闻：混合名人将在 %d 天后到访水静市华丽大赛大厅。"%days],"电视播报员")
	return true

static func random_berry(g,group: Array) -> String:
	return group[g.rng.randi_range(0,group.size()-1)]

static func berries(g,who: String,keys: Array,day: String) -> void:
	var names: Array=[]
	for key in keys:
		var name_text: String=g.get_node("/root/Data").berry_name(key)
		g._give_bag_item(name_text,"berry","",key)
		names.append(name_text)
	g._flags()["h_daily_"+who]=day
	g._persist()
	g._dialog(["收到了%s。"% "和".join(names)])

static func talk(g,script: String) -> bool:
	if not DAILY.has(script):return false
	var who: String=DAILY[script]
	var day:=Time.get_date_string_from_system()
	var flags: Dictionary=g._flags()
	if who=="kiri" and flags.get("h_duel",false) and not flags.get("h_peace",false):
		g._dialog(["那两只巨大的宝可梦……我希望大家都平安。"],"琪莉");return true
	if str(flags.get("h_daily_"+who,""))==day:
		g._dialog(["今天已经领过了，明天再来吧。" if who!="loto" else "今天的彩票已经核对过了。"]);return true
	match who:
		"master":berries(g,who,[random_berry(g,MASTER),random_berry(g,MASTER)],day)
		"florist":berries(g,who,[random_berry(g,COMMON.slice(0,8))],day)
		"route114":berries(g,who,[random_berry(g,["razz","bluk","nanab","wepear","pinap"])],day)
		"kiri":berries(g,who,[random_berry(g,MASTER),random_berry(g,["figy","iapapa"])],day)
		"wife":
			g._pick("有什么好词句吗？选择第一个词。",WORDS,func(i):
				var endings:=ENDINGS.duplicate()
				var seen: Array=g.save_data.get("dex",{}).get("seen",g.save_data.get("dex_seen",[]))
				for pair in [["拉帝亚斯",380],["拉帝欧斯",381]]:
					if not seen.any(func(s):return str(s)==str(pair[1])):endings.erase(pair[0])
				g._pick("「%s」　选择第二个词。"%WORDS[i],endings,func(j):
					var rare: String=SAYINGS.get(WORDS[i]+"|"+endings[j],"")
					var key:=rare
					if rare=="" or flags.get("h_saying_"+rare,false):key=random_berry(g,COMMON)
					else:flags["h_saying_"+rare]=true
					berries(g,who,[key],day)))
		"loto":
			g._pick("要抽取今天的宝可梦彩票号码吗？",["抽取并核对","离开"],func(i):
				if i==0:lottery(g,day))
	return true

static func lottery(g,day: String) -> void:
	var f: Dictionary=g._flags()
	if f.get("h_daily_loto","")==day:return
	if not g.save_data.has("js_trainer_id"):g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
	var ticket: int=g.rng.randi_range(0,65535)
	var entrants: Array=g.save_data.party.duplicate()
	for box in g.save_data.get("boxes",[]):entrants.append_array(box.get("mons",[]))
	var best:=0
	var winner:=""
	for mon in entrants:
		if not mon is Dictionary or mon.is_empty() or mon.get("is_egg",false):continue
		var n:=preload("res://core/crystal_phone.gd").match_digits(int(mon.get("ot_id",g.save_data.js_trainer_id)),ticket)
		if n>best:
			best=n
			winner=mon.name
	var prize: String=["","","PP 提升剂","学习装置","活力块","大师球"][best]
	if best==3:g._give_bag_item(prize,"held","EXP_SHARE")
	elif best>=2:g._give_item(prize,1,"ball" if best==5 else "heal")
	f.h_daily_loto=day
	g._persist()
	g._dialog(["今天的彩票号码是 %05d。"%ticket,"恭喜！%s 的训练家编号末 %d 位吻合，你获得了%s！"%[winner,best,prize] if best>=2 else "队伍和电脑里伙伴的训练家编号都没对上末两位。"],"彩票柜台")
