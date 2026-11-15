class_name Hostage
extends Sprite3D
## A fellow prisoner tied to an iron post. Cut the ropes with the shiv to
## free them: they cheer, hand Rook something useful and slip away through
## the vents. Stray gunfire kills them.

enum { BOUND, FREED, DEAD, GONE }

const FREED_TIME := 1.8
const FADE_TIME := 0.6

var world
var tile := Vector2i.ZERO
var pos := Vector2.ZERO
var state := BOUND
var _t := 0.0


func setup(w, t: Vector2i) -> void:
	world = w
	tile = t
	pos = Vector2(t.x + 0.5, t.y + 0.5)
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = false
	texture_filter = Game.filter_3d()
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	position = Vector3(pos.x, 0.5, pos.y)
	_t = randf() * 2.0
	_show("bound", 0)


func is_bound() -> bool:
	return state == BOUND


## Freed hostages stay solid (and hittable) until they leave.
func is_present() -> bool:
	return state == BOUND or state == FREED


func _show(pose: String, frame: int) -> void:
	var t := Tex.enemy("hostage", pose, frame, 0)
	if t != texture:
		texture = t
		pixel_size = 1.0 / t.get_height()


func tick(delta: float) -> void:
	_t += delta
	match state:
		BOUND:
			# Struggle against the ropes now and then.
			_show("bound", 1 if fmod(_t, 2.2) > 1.7 else 0)
		FREED:
			_show("freed", int(_t / 0.22) % 2)
			if _t > FREED_TIME:
				var k := clampf((_t - FREED_TIME) / FADE_TIME, 0.0, 1.0)
				alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				modulate.a = 1.0 - k
				if k >= 1.0:
					state = GONE
					visible = false
					world.on_hostage_gone(self)


func free_hostage() -> void:
	state = FREED
	_t = 0.0


func kill() -> void:
	state = DEAD
	modulate = Color.WHITE
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_show("dead", 0)
