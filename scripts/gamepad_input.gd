class_name GamepadInput
extends Node
## Gamepad / joystick support.
## In play the sticks, triggers and buttons drive the normal input actions
## (bound in main._setup_input). On menu screens the pad is turned into the
## same key presses the keyboard would send, so main.gd's menu logic is shared.
## As soon as a pad is connected or used, the on-screen touch controls hide
## and the hints switch to pad buttons; touching the screen, or pressing a
## real key / mouse button, switches back.

## True while a gamepad is the active controller.
static var active := false

const STICK_ON := 0.6
const STICK_OFF := 0.3
## Device id stamped on the key presses this script fakes, so they are not
## mistaken for the player switching back to the keyboard.
const FAKE_DEVICE := 77

var main: Node
var _dir := {}   # axis -> -1 / 0 / 1 for menu navigation with the stick
var _queue: Array = []


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_changed)
	if not Input.get_connected_joypads().is_empty() and not "--no-pad" in OS.get_cmdline_user_args():
		_activate.call_deferred()


func _on_joy_changed(_device: int, connected: bool) -> void:
	if "--no-pad" in OS.get_cmdline_user_args():
		return  # tests: ignore the pad plugged into this machine
	if connected:
		_activate()
	elif Input.get_connected_joypads().is_empty() and active:
		active = false
		TouchControls.active = TouchControls.is_touch_device()
		main.on_input_mode_changed()


func _activate() -> void:
	if active:
		return
	active = true
	if TouchControls.active:
		main.touch.release_all()
		TouchControls.active = false
	main.on_input_mode_changed()


## The first touch after using a pad hands control back to touch.
static func deactivate() -> void:
	active = false


func _input(event: InputEvent) -> void:
	if active and ((event is InputEventKey and event.pressed and event.device != FAKE_DEVICE)
			or (event is InputEventMouseButton and event.pressed)):
		# Back on keyboard and mouse.
		active = false
		main.on_input_mode_changed()
		return
	if event is InputEventJoypadButton:
		if event.pressed:
			_activate()
			_button(event.button_index)
	elif event is InputEventJoypadMotion:
		if absf(event.axis_value) > STICK_ON:
			_activate()
		if event.axis in [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]:
			_stick(event.axis, event.axis_value)


func _playing() -> bool:
	return main.state == "playing" and main.world != null


func _button(b: int) -> void:
	var st: String = main.state
	if _playing():
		match b:
			JOY_BUTTON_START:
				_key(KEY_ESCAPE)
			JOY_BUTTON_LEFT_SHOULDER:
				main.world.player.cycle_weapon(-1)
			JOY_BUTTON_RIGHT_SHOULDER:
				main.world.player.cycle_weapon(1)
			JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP:
				main.hud.minimap.toggle_size()
		return
	if st == "dying":
		return
	match b:
		JOY_BUTTON_A:
			_key(KEY_ENTER)
		JOY_BUTTON_START:
			_key(KEY_ESCAPE if st == "paused" else KEY_ENTER)
		JOY_BUTTON_B:
			_key(KEY_C if st == "craft" else KEY_ESCAPE)
		JOY_BUTTON_X:
			if st == "cell":
				_key(KEY_P)
		JOY_BUTTON_Y:
			if st == "title":
				_key(KEY_M)
		JOY_BUTTON_BACK:
			if st == "paused":
				_key(KEY_Q)
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER:
			if st == "title":
				var d := -1 if b == JOY_BUTTON_LEFT_SHOULDER else 1
				_key(KEY_1 + clampi(Game.difficulty + d, 0, 2))
		JOY_BUTTON_DPAD_UP:
			_key(KEY_W)
		JOY_BUTTON_DPAD_DOWN:
			_key(KEY_S)
		JOY_BUTTON_DPAD_LEFT:
			_key(KEY_A)
		JOY_BUTTON_DPAD_RIGHT:
			_key(KEY_D)


## Left stick on menus: one step each time it is pushed past STICK_ON.
func _stick(axis: int, v: float) -> void:
	var was: int = _dir.get(axis, 0)
	var now := was
	if absf(v) > STICK_ON:
		now = 1 if v > 0 else -1
	elif absf(v) < STICK_OFF:
		now = 0
	_dir[axis] = now
	if now == was or now == 0 or _playing() or main.state == "dying":
		return
	if axis == JOY_AXIS_LEFT_X:
		_key(KEY_D if now > 0 else KEY_A)
	else:
		_key(KEY_S if now > 0 else KEY_W)


## Queue a key press; it is sent next frame, because keys parsed while the
## pad event itself is being handled can be dropped.
func _key(k: int) -> void:
	_queue.append(k)


func _process(_delta: float) -> void:
	for k in _queue.duplicate():
		var e := InputEventKey.new()
		e.physical_keycode = k
		e.keycode = k
		e.device = FAKE_DEVICE
		e.pressed = true
		Input.parse_input_event(e)
		var r := e.duplicate()
		r.pressed = false
		Input.parse_input_event(r)
	_queue.clear()
