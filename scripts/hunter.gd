class_name Hunter
extends Enemy
## Purge Protocol's Hunter Warden. It can't be killed by guns: it marches
## toward Rook along the shortest path (battering down any door in the way,
## keycard doors included), grabs Rook at arm's length, and only stops for:
##   * a stun: 30 damage (any weapon, shiv included) jams its leg servos for
##     4 s, and Rook can walk straight through it;
##   * a Shock Mine (6 s stun);
##   * a rocket from a wall pod or a crafted Breach Rocket, which scraps it
##     for the rest of the floor.
## Unsilenced gunfire it can hear makes it surge from 75% to 110% of Rook's
## walking speed for 3 s.

const STUN_AT := 30.0
const STUN_TIME := 4.0
const BASH_TIME := 2.5
const BRACE_TIME := 6.0
const GRAB_RANGE := 0.8
const GRAB_TIME := 0.5
const RAGE_TIME := 3.0

var stun_dmg := 0.0
var stun_t := 0.0
var stun_len := STUN_TIME
var rage_t := 0.0
var bash_door: Door = null
var bash_t := 0.0
var bash_len := BASH_TIME
var grab_t := 0.0
var _step_t := 0.0
var _bang_t := 0.0
var _bash_braces := 0   # braces on the door when the battering started
var _braces_broken := 0


func setup_hunter(w, t: Vector2i) -> void:
	setup(w, "hunter", t)
	die_time = 1.2
	state = CHASE
	facing = Vector2i(0, 1)


func is_stunned() -> bool:
	return stun_t > 0.0


func speed() -> float:
	return Player.WALK * (1.1 if rage_t > 0.0 else 0.75)


func enrage() -> void:
	if is_alive() and not is_stunned():
		if rage_t <= 0.0:
			world.play_sfx("hunter_roar", pos)
		rage_t = RAGE_TIME


func stun(seconds: float) -> void:
	stun_t = seconds
	stun_len = seconds
	stun_dmg = 0.0
	grab_t = 0.0
	bash_door = null
	rage_t = 0.0
	world.play_sfx("stun", pos)
	Game.message.emit("HUNTER STUNNED - run past it!")


func tick(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	if state == DYING or state == DEAD:
		super.tick(delta)
		return
	stun_dmg = maxf(0.0, stun_dmg - delta * 2.0)
	rage_t -= delta
	if stun_t > 0.0:
		stun_t -= delta
		_frame("stun", int(stun_t * 5.0) % 2)
		if stun_t <= 0.0:
			_frame("stand")
		_finish()
		return
	if world.hunter_paused():
		_frame("stand")
		_finish()
		return
	var d: float = pos.distance_to(world.player.pos)
	if grab_t > 0.0:
		grab_t -= delta
		if grab_t <= 0.0:
			if d < GRAB_RANGE + 0.35 and not world.player.dead:
				world.hunter_grab(self)
			_frame("stand")
		_finish()
		return
	if d < GRAB_RANGE and not world.player.dead:
		grab_t = GRAB_TIME
		facing = _dir_to(world.player.pos)
		_frame("grab")
		world.play_sfx("hunter_roar", pos)
		_finish()
		return
	if bash_door != null:
		_bash(delta)
		_finish()
		return
	_march(delta)
	_finish()


func _finish() -> void:
	position = Vector3(pos.x, 0.5, pos.y)
	_apply_sprite()


func _dir_to(p: Vector2) -> Vector2i:
	var v := p - pos
	return Vector2i(int(signf(v.x)), 0) if absf(v.x) > absf(v.y) else Vector2i(0, int(signf(v.y)))


func _bash(delta: float) -> void:
	if not world.doors.has(bash_door.tile) or bash_door.passable():
		bash_door = null
		return
	bash_t -= delta
	_bang_t -= delta
	_frame("bash", 0 if _bang_t > 0.25 else 1)
	if _bang_t <= 0.0:
		_bang_t = 0.6
		bash_door.bash_hit()
		world.play_sfx("bash", Vector2(bash_door.tile.x + 0.5, bash_door.tile.y + 0.5))
	# Each brace soaks up BRACE_TIME of battering, then snaps off.
	while _braces_broken < _bash_braces and bash_len - bash_t >= BRACE_TIME * (_braces_broken + 1):
		_braces_broken += 1
		world.snap_brace(bash_door, pos)
	if bash_t <= 0.0:
		world.break_door(bash_door)
		bash_door = null


func _march(delta: float) -> void:
	if target != tile:
		var door = world.doors.get(target)
		if door != null and not door.passable():
			# A closed door: open it if it would open anyway, otherwise batter it.
			bash_door = door
			_bash_braces = door.brace_count()
			_braces_broken = 0
			bash_len = BASH_TIME + BRACE_TIME * _bash_braces
			bash_t = bash_len
			_bang_t = 0.0
			return
		var tc := Vector2(target.x + 0.5, target.y + 0.5)
		var to := tc - pos
		var step := speed() * delta
		anim_t += delta
		if anim_t > (0.07 if rage_t > 0.0 else 0.1) or pose != "walk":
			anim_t = 0.0
			walk_frame = (walk_frame + 1) % 8
			_frame("walk", walk_frame)
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = 0.36 if rage_t > 0.0 else 0.5
			world.hunter_stomp(self)
		if to.length() <= step:
			pos = tc
			tile = target
			world.hunter_entered(self, tile)
		else:
			pos += to / to.length() * step
		return
	var nxt: Vector2i = world.hunt_step(self)
	if nxt != tile:
		target = nxt
		facing = nxt - tile
	else:
		_frame("stand")


func take_damage(n: int, _force_pain := false) -> void:
	if not is_alive() or is_stunned():
		return
	_hit_flash = 0.1
	stun_dmg += n
	world.play_sfx("clank", pos)
	if stun_dmg >= STUN_AT:
		stun(STUN_TIME)


## A rocket hit: the Hunter Warden is scrapped for the rest of the floor.
func destroy() -> void:
	if not is_alive():
		return
	state = DYING
	state_t = die_time
	stun_t = 0.0
	_frame("die", 0)
