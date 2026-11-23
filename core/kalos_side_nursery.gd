extends RefCounted
## Kalos deposits and carried eggs are saved independently from other regions.
const Party := preload("res://core/party.gd")
const FR := preload("res://core/frlg_sidequests.gd")
const Care := preload("res://core/sinnoh_day_care.gd")

static func state(g) -> Dictionary:
	return g.save_data.get_or_add("kalos_nursery",{"parents":[],"steps":0,"eggs":[]})

static func open(g) -> void:
	var s:=state(g)
	var labels: Array=[]
	if s.has("egg"):labels.append("领取宝可梦蛋")
	if s.parents.size()<2:labels.append("寄放伙伴")
	for p in s.parents:labels.append("领回%s　Lv.%d"%[p.mon.name,Care.preview(p).level])
	labels.append("离开")
	g._pick("7号道路 · 宝可梦培育屋",labels,func(i):
		var choice: String=labels[i]
		if choice=="领取宝可梦蛋":
			if Party.occupied(g.save_data.party)+s.eggs.size()>=Party.MAX_SIZE:g._dialog(["请先腾出一个队伍位置。"]);return
			s.eggs.append(s.egg)
			s.erase("egg")
			g._give_item("卡洛斯的蛋",1,"key")
			g._persist()
			g._dialog(["你接过了培育家照顾的宝可梦蛋。"])
		elif choice=="寄放伙伴":
			FR.pick_party(g,"寄放哪只宝可梦？",func(m):return not m.get("is_egg",false) and not m.has("fused_part"),func(slot):
				var mon: Dictionary=g.save_data.party[slot]
				if not g.save_data.party.any(func(m):return not is_same(m,mon) and not m.is_empty() and int(m.get("hp",0))>0):
					g._dialog(["至少留一只可以同行的伙伴吧。"]);return
				Party.restore_trim(mon,true)
				s.parents.append({"mon":mon,"steps":0})
				g.save_data.party.remove_at(slot)
				g._persist();g._dialog(["我们会照顾好%s。"%mon.name]))
		elif choice.begins_with("领回"):
			var index: int=i-int(s.has("egg"))-int(s.parents.size()<2)
			var entry: Dictionary=s.parents[index]
			var mon:=Care.preview(entry)
			var price:=100*(1+int(mon.level)-int(entry.mon.level))
			g._pick("领回%s需要 %d 元。"%[mon.name,price],["领回","取消"],func(n):
				if n!=0:return
				if int(g.save_data.money)<price or Party.occupied(g.save_data.party)>=Party.MAX_SIZE:
					g._dialog(["请检查队伍空位和余额。"]);return
				g.save_data.money-=price
				g._store_mon(mon)
				s.parents.remove_at(index)
				g._persist();g._dialog(["%s 回到了队伍。"%mon.name])))

static var archive: Dictionary
static func data() -> Dictionary:
	if archive.is_empty():archive=JSON.parse_string(FileAccess.get_file_as_string("res://content/kalos_breeding.json"))
	return archive

static func chance(g,a: Dictionary,b: Dictionary) -> int:
	var ida:=int(a.species_id);var idb:=int(b.species_id)
	var x: Array=data().get(str(ida),[[]])[0];var y: Array=data().get(str(idb),[[]])[0]
	if x.is_empty() or y.is_empty() or x.has(15.0) or y.has(15.0) or ida==132 and idb==132:return 0
	if ida!=132 and idb!=132:
		if a.get("sex","")==b.get("sex","") or not a.get("sex","") in ["male","female"] or not b.get("sex","") in ["male","female"]:return 0
		if not x.any(func(n):return y.has(n)):return 0
	var foreign:=int(a.get("ot_id",0))!=int(b.get("ot_id",0))
	var base:=70 if ida==idb and foreign else 50 if ida==idb or foreign else 20
	return int({20:40,50:80,70:88}[base]) if g._flags().get("ks_oval",false) else base

static func egg(g,a: Dictionary,b: Dictionary) -> Dictionary:
	var parent:=a if a.get("sex","")=="female" or int(b.species_id)==132 else b
	if int(parent.species_id)==132:parent=b if is_same(a,parent) else a
	var id:=int(data()[str(int(parent.species_id))][1])
	var holds:=[a.get("held",""),b.get("held","")]
	if Care.INCENSE.has(id) and not holds.has(Care.INCENSE[id][0]):id=int(Care.INCENSE[id][1])
	if id in [29,32]:id=[29,32][g.rng.randi_range(0,1)]
	if id in [313,314]:id=[313,314][g.rng.randi_range(0,1)]
	if id==490:id=489
	var info: Array=data()[str(id)]
	var mon: Dictionary=load("res://core/kalos_side.gd").roster_mon(g,id,1)
	var inherited: Array=info[3].map(func(n):return int(n))
	var level_moves: Array=preload("res://core/kalos_field.gd").learnset(id).map(func(row):return int(row[1]))
	for n in a.moves+b.moves:
		if inherited.has(int(n)) or (int(n) in level_moves and a.moves.any(func(k):return int(n)==int(k)) and b.moves.any(func(k):return int(n)==int(k))):Care.add_move(mon.moves,int(n))
	if id==172 and "LIGHT_BALL" in holds:Care.add_move(mon.moves,344)
	var parents:=[a,b]
	var stones:=parents.filter(func(m):return m.get("held","")=="EVERSTONE")
	if not stones.is_empty():mon.nature=stones[g.rng.randi_range(0,stones.size()-1)].nature
	var stats:=["hp","atk","def","spa","spd","spe"]
	var nstats:=5 if "DESTINY_KNOT" in holds else 3
	mon.ivs={}
	for stat in stats:mon.ivs[stat]=g.rng.randi_range(0,31)
	var power_parents:=parents.filter(func(m):return preload("res://core/unova_side_breeding.gd").POWER.has(str(m.get("held",""))))
	if not power_parents.is_empty():
		var forced: Dictionary=power_parents[g.rng.randi_range(0,power_parents.size()-1)]
		var stat: String=preload("res://core/unova_side_breeding.gd").POWER[forced.held]
		mon.ivs[stat]=int(forced.get("ivs",{}).get(stat,31))
		stats.erase(stat);nstats-=1
	for i in nstats:
		var stat: String=stats.pop_at(g.rng.randi_range(0,stats.size()-1))
		mon.ivs[stat]=int(parents[g.rng.randi_range(0,1)].get("ivs",{}).get(stat,31))
	var tries:=1+2*int(bool(g._flags().get("ks_shiny",false)))
	for i in tries:
		var kind:=Party.roll_shiny(g.appearance_rng)
		Party.set_shiny_kind(mon,kind)
		if kind!="none":break
	Party.recalc(mon);mon.hp=mon.max_hp
	mon.kalos_egg_memory=mon.moves.duplicate()
	return {"mon":mon,"steps":maxi(1,int(info[2]))*257}

static func step(g) -> bool:
	var s: Dictionary=g.save_data.get("kalos_nursery",{})
	if s.is_empty():return false
	for parent in s.parents:parent.steps+=1
	s.steps=int(s.steps)+1
	if int(s.steps)%256==0 and s.parents.size()==2 and not s.has("egg"):
		var a: Dictionary=s.parents[0].mon;var b: Dictionary=s.parents[1].mon
		if g.rng.randi_range(0,99)<chance(g,a,b):s.egg=egg(g,a,b)
	var warmth:=2 if g.save_data.party.any(func(m):return m is Dictionary and m.get("ability",0) in [40,49,"FLAME_BODY","MAGMA_ARMOR"]) else 1
	var progress:=preload("res://core/kalos_opowers.gd").hatch_steps(g,s,warmth) if not s.eggs.is_empty() else 0
	for pending in s.eggs:
		pending.steps-=progress
		if pending.steps>0:continue
		s.eggs.erase(pending)
		g._consume_item("卡洛斯的蛋")
		g._store_mon(pending.mon)
		g._persist()
		g._dialog(["蛋壳在小悠手中摇晃起来。%s 孵出来了！"%pending.mon.name])
		return true
	return false
