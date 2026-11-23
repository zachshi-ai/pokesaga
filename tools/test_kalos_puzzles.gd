extends SceneTree
## Test the XY room geometry, including button persistence and the former early-entry shortcuts.
const Gyms:=preload("res://core/kalos_gyms.gd")
const Geometry:=preload("res://core/kalos_geometry.gd")
class Field extends "res://core/world.gd":
	func _ready()->void:pass
	func _rebuild(_state=null)->void:pass
class Silent:
	func play_sfx(_key:String)->void:pass
class SwitchControls:
	var world
	var snd:=Silent.new()
	var progress:Dictionary={}
	func _flags()->Dictionary:return progress
	func _show_toast(_text:String)->void:pass
	func _persist()->void:pass
var bad:=0
func check(ok:bool,note:String)->void:
	if not ok:
		bad+=1
		push_error("KALOS PUZZLE FAIL "+note)
func _initialize()->void:run.call_deferred()
func run()->void:
	var db=root.get_node("Data")
	var w:=Field.new()
	root.add_child(w)
	var snow:Dictionary=db.load_map("kalos","kalos_gym_snowbelle")
	w.load_map(snow)
	var controls:=SwitchControls.new()
	controls.world=w
	var pads:Dictionary={}
	for o in snow.objects:
		if o.get("kind","")=="kalos_ice_switch":pads[o.color]=o
	check(pads.size()==4,"four coloured switches")
	Gyms.ice_switch(controls,pads.pink)
	check(controls.progress.is_empty(),"fighting the guardian is required")
	for id in [169,32,168,31]:controls.progress["k_trainer_%d"%id]=true
	for item in [["pink",2],["blue",3],["pink",3],["yellow",1],["green",3]]:
		for i in int(item[1]):Gyms.ice_switch(controls,pads[item[0]])
		if item==["pink",2]:
			check(w.can_enter(Vector2i(24,36),Vector2i.RIGHT),"first ice bridge did not turn")
			check(not w.can_enter(Vector2i(19,30),Vector2i.UP),"centre bridge open too soon")
		if item==["pink",3]:
			check(w.can_enter(Vector2i(19,30),Vector2i.UP),"centre bridge did not turn")
			check(not w.can_enter(Vector2i(19,13),Vector2i.UP),"leader bridge open too soon")
	check(w.can_enter(Vector2i(19,13),Vector2i.UP),"leader bridge did not turn")
	w.taken=JSON.parse_string(JSON.stringify(controls.progress))
	check(w.can_enter(Vector2i(19,13),Vector2i.UP),"reloaded active ice bridge")
	var kalos:Dictionary=db.load_map("kalos","kalos_geosenge")
	var normal:=Geometry.town(w,kalos.hoenn_art,{})
	var initial: Array=w.emerald_collision
	var weapon:=Geometry.town(w,kalos.hoenn_art,{"k_two_buttons":true})
	var during: Array=w.emerald_collision
	var crater:=Geometry.town(w,kalos.hoenn_art,{"k_two_buttons":true,"k_last_lysandre":true})
	check(initial!=during and during!=w.emerald_collision,"three Geosenge collision phases")
	check(normal.scene!=weapon.scene and weapon.scene!=crater.scene,"three Geosenge field appearances")
	var fairy:Dictionary=db.load_map("kalos","kalos_gym_laverre")
	var portals:Array=fairy.warps.filter(func(row):return row.to.map==fairy.id)
	check(portals.size()==24 and portals.filter(func(row):return row.to.get("kalos_requires",[])==["k_badge_6"]).size()==2,"twelve pairs and the badge shortcut")
	if bad==0:print("KALOS PUZZLES PASS ice rotations, trainer gates, save reload, Geosenge phases, Laverre portals")
	quit(int(bad>0))
