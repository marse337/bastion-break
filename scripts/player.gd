class_name Player
extends Node3D
## First-person player. Position lives on the 2D tile grid (pos.x = world X,
## pos.y = world Z); the camera only turns horizontally, like classic
## raycaster shooters.

const RADIUS := 0.24
const WALK := 2.6
const RUN := 4.4
const TURN := 2.4

var world
var pos := Vector2.ZERO
var angle := 0.0
var cam: Camera3D
var fire_cd := 0.0
var fire_anim := 0.0
var bob := 0.0
var moving := false
var running := false
var dead := false
var mouse_sens := 0.006
var invulnerable := 0.0
## Camera shake from nearby blasts, 0-1; fades on its own.
var shake := 0.0
var since_shot := 99.0
var anim_len := 0.15
## Locked in place (the calibration range): can turn and shoot, not walk.
var locked := false
var _half_tick := false


func setup(w, p: Vector2, a: float) -> void:
	world = w
	pos = p
	angle = a
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 80.0
	cam.near = 0.03
	cam.far = 80.0
	add_child(cam)
	cam.current = true
	_sync()


func turn(amount: float) -> void:
	if not dead:
		angle = wrapf(angle + amount, -PI, PI)


func is_running() -> bool:
	return running and moving


func forward() -> Vector2:
	return Vector2(cos(angle), sin(angle))


func tick(delta: float) -> void:
	fire_cd -= delta
	fire_anim -= delta
	since_shot += delta
	invulnerable = maxf(0.0, invulnerable - delta)
	shake = maxf(0.0, shake - delta * 2.5)
	if dead:
		cam.position.y = lerpf(cam.position.y, 0.1, delta * 3.0)
		cam.rotation.z = lerpf(cam.rotation.z, 0.5, delta * 2.0)
		return
	running = Input.is_action_pressed("run")
	var turn_in := Input.get_axis("turn_left", "turn_right")
	angle = wrapf(angle + turn_in * TURN * delta * (1.5 if running else 1.0), -PI, PI)
	var fwd := forward()
	var right := Vector2(-sin(angle), cos(angle))
	var mv := fwd * Input.get_axis("move_back", "move_forward") + right * Input.get_axis("strafe_left", "strafe_right")
	if locked:
		mv = Vector2.ZERO
	moving = mv.length_squared() > 0.01
	if moving:
		var speed_mult := 1.15 if Game.has_perk("fleet_foot") else 1.0
		mv = mv.normalized() * (RUN if running else WALK) * speed_mult * delta
		_move(mv)
		bob += delta * (11.0 if running else 8.0)
	_weapons()
	if Input.is_action_just_pressed("use"):
		world.player_use()
	_sync()


func _move(d: Vector2) -> void:
	var np := Vector2(pos.x + d.x, pos.y)
	if not world.player_blocked(pos, np, RADIUS):
		pos = np
	np = Vector2(pos.x, pos.y + d.y)
	if not world.player_blocked(pos, np, RADIUS):
		pos = np


## Selects slot `i`. Pressing the key of the slot already in hand switches
## between the weapons stored in it (base weapon and prototypes).
func select_weapon(i: int) -> void:
	if world.range_state == 1:
		return
	if not Game.owned[i] or (i != Game.Weapon.SHIV and Game.ammo <= 0):
		return
	if Game.current_weapon == i and Game.slot_guns[i].size() > 1:
		var list: Array = Game.slot_guns[i]
		Game.slot_active[i] = list[(list.find(Game.slot_active[i]) + 1) % list.size()]
		Game.message.emit(Game.WEAPONS[Game.slot_active[i]].name)
	Game.current_weapon = i
	Game.auto_shiv = false


## Mouse wheel / touch SWAP: steps through every weapon you carry.
func cycle_weapon(dir: int) -> void:
	if world.range_state == 1:
		return
	var all := []
	for s in 4:
		if s == Game.Weapon.SHIV or Game.ammo > 0:
			for id in Game.slot_guns[s]:
				all.append([s, id])
	if all.is_empty():
		return
	var cur := 0
	for k in all.size():
		if all[k][0] == Game.current_weapon and all[k][1] == Game.weapon_id():
			cur = k
	var nx: Array = all[posmod(cur + dir, all.size())]
	Game.current_weapon = nx[0]
	Game.slot_active[nx[0]] = nx[1]
	Game.auto_shiv = false


func _weapons() -> void:
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			select_weapon(i)
	var w: int = Game.current_weapon
	var st: Dictionary = Game.WEAPONS[Game.weapon_id()]
	var want := Input.is_action_pressed("fire") if st.auto else Input.is_action_just_pressed("fire")
	if not want or fire_cd > 0.0:
		return
	var calib: bool = world.range_state == 1
	var bullets := 1
	if calib:
		# Calibration clip: 12 free rounds, the real ammo pool is untouched.
		if world.range_ammo <= 0:
			fire_cd = 0.3
			world.play_sfx("denied")
			return
		world.range_ammo -= 1
	elif w != Game.Weapon.SHIV:
		if Game.ammo <= 0:
			Game.switch_to_shiv()
			return
		if st.get("arc", false) and world.arc_target() == null:
			return  # the discharger only fires with a target in reach
		var cost: int = st.get("cost", 1)
		if st.get("half_cost", false):
			_half_tick = not _half_tick
			cost = 1 if _half_tick else 0
		cost = mini(cost, Game.ammo)
		if int(st.get("cost", 1)) >= 2:
			bullets = maxi(1, cost)
		Game.ammo -= cost
	fire_cd = float(st.delay) * (0.85 if Game.has_perk("quick_hands") else 1.0)
	since_shot = 0.0
	if w == Game.Weapon.SHIV:
		anim_len = 0.36 if Game.weapon_id() == "baton" else 0.24
	else:
		anim_len = minf(0.26 if Game.weapon_id() == "slugger" else 0.16, fire_cd * 1.6)
	fire_anim = 0.2 if w == Game.Weapon.SHIV else 0.08
	world.player_attack(w, bullets)
	if not calib and w != Game.Weapon.SHIV and Game.ammo <= 0:
		Game.switch_to_shiv()


## First-person weapon frame: 0 idle, 1 flash, 2 recoil, 3 recover.
func weapon_frame() -> int:
	if since_shot >= anim_len:
		return 0
	return 1 + clampi(int(since_shot / (anim_len / 3.0)), 0, 2)


func _sync() -> void:
	position = Vector3(pos.x, 0, pos.y)
	cam.position.y = 0.5 + (sin(bob) * 0.018 if moving else 0.0)
	cam.rotation.y = -angle - PI / 2.0
	# Blast shake: a quick jitter that dies away.
	if shake > 0.0:
		cam.position.x = randf_range(-1.0, 1.0) * shake * 0.03
		cam.position.y += randf_range(-1.0, 1.0) * shake * 0.03
		cam.rotation.z = randf_range(-1.0, 1.0) * shake * 0.015
	elif not dead:
		cam.position.x = 0.0
		cam.rotation.z = 0.0
