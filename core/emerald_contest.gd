extends RefCounted
## The same runner resolves appeals for the player's Pokémon and the three NPCs.
const CATEGORIES := ["帅气","美丽","可爱","聪明","强壮"]
const RANKS := ["普通","超级","高级","大师"]
const MAX_ROUNDS := 5
static var tables: Dictionary
var category: int
var rank: int
var round_number := 0
var crowd := 0
var entrants := []
var order := []
var rng := RandomNumberGenerator.new()

static func data() -> Dictionary:
	if tables.is_empty():
		tables=JSON.parse_string(FileAccess.get_file_as_string("res://content/emerald_contests.json"))
	return tables

static func profile(name_text: String, species: int, moves: Array, condition: Array, sheen: int) -> Dictionary:
	var eligible: Array=[]
	for id in moves:
		if data().moves.has(str(int(id))) and int(id) not in eligible: eligible.append(int(id))
	return {"name":name_text,"species":species,"moves":eligible,"condition":condition,"sheen":sheen,
		"form":"","shiny":false,"last":0,"repeats":0,"stars":0,"points":0,"skip":0,
		"attention":false,"tie":0,"opening":0,"appeal":0,"next":0}

func begin(mon: Dictionary, cat: int, level: int, champion: bool, db) -> void:
	category=cat
	rank=level
	entrants.clear()
	var player:=profile(mon.name,mon.species_id,mon.moves,mon.get("contest_condition",[0,0,0,0,0]),mon.get("sheen",0))
	player.form=mon.get("form","")
	player.shiny=mon.get("shiny",false)
	entrants.append(player)
	var pool: Array=data().opponents.filter(func(n):return int(n.rank)==rank and n.categories.any(func(c):return int(c)==category) and n.filter!=("NO_POSTGAME" if champion else "ONLY_POSTGAME"))
	while entrants.size()<4 and not pool.is_empty():
		var foe: Dictionary=pool.pop_at(rng.randi_range(0,pool.size()-1))
		var species: Dictionary=db.species_of(int(foe.species))
		entrants.append(profile(species.get("name",foe.trainer),foe.species,foe.moves,foe.condition,foe.sheen))
	order=range(entrants.size())
	for n in entrants:
		n.tie=rng.randi()
		n.opening=int(n.condition[category])+floori((n.condition[(category+4)%5]+n.condition[(category+1)%5]+n.sheen)/2.0)
	order.sort_custom(func(a,b):return entrants[a].opening>entrants[b].opening if entrants[a].opening!=entrants[b].opening else entrants[a].tie>entrants[b].tie)

func crowd_delta(cat: int) -> int:
	if category==cat:return 1
	return 0 if (cat-category+5)%5 in [1,4] else -1

func cpu_pick(n: Dictionary) -> int:
	var best: int=n.moves[0]
	var highest := -999
	for id in n.moves:
		var move: Dictionary=data().moves[str(id)]
		var score:=int(move.appeal)+int(move.jam)+10*crowd_delta(move.category)+rng.randi_range(0,30)
		if n.attention and data().moves.get(str(n.last),{}).get("starter","0") in move.combo: score+=move.appeal
		if n.last==id and move.effect!="REPETITION_NOT_BORING":score-=20
		if move.effect=="GREAT_APPEAL_BUT_NO_MORE_MOVES" and round_number<4:score-=60
		if score>highest:
			best=id
			highest=score
	return best

func turn(chosen: int) -> Array:
	if round_number>=MAX_ROUNDS or chosen not in entrants[0].moves:return []
	var results: Array=[]
	var played: Array=[]
	var frozen_by := -1
	var shuffle_next := false
	for n in entrants:
		n.appeal=0
		n.guard=0
		n.nervous=false
		n.fragile=false
		n.next=0
	for index in order:
		var n: Dictionary=entrants[index]
		if n.skip>0 or n.nervous:
			n.skip=maxi(0,n.skip-1)
			n.attention=false
			n.last=0
			results.append({"index":index,"move":0})
			continue
		var id: int=chosen if index==0 else cpu_pick(n)
		var m: Dictionary=data().moves[str(id)]
		var pos:=order.find(index)
		var last: Dictionary=entrants[played.back()] if not played.is_empty() else {}
		var prev: Dictionary=data().moves.get(str(last.get("last",0)),{})
		var points:=int(m.appeal)
		var excitement:=crowd_delta(int(m.category))
		match m.effect:
			"BETTER_IF_FIRST":if pos==0:points*=3
			"BETTER_IF_LAST":if pos==3:points*=3
			"BETTER_WHEN_LATER":points=maxi(10,20*pos)
			"QUALITY_DEPENDS_ON_TIMING":points=[10,10,10,20,20,20,40,40,60,80][rng.randi_range(0,9)]
			"BETTER_IF_SAME_TYPE":if prev.get("category",-1)==m.category:points*=3
			"AFFECTED_BY_PREV_APPEAL":
				if not last.is_empty():
					if last.appeal<30:points*=2
					elif last.appeal>30:points=0
			"APPEAL_AS_GOOD_AS_PREV_ONE":points+=maxi(0,last.get("appeal",0))
			"APPEAL_AS_GOOD_AS_PREV_ONES":
				var sum:=0
				for other in played:sum+=entrants[other].appeal
				points+=floori(maxi(sum,0)/20.0)*10
			"BETTER_WHEN_AUDIENCE_EXCITED":points=[10,20,30,50,60][crowd]
			"BETTER_WITH_GOOD_CONDITION":points+=2*int(n.stars)
			"IMPROVE_CONDITION_PREVENT_NERVOUSNESS":n.stars=mini(30,n.stars+10)
			"EXCITE_AUDIENCE_IN_ANY_CONTEST":excitement=1
			"DONT_EXCITE_AUDIENCE":frozen_by=index
			"GREAT_APPEAL_BUT_NO_MORE_MOVES":n.skip=MAX_ROUNDS
			"JAMS_OTHERS_BUT_MISS_ONE_TURN":n.skip=1
			"AVOID_STARTLE":n.guard=4
			"AVOID_STARTLE_ONCE":n.guard=1
			"USER_MORE_EASILY_STARTLED":n.fragile=true
			"NEXT_APPEAL_EARLIER":n.next=-1
			"NEXT_APPEAL_LATER":n.next=1
			"SCRAMBLE_NEXT_TURN_ORDER":shuffle_next=true
			"MAKE_FOLLOWING_MONS_NERVOUS":
				for later in order.slice(pos+1):
					if rng.randi_range(0,99)<maxi(10,60-int(entrants[later].stars)):entrants[later].nervous=true
		for other in played:
			var target: Dictionary=entrants[other]
			var jam:=int(m.jam)
			match m.effect:
				"STARTLE_PREV_MON","BADLY_STARTLE_FRONT_MON":if other!=played.back():jam=0
				"STARTLE_MON_WITH_JUDGES_ATTENTION":jam=50 if target.attention else 10
				"STARTLE_MONS_SAME_TYPE_APPEAL":jam=40 if data().moves[str(target.last)].category==m.category else 10
				"BADLY_STARTLE_MONS_WITH_GOOD_APPEALS":jam=maxi(10,floori(target.appeal/20.0)*10)
				"WORSEN_CONDITION_OF_PREV_MONS":target.stars=0
				"SHIFT_JUDGE_ATTENTION":target.attention=false
			if jam>0:
				if target.guard>0:target.guard-=1
				else:target.appeal-=jam*(2 if target.fragile else 1)
		var repeated: bool=id==n.last and m.effect!="REPETITION_NOT_BORING"
		n.repeats=n.repeats+1 if repeated else 0
		if repeated:points-=(n.repeats+1)*10
		var combo: bool=not repeated and n.attention and data().moves.get(str(n.last),{}).get("starter","0") in m.combo
		if combo:points+=int(m.appeal)
		n.attention=not combo and not repeated and m.starter!="0"
		if frozen_by in [-1,index] and (not repeated or excitement<0):
			crowd=clampi(crowd+excitement,0,5)
			if excitement>0:points+=60 if crowd==5 else 10
			if crowd==5:crowd=0
		n.appeal=points+int(n.stars)
		n.last=id
		played.append(index)
		results.append({"index":index,"move":id})
	for n in entrants:
		n.points+=n.appeal
		n.tie=rng.randi()
	order.sort_custom(func(a,b):
		if entrants[a].next!=entrants[b].next:return entrants[a].next<entrants[b].next
		if not shuffle_next and entrants[a].appeal!=entrants[b].appeal:return entrants[a].appeal>entrants[b].appeal
		return entrants[a].tie>entrants[b].tie)
	round_number+=1
	return results

func total(index: int) -> int:
	return int(entrants[index].opening)+2*int(entrants[index].points)

func standings() -> Array:
	var ranking:=range(entrants.size())
	ranking.sort_custom(func(a,b):
		if total(a)!=total(b):return total(a)>total(b)
		if entrants[a].opening!=entrants[b].opening:return entrants[a].opening>entrants[b].opening
		return entrants[a].tie>entrants[b].tie)
	return ranking
