class_name Door
extends Node3D
## A sliding door occupying one tile. It slides sideways into the wall that
## frames it and closes on its own after a few seconds unless something is
## standing in the doorway.

enum { CLOSED, OPENING, OPEN, CLOSING }

const SPEED := 1.6
const STAY_OPEN := 4.0

var tile := Vector2i.ZERO
var spans_x := true
var key := ""
var unlocked := true
var openness := 0.0
var state := CLOSED
var open_timer := 0.0
var slab: MeshInstance3D

## Door Braces (Purge gadget): steel bars clamped across both faces.
## Each one swings down from its left clamp and slams shut, rattles while
## the Hunter Warden batters the door, and snaps off when it gives way.
signal brace_landed(at: Vector3)

const MAX_BRACES := 2
const BRACE_Y := [0.36, 0.64]
const SWING_TIME := 0.22   # bar swings down...
const SETTLE_TIME := 0.45  # ...then bounces and settles
const SWING_FROM := 1.45   # radians: the bar starts nearly upright

var braces: Array[Dictionary] = []   # {node, pivot, mat, t, landed}
var _shake := 0.0
var _time := 0.0
static var _stripe_texs := {}


func setup(t: Vector2i, along_x: bool, key_name: String, mesh: Mesh, mat: Material) -> void:
	tile = t
	spans_x = along_x
	key = key_name
	unlocked = key == ""
	position = Vector3(t.x, 0, t.y)
	slab = MeshInstance3D.new()
	slab.mesh = mesh
	slab.material_override = mat
	add_child(slab)


func passable() -> bool:
	return openness > 0.75


func blocks_sight() -> bool:
	return openness < 0.5


## Returns true when the door actually starts moving (so the caller can play a sound).
func open() -> bool:
	if state == CLOSED or state == CLOSING:
		state = OPENING
		return true
	if state == OPEN:
		open_timer = 0.0
	return false


func close() -> bool:
	if state == OPEN or state == OPENING:
		state = CLOSING
		return true
	return false


## Returns true when the door starts closing by itself.
func tick(delta: float, occupied: bool) -> bool:
	var started_closing := false
	match state:
		OPENING:
			openness = minf(1.0, openness + delta * SPEED)
			if openness >= 1.0:
				state = OPEN
				open_timer = 0.0
		OPEN:
			open_timer += delta
			if open_timer > STAY_OPEN and not occupied:
				state = CLOSING
				started_closing = true
		CLOSING:
			if occupied:
				state = OPENING
			else:
				openness = maxf(0.0, openness - delta * SPEED)
				if openness <= 0.0:
					state = CLOSED
	var slide := openness * 0.98
	_time += delta
	_shake = maxf(0.0, _shake - delta * 3.0)
	# A battered door jolts back and forth across its frame.
	var jolt := _shake * 0.035 * sin(_time * 55.0)
	slab.position = Vector3(slide, 0, jolt) if spans_x else Vector3(jolt, 0, slide)
	_tick_braces(delta)
	return started_closing


# ---------------------------------------------------------------- braces

func brace_count() -> int:
	return braces.size()


## Clamp a new brace on. Returns false if the door already has the maximum.
func add_brace() -> bool:
	if braces.size() >= MAX_BRACES:
		return false
	# Unshaded like the walls (the floors have no lights).
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = _stripes(false)
	mat.texture_filter = Game.filter_3d()
	var clamp_mat := StandardMaterial3D.new()
	clamp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	clamp_mat.albedo_texture = _clamp_tex()
	clamp_mat.texture_filter = Game.filter_3d()
	# The brace is built along local X, centred on the tile; doors that run
	# along Z just turn it a quarter.
	var node := Node3D.new()
	node.position = Vector3(0.5, BRACE_Y[braces.size()], 0.5)
	node.rotation.y = 0.0 if spans_x else PI / 2.0
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var c := _box(Vector3(0.09, 0.17, 0.05), clamp_mat)
			c.position = Vector3(end * 0.47, 0, side * 0.065)
			c.name = "clamp"
			node.add_child(c)
	# The bars hang off a pivot at the left clamp, so they can swing down.
	var pivot := Node3D.new()
	pivot.position = Vector3(-0.47, 0, 0)
	node.add_child(pivot)
	for side in [-1.0, 1.0]:
		var bar := _box(Vector3(0.96, 0.075, 0.03), mat)
		bar.position = Vector3(0.47, 0, side * 0.075)
		pivot.add_child(bar)
	pivot.rotation.z = SWING_FROM
	slab.add_child(node)
	braces.append({"node": node, "pivot": pivot, "mat": mat, "t": 0.0, "landed": false})
	_tick_braces(0.0)
	return true


## The Hunter landed a blow: shake the door and rattle the braces.
func bash_hit() -> void:
	_shake = 1.0


## The top brace gives way. It is handed back so the world can throw it.
func pop_brace() -> Node3D:
	if braces.is_empty():
		return null
	var b: Dictionary = braces.pop_back()
	var node: Node3D = b.node
	var xf := node.global_transform
	slab.remove_child(node)
	node.transform = xf
	_shake = 1.0
	return node


## Where the right end of brace `i` sits, in world space (sparks go there).
func brace_end(i: int) -> Vector3:
	var node: Node3D = braces[i].node
	return node.to_global(Vector3(0.47, 0, 0))


func _tick_braces(delta: float) -> void:
	for i in braces.size():
		var b: Dictionary = braces[i]
		b.t += delta
		var t: float = b.t
		var pivot: Node3D = b.pivot
		var node: Node3D = b.node
		# Clamps pop out of the frame first.
		var cs := clampf(t / 0.08, 0.0, 1.0)
		for c in node.get_children():
			if c.name.begins_with("clamp"):
				c.scale = Vector3.ONE * maxf(cs, 0.01)
		var angle := 0.0
		if t < SWING_TIME:
			var k := t / SWING_TIME
			angle = SWING_FROM * (1.0 - k * k)   # accelerates as it falls
		elif t < SETTLE_TIME:
			var k := (t - SWING_TIME) / (SETTLE_TIME - SWING_TIME)
			angle = 0.16 * sin(k * PI * 2.0) * (1.0 - k)   # bounce on the clamp
		if not b.landed and t >= SWING_TIME:
			b.landed = true
			_shake = maxf(_shake, 0.6)
			brace_landed.emit(brace_end(i))
		# Rattle while the door is being battered.
		angle += _shake * 0.07 * sin(_time * 47.0 + i * 1.7)
		pivot.rotation.z = angle
		# Glows hot for a moment when it slams home.
		var mat: StandardMaterial3D = b.mat
		var hot := t >= SWING_TIME and t < SWING_TIME + 0.3
		mat.albedo_texture = _stripes(hot)
		mat.albedo_color = Color.WHITE.lerp(Color(1.0, 0.85, 0.6), clampf((t - SWING_TIME) / 0.3, 0.0, 1.0)) if hot else Color.WHITE


func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	return m


## Yellow and black hazard stripes for the bars, with a lit top edge and a
## dark bottom edge so the bar reads as solid steel; `hot` is the white-hot
## flash when it slams home.
static func _stripes(hot: bool) -> ImageTexture:
	var key := 1 if hot else 0
	if not _stripe_texs.has(key):
		var img := Image.create(32, 32, false, Image.FORMAT_RGB8)
		var yellow := Color(1.0, 0.95, 0.7) if hot else Color(0.95, 0.72, 0.1)
		var black := Color(1.0, 0.6, 0.25) if hot else Color(0.1, 0.1, 0.1)
		for y in 32:
			for x in 32:
				var c := yellow if ((x + y) / 8) % 2 == 0 else black
				if y < 3:
					c = c.lightened(0.35)
				elif y > 28:
					c = c.darkened(0.45)
				img.set_pixel(x, y, c)
		_stripe_texs[key] = ImageTexture.create_from_image(img)
	return _stripe_texs[key]


## Gunmetal clamp with a bolt head in the middle.
static func _clamp_tex() -> ImageTexture:
	if not _stripe_texs.has(2):
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		for y in 16:
			for x in 16:
				var c := Color(0.3, 0.32, 0.37)
				if x < 2 or y < 2:
					c = Color(0.45, 0.47, 0.52)
				elif x > 13 or y > 13:
					c = Color(0.16, 0.17, 0.2)
				if Vector2(x, y).distance_to(Vector2(7.5, 7.5)) < 3.0:
					c = Color(0.62, 0.64, 0.68)
				img.set_pixel(x, y, c)
		_stripe_texs[2] = ImageTexture.create_from_image(img)
	return _stripe_texs[2]
