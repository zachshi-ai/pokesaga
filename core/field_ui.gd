extends RefCounted
## Shared controls for the touch menus. All sizes are in the 480 × 320 design viewport.

const Party := preload("res://core/party.gd")
const DexArt := preload("res://core/dex_art.gd")
const FingerScroll := preload("res://core/finger_scroll.gd")
const INK := Color("#193e3c")
const MUTED := Color("#506761")
const PAPER := Color("#f4f2e7")
const CARD := Color("#fffef5")
const LINE := Color("#c8d7c6")
const GREEN := Color("#216c60")
const PALE := Color("#dcebd9")
const ORANGE := Color("#e87a49")
const SUN := Color("#f6ce76")
const MEADOW := preload("res://assets/ui/field/meadow.webp")

static func box(fill: Color, border: Color = LINE, radius: int = 6) -> StyleBoxFlat:
	var bg := StyleBoxFlat.new()
	bg.bg_color = fill
	bg.border_color = border
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(radius)
	bg.content_margin_left = 7
	bg.content_margin_right = 7
	bg.content_margin_top = 2
	bg.content_margin_bottom = 2
	return bg

static func style_button(btn: Button, active := false) -> void:
	btn.add_theme_stylebox_override("normal", box(GREEN if active else CARD, GREEN if active else LINE))
	btn.add_theme_stylebox_override("hover", box(Color("#2d786a") if active else PALE, GREEN))
	btn.add_theme_stylebox_override("pressed", box(INK, INK))
	btn.add_theme_stylebox_override("disabled", box(Color("#e5e7dc"), LINE))
	var focus := box(Color.TRANSPARENT, ORANGE)
	focus.set_border_width_all(2)
	btn.add_theme_stylebox_override("focus",focus)
	btn.add_theme_color_override("font_color", CARD if active else INK)
	btn.add_theme_color_override("font_hover_color", CARD if active else INK)
	btn.add_theme_color_override("font_pressed_color", CARD)
	btn.add_theme_color_override("font_disabled_color", MUTED)
	btn.add_theme_font_size_override("font_size", 13)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE

static func label(value: String, fs := 13, color := INK) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func button(value: String, fn: Callable, active := false) -> Button:
	var b := Button.new()
	b.text = value
	b.custom_minimum_size = Vector2(0,36)
	style_button(b, active)
	if fn.is_valid():
		b.pressed.connect(fn)
	return b

static func place(parent: Control, child: Control, x: float, y: float, w: float, h: float) -> void:
	parent.add_child(child)
	child.position = Vector2(x,y)
	child.size = Vector2(w,h)

static func sheet(parent: Control, fill := PAPER) -> ColorRect:
	var panel := ColorRect.new()
	panel.color = fill
	parent.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	return panel

static func art(path: String) -> TextureRect:
	var t := TextureRect.new()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not path.is_empty() and ResourceLoader.exists(path):
		t.texture = load(path)
	return t

static func portrait(id: int, form := "") -> TextureRect:
	var texture := DexArt.model_view(id,form,false)
	var t := art("")
	t.texture = texture if texture != null else load(Data.party_hd_path(id) if form.is_empty() else Data.sprite_path(id,form))
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	return t

static func member_portrait(mon: Dictionary) -> TextureRect:
	var id := int(mon.get("species_id",0))
	var form := str(mon.get("form",""))
	if Party.shiny_kind(mon)=="none":
		return portrait(id, form)
	var t := art("")
	t.texture = DexArt.texture(id, form, true)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t

static func header(parent: Control, title: String, meta: String, back: Callable) -> void:
	var band := ColorRect.new()
	band.color = CARD
	place(parent,band,0,0,parent.size.x,47)
	var rule := ColorRect.new()
	rule.color = LINE
	place(band,rule,0,46,parent.size.x,1)
	var back_btn := button("‹ 返回",back)
	place(band,back_btn,8,5,64,36)
	place(band,label(title,20),82,3,138,39)
	var extra := label(meta,12,MUTED)
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	place(band,extra,220,5,parent.size.x-230,35)

static func scroll(parent: Control, pos: Vector2, extent: Vector2) -> ScrollContainer:
	var sc := FingerScroll.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.scroll_deadzone = 7
	place(parent,sc,pos.x,pos.y,extent.x,extent.y)
	return sc

static func clear(parent: Node) -> void:
	for c in parent.get_children():
		parent.remove_child(c)
		c.queue_free()

static func wrapped(value: String, fs := 13, color := INK) -> Label:
	var l := label(value,fs,color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func landscape(parent: Control, x: float, y: float, w: float, h: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = MEADOW
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(parent,t,x,y,w,h)
	return t

static func meter(parent: Control, x: float, y: float, w: float, value: float) -> void:
	var track := ColorRect.new()
	track.color = LINE
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(parent,track,x,y,w,4)
	var level := ColorRect.new()
	level.color = GREEN if value > 0.5 else (Color("#dcaa43") if value > 0.2 else ORANGE)
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(track,level,0,0,clampf(value,0,1)*w,4)

static func list_box(sc: ScrollContainer, gap := 5) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation",gap)
	sc.add_child(v)
	return v
