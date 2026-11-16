class_name ModeSelect
extends Control
## Title screen game mode picker: a dropdown box showing the chosen mode,
## a PLAY button, and the mode's description. Clicking the box (or M / Space)
## opens a list of every mode with a one-line summary.

signal play_pressed
signal changed

const MODES := ["escape", "purge", "ghost", "gauntlet", "scramble", "daily", "classic"]
const SUMMARY := {
	"escape": "Roguelite run: 2 generated floors, then the Overseer",
	"purge": "An unkillable Hunter Warden stalks every floor",
	"ghost": "No ammo - free every hostage to open the exit",
	"gauntlet": "Endless small floors - how deep can you get?",
	"scramble": "Random prototype guns issued every floor",
	"daily": "Today's seed, the same for everyone",
	"classic": "The handcrafted campaign floors, no Cell or perks",
}
const CLASSIC_DESC := "The original handmade floors in order, with no Cell upgrades or perks. Score carries from floor to floor."

const Y := 110.0
const BOX := Rect2(116, Y, 186, 20)
const PLAY := Rect2(308, Y, 56, 20)
const ROW_H := 17.0
const LIST_X := 90.0
const LIST_W := 300.0

const C_PANEL := Color(0.08, 0.09, 0.13, 0.98)
const C_EDGE := Color(0.3, 0.35, 0.45)
const C_HOT := Color(1, 0.55, 0.15)
const C_GOLD := Color(1.0, 0.8, 0.25)
const C_DIM := Color(0.55, 0.58, 0.65)
const C_TEXT := Color(0.85, 0.88, 0.95)

var open := false
var index := 0
var hover := -1
var _font: Font
var _list: Control
var desc: Label
var _t := 0.0


func _ready() -> void:
	_font = ThemeDB.fallback_font
	size = Vector2(Hud.W, Hud.H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	desc = Label.new()
	desc.position = Vector2(80, Y + 25)
	desc.size = Vector2(Hud.W - 160, 24)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 8)
	desc.add_theme_color_override("font_color", C_DIM)
	desc.add_theme_color_override("font_outline_color", Color.BLACK)
	desc.add_theme_constant_override("outline_size", 3)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(desc)
	# The open list is its own child so it draws over the labels below it.
	_list = Control.new()
	_list.size = size
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.draw.connect(_draw_list)
	add_child(_list)
	visible = false


func mode() -> String:
	return MODES[index]


func show_mode(id: String) -> void:
	index = maxi(MODES.find(id), 0)
	open = false
	visible = true
	_refresh()


func _refresh() -> void:
	desc.text = CLASSIC_DESC if mode() == "classic" else Game.PROTOCOLS[mode()][1]
	desc.visible = not open
	queue_redraw()
	_list.queue_redraw()


## Step the chosen mode (closed) or the highlighted row (open).
func step(d: int) -> void:
	if open:
		hover = posmod((hover if hover >= 0 else index) + d, MODES.size())
		_refresh()
	else:
		index = posmod(index + d, MODES.size())
		changed.emit()
		_refresh()


func toggle() -> void:
	open = not open
	hover = index if open else -1
	_refresh()


func close() -> void:
	open = false
	hover = -1
	_refresh()


## Enter: pick the highlighted row if the list is open, else play.
func confirm() -> void:
	if open:
		_pick(hover if hover >= 0 else index)
	else:
		play_pressed.emit()


func _pick(i: int) -> void:
	index = i
	close()
	changed.emit()


func _row_rect(i: int) -> Rect2:
	return Rect2(LIST_X, BOX.end.y + 2 + i * ROW_H, LIST_W, ROW_H)


func _row_at(p: Vector2) -> int:
	for i in MODES.size():
		if _row_rect(i).has_point(p):
			return i
	return -1


## A tap or click at `p` (screen coordinates). Returns true if it hit something.
func tap(p: Vector2) -> bool:
	if open:
		var r := _row_at(p)
		if r >= 0:
			_pick(r)
		else:
			close()
		return true
	if BOX.grow(3).has_point(p):
		toggle()
		return true
	if PLAY.grow(3).has_point(p):
		play_pressed.emit()
		return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and open:
		var r := _row_at(event.position)
		if r >= 0 and r != hover:
			hover = r
			_list.queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			tap(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			step(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			step(1)
		accept_event()


func _process(delta: float) -> void:
	if visible:
		_t += delta
		queue_redraw()


func _name(id: String) -> String:
	return "Classic Campaign" if id == "classic" else Game.PROTOCOLS[id][0]


func _text(s: String, p: Vector2, fsize: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0, on: CanvasItem = self) -> void:
	on.draw_string_outline(_font, p, s, align, w, fsize, 3, Color.BLACK)
	on.draw_string(_font, p, s, align, w, fsize, c)


func _draw() -> void:
	_text("GAME MODE", Vector2(BOX.position.x + 2, BOX.position.y - 4), 8, C_DIM)
	# The dropdown box.
	draw_rect(BOX, C_PANEL)
	draw_rect(BOX, C_HOT if open else C_EDGE, false, 1.0)
	_text(_name(mode()), Vector2(BOX.position.x + 7, BOX.position.y + 14), 11, C_HOT)
	if mode() == "purge":
		_badge(Vector2(BOX.position.x + 7 + _font.get_string_size(_name(mode()), 0, -1, 11).x + 5, BOX.position.y + 5))
	var ax := BOX.end.x - 11
	var ay := BOX.position.y + 10
	var arrow := PackedVector2Array([Vector2(ax - 4, ay - 2), Vector2(ax + 4, ay - 2), Vector2(ax, ay + 3)]) if not open \
		else PackedVector2Array([Vector2(ax - 4, ay + 2), Vector2(ax + 4, ay + 2), Vector2(ax, ay - 3)])
	draw_colored_polygon(arrow, C_TEXT)
	draw_line(Vector2(ax - 9, BOX.position.y + 3), Vector2(ax - 9, BOX.end.y - 3), C_EDGE, 1.0)
	# PLAY button, gently pulsing.
	var glow := 0.75 + 0.25 * sin(_t * 4.0)
	draw_rect(PLAY, Color(0.55, 0.28, 0.05).lerp(Color(0.8, 0.42, 0.08), glow))
	draw_rect(PLAY, C_GOLD, false, 1.0)
	_text("PLAY", Vector2(PLAY.position.x, PLAY.position.y + 14), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, PLAY.size.x)
	_list.queue_redraw()


func _badge(p: Vector2, on: CanvasItem = self) -> void:
	var r := Rect2(p, Vector2(22, 10))
	on.draw_rect(r, Color(0.85, 0.15, 0.1))
	on.draw_string(_font, Vector2(p.x, p.y + 8), "NEW", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 7, Color.WHITE)


func _draw_list() -> void:
	if not open:
		return
	var all := Rect2(LIST_X, BOX.end.y + 2, LIST_W, ROW_H * MODES.size())
	_list.draw_rect(all.grow(1), Color(0, 0, 0, 0.9))
	_list.draw_rect(all, C_PANEL)
	for i in MODES.size():
		var r := _row_rect(i)
		var id: String = MODES[i]
		if i == hover:
			_list.draw_rect(r, Color(0.35, 0.2, 0.05))
		if i == index:
			_list.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), C_HOT)
		if i > 0:
			_list.draw_line(r.position, Vector2(r.end.x, r.position.y), Color(0.18, 0.2, 0.26), 1.0)
		var nc := C_HOT if i == index else C_TEXT
		_text(_name(id), Vector2(r.position.x + 7, r.position.y + 12), 9, nc, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _list)
		if id == "purge":
			_badge(Vector2(r.position.x + 7 + _font.get_string_size(_name(id), 0, -1, 9).x + 4, r.position.y + 4), _list)
		_text(SUMMARY[id], Vector2(r.position.x + 108, r.position.y + 11), 7, C_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _list)
	_list.draw_rect(all, C_HOT, false, 1.0)
