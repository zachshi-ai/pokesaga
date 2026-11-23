extends Control
signal closed
const UI=preload("res://core/field_ui.gd")
const Art=preload("res://core/dex_art.gd")
const WALK=preload("res://assets/player_emerald.png")
const GUIDE=preload("res://assets/alola/guide_player_emerald.png")
const FRAMES=["无边框","海蓝边框","夕阳边框"]
const BGS={"海滩":"海边","花园":"树荫","夜空":"星光","究极空间":"异界"}
const CATALOG:={"海滩":["#93dadd","#e4efe0","#418eb0","#eed398"],"花园":["#b3ded2","#e9e8ce","#719867","#a3c58c"],"夜空":["#394667","#776693","#4d6076","#788193"],"究极空间":["#342b60","#86629b","#436479","#6f67a2"]}
const DECALS={"花朵":"flowers","精灵球":"pickup","星星":"alola_crystal","霸主贴纸":"alola_sticker"}
const FILES:="user://alola-album/"
const SIZE:=Vector2i(320,184)
var game
var mon:Dictionary={}
var pose:=0
var bg:="海滩"
var sticker:=""
var frame:=0
var stamps:Array=[]
var index:=-1
var preview_rect:TextureRect
var notice:=""
var picture:Image

static func bitmap(tex:Texture2D) -> Image:
	var img:=tex.get_image()
	if img.is_compressed():img.decompress()
	img.convert(Image.FORMAT_RGBA8);return img

func start(g,who:Dictionary) -> void:
	game=g;mon=who;set_anchors_and_offsets_preset(PRESET_FULL_RECT);render()
func gallery(g,i:int) -> void:
	game=g;index=i;set_anchors_and_offsets_preset(PRESET_FULL_RECT);render()
func sprite(img:Image,art:Texture2D,pt:Vector2i,height:int,flip:=false) -> void:
	var icon:=bitmap(art)
	var cropped:=icon.get_used_rect()
	if cropped.size.x==0:return
	icon=icon.get_region(cropped)
	icon.resize(maxi(1,roundi(float(icon.get_width())*height/icon.get_height())),height,Image.INTERPOLATE_NEAREST)
	if flip:icon.flip_x()
	img.blend_rect(icon,Rect2i(Vector2i.ZERO,icon.get_size()),Vector2i(pt.x-icon.get_width()/2,pt.y-height))
func compose() -> Image:
	var img:=Image.create_empty(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	var palette:Array=CATALOG[bg]
	for y in SIZE.y:
		var col:Color=Color(palette[0]).lerp(Color(palette[1]),floorf(float(y)/8)*8/100) if y<98 else Color(palette[2] if y<133 else palette[3])
		img.fill_rect(Rect2i(0,y,SIZE.x,1),col)
	if bg in ["海滩","花园"]:
		for j in 3:
			var x:=15+j*108
			img.fill_rect(Rect2i(x,24+j%2*14,40,7),Color("#f1f1d6"));img.fill_rect(Rect2i(x+11,19+j%2*14,21,9),Color("#f1f1d6"))
	else:
		for i in 41:
			img.fill_rect(Rect2i((i*73)%320,5+(i*41)%83,2 if i%4 else 3,2),Color("#f1dfb4"))
	if bg=="花园":
		for i in 11:sprite(img,load("res://assets/emerald/field/tree.png"),Vector2i(i*32,134+(i%3)*2),34+(i%4)*9)
	elif bg=="海滩":
		for i in 9:img.fill_rect(Rect2i((i*71)%320,103+(i*13)%27,10+i%11,2),Color("#8dcacd"))
		img.fill_rect(Rect2i(0,131,320,3),Color("#f7edca"))
	elif bg=="究极空间":
		for i in 9:sprite(img,load("res://assets/emerald/field/alola_crystal.png"),Vector2i(8+i*40,135),22+(i*7)%34)
	var sheet:=bitmap(GUIDE if game._flags().get("a_guide_worn",false) else WALK)
	var actor:=sheet.get_region(Rect2i(16*[0,2,4][pose%3],0,16,32))
	var pose_height:int=[73,69,76][pose%3]
	sprite(img,ImageTexture.create_from_image(actor),Vector2i(105,163),pose_height,pose==1)
	var poke:=Art.battle_texture(int(mon.species_id),str(mon.get("form","")),preload("res://core/party.gd").shiny_kind(mon)!="none",false)
	if poke==null:poke=load(game.get_node("/root/Data").sprite_path(int(mon.species_id),str(mon.get("form",""))))
	sprite(img,poke,Vector2i(207,164 if pose!=2 else 145),[79,67,85][pose%3],pose==1)
	for mark in stamps:
		sprite(img,load("res://assets/emerald/field/"+str(DECALS[mark[0]])+".png"),Vector2i(mark[1],mark[2]),19)
	if frame>0:
		var edge:=Color("#47789b") if frame==1 else Color("#ce8968")
		for rect in [Rect2i(0,0,320,5),Rect2i(0,179,320,5),Rect2i(0,0,5,184),Rect2i(315,0,5,184)]:img.fill_rect(rect,edge)
	return img
func tap(event:InputEvent) -> void:
	if index>=0 or sticker.is_empty():return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var pos:Vector2=event.position*Vector2(SIZE)/preview_rect.size
		stamps.append([sticker,clampi(int(pos.x),9,310),clampi(int(pos.y)+9,18,181)])
		sticker="";notice="";render()
func choose(items:Array,callback:Callable) -> void:
	game._pick("拍摄设置",items,func(i):callback.call(i);render())
func shutter() -> void:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FILES))!=OK:
		notice="无法打开本机相册。";render();return
	var list:Array=game.save_data.get_or_add("alola_photos",[])
	var name:="photo-%d-%d-%d.png"%[int(Time.get_unix_time_from_system()),Time.get_ticks_usec(),list.size()]
	var path:=FILES+name
	if picture.save_png(path)!=OK:notice="照片未能保存。";render();return
	list.append({"file":name,"name":mon.name,"species":mon.species_id,"at":int(Time.get_unix_time_from_system()),"bg":bg})
	if not game._persist():
		list.pop_back();DirAccess.remove_absolute(ProjectSettings.globalize_path(path));notice="存档未能保存。"
	else:notice="已收入阿罗拉相册。"
	render()
func render() -> void:
	for c in get_children():remove_child(c);c.queue_free()
	var paper:=UI.sheet(self,Color("#f4f0dc"));var photos:Array=game.save_data.get("alola_photos",[])
	var title:="阿罗拉摄影俱乐部" if index<0 else "%s · %s (%d/%d)"%[photos[index].name,photos[index].bg,index+1,photos.size()]
	UI.place(paper,UI.label(title,15),14,3,362,32);UI.place(paper,UI.button("返回",finish),398,2,68,36)
	if index>=0:
		picture=Image.load_from_file(FILES+str(photos[index].file))
	else:picture=compose()
	preview_rect=TextureRect.new();preview_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview_rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if picture and not picture.is_empty():preview_rect.texture=ImageTexture.create_from_image(picture)
	UI.place(paper,preview_rect,57,39,366,210)
	preview_rect.gui_input.connect(tap)
	if index>=0:
		UI.place(paper,UI.button("上一张",func():index=posmod(index-1,photos.size());render()),43,259,132,48)
		UI.place(paper,UI.button("下一张",func():index=(index+1)%photos.size();render()),305,259,132,48)
		return
	UI.place(paper,UI.label(notice if notice!="" else ("触碰画面贴上"+sticker if sticker!="" else "%s · %s"%[bg,mon.name]),12),13,249,452,22)
	var controls={"背景":func():
		var opts:=["海滩","花园"]
		if game._flags().get("a_electric",false):opts.append("夜空")
		if game._flags().get("a_ultra_necrozma",false):opts.append("究极空间")
		choose(opts,func(i):bg=opts[i]),
	"姿势":func():choose(["并肩","侧身","跃起"],func(i):pose=i),
	"贴纸":func():
		var opts:=["花朵","精灵球"]
		if game._flags().get("a_hala",false):opts.append("星星")
		if game._flags().get("a_credits",false):opts.append("霸主贴纸")
		opts.append("撤回上一张")
		choose(opts,func(i):
			if opts[i]=="撤回上一张":
				if not stamps.is_empty():stamps.pop_back()
			else:sticker=opts[i]),
	"边框":func():choose(FRAMES,func(i):frame=i),
	"拍照":shutter}
	for i in controls.size():
		var key:String=controls.keys()[i];UI.place(paper,UI.button(key,controls[key],key=="拍照"),7+i*94,272,87,41)
func finish() -> void:closed.emit();queue_free()
func handle_back() -> void:finish()
