extends RefCounted
## Sword/Shield stadium power spots. The original species and its dex form are preserved.
const KEY := "DYNAMAX"

static func available(b, side: String) -> bool:
	var mon: Dictionary = b.cur_a() if side == "a" else b.cur_b()
	return (b.galar_power_spot and (side == "b" or b.galar_band) and not b.galar_used[side]
		and not mon.get("fainted", false) and int(mon.hp) > 0 and int(mon.species_id) not in [888, 889, 890])

static func giant_key(mon:Dictionary)->String:
	if not mon.get("gmax_factor",false):return ""
	var regular:=str(mon.get("form",""))
	var desired:=str(mon.get("galar_gmax_key",""))
	if regular.contains("_CAP") or regular in ["PIKACHU_PARTNER","EEVEE_PARTNER"]:return ""
	if int(mon.species_id)==892 and desired.is_empty():
		desired="URSHIFU_RAPID_STRIKE_GMAX" if regular.contains("RAPID") else "URSHIFU_SINGLE_STRIKE_GMAX"
	var db=Engine.get_main_loop().root.get_node("Data")
	for form:Dictionary in db.forms_of(int(mon.species_id)):
		if form.get("kind","")=="gmax" and (desired.is_empty() or desired==str(form.key)):return str(form.key)
	return ""

static func transform(b, side: String) -> Dictionary:
	if not available(b,side):
		return {"ok":false,"text":"这里无法发动极巨化。"}
	var mon: Dictionary = b.cur_a() if side=="a" else b.cur_b()
	var initial := int(mon.max_hp)
	var level := clampi(int(mon.get("dynamax_level",0)),0,10)
	mon.galar_base_hp = initial
	mon.galar_turns = 3
	var giant:=giant_key(mon)
	if not giant.is_empty():
		mon.galar_original_form=mon.get("form","")
		mon.form=giant
	mon.gmax_active = true
	b.galar_used[side] = true
	if int(mon.species_id)!=292:
		mon.max_hp = floori(initial*(1.5+0.05*level))
		b._set_hp(mon,ceili(float(mon.hp)*int(mon.max_hp)/initial))
	return {"ok":true,"text":"%s %s了！"%[str(mon.name),"极巨化" if giant.is_empty() else "超极巨化"]}

static func before_move(b, side: String, choice: String) -> void:
	var mon: Dictionary = b.cur_a() if side=="a" else b.cur_b()
	var intent: bool = bool(mon.get("galar_intent",false)) or (side=="b" and int(mon.species_id)==b.galar_ace)
	mon.erase("galar_intent")
	if intent and choice.begins_with("move:") and available(b,side):
		b.log.append(transform(b,side).text)

static func restore(b,mon: Dictionary) -> void:
	if not mon.has("galar_base_hp"):return
	var hp := ceili(float(mon.hp)*int(mon.galar_base_hp)/int(mon.max_hp))
	mon.max_hp = mon.galar_base_hp
	mon.erase("galar_base_hp")
	mon.erase("galar_turns")
	if mon.has("galar_original_form"):
		mon.form=mon.galar_original_form
		mon.erase("galar_original_form")
	mon.gmax_active = false
	b._set_hp(mon,hp)
	b.log.append("%s 恢复了原来的大小。"%str(mon.name))

static func finish_turn(b) -> void:
	finish_mon(b,b.cur_a())
	finish_mon(b,b.cur_b())

static func finish_mon(b,mon:Dictionary)->void:
	if mon.has("galar_turns"):
		mon.galar_turns=int(mon.galar_turns)-1
		if int(mon.hp)<=0 or int(mon.galar_turns)==0:restore(b,mon)

const MAX_WEATHER := {"fire":"sun","water":"rain","rock":"sandstorm","ice":"snow"}
const MAX_TERRAIN := {"grass":"grassy","electric":"electric","psychic":"psychic","fairy":"misty"}
const MAX_RAISE := {"fighting":"atk","flying":"spe","poison":"spa","ground":"spd","steel":"def"}
const MAX_LOWER := {"normal":"spe","bug":"spa","ghost":"def","dragon":"atk","dark":"spd"}

static func after_hit(b,attacker:Dictionary,defender:Dictionary,move:Dictionary)->void:
	var type:=str(move.type)
	if MAX_WEATHER.has(type):b.log.append(b.field.set_weather(MAX_WEATHER[type]))
	elif MAX_TERRAIN.has(type):b.log.append(b.field.set_terrain(MAX_TERRAIN[type]))
	elif MAX_RAISE.has(type):b._apply_stage(attacker,MAX_RAISE[type],1,b.log)
	elif MAX_LOWER.has(type) and not defender.fainted:b._apply_stage(defender,MAX_LOWER[type],-1,b.log)

const SIDE_DAMAGE := {"G_MAX_VINE_LASH":"grass","G_MAX_WILDFIRE":"fire","G_MAX_CANNONADE":"water","G_MAX_VOLCALITH":"rock"}
const SPECIAL := ["G_MAX_ONE_BLOW","G_MAX_RAPID_FLOW","G_MAX_TERROR","G_MAX_RESONANCE","G_MAX_FINALE","G_MAX_CHI_STRIKE","G_MAX_DEPLETION","G_MAX_CENTIFERNO","G_MAX_SANDBLAST"]
static func handled(move:String)->bool:return SIDE_DAMAGE.has(move) or move in SPECIAL
static func active_mons(b,side:String)->Array:
	if b.has_method("viable"):
		var result:Array=[]
		for i in b.positions:
			if b.viable(side,i):result.append((b.team_a if side=="a" else b.team_b)[b.lanes[side][i]])
		return result
	return [b.cur_a() if side=="a" else b.cur_b()]
static func effective_max_hp(mon:Dictionary)->int:return int(mon.get("galar_base_hp",mon.max_hp))

static func special_hit(b,attacker:Dictionary,defender:Dictionary,mv:Dictionary)->void:
	var owner:String=b._side_of(attacker);var enemy:="a" if owner=="b" else "b"
	var move:=str(mv.key)
	if SIDE_DAMAGE.has(move):
		b.galar_side_damage[enemy]={"turns":4,"type":SIDE_DAMAGE[move]}
		b.log.append("强烈的能量留在了对手一侧的场地。")
		return
	match move:
		"G_MAX_FINALE":
			for mon:Dictionary in active_mons(b,owner):
				if not mon.fainted:b._set_hp(mon,mini(int(mon.max_hp),int(mon.hp)+maxi(1,effective_max_hp(mon)/6)))
			b.log.append("香甜的奶油为场上的伙伴回复了体力。")
		"G_MAX_RESONANCE":
			var duration:=8 if str(attacker.get("held",""))=="LIGHT_CLAY" else 5
			for screen in ["reflect","light_screen"]:b.field.set_screen(owner,screen,duration)
			b.log.append("极光幕保护了这一侧的场地。")
		"G_MAX_CHI_STRIKE":
			for mon:Dictionary in active_mons(b,owner):mon.crit_stage=int(mon.get("crit_stage",0))+1
			b.log.append("我方场上的宝可梦更容易击中要害了。")
		"G_MAX_TERROR":
			if "ghost" not in defender.types and not defender.fainted:
				defender.trapped=true
				defender.galar_terror_source=(b.team_a if owner=="a" else b.team_b).find(attacker)
				b.log.append("%s 被暗影困住，无法替换！"%defender.name)
		"G_MAX_CENTIFERNO","G_MAX_SANDBLAST":
			if not defender.fainted:
				defender.galar_bind=b.rng.randi_range(4,5)
				if "ghost" not in defender.types:defender.trapped=true
				b.log.append("%s 被旋涡困住了！"%defender.name)
		"G_MAX_DEPLETION":
			for mon:Dictionary in active_mons(b,enemy):
				var i:int=mon.moves.find(int(mon.get("last_move",0)))
				if i>=0:mon.pp[i]=maxi(0,int(mon.pp[i])-2)
			b.log.append("对方最近使用的招式减少了 2 PP。")

static func lingering(b)->void:
	for side:String in ["a","b"]:
		var hazard:Dictionary=b.galar_side_damage.get(side,{})
		for mon:Dictionary in active_mons(b,side):
			if mon.fainted:continue
			if mon.has("galar_terror_source"):
				var source_slot:=int(mon.galar_terror_source)
				var source_team:Array=b.team_b if side=="a" else b.team_a
				var foes:=active_mons(b,"b" if side=="a" else "a")
				if source_slot<0 or source_slot>=source_team.size() or source_team[source_slot].fainted or source_team[source_slot] not in foes:
					mon.erase("galar_terror_source")
					mon.trapped=int(mon.get("galar_bind",0))>0
			var damage:int=0
			if not hazard.is_empty() and str(hazard.type) not in mon.types:damage+=maxi(1,effective_max_hp(mon)/6)
			if int(mon.get("galar_bind",0))>0:
				damage+=maxi(1,effective_max_hp(mon)/8)
				mon.galar_bind=int(mon.galar_bind)-1
				if int(mon.galar_bind)==0:mon.trapped=mon.has("galar_terror_source")
			if damage>0:
				b._set_hp(mon,maxi(0,int(mon.hp)-damage));mon.fainted=int(mon.hp)==0
				b.log.append("%s 受到了超极巨招式的持续伤害。"%mon.name)
		if not hazard.is_empty():
			hazard.turns=int(hazard.turns)-1
			if int(hazard.turns)<=0:b.galar_side_damage.erase(side)
