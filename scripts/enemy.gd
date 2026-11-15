class_name Enemy
extends Sprite3D
## Tile-based enemy AI: stands guard until it sees or hears the player, then
## chases tile by tile (opening doors on the way) and stops to shoot.

enum { IDLE, CHASE, ATTACK, PAIN, DYING, DEAD }

const STATS := {
	"sentry": {"hp": 25, "speed": 1.7, "score": 100, "aim": 0.45, "burst": 1, "acc": 0.75, "dmg": [4, 13], "range": 16.0, "pain": 0.8},
	"hound": {"hp": 8, "speed": 3.6, "score": 200, "aim": 0.2, "burst": 1, "acc": 0.8, "dmg": [5, 11], "range": 1.4, "pain": 0.8},
	"overseer": {"hp": 650, "speed": 1.3, "score": 5000, "aim": 0.5, "burst": 6, "acc": 0.55, "dmg": [3, 9], "range": 22.0, "pain": 0.06, "radius": 0.45, "boss": true},
	"warden": {"hp": 100, "speed": 2.0, "score": 500, "aim": 0.4, "burst": 3, "acc": 0.85, "dmg": [5, 14], "range": 18.0, "pain": 0.35},
	# Bounty Warden: 5-shot bursts, then a 1.5 s cooling vent where every hit
	# deals triple damage. Waits in its room until it has seen you.
	"crimson": {"hp": 260, "speed": 1.9, "score": 3000, "aim": 0.45, "burst": 5, "acc": 0.8, "dmg": [5, 13], "range": 18.0, "pain": 0.08, "name": "BOUNTY WARDEN"},
	# Iron Gauntlet mini-boss: a smaller Overseer.
	"suboverseer": {"hp": 300, "speed": 1.4, "score": 2500, "aim": 0.5, "burst": 4, "acc": 0.55, "dmg": [3, 8], "range": 22.0, "pain": 0.08, "radius": 0.42, "boss": true, "sprite": "overseer", "name": "SUB-OVERSEER"},
}
const HP_SCALE := [0.75, 1.0, 1.3]

var world
var kind := "sentry"
var stats: Dictionary
var hp := 1
var state := IDLE
var tile := Vector2i.ZERO
var target := Vector2i.ZERO
var pos := Vector2.ZERO
var facing := Vector2i(0, 1)
var anim_t := 0.0
var state_t := 0.0
var think_t := 0.0
var phase := ""
var shots_left := 0
var walk_frame := 0
var pose := "stand"
var max_hp := 1
var is_boss := false
var die_time := 0.45
var pose_frame := 0
var sprite_kind := "sentry"
var home_room := -1
var gun_alerted := false
var unleashed := false
var _hit_flash := 0.0



func setup(w, k: String, t: Vector2i) -> void:
	world = w
	kind = k
	stats = STATS[k]
	sprite_kind = stats.get("sprite", k)
	if k == "suboverseer":
		modulate = Color(0.7, 0.85, 1.0)
	hp = int(stats.hp * HP_SCALE[Game.difficulty])
	max_hp = hp
	is_boss = stats.get("boss", false)
	die_time = 1.4 if is_boss else 0.45
	tile = t
	target = t
	pos = Vector2(t.x + 0.5, t.y + 0.5)
	facing = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)].pick_random()
	think_t = randf() * 0.2
	pixel_size = 1.0 / 64.0
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = false
	texture_filter = Game.filter_3d()
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_frame("stand")
	position = Vector3(pos.x, 0.5, pos.y)
	_apply_sprite()


func is_alive() -> bool:
	return state != DYING and state != DEAD


func _frame(p: String, f := 0) -> void:
	pose = p
	pose_frame = f


## Which of the 8 rendered angles to show: 0 = facing the player, counting
## around the enemy (matches the Blender turntable renders).
func _view_dir() -> int:
	if world.player == null:
		return 0
	var v: Vector2 = world.player.pos - pos
	var a := Vector2(facing).angle_to(v)
	return posmod(-roundi(a / (PI / 4.0)), 8)


func _apply_sprite() -> void:
	var dir := _view_dir() if pose == "stand" or pose == "walk" else 0
	var t := Tex.enemy(sprite_kind, pose, pose_frame, dir)
	if t != texture:
		texture = t
		pixel_size = 1.0 / t.get_height()
	var base := Color(0.7, 0.85, 1.0) if kind == "suboverseer" else Color.WHITE
	modulate = Color(1, 0.55, 0.5) if state == PAIN or _hit_flash > 0.0 else base


func display_name() -> String:
	return stats.get("name", "THE OVERSEER")


func tick(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	match state:
		IDLE:
			think_t -= delta
			if think_t <= 0.0:
				think_t = 0.2
				if _can_see_player(true):
					unleashed = true
					alert()
		CHASE:
			_chase(delta)
		ATTACK:
			_attack(delta)
		PAIN:
			state_t -= delta
			if state_t <= 0.0:
				state = CHASE
				think_t = 0.0
				_frame("stand")
		DYING:
			state_t -= delta
			_frame("die", clampi(int((die_time - state_t) / (die_time / 4.0)), 0, 3))
			if state_t <= 0.0:
				state = DEAD
				_frame("dead")
	position = Vector3(pos.x, 0.5, pos.y)
	_apply_sprite()


func _can_see_player(use_fov: bool) -> bool:
	var to: Vector2 = world.player.pos - pos
	var d := to.length()
	if d > 24.0:
		return false
	if use_fov and not is_boss and d > 1.2 and to.normalized().dot(Vector2(facing)) < -0.1:
		return false
	return world.has_los(pos, world.player.pos)


func alert() -> void:
	if state != IDLE:
		return
	state = CHASE
	think_t = randf() * 0.3
	if is_boss:
		world.play_sfx("boss_alert")
		Game.message.emit("%s HAS SEEN YOU" % display_name())
	elif kind == "crimson":
		world.play_sfx("boss_alert", pos)
	else:
		world.play_sfx("hound" if kind == "hound" else "alert", pos)


func _chase(delta: float) -> void:
	if target != tile:
		var door = world.doors.get(target)
		if door != null and not door.passable():
			if kind != "hound" and (kind != "crimson" or unleashed):
				world.enemy_open_door(door)
			_frame("stand")
			return
		var tc := Vector2(target.x + 0.5, target.y + 0.5)
		var to := tc - pos
		var step: float = stats.speed * delta
		anim_t += delta
		if anim_t > (0.14 if kind == "hound" else 0.09) or pose != "walk":
			anim_t = 0.0
			walk_frame = (walk_frame + 1) % (4 if kind == "hound" else 8)
			_frame("walk", walk_frame)
		if to.length() <= step:
			pos = tc
			world.release(tile, self)
			tile = target
			think_t = 0.0
		else:
			pos += to / to.length() * step
		return
	think_t -= delta
	if think_t > 0.0:
		return
	think_t = 0.3
	var d: float = pos.distance_to(world.player.pos)
	if d < 26.0 and world.has_los(pos, world.player.pos):
		if kind == "hound":
			if d <= stats.range:
				_start_attack()
				return
		elif d <= stats.range and randf() < clampf(1.1 - d / 12.0, 0.15, 0.95):
			_start_attack()
			return
	var nxt: Vector2i = world.next_step(self)
	if nxt != tile:
		world.reserve(nxt, self)
		target = nxt
		facing = nxt - tile
		think_t = 0.0
	else:
		_frame("stand")


func _start_attack() -> void:
	state = ATTACK
	if is_boss and randf() < 0.4:
		phase = "launch"
		state_t = 0.6
		_frame("launch")
		return
	phase = "aim"
	state_t = stats.aim
	shots_left = stats.burst
	_frame("aim")


func _attack(delta: float) -> void:
	state_t -= delta
	if phase == "fire" and state_t < 0.06 and pose == "fire":
		_frame("fire", 1)  # recoil frame after the muzzle flash
	if state_t > 0.0:
		return
	match phase:
		"aim":
			_fire()
			phase = "fire"
			state_t = 0.12
			_frame("fire", 0)
		"fire":
			shots_left -= 1
			if shots_left > 0:
				phase = "aim"
				state_t = 0.1
			else:
				phase = "recover"
				state_t = 0.3
				if kind == "crimson":
					phase = "vent"
					state_t = 1.5
					_frame("vent")
					world.play_sfx("vent", pos)
					if not world._vent_hint:
						world._vent_hint = true
						Game.message.emit("It's venting - hit it now for triple damage!")
					return
			_frame("aim")
		"vent":
			phase = "recover"
			state_t = 0.15
			_frame("aim")
		"launch":
			world.fire_plasma(self)
			phase = "recover"
			state_t = 0.5
		"recover":
			state = CHASE
			think_t = 0.1
			_frame("stand")


func _fire() -> void:
	var d: float = pos.distance_to(world.player.pos)
	if kind == "hound":
		world.play_sfx("bite", pos)
		if d <= stats.range + 0.3:
			world.damage_player(randi_range(stats.dmg[0], stats.dmg[1]))
		return
	world.play_sfx("enemy_shot", pos)
	if not world.has_los(pos, world.player.pos):
		return
	var chance: float = stats.acc - d * 0.035
	if world.player.is_running():
		chance -= 0.15
	if randf() < clampf(chance, 0.08, 0.95):
		var dmg: int = randi_range(stats.dmg[0], stats.dmg[1])
		if d < 2.0:
			dmg = int(dmg * 1.6)
		elif d > 8.0:
			dmg = int(dmg * 0.6)
		world.damage_player(maxi(1, dmg))


func take_damage(n: int, force_pain := false) -> void:
	if not is_alive():
		return
	var venting := kind == "crimson" and state == ATTACK and phase == "vent"
	if venting:
		n *= 3
	unleashed = true
	hp -= n
	if hp <= 0:
		state = DYING
		state_t = die_time
		_frame("die", 0)
		world.on_enemy_killed(self)
		return
	if state == IDLE:
		alert()
	if venting:
		_hit_flash = 0.12  # flinch flash, but it keeps venting
		return
	if force_pain or randf() < stats.pain:
		state = PAIN
		state_t = 0.22
		_frame("pain")
