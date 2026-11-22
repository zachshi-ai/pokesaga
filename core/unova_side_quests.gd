extends RefCounted

const FR := preload("res://core/frlg_sidequests.gd")
const Field := preload("res://core/unova_field.gd")
const Party := preload("res://core/party.gd")
const Fusion := preload("res://core/fusion.gd")
const Dex := preload("res://core/dex_variants.gd")
const RELICS := {"RELIC_COPPER":1000,"RELIC_SILVER":5000,"RELIC_GOLD":10000,"RELIC_VASE":50000,"RELIC_BAND":100000,"RELIC_STATUE":200000,"RELIC_CROWN":300000}
const FOSSILS := ["DOME_FOSSIL","HELIX_FOSSIL","OLD_AMBER","ROOT_FOSSIL","CLAW_FOSSIL","SKULL_FOSSIL","ARMOR_FOSSIL"]
static var archive: Dictionary

static func side():
	return load("res://core/unova_side.gd")

static func special() -> Dictionary:
	if archive.is_empty():archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/unova_side_special.json"))
	return archive

static func seen(g,id: int) -> bool:
	return g.save_data.get("dex",{}).get("seen",[]).any(func(n):return int(n)==id)

static func grant(g,key: String,flag: String,who: String) -> void:
	side().give(g,key)
	side().mark(g,flag)
	g._dialog(["获得了%s。"%side().item_name(key)],who)

static func battle(g,name: String,team: Array,win: Callable) -> void:
	if not g._has_party():g._dialog(["请带上能够战斗的伙伴。"]);return
	g._start_battle({"name":name,"battle":{"team":team}},func(result):
		if result=="a":win.call()
		elif g._party_fainted():g._blackout())

static func legendaries_ready(g,r: Dictionary) -> bool:
	var requirements: Array={645:[641,642],486:[377,378,379]}.get(int(r.species),[])
	for n in requirements:
		if not side().has_mon(g,n):
			g._dialog(["神龛没有回应。让龙卷云和雷电云一起同行吧。" if int(r.species)==645 else "石像纹丝不动。这里的封印需要岩、冰和钢三位巨人。"])
			return false
	return true

static func interact(g,r: Dictionary) -> void:
	var f: Dictionary=g._flags()
	var who:=str(r.name)
	var flag:="us_"+str(r.id)
	var done:=bool(f.get(flag,false))
	match str(r.type):
		"facility":preload("res://core/unova_side_facilities.gd").open(g,r.facility)
		"musical","cinema","avenue","medals","phone","yancy":
			preload("res://core/unova_side_activities.gd").interact(g,r)
		"trade":
			if done:g._dialog(["谢谢你！你的伙伴在我这里过得很好。"],who);return
			var t: Dictionary=side().data()["trades" if r.era=="b2" else "bw_trades"][int(r.trade)]
			trade(g,t,flag)
		"tutor":shard_tutor(g,str(r.shard))
		"ruin_exit":warp(g,"unova_b2_zone_565")
		"key_share":
			if done:g._dialog(["你已经收到了来自白色森林的冰山钥匙。"],who);return
			side().mark(g,"us_b2_icekey")
			g._give_item("冰山钥匙",1,"key")
			side().mark(g,flag)
			g._dialog(["已通过本地钥匙共享接收冰山钥匙。在地下遗迹的石门前选择冰山之间。"],who)
		"keys":
			if not f.get("us_b2_ruin_switch",false):
				g._dialog(["石门上写着：从圆环中央向下六步，再向右九步，寻找地面的开关。"]);return
			var rooms:=["岩山之间"]
			var dest:=["unova_b2_zone_611"]
			if f.get("us_b2_enc_377",false):
				if g._bag_count("铁钥匙")==0:g._give_item("铁钥匙",1,"key");g._persist()
				rooms.append("黑金之间")
				dest.append("unova_b2_zone_613")
			if f.get("us_b2_icekey",false):rooms.append("冰山之间");dest.append("unova_b2_zone_612")
			rooms.append("离开")
			g._pick("使用哪一把遗迹钥匙？",rooms,func(i):
				if i<dest.size():warp(g,dest[i]))
		"weather_link":
			if done:g._dialog(["带着龙卷云和雷电云一起去丰收之祠看看吧。"],who);return
			g._pick("白森林的来客约你挑战雷电云。",["挑战","下次再来"],func(i):
				if i==0:side().fight_wild(g,642,40,flag))

		"daycare":preload("res://core/unova_side_breeding.gd").open(g)
		"charms":preload("res://core/unova_side_breeding.gd").charms(g)
		"gracidea":
			if done or not side().has_mon(g,492):g._dialog(["葛拉西蒂亚花能让谢米在白昼里变成天空的模样。"],who)
			else:grant(g,"GRACIDEA",flag,who)
		"gram":
			if not done:grant(g,str(r.key),flag,who)
			else:g._dialog(["请把信交还给那只送信的长翅鸥。"],who)
		"grams","wingull":
			if f.get("us_bw_grams_sent",false):g._dialog(["它已经带着大家的信，飞往下一座城镇了。"],who);return
			side().mark(g,"us_bw_gram_search")
			var total:=0
			for n in range(1,4):
				var name: String=side().item_name("GRAM_%d"%n)
				var sent:="us_bw_sent_gram%d"%n
				if not f.get(sent,false) and g._bag_count(name)>0:
					g._consume_item(name)
					f[sent]=true
				if f.get(sent,false):total+=1
			if total==3:
				Field.give_machine(g,89,false)
				side().mark(g,"us_bw_grams_sent")
				g._dialog(["三封信都回来了！长翅鸥振翅起飞，从身边落下了招式学习器「急速折返」。"],"送信少女")
			else:
				g._persist()
				g._dialog(["这只送信的长翅鸥弄丢了三封信。有人在海滩上捡到了，还有一封可能掉在桥南边的悬崖上。","已经交还 %d / 3 封。"%total],"送信少女")
		"hanky":
			if not done:grant(g,"GRUBBY_HANKY",flag,who)
			elif f.get("us_b2_hanky_guest",false) and not f.get("us_b2_hanky_reward",false):grant(g,"FLUFFY_TAIL","us_b2_hanky_reward",who)
			else:g._dialog(["那位客人带着一只棕色的、会愤怒门牙的宝可梦。"],who)
		"hanky_guest":
			var name: String=side().item_name("GRUBBY_HANKY")
			if g._bag_count(name)>0:g._consume_item(name);side().mark(g,flag)
			g._dialog(["是我的手帕！探探鼠吃完树果后，我总用它给它擦擦脸。"],who)

		"look":
			var count:=0
			for k in f:
				if str(k).begins_with("us_bw_sage_") and f[k]:count+=1
			if not done:
				if g._bag_count("厉害钓竿")==0:g._give_item("厉害钓竿",1,"key")
				f.u1_super_rod=true
				side().mark(g,flag)
				g._dialog(["我是国际警察帅哥。魁奇思以外的六位贤人分散在合众，请帮我寻找他们。","这支厉害钓竿交给你，在水边可以钓鱼。"],who)
			else:g._dialog(["已找到全部六人。有消息说，N 和一位龙宝可梦正旅居远方。" if count==6 else "还有 %d 位贤人下落不明。"%(6-count)],who)
		"sage":
			var finish:=func():
				Field.give_machine(g,int(r.tm),false)
				side().mark(g,flag)
				g._dialog(["这枚学习器是我的心意。","帅哥赶到，将%s带走接受调查。"%who],who)
			if r.id=="bw_sage_bronius":
				battle(g,"等离子队队员",[{"species":505,"level":63},{"species":560,"level":63}],func():battle(g,"等离子队队员",[{"species":552,"level":62},{"species":510,"level":62},{"species":552,"level":62}],finish))
			else:finish.call()
		"monkey","zoruagift","tower_gift":
			if done:g._dialog(["好好照顾那个孩子。"],who);return
			var species:=570
			var lv:=25
			if r.type=="monkey":
				species=int({495:515,498:511,501:513}.get(int(f.get("u1_starter",0)),0))
				lv=10
				if species==0:return
			elif r.type=="tower_gift":
				species=443
				lv=1
			var mon:=Party.make(species,lv,Field.moves_for(species,lv,f))
			if species==570:
				mon.ot="N"
				mon.ot_id=2
				mon.nature="急躁"
				mon.unova_n=true
				for k in ["hp","atk","def","spa","spd","spe"]:mon.get_or_add("ivs",{})[k]=30
			if species==443:
				Party.set_shiny_kind(mon,"star")
				mon.held="EXP_SHARE"
			Party.recalc(mon,true)
			g._store_mon(mon)
			side().mark(g,flag)
			g._dialog(["把%s托付给你了。"%mon.name],who)
		"lake","lakes":
			if not done:side().mark(g,flag)
			g._dialog(["三道身影分别飞向七宝市、天堂之塔和23号道路。"],who)
		"dragonstone":
			if not done:
				battle(g,"N",special().teams.n,func():grant(g,"DARK_STONE",flag,"N"))
			elif f.get("us_b2_enc_646",false):
				var now:=Time.get_date_dict_from_system()
				var key:="us_n_season_%d_%d"%[int(now.year),int(now.month)]
				if f.get(key,false):g._dialog(["下一个季节，再来看看我和伙伴们吧。"],"N");return
				battle(g,"N",special().teams["n_"+str(3+Field.season(now.month))],func():side().mark(g,key))
			else:g._dialog(["请到龙螺旋之塔的塔顶，唤醒黑暗石中的捷克罗姆。"],"N")
		"egg":
			if done:g._dialog(["那枚蛋里究竟是怎样的孩子呢？"],who);return
			if Party.occupied(g.save_data.party)>=Party.MAX_SIZE:g._dialog(["队伍满了，先腾出位置再来吧。"],who);return
			g.save_data.unova_egg_steps=40*255
			g._give_item("燃烧虫的蛋",1,"key")
			side().mark(g,flag)
			g._dialog(["请带着这枚蛋旅行。和伙伴一起走路，里面的孩子就会长大。"],who)
		"appraise":sell_relic(g,who)
		"daily_fossil":
			var day:=Time.get_date_string_from_system()
			if f.get(flag,"")==day:g._dialog(["今天挖出的化石已经交给你了。"],who);return
			var key:=str(FOSSILS.pick_random())
			side().give(g,key)
			f[flag]=day
			g._persist()
			g._dialog(["我在罗斯山里发现了%s，带去七宝市复原吧。"%side().item_name(key)],who)
		"fish":
			if done:g._dialog(["你买的鲤鱼王怎么样？"],who);return
			g._pick("花 500 元买下鲤鱼王？",["买下","离开"],func(i):
				if i!=0:return
				if int(g.save_data.money)<500:g._dialog(["钱不够。"]);return
				g.save_data.money-=500
				side().gift_mon(g,129,5)
				side().mark(g,flag)
				g._dialog(["鲤鱼王加入了队伍。"],who))
		"storm":
			if not done:
				side().mark(g,flag)
				g.save_data.unova_roamer=Party.make(641,40,Field.moves_for(641,40,f))
				g._persist()
			g._dialog(["7号道路的风雨稍稍平息了。留意合众道路间突然卷起的暴风。"],who)
		"statues":
			var count:=int(f.get(flag,0))
			if count>=5:g._dialog(["五座石像都已经苏醒。"]);return
			var bar: String=side().item_name("RAGE_CANDY_BAR")
			if g._bag_count(bar)==0:g._dialog(["沙里像是埋着一只宝可梦。也许它会对愤怒馒头作出反应。"]);return
			g._pick("用%s唤醒石像？"%bar,["使用","取消"],func(i):
				if i!=0:return
				var mon:=Party.make(555,35,Field.moves_for(555,35,f))
				mon.unova_stationary=true
				mon.ability=161
				g._consume_item(bar)
				f[flag]=count+1
				g._persist()
				g._start_wild_battle(555,35,"",func(result):
					if result=="b" and g._party_fainted():g._blackout(),"none",0,mon))
		"weekday":
			var today:=Time.get_date_dict_from_system()
			if int(today.weekday)!=int(r.weekday) or str(f.get(flag,""))==Time.get_date_string_from_system():
				g._dialog(["星期五的梦境烟雾里，有时会出现梦梦蚀。"]);return
			var mon:=Party.make(518,50,Field.moves_for(518,50,f))
			mon.unova_stationary=true
			mon.ability=140
			g._start_wild_battle(518,50,"",func(result):
				if result=="caught" or result=="a":f[flag]=Time.get_date_string_from_system();g._persist()
				elif result=="b" and g._party_fainted():g._blackout(),"",0,mon)
		"boat","nature_flight":
			var returning: bool=r.id in ["bw_liberty_return","b2_return_flight"]
			var key: String=side().item_name("LIBERTY_PASS" if r.type=="boat" else "PERMIT")
			if not returning and g._bag_count(key)==0:g._dialog(["出发时请出示%s。"%key],who);return
			var target: Dictionary=g.get_node("/root/Data").load_map("unova",r.destination)
			if target.is_empty():return
			g._pick("前往%s？"%target.name,["出发","留下"],func(i):
				if i==0:g._do_warp({"region":"unova","map":r.destination,"at":target.spawn}))
		"permit":
			var left: Array=special().regional.filter(func(id):return not seen(g,int(id)))
			if done:g._dialog(["吹寄市的风露会送你去自然保护区。"],who)
			elif not left.is_empty():g._dialog(["新合众图鉴里，还有 %d 种宝可梦尚未亲眼见过。"%left.size()],who)
			else:grant(g,"PERMIT",flag,who)
		"mirror":
			if done:g._dialog(["现形镜可以显露三只化身宝可梦的另一种模样。"],who)
			elif side().has_mon(g,645):grant(g,"REVEAL_GLASS",flag,who)
			else:g._dialog(["带着土地云到丰收之祠来吧。"],who)
		"drive":
			if done or not side().has_mon(g,649):g._dialog(["研究所曾用特殊卡带改变盖诺赛克特的炮击属性。"],who);return
			battle(g,who,special().teams.scientist_dudley,func():
				side().give(g,"SHOCK_DRIVE")
				grant(g,"BURN_DRIVE",flag,who))
		"song":FR.teach(g,547,"",[648],who)
		"sword":
			if r.era=="bw" and not [638,639,640].all(func(n):return side().has_mon(g,n)):
				g._dialog(["岩壁上有三道剑痕。让三位圣剑士和凯路迪欧一起来吧。"]);return
			FR.pick_party(g,"让哪只凯路迪欧读懂剑痕？",func(m):return int(m.species_id)==647,func(slot):
				g._tm_teach_one(548,slot,g.get_node("/root/Data").move_of(548).name,true,func():
					if r.era=="b2":
						Party.set_form(g.save_data.party[slot],"KELDEO_RESOLUTE")
						Dex.record(g.save_data,g.save_data.party[slot],true)))
		"duel","alder":
			var day:=Time.get_date_string_from_system()
			if f.get(flag,"")==day:g._dialog(["今天的对战很精彩。我们下次再见。"],who);return
			if r.type=="duel" and done and Field.season(Time.get_date_dict_from_system().month)!=0:
				g._dialog(["等到合众的春天，再来一场吧。"],who);return
			var team: Array=special().teams.get(r.get("trainer","cynthia"),[])
			if r.era=="bw":
				team=[{"species":442,"level":75},{"species":604,"level":75},{"species":350,"level":75},{"species":628,"level":75},{"species":448,"level":75},{"species":445,"level":77}]
			g._pick("和%s对战？"%who,["挑战","下次再来"],func(i):
				if i==0:battle(g,who,team,func():
					f[flag]=day
					g.world.refresh_story_actors(f)
					g._persist()
					g._dialog(["蕃石郎在黑色摩天楼的第十区等你。" if r.type=="alder" else "你的伙伴们真是出色！"],who)))
		"zoroark":
			if done:g._dialog(["森林里只有树叶沙沙作响。"]);return
			if r.era=="b2":
				Field.give_machine(g,95,false)
				side().mark(g,flag)
				g._dialog(["背包客留下大声咆哮的学习器，化作索罗亚克跑进森林。"])
			elif g.save_data.party.any(func(m):return int(m.get("species_id",0)) in [243,244,245] and Party.shiny_kind(m)!="none"):
				side().fight_wild(g,571,25,flag)
			else:g._dialog(["拖车里的女人没有说话。一股古怪的气息笼罩着森林。"])

static func warp(g,mid: String) -> void:
	var map: Dictionary=g.get_node("/root/Data").load_map("unova",mid)
	if not map.is_empty():g._do_warp({"region":"unova","map":mid,"at":map.spawn})

static func shard_tutor(g,shard: String) -> void:
	var name: String=side().item_name(shard)
	var entries: Array=special().shards[shard]
	var data=g.get_node("/root/Data")
	var labels:=entries.map(func(row):return "%s　%d 枚"%[data.move_of(int(row[0])).name,int(row[1])])
	labels.append("离开")
	g._pick("%s · 持有 %d 枚"%[name,g._bag_count(name)],labels,func(i):
		if i>=entries.size():return
		var cost:=int(entries[i][1])
		var move:=int(entries[i][0])
		if g._bag_count(name)<cost:g._dialog(["还缺 %d 枚%s。"%[cost-g._bag_count(name),name]]);return
		FR.pick_party(g,"选择学习%s的伙伴"%data.move_of(move).name,func(m):
			return special().tutor.get(str(int(m.species_id)),[]).any(func(v):return int(v)==move) and not m.moves.any(func(v):return int(v)==move),func(slot):
			g._tm_teach_one(move,slot,data.move_of(move).name,true,func():
				for j in cost:g._consume_item(name)
				g._persist())))

static func sell_relic(g,who: String) -> void:
	var keys:=RELICS.keys().filter(func(key):return g._bag_count(side().item_name(key))>0)
	if keys.is_empty():g._dialog(["海底遗迹的古代铜币、银币、金币和古代摆件，我都愿意收购。"],who);return
	var labels:=keys.map(func(k):return "%s　%d 元"%[side().item_name(k),int(RELICS[k])])
	labels.append("离开")
	g._pick("要出售哪件古物？",labels,func(i):
		if i>=keys.size():return
		var key: String=keys[i]
		var name: String=side().item_name(key)
		if g._bag_count(name)==0:return
		g._consume_item(name)
		g.save_data.money+=int(RELICS[key])
		g._refresh_hud()
		g._persist()
		g._dialog(["卖出了%s。"%name],who))

static func trade(g,t: Dictionary,flag: String,any_species:=false) -> void:
	var wanted:=int(t.get("wanted",0))
	var id:=int(t.species)
	var data=g.get_node("/root/Data")
	FR.pick_party(g,"用%s交换%s？"%["一只伙伴" if any_species else data.species_of(wanted).name,data.species_of(id).name],func(m):
		return not m.get("is_egg",false) and not m.has("fused_part") and (any_species or int(m.species_id)==wanted),func(slot):
		var former: Dictionary=g.save_data.party[slot]
		g._pick("将%s交给对方？"%former.name,["交换","取消"],func(i):
			if i!=0 or g.save_data.party[slot]!=former or g._flags().get(flag,false):return
			var lv:=int(t.level)
			var mon:=Party.make(id,lv,Field.moves_for(id,lv,g._flags()),"BASCULIN_BLUE_STRIPED" if id==550 and int(t.get("form",0))==1 else "")
			var nature:=str(t.get("nature","")).trim_prefix("NATURE_")
			var natures:=["HARDY","LONELY","BRAVE","ADAMANT","NAUGHTY","BOLD","DOCILE","RELAXED","IMPISH","LAX","TIMID","HASTY","SERIOUS","JOLLY","NAIVE","MODEST","MILD","QUIET","BASHFUL","RASH","CALM","GENTLE","SASSY","CAREFUL","QUIRKY"]
			var chinese:=["勤奋","怕寂寞","勇敢","固执","顽皮","大胆","坦率","悠闲","淘气","乐天","胆小","急躁","认真","爽朗","天真","内敛","慢吞吞","冷静","害羞","马虎","温和","温顺","自大","慎重","浮躁"]
			if natures.has(nature):mon.nature=chinese[natures.find(nature)]
			mon.ot=t.get("ot","合众训练家")
			mon.ot_id=int(t.get("id",0)) if t.get("id",0) is float or t.get("id",0) is int else 0
			if t.get("name","")!="" and not t.has("type"):mon.nickname=t.name
			var key:=str(t.get("item","NONE"))
			if key!="NONE":mon.held=key
			var slot_id:=int(t.get("ability_slot",0))
			var abil: Array=data.species_of(id).get("abilities",[])
			if slot_id==2:mon.ability=int(side().data().hidden_abilities.get(str(id),mon.ability))
			elif slot_id<abil.size():mon.ability=int(abil[slot_id])
			mon.ability_name=data.abilities.get(int(mon.ability),{}).get("name","")
			var stat_names:={"hp":"hp","attack":"atk","defense":"def","special_attack":"spa","special_defense":"spd","speed":"spe"}
			for stat in t.get("ivs",{}):
				if t.ivs[stat]!=null:mon.get_or_add("ivs",{})[stat_names[stat]]=int(t.ivs[stat])
			Party.recalc(mon,true)
			g.save_data.party[slot]=mon
			Dex.record(g.save_data,mon,true)
			if flag.begins_with("us_b2_yancy_trade_"):
				g._flags().us_yancy_day=Time.get_date_string_from_system()
				g._flags().us_yancy_trades=int(g._flags().get("us_yancy_trades",0))+1
			side().mark(g,flag)
			g._dialog(["交换完成！请好好照顾%s。"%mon.name],str(mon.ot))))

static func use_item(g,name: String) -> bool:
	if name=="基因之楔":
		var party: Array=g.save_data.party
		var opts:=Fusion.options(party).filter(func(o):return o.form in ["KYUREM_BLACK","KYUREM_WHITE"])
		for o in Fusion.unfusable(party):
			if int(party[int(o.base)].species_id)==646:opts.append(o)
		if opts.is_empty():g._dialog(["请让酋雷姆与捷克罗姆或莱希拉姆同行。"]);return true
		var labels:=opts.map(func(o):return ("合体　" if o.has("part") else "分离　")+str(o.text))
		labels.append("取消")
		g._pick("基因之楔",labels,func(i):
			if i>=opts.size():return
			var o: Dictionary=opts[i]
			var msg:=Fusion.fuse(party,int(o.base),int(o.part),o.form) if o.has("part") else Fusion.unfuse(party,int(o.base))
			Dex.sync_owned(g.save_data,party)
			g._persist()
			g._dialog([msg]))
		return true
	if name=="现形镜":
		FR.pick_party(g,"对谁使用现形镜？",func(m):return int(m.species_id) in [641,642,645],func(slot):
			var mon: Dictionary=g.save_data.party[slot]
			Party.set_form(mon,Fusion.form_for_item(int(mon.species_id),"REVEAL_GLASS") if str(mon.get("form",""))=="" else "")
			Dex.record(g.save_data,mon,true)
			g._persist()
			g._dialog(["镜中映出了%s。"%mon.name]))
		return true
	if g.world.map_data.get("region","")!="unova":return false
	if name=="合众的蛋":
		g._dialog(["贴近蛋壳，似乎听见了伙伴的心跳。"])
		return true
	if name=="燃烧虫的蛋":
		g._dialog(["蛋里传来了轻轻的动静。" if int(g.save_data.get("unova_egg_steps",0))<2550 else "这枚蛋摸上去很温暖。"])
		return true
	if name=="探宝器":
		var nearest:=Vector2i.ZERO
		var best:=99999
		for o in g.world.map_data.get("objects",[]):
			if o.get("kind","")!="unova_hidden" or g._flags().get(o.flag,false):continue
			var delta:=Vector2i(int(o.at[0]),int(o.at[1]))-Vector2i(g.world.player_pos)
			var d:=absi(delta.x)+absi(delta.y)
			if d<best:best=d;nearest=delta
		var hint:="这一带没有信号。"
		if best==0:hint="脚下有强烈反应。退后一步，面向这里调查。"
		elif best<99999:hint="信号来自%s%s方，约 %d 步。"%["北" if nearest.y<0 else "南" if nearest.y>0 else "","西" if nearest.x<0 else "东" if nearest.x>0 else "",best]
		g._dialog([hint],"探宝器")
		return true
	if name in ["奖牌盒","即时通讯器","遗忘物","物品箱"]:
		return preload("res://core/unova_side_activities.gd").use_item(g,name)
	return false

static func step(g) -> bool:
	if g.world.map_data.get("region","")!="unova":return false
	if preload("res://core/unova_side_breeding.gd").step(g):return true
	if int(g.save_data.get("unova_egg_steps",0))>0:
		var pace:=2 if g.save_data.party.any(func(m):return int(m.get("ability",0)) in [40,49]) else 1
		g.save_data.unova_egg_steps=maxi(0,int(g.save_data.unova_egg_steps)-pace)
		if int(g.save_data.unova_egg_steps)==0:
			g._consume_item("燃烧虫的蛋")
			side().gift_mon(g,636,1)
			g._record_hatch()
			g._persist()
			g._dialog(["蛋壳裂开，燃烧虫孵化了！"])
			return true
	var mon: Dictionary=g.save_data.get("unova_roamer",{})
	if Field.era(g._flags())=="bw" and not mon.is_empty() and g.world.map_data.get("unova_zone","").begins_with("route_") and not g.world.is_water(g.world.player_pos) and randi_range(0,255)==0:
		g._start_wild_battle(int(mon.species_id),int(mon.level),"",func(outcome):
			if outcome=="caught":g.save_data.erase("unova_roamer");g._flags().us_bw_roamer_caught=true
			elif int(mon.hp)<=0:mon.hp=mon.max_hp
			g._persist()
			if outcome=="b" and g._party_fainted():g._blackout(),"",0,mon)
		return true
	return preload("res://core/unova_side_activities.gd").step(g)
