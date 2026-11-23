extends RefCounted
## Sword/Shield stadium power spots. The original species and its dex form are preserved.
const KEY := "DYNAMAX"

static func available(b, side: String) -> bool:
	var mon: Dictionary = b.cur_a() if side == "a" else b.cur_b()
	return (b.galar_power_spot and (side == "b" or b.galar_band) and not b.galar_used[side]
		and not mon.get("fainted", false) and int(mon.hp) > 0 and int(mon.species_id) not in [888, 889, 890])

static func transform(b, side: String) -> Dictionary:
	if not available(b,side):
		return {"ok":false,"text":"这里无法发动极巨化。"}
	var mon: Dictionary = b.cur_a() if side=="a" else b.cur_b()
	var initial := int(mon.max_hp)
	var level := clampi(int(mon.get("dynamax_level",0)),0,10)
	mon.galar_base_hp = initial
	mon.galar_turns = 3
	mon.gmax_active = true
	b.galar_used[side] = true
	if int(mon.species_id)!=292:
		mon.max_hp = floori(initial*(1.5+0.05*level))
		b._set_hp(mon,ceili(float(mon.hp)*int(mon.max_hp)/initial))
	return {"ok":true,"text":"%s 极巨化了！"%str(mon.name)}

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
	mon.gmax_active = false
	b._set_hp(mon,hp)
	b.log.append("%s 恢复了原来的大小。"%str(mon.name))

static func finish_turn(b) -> void:
	for mon in [b.cur_a(),b.cur_b()]:
		if not mon.has("galar_turns"):continue
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
