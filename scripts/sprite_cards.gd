class_name SpriteCards
extends Control
## Base for the illustrated card screens (perk terminal, Cell shop): a row or
## grid of cards, each with a small looping scene drawn from the game's own
## sprites. Subclasses lay the cards out and draw the scenes.

signal picked(index: int)

const LOOP := 3.0

const C_PANEL := Color(0.08, 0.09, 0.13, 0.96)
const C_SCENE := Color(0.02, 0.025, 0.04)
const C_EDGE := Color(0.3, 0.35, 0.45)
const C_HOT := Color(1, 0.55, 0.15)
const C_GOOD := Color(0.4, 1.0, 0.5)
const C_GOLD := Color(1.0, 0.8, 0.25)
const C_DIM := Color(0.55, 0.58, 0.65)
const C_BAD := Color(1.0, 0.3, 0.25)
const C_TEXT := Color(0.85, 0.88, 0.95)

static var _used: Dictionary = {}

var _t := 0.0
var _hover := -1
## Keyboard-choosable cards (A / D, arrows, ENTER) always keep one card
## selected: it gets an orange "ENTER" tab and the other cards dim.
var selectable := false
var sel_verb := "TAKE"
## Mouse travel since the cards appeared; hover only takes over the keyboard
## selection once the mouse has really moved (not just sat under the cursor).
var _mouse_travel := 0.0
var _labels: Array[Label] = []
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	visible = false


## Overridden: how many cards there are and where each one sits.
func _card_count() -> int:
	return 0


func _card_rect(_i: int) -> Rect2:
	return Rect2()


func _clear_labels() -> void:
	for l in _labels:
		l.queue_free()
	_labels.clear()


func _label(p: Vector2, s: Vector2, font_size: int, c: Color, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.position = p
	l.size = s
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	_labels.append(l)
	return l


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()
		if selectable:
			for l in _labels:
				var i := _card_at(l.position + Vector2(2, 2))
				l.modulate.a = 1.0 if i == selected() else 0.5


## Moves the keyboard selection one card left (-1) or right (+1).
func move_sel(d: int) -> void:
	if _card_count() == 0:
		return
	_hover = posmod(selected() + d, _card_count())
	queue_redraw()


## Fresh cards: select the first one and wait for real mouse movement.
func reset_sel() -> void:
	_hover = 0
	_mouse_travel = 0.0


func selected() -> int:
	return _hover if _hover >= 0 else 0


## Drawn last by subclasses: the ENTER tab on the chosen card, dim the rest.
func _sel_marks() -> void:
	if not selectable:
		return
	for i in _card_count():
		var r := _card_rect(i)
		if i != selected():
			draw_rect(r, Color(0, 0, 0, 0.4))
			continue
		var bob := 1.5 * sin(_t * 6.0)
		var tab := Rect2(r.get_center().x - 34, r.position.y - 6 + bob, 68, 11)
		draw_rect(tab, C_HOT)
		draw_string(_font, Vector2(tab.position.x, tab.position.y + 8.5), "ENTER: " + _verb(i), HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 7, Color.BLACK)


## The word on the ENTER tab for card `i`.
func _verb(_i: int) -> String:
	return sel_verb


func _card_at(p: Vector2) -> int:
	for i in _card_count():
		if _card_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_travel += event.relative.length()
		if selectable and _mouse_travel < 12.0:
			return
		var i := _card_at(event.position)
		if i >= 0 or not selectable:
			_hover = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := _card_at(event.position)
		if i >= 0:
			picked.emit(i)
			accept_event()


## Card background and its scene box, with a floor strip for sprites to stand on.
func _card_frame(r: Rect2, scene: Rect2, hot: bool) -> void:
	draw_rect(r, C_PANEL)
	draw_rect(r, C_HOT if hot else C_EDGE, false, 2.0 if hot else 1.0)
	draw_rect(scene, C_SCENE)
	var fy := scene.end.y - 12
	draw_rect(Rect2(scene.position.x, fy, scene.size.x, 12), Color(0.07, 0.07, 0.09))
	draw_line(Vector2(scene.position.x, fy), Vector2(scene.end.x, fy), Color(0.16, 0.17, 0.2))


# ---------------------------------------------------------------- helpers

## Draws a sprite whose art sits on the bottom edge, centred on `x`.
func _spr(t: Texture2D, x: float, bottom: float, h: float, tint := Color.WHITE, flip := false) -> void:
	var w := h * t.get_width() / float(t.get_height())
	var r := Rect2(x - w / 2.0, bottom - h, w, h)
	if flip:
		r.position.x += w
		r.size.x = -w
	draw_texture_rect(t, r, false, tint)


## Item sprite cropped to its visible pixels, so small pickups read clearly.
func _item(tex_name: String, x: float, bottom: float, h: float, tint := Color.WHITE) -> void:
	var t := Tex.tex(tex_name)
	if not _used.has(tex_name):
		var img := t.get_image()
		_used[tex_name] = img.get_used_rect() if img != null else Rect2i(Vector2i.ZERO, t.get_size())
	var src: Rect2i = _used[tex_name]
	var w := h * src.size.x / float(src.size.y)
	draw_texture_rect_region(t, Rect2(x - w / 2.0, bottom - h, w, h), Rect2(src), tint)


func _txt(s: String, p: Vector2, fsize: int, c: Color, strike := false) -> void:
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := p - Vector2(w / 2.0, 0)
	draw_string_outline(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 3, Color(0, 0, 0, c.a))
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, c)
	if strike:
		draw_line(pos + Vector2(-1, -fsize * 0.35), pos + Vector2(w + 1, -fsize * 0.35), c, 1.0)


func _bar(p: Vector2, w: float, h: float, frac: float, c: Color) -> void:
	draw_rect(Rect2(p, Vector2(w, h)), Color(0.05, 0.02, 0.02))
	draw_rect(Rect2(p + Vector2(1, 1), Vector2((w - 2) * clampf(frac, 0, 1), h - 2)), c)


## 0 -> 1 as t goes from a to b.
func _k(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


## Text that floats up and fades out after `start`.
func _pop(s: String, p: Vector2, t: float, start: float, c: Color, fsize := 10) -> void:
	if t < start:
		return
	var k := _k(t, start, start + 1.2)
	var col := c
	col.a = 1.0 - _k(t, start + 0.9, start + 1.4)
	_txt(s, p - Vector2(0, k * 12), fsize, col)


func _flash(p: Vector2, r: float) -> void:
	draw_circle(p, r, Color(1, 0.85, 0.4, 0.9))
	draw_circle(p, r * 0.5, Color(1, 1, 0.85))
