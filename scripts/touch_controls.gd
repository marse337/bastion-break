class_name TouchControls
extends Control
## On-screen controls for phones and tablets.
## In play: a floating move stick on the left half, drag anywhere on the
## right half to turn, FIRE / USE / SWAP buttons, a pause button, and tap the
## minimap to enlarge it. On menu screens: a row of buttons that send the
## same keys the keyboard would, so the menu logic in main.gd is unchanged.

const W := 480.0
const H := 270.0
const PLAY_H := 230.0
const STICK_R := 34.0
const LOOK_SENS := 0.011
const DEADZONE := 0.15

const FIRE_BTN := {"c": Vector2(428, 186), "r": 28.0, "label": "FIRE"}
const USE_BTN := {"c": Vector2(364, 206), "r": 18.0, "label": "USE"}
const SWAP_BTN := {"c": Vector2(440, 124), "r": 16.0, "label": "SWAP"}
const PAUSE_BTN := {"c": Vector2(16, 14), "r": 11.0, "label": "II"}
# Purge Protocol: the workbench, and one button per gadget you carry.
const CRAFT_BTN := {"c": Vector2(396, 106), "r": 14.0, "label": "CRAFT", "key": KEY_C}
const GADGET_BTNS := {
	"rocket": {"c": Vector2(398, 140), "r": 13.0, "label": "RKT", "key": KEY_R},
	"mine": {"c": Vector2(364, 160), "r": 13.0, "label": "MINE", "key": KEY_F},
	"brace": {"c": Vector2(330, 180), "r": 13.0, "label": "BRACE", "key": KEY_B},
}
const FULL_BTN := {"c": Vector2(44, 14), "r": 11.0, "label": "[ ]"}
const MAP_RECT := Rect2(352, 4, 124, 84)

## True once the device has shown it is touch-driven. main.gd reads this to
## switch help text and cap the HD render size.
static var active := false

var main: Node
var _touches := {}          # finger index -> role ("stick", "look", "fire", "")
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_last := Vector2.ZERO
var _menu: Array = []       # [{rect, label, key}]
var _menu_state := ""
var _pressed_menu := -1


static func is_touch_device() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


func _ready() -> void:
	size = Vector2(W, H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_touch_device() or "--touch" in OS.get_cmdline_user_args():
		active = true


func _playing() -> bool:
	return main.state == "playing" and main.world != null


func _process(_delta: float) -> void:
	visible = active
	if not active:
		return
	if not _playing() and _has_role("stick", "fire"):
		_release_all()
	if main.state != _menu_state:
		_menu_state = main.state
		_build_menu()
	queue_redraw()


func _has_role(a: String, b: String) -> bool:
	for r in _touches.values():
		if r == a or r == b:
			return true
	return false


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not active:
			active = true
			main.on_touch_activated()
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position, event.relative)
		get_viewport().set_input_as_handled()


func _hit(btn: Dictionary, p: Vector2, slack := 6.0) -> bool:
	return p.distance_to(btn.c) <= btn.r + slack


func _touch_down(i: int, p: Vector2) -> void:
	if not _playing():
		_touches[i] = ""
		for m in _menu.size():
			if (_menu[m].rect as Rect2).grow(3).has_point(p):
				_pressed_menu = m
				_touches[i] = "menu%d" % m
		return
	if _hit(PAUSE_BTN, p):
		_touches[i] = ""
		_key(KEY_ESCAPE)
	elif OS.has_feature("web") and _hit(FULL_BTN, p):
		_touches[i] = ""
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif Game.is_protocol("purge") and _purge_button(p) != 0:
		_touches[i] = ""
		_key(_purge_button(p))
	elif _hit(FIRE_BTN, p, 10.0):
		_touches[i] = "fire"
		Input.action_press("fire")
	elif _hit(USE_BTN, p):
		_touches[i] = ""
		_tap_action("use")
	elif _hit(SWAP_BTN, p):
		_touches[i] = ""
		main.world.player.cycle_weapon(1)
	elif MAP_RECT.has_point(p) or (main.hud.minimap.expanded and p.y < PLAY_H and p.x > 60 and p.x < 420):
		_touches[i] = ""
		main.hud.minimap.toggle_size()
	elif p.x < W * 0.42 and not _has_role("stick", "stick"):
		_touches[i] = "stick"
		_stick_origin = Vector2(clampf(p.x, STICK_R + 4, W * 0.42 - STICK_R), clampf(p.y, 40 + STICK_R, PLAY_H - STICK_R - 2))
		_stick_pos = p
		_apply_stick()
	else:
		_touches[i] = "look"
		_look_last = p


## Key for the purge button under `p`, or 0.
func _purge_button(p: Vector2) -> int:
	if _hit(CRAFT_BTN, p, 3.0):
		return CRAFT_BTN.key
	for id in GADGET_BTNS:
		if int(Game.gadgets.get(id, 0)) > 0 and _hit(GADGET_BTNS[id], p, 3.0):
			return GADGET_BTNS[id].key
	return 0


func _touch_move(i: int, p: Vector2, rel: Vector2) -> void:
	match _touches.get(i, ""):
		"stick":
			_stick_pos = p
			_apply_stick()
		"look":
			if _playing():
				main.world.player.turn(rel.x * LOOK_SENS)
			_look_last = p
		"fire":
			# Sliding off the fire button onto the right half also turns,
			# so you can aim while holding fire.
			if _playing():
				main.world.player.turn(rel.x * LOOK_SENS)


func _touch_up(i: int) -> void:
	var role: String = _touches.get(i, "")
	_touches.erase(i)
	match role:
		"stick":
			_stick_pos = _stick_origin
			_apply_stick()
		"fire":
			Input.action_release("fire")
		_:
			if role.begins_with("menu"):
				var m := int(role.substr(4))
				_pressed_menu = -1
				if m < _menu.size():
					_key(_menu[m].key)


func _apply_stick() -> void:
	var v := (_stick_pos - _stick_origin) / STICK_R
	if v.length() > 1.0:
		v = v.normalized()
	var mag := v.length()
	if mag < DEADZONE:
		v = Vector2.ZERO
	_set_axis("strafe_right", "strafe_left", v.x)
	_set_axis("move_back", "move_forward", v.y)
	if mag > 0.92:
		Input.action_press("run")
	else:
		Input.action_release("run")


func _set_axis(pos_action: String, neg_action: String, value: float) -> void:
	if value > 0.0:
		Input.action_press(pos_action, value)
		Input.action_release(neg_action)
	elif value < 0.0:
		Input.action_press(neg_action, -value)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _release_all() -> void:
	for a in ["fire", "run", "move_forward", "move_back", "strafe_left", "strafe_right"]:
		Input.action_release(a)
	_touches.clear()


## Presses an action for exactly one frame so is_action_just_pressed sees it.
func _tap_action(action: String) -> void:
	Input.action_press(action)
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release(action)


## Sends a key press + release through the normal input path.
func _key(k: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	Input.parse_input_event(e)
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)


# ---------------------------------------------------------------- menus

func _build_menu() -> void:
	_menu.clear()
	_pressed_menu = -1
	var items: Array = []
	match main.state:
		"title":
			items = [["ESCAPE RUN", KEY_ENTER], ["CLASSIC", KEY_C], ["EASY", KEY_1], ["NORMAL", KEY_2], ["HARD", KEY_3]]
		"cell":
			for n in Game.UPGRADE_ORDER.size():
				items.append(["BUY %d" % (n + 1), KEY_1 + n])
			items.append(["MODE", KEY_P])
			items.append(["START", KEY_ENTER])
			items.append(["BACK", KEY_ESCAPE])
		"perk":
			for n in main.perk_choices.size():
				items.append(["PICK %d" % (n + 1), KEY_1 + n])
		"craft":
			for n in Game.GADGET_ORDER.size():
				items.append(["CRAFT %d" % (n + 1), KEY_1 + n])
			items.append(["BACK", KEY_C])
		"paused":
			items = [["RESUME", KEY_ESCAPE], ["QUIT RUN", KEY_Q], ["PIXELS", KEY_F2]]
		"tally", "runover", "gameover", "victory":
			items = [["CONTINUE", KEY_ENTER]]
	if items.is_empty():
		return
	var gap := 4.0
	var bw := minf(110.0, (W - 16.0 - gap * (items.size() - 1)) / items.size())
	var total := bw * items.size() + gap * (items.size() - 1)
	var x := (W - total) / 2.0
	for it in items:
		_menu.append({"rect": Rect2(x, H - 26, bw, 22), "label": it[0], "key": it[1]})
		x += bw + gap


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if not active:
		return
	var font := get_theme_default_font()
	var win := get_window().size
	if win.y > win.x:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.85))
		draw_string(font, Vector2(0, H / 2), "Turn your phone sideways to play", HORIZONTAL_ALIGNMENT_CENTER, W, 16, Color.WHITE)
		return
	if _playing():
		_draw_play(font)
	else:
		for m in _menu.size():
			var r: Rect2 = _menu[m].rect
			var down := m == _pressed_menu
			draw_rect(r, Color(0.9, 0.5, 0.15, 0.95) if down else Color(0.16, 0.2, 0.3, 0.92))
			draw_rect(r, Color(1, 0.6, 0.2), false, 1.0)
			draw_string(font, Vector2(r.position.x, r.position.y + 15), _menu[m].label, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color.WHITE)


func _draw_play(font: Font) -> void:
	var fire_down := _has_role("fire", "fire")
	_button(font, FIRE_BTN, fire_down, Color(0.85, 0.2, 0.15))
	_button(font, USE_BTN, false, Color(0.25, 0.5, 0.85))
	_button(font, SWAP_BTN, false, Color(0.4, 0.4, 0.45))
	_button(font, PAUSE_BTN, false, Color(0.3, 0.3, 0.35))
	if OS.has_feature("web"):
		_button(font, FULL_BTN, false, Color(0.3, 0.3, 0.35))
	if Game.is_protocol("purge"):
		_button(font, CRAFT_BTN, false, Color(0.75, 0.55, 0.1))
		for id in GADGET_BTNS:
			if int(Game.gadgets.get(id, 0)) > 0:
				_button(font, GADGET_BTNS[id], false, Color(0.55, 0.3, 0.1))
	if _has_role("stick", "stick"):
		draw_circle(_stick_origin, STICK_R, Color(1, 1, 1, 0.12))
		draw_arc(_stick_origin, STICK_R, 0, TAU, 32, Color(1, 1, 1, 0.35), 1.5)
		var k := _stick_pos - _stick_origin
		if k.length() > STICK_R:
			k = k.normalized() * STICK_R
		draw_circle(_stick_origin + k, 13, Color(1, 1, 1, 0.4))
	else:
		var hint := Vector2(70, 180)
		draw_arc(hint, STICK_R, 0, TAU, 32, Color(1, 1, 1, 0.15), 1.0)
		draw_string(font, hint + Vector2(-40, 4), "MOVE", HORIZONTAL_ALIGNMENT_CENTER, 80, 8, Color(1, 1, 1, 0.3))


func _button(font: Font, b: Dictionary, down: bool, col: Color) -> void:
	var c := col
	c.a = 0.75 if down else 0.38
	draw_circle(b.c, b.r, c)
	draw_arc(b.c, b.r, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.0)
	var fs := 9 if b.r > 14.0 else 7
	draw_string(font, Vector2(b.c.x - b.r, b.c.y + fs * 0.35), b.label, HORIZONTAL_ALIGNMENT_CENTER, b.r * 2.0, fs, Color(1, 1, 1, 0.9))
