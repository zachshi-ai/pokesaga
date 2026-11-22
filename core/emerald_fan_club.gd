extends RefCounted

const BASE:=preload("res://core/hoenn_base.gd")
const GROUPS:=["宝可梦","训练家","状态","对战","问候","人物","声音","交谈","语气","感情","状况","行动","生活","爱好","时间","其他","形容","事件","招式一","招式二","流行用语","全国宝可梦"]
const ELDERS:=["吟游老人","时髦老人","交换老人","说书老人","开心老人"]
const OFFERS:=["DUSKULL_DOLL","BALL_CUSHION","TIRE","PRETTY_FLOWERS"]
const OWNERS:=["特里斯坦","菲利普","丹尼斯","罗伯托"]
const QUESTIONS:=["真想放个假去旅行啊。你呢？","我买了一盒一百二十种颜色的蜡笔。厉害吧？","如果人能在空中飘着，该有多好啊？","写在海滩上的字，被浪抹去的时候你会难过吗？","你也想去看看海底的样子吗？","看到夕阳，你也会忽然想念某个人吗？","躺在青青草地上，什么烦恼都消失了，对吧？","秘密基地很棒吧？"]
const ADJECTIVES:=["漂亮","讨人喜欢","自在","明朗","让人向往","刺激","有趣","神奇"]
const STORY_NAMES:={"SAVED_GAME":"记下旅程","STARTED_TRENDS":"武斗镇的新潮流","TRAINER_BATTLES":"训练家的对决","POKEMON_CAPTURES":"精灵球中的相遇","PLANTED_BERRIES":"种下的树果","GOT_INTERVIEWED":"记者来访","WON_CONTEST":"华丽大赛的胜利","ENTERED_CONTEST":"华丽大赛的舞台","WON_POKEMON_LOTTERY":"抽奖的好运","ENTERED_BATTLE_TOWER":"向对战塔进发","POKEBLOCKS":"宝可方块制作","USED_ITEMFINDER":"探宝器的发现","CHECKED_POKEDEX":"翻开的图鉴","TRADED_BIKES":"换过的自行车","RESTED_AT_HOME":"家中的休息","FISHING_ENCOUNTERS":"上钩的宝可梦","HATCHED_EGGS":"孵出的蛋","EVOLVED_POKEMON":"进化的伙伴","USED_POKECENTER":"宝可梦中心的灯","ENTERED_SAFARI_ZONE":"原野区冒险","USED_CUT":"居合斩开路","USED_ROCK_SMASH":"岩石的裂缝","MOVED_SECRET_BASE":"搬迁秘密基地","USED_SPLASH":"水花四溅","USED_STRUGGLE":"最后的挣扎","SLOT_JACKPOTS":"大奖","CONSECUTIVE_ROULETTE_WINS":"轮盘连胜","SHOPPED":"商店采购","GOT_RAINED_ON":"雨中旅行","RECEIVED_RIBBONS":"收集的奖章","JUMPED_DOWN_LEDGES":"越过矮坡","WATCHED_TV":"看过的节目","CHECKED_CLOCK":"钟上的时间","USED_DAYCARE":"寄养的伙伴","RODE_CABLE_CAR":"登山缆车","ENTERED_HOT_SPRINGS":"釜炎的温泉"}
static var book:Dictionary
static var sample_cache:Dictionary
static var water_id:Dictionary

static func data()->Dictionary:
	if book.is_empty():book=JSON.parse_string(FileAccess.get_file_as_string("res://content/hoenn_native/fan_club.json"))
	return book

static func state(g)->Dictionary:
	var s:Dictionary=g.save_data.get_or_add("h_fan_club",{})
	if not g.save_data.has("js_trainer_id"):g.save_data.js_trainer_id=g.rng.randi_range(0,65535)
	var new_identity:=not s.has("id")
	s.get_or_add("id",int(g.save_data.js_trainer_id)%10/2)
	s.get_or_add("lyrics",data().original.duplicate())
	s.get_or_add("stats",{})
	s.get_or_add("taught",[])
	if new_identity:g._persist()
	return s

static func record(g,stat:String):
	if not STORY_NAMES.has(stat):return
	var records:Dictionary=g.save_data.get_or_add("h_fan_club",{}).get_or_add("stats",{})
	records[stat]=int(records.get(stat,0))+1

static func name_of(word)->String:
	return str(data().words[str(int(word))][0])

static func phrase(words:Array)->String:
	var text:Array=[]
	for id in words:text.append(name_of(id))
	return " ".join(text)

static func randword(g,group:int)->int:
	var words:Array=data().groups[str(group)]
	return int(words[g.rng.randi_range(0,words.size()-1)])

static func make_trend(g,words:Array,growing:bool)->Dictionary:
	var r:int=g.rng.randi_range(0,97)
	if r>50:
		r=g.rng.randi_range(0,97)
		if r>80:r=g.rng.randi_range(0,97)
	return {"words":words.duplicate(),"max":r+30,"score":g.rng.randi_range(0,r)+30,"up":growing,"rand":g.rng.randi_range(0,65535)}

static func outranks(g,a:Dictionary,b:Dictionary)->bool:
	if int(a.score)!=int(b.score):return int(a.score)>int(b.score)
	if int(a.max)!=int(b.max):return int(a.max)>int(b.max)
	return bool(g.rng.randi()&1)

static func rank(g,rows:Array):
	for i in rows.size()-1:
		for j in range(i+1,rows.size()):
			if outranks(g,rows[j],rows[i]):
				var temp:Dictionary=rows[i];rows[i]=rows[j];rows[j]=temp

static func today()->int:
	var d:=Time.get_date_dict_from_system()
	return int(Time.get_unix_time_from_datetime_dict(d))/86400

static func trends(g,day:int=-1)->Array:
	if day<0:day=today()
	var s:=state(g)
	if not s.has("trends"):
		s.trends=[]
		for i in 5:s.trends.append(make_trend(g,[randword(g,10),randword(g,12+g.rng.randi_range(0,1))],g.rng.randi()%2==1))
		s.day=day
		rank(g,s.trends)
		g._persist()
	elif day>int(s.day):
		var passed:=day-int(s.day)
		for t in s.trends:
			var distance:=passed*5
			var score:=int(t.score)
			var limit:=int(t.max)
			var position:=score if t.up else 2*limit-score
			position=posmod(position+distance,2*limit)
			t.up=position<limit
			t.score=position if t.up else 2*limit-position
		rank(g,s.trends);s.day=day;g._persist()
	return s.trends

static func submit(g,words:Array)->bool:
	var rows:=trends(g);var s:=state(g)
	record(g,"STARTED_TRENDS")
	for t in rows:
		if t.words==words:g._persist();return false
	if not s.get("submitted",false):
		s.submitted=true;rows[0].words=words.duplicate();g._persist();return true
	var entry:=make_trend(g,words,true)
	var at:=0
	while at<rows.size()-1 and not outranks(g,entry,rows[at]):at+=1
	rows.insert(at,entry);rows.pop_back();g._persist()
	return at==0

static func fishing_numbers(seed_value:int)->Array:
	var result:=[]
	var seed:=seed_value
	while result.size()<6:
		seed=(1103515245*seed+12345)&0xffffffff
		var index:=(seed>>16)%447
		if index==0:index=447
		if index>=4:result.append(index)
	return result

# A successful override uses the ordinary rod battle and capture flow.
static func feebas(g,face:Vector2i)->Dictionary:
	if g.world.map_data.get("source_id","")!="MAP_ROUTE119":return {}
	if water_id.is_empty():
		for i in data().water.size():
			var p:Array=data().water[i];water_id[Vector2i(int(p[0]),int(p[1]))]=i+1
	var id:int=water_id.get(face,0)
	if id<4 or g.rng.randi_range(0,99)>=50:return {}
	if id not in fishing_numbers(int(trends(g)[0].rand)):return {}
	return {"species":349,"min":20,"max":25,"weight":100}

static func permitted(g,group:int)->Array:
	var words:Array=data().groups[str(group)]
	var f:Dictionary=g._flags()
	if group==20:return state(g).taught
	if group in [17,18,19] and not f.get("h_champion",false):return []
	if group==21:return words if f.get("h_national_dex",false) else []
	if group==1:return words.filter(func(w):return w not in data().unavailable)
	if group==0:
		var dex:Dictionary=g.save_data.get("dex",{})
		var known:Array=dex.get("seen",[])
		return words.filter(func(i):return int(data().words[str(int(i))][1]) in known)
	return words

static func choose_word(g,prompt:String,after:Callable):
	var ids:=[];var choices:=[]
	for group in GROUPS.size():
		if not permitted(g,group).is_empty():
			ids.append(group);choices.append(GROUPS[group])
	g._pick(prompt,choices,func(i):
		var entries:=permitted(g,ids[i])
		var labels:=entries.map(func(w):return name_of(w))
		g._pick(prompt+" · "+str(choices[i]),labels,func(index):after.call(int(entries[index])),func():choose_word(g,prompt,after)))

static func boy(g):
	var old:=phrase(trends(g)[0].words)
	g._pick("最近最时髦的是「%s」，对吧？"%old,["没错","我听说了别的流行语"],func(i):
		if i==0:g._dialog(["果然，大家都在谈这个！"],"武斗镇少年");return
		choose_word(g,"新流行语 · 第一个词",func(first):
			choose_word(g,"「%s」· 第二个词"%name_of(first),func(second):
				var words:=[first,second]
				g._pick("要告诉他「%s」吗？"%phrase(words),["投稿","算了"],func(ok):
					if ok!=0:return
					var accepted:=submit(g,words)
					g._dialog(["啊，「%s」！我当然知道，接下来要流行的就是它！"%phrase(words) if accepted else "嗯，我还是觉得「%s」最酷。"%phrase(trends(g)[0].words)],"武斗镇少年")))))

static func hall(g,key:String)->bool:
	var rows:=trends(g);var top:=phrase(rows[0].words)
	match key:
		"Girl":
			var bored:bool=int(rows[0].score)-int(rows[1].score)<=1 and not rows[0].up and rows[1].up
			g._dialog(["大家都说「%s」，我听得有点腻了。"%top if bored else "真想不出没有「%s」的日子会怎样。"%top])
		"Woman":g._dialog(["我正在教我的宝可梦说「%s」。"%top])
		"Man":
			var link:=name_of(randword(g,12+g.rng.randi_range(0,1)))
			g._pick("你觉得「%s」和「%s」有关联吗？"%[top,link],["有道理","我看不出来"],func(i):g._dialog(["果然，我的直觉没错！" if i==0 else "这年头，想跟上潮流还真难啊。"]))
		"ExpertM":g._dialog(["快看！电视里也在说「%s」！"%top])
		"Twin":g._dialog(["海的另一边也一样流行「%s」吗？"%top])
		"LittleBoy":g._dialog(["我专门收集「%s」的周边。"%top])
		"Bookshelf":g._dialog(["书架排满了《如何分辨好的%s》《%s与宝可梦》《实用%s》……"%[top,top,top]])
		"Painting":
			var words:Array=rows[0].words
			var title:String=["%s的呐喊","%s的微笑","最后的%s","%s的诞生","%s的呐喊","%s的呐喊","最后的%s","最后的%s"][(int(words[0])+int(words[1]))&7]%top
			g._dialog(["画框下方写着《%s》。"%title])
		_:return false
	return true

static func field(g,obj:Dictionary)->bool:
	var label:=str(obj.get("source_script",""))
	if label not in ["DewfordTown_Hall_EventScript_Painting","DewfordTown_Hall_EventScript_Bookshelf"]:return false
	return hall(g,label.get_slice("EventScript_",1))

static func interact(g,npc:Dictionary)->bool:
	var script:=str(npc.get("source_script",""))
	if script=="DewfordTown_EventScript_TrendyPhraseBoy":boy(g);return true
	if script.begins_with("DewfordTown_Hall_EventScript_"):return hall(g,script.get_slice("EventScript_",1))
	if script!="MauvilleCity_PokemonCenter_1F_EventScript_MauvilleOldMan":return false
	var s:=state(g)
	match int(s.id):
		0:bard(g,s)
		1:hipster(g,s)
		2:trader(g,s)
		3:storyteller(g,s)
		4:giddy(g)
	return true

static func song_audio(words:Array)->AudioStreamWAV:
	const RATE:=12000
	var pcm:=PackedByteArray()
	for raw_id in words:
		var id:=int(raw_id)
		var index:=posmod(id,4)+((id>>3)&1)
		var tones:Array=data().pitch[index]
		var segments:Array=data().notes[str(id)]
		for pos in segments.size():
			var note:Array=segments[pos]
			var voice:=3*(int(note[0])/3)+1
			var frames:=int(note[1])*RATE/60
			var source:Array=data().samples[voice]
			if not sample_cache.has(voice):sample_cache[voice]=Marshalls.base64_to_raw(source[1])
			var sample:PackedByteArray=sample_cache[voice]
			var speed:=float(source[0])/RATE*pow(2.0,(2.0+float(tones[pos]))/12)
			var loop_start:=int(source[2]);var loop_end:=int(source[3])
			var start:=pcm.size()
			pcm.resize(start+frames*2)
			for i in frames:
				var source_at:=int(i*speed)
				if loop_start>=0 and source_at>loop_end:source_at=loop_start+posmod(source_at-loop_start,loop_end-loop_start+1)
				if source_at>=sample.size():break
				var value:=(int(sample[source_at])-128)*200
				pcm.encode_s16(start+i*2,value)
		pcm.resize(pcm.size()+RATE/16*2)
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=RATE;stream.data=pcm
	return stream

static func perform(g,words:Array,after:Callable):
	var player:=AudioStreamPlayer.new()
	g.add_child(player)
	player.stream=song_audio(words)
	if g.snd.sfx_on:player.play()
	var dialogue=g._dialog(["♪　"+phrase(words.slice(0,3))+"\n♪　"+phrase(words.slice(3))],"吟游老人")
	dialogue.closed.connect(func():
		player.stop();player.queue_free()
		after.call(),CONNECT_ONE_SHOT)

static func bard(g,s:Dictionary):
	g._pick("想听听我写的歌吗？",["听他唱歌","下次吧"],func(i):
		if i!=0:return
		perform(g,s.lyrics,func():
			if s.get("song_changed",false):g._dialog(["我正在练你改的那首歌。真想唱给更多训练家听啊。"],ELDERS[0]);return
			g._pick("你愿意帮我改一个词吗？",["改一句歌词","保留原词"],func(j):
				if j==0:edit_song(g,s))))

static func edit_song(g,s:Dictionary):
	var slots:=[]
	for i in s.lyrics.size():slots.append("第%d词　%s"%[i+1,name_of(s.lyrics[i])])
	g._pick("想换掉哪一个词？",slots,func(i):
		choose_word(g,"为第%d个位置挑一个词"%[i+1],func(word):
			var draft:Array=s.lyrics.duplicate();draft[i]=word
			perform(g,draft,func():
				g._pick("这就是你想要的唱法吗？",["就这样唱","重新改词"],func(j):
					if j!=0:edit_song(g,s);return
					s.lyrics=draft;s.song_changed=true;g._persist()
					g._dialog(["好，这一阵子就唱你改的歌。"],ELDERS[0])))))

static func hipster(g,s:Dictionary):
	if s.get("word_taught",false):
		g._dialog(["上回我已经教过你了。试着用「%s」组合一句话吧。"%name_of(s.taught.back())],ELDERS[1]);return
	var words:Array=data().groups["20"].filter(func(x):return x not in s.taught)
	if words.is_empty():g._dialog(["你把我的流行语全学会了。"],ELDERS[1]);return
	var word:int=words[g.rng.randi_range(0,words.size()-1)]
	s.taught.append(word);s.word_taught=true;g._persist()
	g._dialog(["现在最流行的说法是「%s」。收进你的词库吧！"%name_of(word)],ELDERS[1])

static func unused(g,id:String)->int:
	var placed:=0
	for dec in g._flags().get("h_base_furniture",[]):
		if dec.id==id:placed+=1
	return int(g._flags().get("h_decorations",{}).get(id,0))+g._bag_count(BASE.title(id))-placed

static func trader(g,s:Dictionary):
	if s.get("traded",false):g._dialog(["你上次留下的%s，我会好好收藏的。"%BASE.title(s.trade_given)],ELDERS[2]);return
	var labels:=[]
	for i in OFFERS.size():labels.append("%s　%s留下的"%[BASE.title(OFFERS[i]),OWNERS[i]])
	g._pick("我在交换秘密基地装饰。你想要哪件？",labels,func(i):
		var want:String=OFFERS[i]
		var all:Dictionary=g.get_node("/root/Data").load_map("hoenn","em_secret_base_red_cave1").mechanisms.base.furniture
		var stock:=all.keys().filter(func(key):return unused(g,key)>0)
		if stock.is_empty():g._dialog(["拿一件闲置的装饰来吧，基地里正在摆放的要先收起来。"],ELDERS[2]);return
		g._pick("你愿意用哪件闲置装饰交换？",stock.map(BASE.title),func(j):
			var given:String=stock[j]
			g._pick("用%s换%s？"%[BASE.title(given),BASE.title(want)],["交换装饰","再想想"],func(ok):
				if ok!=0 or unused(g,given)<1 or s.get("traded",false):return
				var owned:Dictionary=g._flags().get_or_add("h_decorations",{})
				if int(owned.get(given,0))>0:owned[given]-=1
				else:g._consume_item(BASE.title(given))
				owned[want]=int(owned.get(want,0))+1
				s.traded=true;s.trade_given=given;g._persist()
				g._dialog(["%s已经送到你的装饰电脑里了！"%BASE.title(want)],ELDERS[2]))))

static func storyteller(g,s:Dictionary):
	g._pick("想听旅行者的传说吗？",["听听传说","下次吧"],func(i):
		if i!=0:return
		if s.has("story"):
			var stat:String=s.story
			var now:=int(s.stats.get(stat,0));var past:=int(s.story_count)
			var lines:=["%s的传说——「%s」。那一次，记录停在了%d次。"%[s.get("author","小悠"),STORY_NAMES[stat],past]]
			if now>past:
				lines.append("等等，你已经创下%d次的新纪录！我要把传说重新记下。"%now)
				s.story_count=now;g._persist()
			g._dialog(lines,ELDERS[3]);return
		g._pick("我还没有记下传说。你愿意把自己的故事留下来吗？",["讲述自己的事迹","下次再说"],func(j):
			if j!=0:return
			var candidates:=[]
			for key in STORY_NAMES:
				var cutoff:=2 if key=="CONSECUTIVE_ROULETTE_WINS" else 1
				if int(s.stats.get(key,0))>=cutoff:candidates.append(key)
			if candidates.is_empty():g._dialog(["再去旅行看看吧。下次也许能带回一段传说。"],ELDERS[3]);return
			var key:String=candidates[g.rng.randi_range(0,candidates.size()-1)]
			s.story=key;s.story_count=int(s.stats[key]);s.author=str(g.save_data.get("player_name","小悠"));g._persist()
			g._dialog(["「%s」！%s已经有过%d次这样的经历了。这就是我要讲的故事。"%[STORY_NAMES[key],s.author,s.story_count]],ELDERS[3])))

static func giddy(g):
	g._pick("我刚想到件有意思的事，想听吗？",["听他说说","先告辞"],func(i):
		if i!=0:return
		var questions:=QUESTIONS.duplicate()
		for n in range(questions.size()-1,0,-1):
			var j:int=g.rng.randi_range(0,n)
			var entry:String=questions[j];questions[j]=questions[n];questions[n]=entry
		giddy_tale(g,questions,0))

static func giddy_tale(g,questions:Array,count:int):
	var line:String
	if not questions.is_empty() and g.rng.randi_range(0,9)<3:line=questions.pop_back()
	else:
		var options:=[]
		for id in [0,12,13,18,19,21]:options.append_array(permitted(g,id))
		var word:int=options[g.rng.randi_range(0,options.size()-1)]
		line="「%s」真的很%s，你也这样想吧？"%[name_of(word),ADJECTIVES[g.rng.randi_range(0,ADJECTIVES.size()-1)]]
	var last:bool=count>=9 or g.rng.randi_range(0,9)==0
	g._pick(line,["我觉得是","我不这么想"],func(_i):
		if last:g._dialog(["今天就聊到这里。下次再见！"],ELDERS[4])
		else:giddy_tale(g,questions,count+1))
