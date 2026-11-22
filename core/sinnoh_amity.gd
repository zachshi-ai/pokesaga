extends RefCounted
const Fashion := preload("res://core/sinnoh_contests.gd")
const Cast := preload("res://core/sinnoh_cast.gd")
const POOLS := [[390,391,392],[393,394,395],[387,388,389],[54,427,425],[25,35,417,440],[39,255,300,285]]
const BERRIES := ["magost","cornn","rabuta","nomel","spelon","pamtre","watmel","durin","belue"]
const BERRY_ROLLS := [20,35,50,65,72,79,86,93,100]
const ACCESSORY_ROLLS := [15,30,45,60,70,80,88,93,98,100]
const PARK := "MAP_HEADER_AMITY_SQUARE"
const WALKER := "s_square_walker"

class WalkerSprite extends Sprite2D:
	func _process(_delta: float) -> void:
		if get_parent().map_data.get("source_id","")!=PARK:queue_free()

static func step(g, kind: String, ctx: Dictionary) -> Dictionary:
	var state: Dictionary=g._flags().get(WALKER,{})
	var pos: Vector2i=g.world.player_pos
	var action := ""
	if kind=="field" and not state.is_empty() and ctx.at==Vector2i(int(state.buddy[0]),int(state.buddy[1])):
		action="talk"
	elif kind in ["step","map_enter"]:
		if state.is_empty() and pos in [Vector2i(12,46),Vector2i(51,46)]:action="choose"
		elif not state.is_empty():
			if pos in [Vector2i(12,47),Vector2i(51,47)]:action="leave"
			elif state.player!=[pos.x,pos.y]:
				var hut: Array=Fashion.data().huts.get("%d,%d"%[pos.x,pos.y],[])
				if not hut.is_empty():
					pos=Vector2i(int(hut[0]),int(hut[1]));g.world.warp_to(pos)
					state.player=[pos.x,pos.y-1]
				state.steps=mini(200,int(state.steps)+1)
				state.buddy=state.player
				state.player=[pos.x,pos.y]
				draw(g,state)
			elif not g.world.has_node("AmityCompanion"):draw(g,state)
	if action.is_empty():return {}
	return {"id":"s_amity_interaction","once":false,"steps":[{"sinnoh_amity":action}]}

static func draw(g, state: Dictionary) -> void:
	var sprite=g.world.get_node_or_null("AmityCompanion")
	if not is_instance_valid(sprite):
		sprite=WalkerSprite.new()
		sprite.name="AmityCompanion"
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		g.world.add_child(sprite)
	var a:=Vector2i(int(state.buddy[0]),int(state.buddy[1]))
	var player: Vector2i=g.world.player_pos
	var face: String="down" if player.y>a.y else "up"
	if player.x!=a.x:face="right" if player.x>a.x else "left"
	Cast.draw(sprite,state.gfx,face,int(state.steps)%2)
	sprite.centered=false
	sprite.offset=Vector2(-sprite.texture.get_width()/2,-sprite.texture.get_height())
	sprite.position=Vector2(a.x*16+8,(a.y+1)*16)
	sprite.z_index=g.world.Z_ACTOR+a.y*2

static func remove_sprite(g) -> void:
	var sprite=g.world.get_node_or_null("AmityCompanion")
	if is_instance_valid(sprite):g.world.remove_child(sprite);sprite.queue_free()

static func stop(g) -> void:
	g._flags().erase(WALKER)
	remove_sprite(g)
	g._persist()

static func roll(g, limits: Array) -> int:
	var x:int=g.rng.randi_range(0,99)
	for i in limits.size():
		if x<int(limits[i]):return i
	return limits.size()-1

static func next_pickup(g,state: Dictionary) -> void:
	var table: Array=Fashion.data().amity[int(state.pool)]
	state.accessory=int(table[roll(g,ACCESSORY_ROLLS)])
	state.berry=BERRIES[roll(g,BERRY_ROLLS)]
	state.prefers_item=g.rng.randi_range(0,4)==0

static func handle(g,action: String) -> void:
	if action=="leave":
		stop(g)
		g._dialog(["散步结束。欢迎再带伙伴来玩。"],"接待员").closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return
	if action=="talk":
		var state: Dictionary=g._flags()[WALKER]
		var line: String=state.name+"开心地跟在你身旁。"
		if int(state.steps)>=200:
			var id:=int(state.accessory)
			var stock: Dictionary=Fashion.case(g).get_or_add("accessories",{})
			var picked: String
			if not state.prefers_item and int(stock.get(str(id),0))<Fashion.capacity(id):
				picked=Fashion.data().accessories[id]
				stock[str(id)]=int(stock.get(str(id),0))+1
			else:
				picked=g.get_node("/root/Data").berry_name(state.berry)
				g._give_bag_item(picked,"berry","",state.berry)
			state.steps=0
			next_pickup(g,state)
			g._persist()
			line="%s把捡到的%s交给了你。"%[state.name,picked]
		g._dialog([line],state.name).closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return
	var choices:=[];var entrants:=[]
	for mon in g.save_data.party:
		if mon.is_empty() or mon.get("egg",false):continue
		for i in POOLS.size():
			if int(mon.species_id) in POOLS[i] and (i!=5 or g._flags().get("s_national_dex",false)):
				choices.append(mon.name)
				entrants.append({"mon":mon,"pool":i})
	if choices.is_empty():
		g.world.warp_to(g.world.player_pos+Vector2i.DOWN)
		g._dialog(["请带皮卡丘、皮皮、可达鸭、帕奇利兹、飘飘球、卷卷耳、小福蛋，或神奥最初伙伴的任一进化阶段来散步。"],"接待员").closed.connect(g._story_step,CONNECT_ONE_SHOT)
		return
	g._pick("想和谁一起逛互动广场？",choices,func(i):
		var mon: Dictionary=entrants[i].mon
		var p: Vector2i=g.world.player_pos
		var state: Dictionary={"name":mon.name,"species":mon.species_id,"gfx":g.get_node("/root/Data").species_of(mon.species_id).key.to_lower(),"pool":entrants[i].pool,"steps":0,"player":[p.x,p.y],"buddy":[p.x,p.y+1]}
		next_pickup(g,state)
		g._flags()[WALKER]=state
		draw(g,state);g._persist();g._story_step(),
		func():g.world.warp_to(g.world.player_pos+Vector2i.DOWN);g._story_step())

static func gift(g) -> void:
	var day:=Time.get_date_string_from_system()
	var flags: Dictionary=g._flags()
	if flags.get("s_square_gift_day","")==day:g._dialog(["今天的礼物已经交给你了。明天再来吧。"]);return
	if flags.get("s_square_offer_day","")!=day:
		flags.s_square_offer_day=day
		flags.s_square_offer=g.rng.randi_range(0,Fashion.data().park_gifts.size()-1)
		g._persist()
	var offer=Fashion.data().park_gifts[int(flags.s_square_offer)]
	var berry:=offer is String
	var nm: String=g.get_node("/root/Data").berry_name(offer) if berry else Fashion.data().accessories[int(offer)]
	g._pick("今天的礼物是%s。要收下吗？"%nm,["收下","下次再说"],func(i):
		if i!=0:return
		if berry:g._give_bag_item(nm,"berry","",offer)
		else:
			var stock: Dictionary=Fashion.case(g).get_or_add("accessories",{})
			var key:=str(int(offer))
			if int(stock.get(key,0))>=Fashion.capacity(int(offer)):g._dialog(["饰品盒里已经装不下了。"]);return
			stock[key]=int(stock.get(key,0))+1
		flags.s_square_gift_day=day;g._persist();g._dialog(["收到了%s。"%nm]))
