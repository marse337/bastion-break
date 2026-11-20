class_name GadgetFx
extends Node3D
## Short-lived 3D effects for the Purge gadgets: smoke puffs, glowing
## flashes, floor shockwave rings, bouncing metal debris and electric arcs
## that crackle around a target. Everything is unshaded (the floors have no
## lights) and cleans itself up.

const GRAVITY := 9.0

## Every effect spawned so far, by kind (play tests read this).
var spawned := {}

var _parts: Array[Dictionary] = []
var _arcs: Array[Dictionary] = []   # {at: Callable -> Vector3, left, every, alive: Callable}
static var _disc: ImageTexture
static var _ring: ImageTexture


func tick(delta: float) -> void:
	for p in _parts.duplicate():
		p.t += delta
		var node: Node3D = p.node
		var k: float = p.t / p.life
		if k >= 1.0:
			node.queue_free()
			_parts.erase(p)
			continue
		match p.kind:
			"debris":
				_tick_debris(p, delta)
			_:
				p.vel.y -= p.get("gravity", 0.0) * delta
				node.position += p.vel * delta
				var s: float = lerpf(p.size0, p.size1, 1.0 - pow(1.0 - k, 2.0))
				node.scale = Vector3.ONE * s
				var mat: StandardMaterial3D = p.mat
				var c: Color = p.color
				c.a *= (1.0 - k) if p.get("fade_in", 0.0) <= 0.0 else minf(p.t / p.fade_in, 1.0) * (1.0 - k)
				mat.albedo_color = c
	for a in _arcs.duplicate():
		a.left -= delta
		a.next -= delta
		if a.left <= 0.0 or not a.alive.call():
			_arcs.erase(a)
			continue
		if a.next <= 0.0:
			a.next = 0.05
			var c: Vector3 = a.at.call()
			for j in 2:
				var off := Vector3(randf_range(-0.3, 0.3), randf_range(-0.35, 0.3), randf_range(-0.3, 0.3))
				var tex := Tex.tex("arc_%d" % (randi() % 2))
				var sz := randf_range(0.45, 0.75)
				_quad(c + off, tex, sz, Color(0.75, 0.9, 1.0), 0.09, sz, true, true, "arc")
			# A faint blue glow over the target while the arcs run.
			_quad(c, _disc_tex(), 0.9, Color(0.35, 0.6, 1.0, 0.25), 0.06, 0.9, true, true, "arc_glow")


# ---------------------------------------------------------------- spawners

## A soft round puff (smoke, fire, glow). `add` blends additively (glows).
func puff(at: Vector3, size0: float, size1: float, color: Color, life: float, vel := Vector3.ZERO, add := false, kind := "puff", gravity := 0.0) -> Dictionary:
	var p := _quad(at, _disc_tex(), size0, color, life, size1, add, true, kind)
	p.vel = vel
	p.gravity = gravity
	return p


## A bright additive flash that pops and fades fast.
func flash(at: Vector3, size: float, color: Color, life := 0.15) -> void:
	puff(at, size * 0.6, size, color, life, Vector3.ZERO, true, "flash")


## A flat ring that races out across the floor.
func ring(at: Vector3, r0: float, r1: float, color: Color, life: float) -> void:
	var p := _quad(Vector3(at.x, 0.02, at.z), _ring_tex(), r0 * 2.0, color, life, r1 * 2.0, true, false, "ring")
	p.node.rotation.x = -PI / 2.0


## Hot metal chunks thrown out of a blast; they bounce and come to rest.
func debris(at: Vector3, n: int) -> void:
	for i in n:
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(randf_range(0.04, 0.09), randf_range(0.02, 0.05), randf_range(0.04, 0.08))
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.55, 0.15)
		m.material_override = mat
		m.position = at
		add_child(m)
		var ang := randf() * TAU
		var sp := randf_range(1.5, 3.5)
		_parts.append({"node": m, "mat": mat, "kind": "debris", "t": 0.0, "life": randf_range(2.2, 3.0),
			"vel": Vector3(cos(ang) * sp, randf_range(1.5, 3.5), sin(ang) * sp),
			"spin": Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))})
		_count("debris")


## Electric arcs crackling around `at.call()` for `seconds`, or until
## `alive.call()` turns false.
func arcs(at: Callable, seconds: float, alive: Callable = func(): return true) -> void:
	_arcs.append({"at": at, "left": seconds, "next": 0.0, "alive": alive})


## Live (not yet finished) effects of one kind, or all of them.
func active(kind := "") -> int:
	var n := 0
	for p in _parts:
		if kind == "" or p.kind == kind:
			n += 1
	return n


func arcs_running() -> int:
	return _arcs.size()


# ---------------------------------------------------------------- internals

func _tick_debris(p: Dictionary, delta: float) -> void:
	var node: Node3D = p.node
	var resting: bool = p.get("rest", false)
	if not resting:
		p.vel.y -= GRAVITY * delta
		node.position += p.vel * delta
		node.rotation += p.spin * delta
		if node.position.y <= 0.02:
			node.position.y = 0.02
			if absf(p.vel.y) > 1.2:
				p.vel = Vector3(p.vel.x * 0.4, -p.vel.y * 0.3, p.vel.z * 0.4)
				p.spin *= 0.4
			else:
				p.rest = true
	# Glows orange-hot, then cools to dark metal.
	var mat: StandardMaterial3D = p.mat
	mat.albedo_color = Color(1.0, 0.55, 0.15).lerp(Color(0.18, 0.18, 0.2), clampf(p.t / 0.8, 0.0, 1.0))
	if p.t > p.life - 0.4:
		node.scale = Vector3.ONE * maxf(0.01, (p.life - p.t) / 0.4)


func _quad(at: Vector3, tex: Texture2D, size0: float, color: Color, life: float, size1: float, add: bool, billboard: bool, kind: String) -> Dictionary:
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	m.mesh = q
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if add else BaseMaterial3D.BLEND_MODE_MIX
	mat.albedo_texture = tex
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	if billboard:
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
	m.material_override = mat
	m.position = at
	m.scale = Vector3.ONE * size0
	add_child(m)
	var p := {"node": m, "mat": mat, "kind": kind, "t": 0.0, "life": life, "size0": size0, "size1": size1, "color": color, "vel": Vector3.ZERO}
	_parts.append(p)
	_count(kind)
	return p


func _count(kind: String) -> void:
	spawned[kind] = int(spawned.get(kind, 0)) + 1


## Soft white disc: full in the middle, fading to nothing at the edge.
static func _disc_tex() -> ImageTexture:
	if _disc == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(16, 16)) / 16.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - d, 0.0, 1.0) ** 1.5))
		_disc = ImageTexture.create_from_image(img)
	return _disc


## Thin white ring with soft edges, for shockwaves.
static func _ring_tex() -> ImageTexture:
	if _ring == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(32, 32)) / 32.0
				img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - absf(d - 0.85) / 0.12, 0.0, 1.0)))
		_ring = ImageTexture.create_from_image(img)
	return _ring
