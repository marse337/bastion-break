class_name Player
extends Node3D
## First-person player. Position lives on the 2D tile grid (pos.x = world X,
## pos.y = world Z); the camera only turns horizontally, like classic
## raycaster shooters.

const RADIUS := 0.24
const WALK := 2.6
const RUN := 4.4
const TURN := 2.4
const FIRE_DELAY := [0.42, 0.28, 0.13, 0.075]

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
var since_shot := 99.0
var anim_len := 0.15


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


func select_weapon(i: int) -> void:
	if Game.owned[i] and (i == Game.Weapon.SHIV or Game.ammo > 0):
		Game.current_weapon = i
		Game.auto_shiv = false


func cycle_weapon(dir: int) -> void:
	var w: int = Game.current_weapon
	for _i in 4:
		w = posmod(w + dir, 4)
		if Game.owned[w] and (w == Game.Weapon.SHIV or Game.ammo > 0):
			select_weapon(w)
			return


func _weapons() -> void:
	for i in 4:
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			select_weapon(i)
	var w: int = Game.current_weapon
	var automatic := w >= Game.Weapon.RIFLE
	var want := Input.is_action_pressed("fire") if automatic else Input.is_action_just_pressed("fire")
	if not want or fire_cd > 0.0:
		return
	if w != Game.Weapon.SHIV:
		if Game.ammo <= 0:
			Game.switch_to_shiv()
			return
		Game.ammo -= 1
	fire_cd = FIRE_DELAY[w] * (0.85 if Game.has_perk("quick_hands") else 1.0)
	since_shot = 0.0
	anim_len = 0.24 if w == Game.Weapon.SHIV else minf(0.16, fire_cd * 1.6)
	fire_anim = 0.2 if w == Game.Weapon.SHIV else 0.08
	world.player_attack(w)
	if w != Game.Weapon.SHIV and Game.ammo <= 0:
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
