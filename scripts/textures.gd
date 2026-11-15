class_name Tex
extends RefCounted
## Procedural pixel art. Every wall, sprite and weapon is drawn in code at
## 64x64, so the project ships with no external image assets.

const WEAPONS := ["shiv", "sidearm", "rifle", "rotary"]

const GUN := Color(0.16, 0.16, 0.19)
const GLOVE := Color(0.2, 0.2, 0.22)
const SLEEVE := Color(0.85, 0.45, 0.12)
const GOLD := Color(0.95, 0.75, 0.2)

static var _cache: Dictionary = {}


## Returns a texture by name. Blender-rendered art in res://assets/tex/ is
## used when present; otherwise a procedural fallback is drawn.
static func tex(tex_name: String) -> Texture2D:
	if not _cache.has(tex_name):
		var path := "res://assets/tex/%s.png" % tex_name
		if ResourceLoader.exists(path):
			_cache[tex_name] = load(path)
		else:
			_cache[tex_name] = ImageTexture.create_from_image(make_image(tex_name))
	return _cache[tex_name]


## Enemy sprite frame. Blender renders live in
## res://assets/enemies/<kind>/<pose>_<frame>_d<dir>.png.
static func enemy(kind: String, pose: String, frame: int, dir: int) -> Texture2D:
	var key := "enemies/%s/%s_%d_d%d" % [kind, pose, frame, dir]
	if _cache.has(key):
		return _cache[key]
	var path := "res://assets/%s.png" % key
	var t: Texture2D
	if ResourceLoader.exists(path):
		t = load(path)
	else:
		var old := pose
		if pose == "walk":
			old = "walk%d" % (frame % 2)
		t = tex(("warden" if kind == "overseer" else kind) + "_" + old)
	_cache[key] = t
	return t


static func make_image(tex_name: String) -> Image:
	match tex_name:
		"stone": return _stone()
		"metal": return _metal()
		"rust": return _rust()
		"sigil": return _sigil()
		"exit": return _exit(false)
		"exit_on": return _exit(true)
		"door": return _door(Color(0, 0, 0, 0))
		"door_red": return _door(Color(0.8, 0.12, 0.1))
		"door_blue": return _door(Color(0.15, 0.35, 0.9))
		"door_gold": return _door(GOLD)
		"stone_secret": return _stone()
		"metal_secret": return _metal()
		"key_gold": return _key(GOLD)
		"plasma": return _orb(Color(1, 0.5, 0.1), 6.0)
		"blast_0": return _orb(Color(1, 0.8, 0.3), 8.0)
		"blast_1": return _orb(Color(1, 0.5, 0.1), 14.0)
		"blast_2": return _orb(Color(0.2, 0.18, 0.18), 18.0)
		"ammo": return _ammo(false)
		"clip": return _ammo(true)
		"medkit": return _medkit()
		"food": return _food()
		"gem": return _gem()
		"idol": return _idol()
		"life": return _life()
		"rifle": return _rifle_item()
		"rotary": return _rotary_item()
		"key_red": return _key(Color(0.85, 0.15, 0.12))
		"key_blue": return _key(Color(0.2, 0.4, 0.95))
		"pillar": return _pillar()
		"lamp": return _lamp()
		"barrel": return _barrel()
		"map": return _map_item()
		"floor": return _flat(Color(0.3, 0.3, 0.31), 606)
		"ceiling": return _flat(Color(0.24, 0.24, 0.27), 707)
	if tex_name.begins_with("w_"):
		var parts := tex_name.split("_")
		return _weapon(parts[1], 1 if int(parts[2]) == 1 else 0)
	var p := tex_name.split("_")
	if p.size() == 2:
		if p[0] == "hound":
			return _hound(p[1])
		if p[0] == "sentry" or p[0] == "warden":
			return _trooper(p[0], p[1])
	push_warning("Unknown texture: " + tex_name)
	var img := _img()
	img.fill(Color.MAGENTA)
	return img


# ---------------------------------------------------------------- helpers

static func _img(w := 64, h := 64) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if r.size.x > 0 and r.size.y > 0:
		img.fill_rect(r, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _ell(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


static func _circ(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	_ell(img, cx, cy, r, r, c)


static func _tint(img: Image, c: Color, amt: float) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a > 0.0:
				img.set_pixel(x, y, Color(lerpf(p.r, c.r, amt), lerpf(p.g, c.g, amt), lerpf(p.b, c.b, amt), p.a))


# ---------------------------------------------------------------- walls

static func _stone() -> Image:
	var img := _img()
	var rng := _rng(101)
	img.fill(Color(0.16, 0.16, 0.18))
	for row in 4:
		var off := 0 if row % 2 == 0 else 16
		for b in range(-1, 3):
			var x0 := b * 32 + off
			var g := rng.randf_range(0.34, 0.48)
			for y in range(row * 16 + 1, row * 16 + 15):
				for x in range(x0 + 1, x0 + 31):
					if x < 0 or x >= 64:
						continue
					var v := g + rng.randf_range(-0.035, 0.035)
					if y == row * 16 + 1 or x == x0 + 1:
						v += 0.07
					elif y == row * 16 + 14 or x == x0 + 30:
						v -= 0.08
					img.set_pixel(x, y, Color(v, v, v * 1.06))
	return img


static func _metal() -> Image:
	var img := _img()
	var rng := _rng(202)
	for y in 64:
		for x in 64:
			var px := x % 32
			var py := y % 32
			var v := 0.36 + rng.randf_range(-0.02, 0.02)
			if px <= 1 or py <= 1:
				v = 0.5
			elif px >= 30 or py >= 30:
				v = 0.2
			img.set_pixel(x, y, Color(v * 0.85, v * 0.95, v * 1.1))
	for cy in [5, 26, 37, 58]:
		for cx in [5, 26, 37, 58]:
			_circ(img, cx, cy, 1.6, Color(0.6, 0.65, 0.72))
			_px(img, cx + 1, cy + 1, Color(0.12, 0.12, 0.15))
	for i in 4:
		_rect(img, 38, 8 + i * 5, 20, 2, Color(0.1, 0.11, 0.13))
	return img


static func _rust() -> Image:
	var img := _img()
	var rng := _rng(303)
	for y in 64:
		for x in 64:
			var s := 0.5 + 0.5 * sin(x * PI / 4.0)
			var c := Color(0.33, 0.19, 0.11).lerp(Color(0.6, 0.34, 0.16), s)
			var n := rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(c.r + n, c.g + n, c.b + n))
	for i in 16:
		_circ(img, rng.randi_range(0, 63), rng.randi_range(0, 63), rng.randf_range(1.5, 4.0), Color(0.27, 0.12, 0.07))
	for by in [0, 30, 60]:
		_rect(img, 0, by, 64, 4 if by != 30 else 3, Color(0.25, 0.25, 0.27))
		for rx in range(4, 64, 12):
			_px(img, rx, by + 1, Color(0.55, 0.55, 0.6))
	return img


static func _sigil() -> Image:
	var img := _stone()
	var red := Color(0.5, 0.07, 0.06)
	_rect(img, 18, 1, 28, 57, Color(0.1, 0.1, 0.12))
	_rect(img, 20, 1, 24, 55, red)
	_rect(img, 20, 1, 24, 2, GOLD)
	_rect(img, 20, 1, 2, 55, GOLD.darkened(0.3))
	_rect(img, 42, 1, 2, 55, GOLD.darkened(0.3))
	for y in range(48, 57):
		var half := y - 48
		_rect(img, 32 - half, y, half * 2, 1, Color(0.16, 0.16, 0.18))
	for i in 8:
		var a := i * TAU / 8.0
		_circ(img, 32 + cos(a) * 11.0, 24 + sin(a) * 11.0, 2.7, GOLD)
	_circ(img, 32, 24, 10, GOLD)
	_circ(img, 32, 24, 6, red)
	_circ(img, 32, 24, 2.5, GOLD)
	_rect(img, 26, 39, 12, 2, GOLD)
	_rect(img, 28, 43, 8, 2, GOLD)
	return img


static func _exit(on: bool) -> Image:
	var img := _metal()
	_rect(img, 17, 8, 30, 48, Color(0.5, 0.52, 0.55))
	_rect(img, 19, 10, 26, 44, Color(0.07, 0.07, 0.09))
	var lamp := Color(0.15, 1.0, 0.25) if on else Color(1.0, 0.18, 0.1)
	_circ(img, 32, 16, 4, lamp.darkened(0.4))
	_circ(img, 32, 16, 2.5, lamp)
	_rect(img, 30, 24, 4, 24, Color(0.02, 0.02, 0.02))
	var ly := 24 if on else 43
	_rect(img, 26, ly, 12, 5, Color(0.82, 0.82, 0.86))
	_rect(img, 26, ly + 4, 12, 1, Color(0.4, 0.4, 0.45))
	var chev := Color(0.15, 0.9, 0.25) if on else Color(0.25, 0.3, 0.25)
	for i in 3:
		for k in 4:
			_px(img, 23 + k, 30 + i * 6 + k, chev)
			_px(img, 40 - k, 30 + i * 6 + k, chev)
	return img


static func _door(band: Color) -> Image:
	var img := _img()
	var rng := _rng(404)
	for y in 64:
		for x in 64:
			var v := 0.3 + rng.randf_range(-0.015, 0.015)
			if y % 8 == 0:
				v = 0.42
			elif y % 8 == 7:
				v = 0.2
			if x < 2 or x > 61 or y < 2 or y > 61:
				v = 0.16
			img.set_pixel(x, y, Color(v * 0.9, v * 1.05, v * 1.1))
	_rect(img, 20, 12, 24, 5, Color(0.04, 0.05, 0.06))
	_rect(img, 21, 13, 22, 1, Color(0.3, 0.6, 0.7))
	_rect(img, 50, 30, 6, 12, Color(0.18, 0.2, 0.22))
	_rect(img, 52, 32, 2, 8, Color(0.55, 0.6, 0.62))
	if band.a > 0.0:
		_rect(img, 4, 26, 56, 10, band.darkened(0.4))
		_rect(img, 4, 27, 56, 8, band)
		_rect(img, 28, 28, 8, 6, Color(0.95, 0.95, 0.9))
		_rect(img, 30, 30, 4, 2, band.darkened(0.5))
	return img


# ---------------------------------------------------------------- items & props

static func _ammo(small: bool) -> Image:
	var img := _img()
	var olive := Color(0.3, 0.36, 0.2)
	if small:
		_rect(img, 27, 52, 10, 11, olive)
		_rect(img, 27, 56, 10, 2, Color(0.9, 0.75, 0.2))
		for i in 2:
			_rect(img, 28 + i * 5, 48, 3, 4, Color(0.85, 0.65, 0.25))
	else:
		_rect(img, 22, 48, 20, 15, olive)
		_rect(img, 22, 48, 20, 2, olive.lightened(0.3))
		_rect(img, 22, 54, 20, 3, Color(0.9, 0.75, 0.2))
		for i in 4:
			_rect(img, 24 + i * 5, 43, 3, 6, Color(0.85, 0.65, 0.25))
			_rect(img, 24 + i * 5, 42, 3, 1, Color(0.7, 0.4, 0.2))
	return img


static func _medkit() -> Image:
	var img := _img()
	var red := Color(0.85, 0.1, 0.1)
	_rect(img, 27, 43, 10, 3, Color(0.4, 0.4, 0.42))
	_rect(img, 18, 46, 28, 17, Color(0.9, 0.9, 0.88))
	_rect(img, 18, 61, 28, 2, Color(0.6, 0.6, 0.6))
	_rect(img, 29, 48, 6, 13, red)
	_rect(img, 24, 52, 16, 5, red)
	return img


static func _food() -> Image:
	var img := _img()
	_ell(img, 32, 61, 14, 2.5, Color(0, 0, 0, 0.5))
	_rect(img, 22, 46, 20, 15, Color(0.6, 0.62, 0.64))
	_rect(img, 22, 50, 20, 7, Color(0.2, 0.5, 0.25))
	_rect(img, 28, 52, 8, 3, Color(0.95, 0.9, 0.6))
	_ell(img, 32, 46, 10, 2, Color(0.78, 0.8, 0.82))
	return img


static func _gem() -> Image:
	var img := _img()
	var c := Color(0.3, 0.9, 1.0)
	for y in 18:
		var half := y * 1.4 if y < 6 else (17 - y) * 0.75
		_rect(img, int(32 - half), 44 + y, int(half * 2) + 1, 1, c.darkened(0.25 * (y / 17.0)))
	_rect(img, 28, 47, 3, 2, Color.WHITE)
	_px(img, 38, 44, Color.WHITE)
	_px(img, 22, 52, Color(0.8, 1, 1))
	return img


static func _idol() -> Image:
	var img := _img()
	_rect(img, 23, 57, 18, 6, GOLD.darkened(0.35))
	_rect(img, 28, 42, 8, 15, GOLD)
	_circ(img, 32, 38, 4.5, GOLD)
	_rect(img, 24, 45, 16, 3, GOLD)
	_rect(img, 30, 36, 1, 2, Color(0.3, 0.1, 0))
	_rect(img, 33, 36, 1, 2, Color(0.3, 0.1, 0))
	_rect(img, 29, 43, 2, 12, GOLD.lightened(0.4))
	return img


static func _life() -> Image:
	var img := _img()
	_ell(img, 32, 50, 13, 3, Color(0.4, 0.7, 1.0, 0.7))
	_circ(img, 32, 49, 10, Color(0.2, 0.45, 1.0))
	_circ(img, 32, 49, 7, Color(0.5, 0.8, 1.0))
	_circ(img, 29, 46, 2.5, Color.WHITE)
	return img


static func _rifle_item() -> Image:
	var img := _img()
	_rect(img, 8, 54, 38, 5, GUN)
	_rect(img, 4, 55, 6, 2, GUN.darkened(0.3))
	_rect(img, 44, 53, 14, 7, Color(0.38, 0.24, 0.12))
	_rect(img, 24, 58, 5, 6, GUN)
	_rect(img, 10, 54, 30, 1, GUN.lightened(0.3))
	return img


static func _rotary_item() -> Image:
	var img := _img()
	for i in 3:
		_rect(img, 6, 50 + i * 3, 30, 2, GUN.lightened(0.15 * i))
	_rect(img, 34, 48, 20, 13, GUN.darkened(0.2))
	_rect(img, 50, 55, 8, 8, Color(0.38, 0.24, 0.12))
	_rect(img, 36, 49, 16, 2, Color(0.6, 0.15, 0.1))
	return img


static func _key(c: Color) -> Image:
	var img := _img()
	_rect(img, 24, 48, 16, 11, c)
	_rect(img, 24, 51, 16, 2, Color(0.05, 0.05, 0.05))
	_rect(img, 27, 54, 4, 3, GOLD)
	_rect(img, 24, 58, 16, 1, c.darkened(0.4))
	return img


static func _pillar() -> Image:
	var img := _img()
	var rng := _rng(505)
	for x in range(22, 42):
		var s := 0.3 + 0.25 * sin((x - 22) / 20.0 * PI)
		for y in 64:
			var v := s + rng.randf_range(-0.02, 0.02)
			img.set_pixel(x, y, Color(v, v, v * 1.05))
	_rect(img, 19, 0, 26, 5, Color(0.42, 0.42, 0.45))
	_rect(img, 19, 59, 26, 5, Color(0.42, 0.42, 0.45))
	_rect(img, 19, 4, 26, 1, Color(0.2, 0.2, 0.22))
	_rect(img, 19, 59, 26, 1, Color(0.2, 0.2, 0.22))
	return img


static func _lamp() -> Image:
	var img := _img()
	_rect(img, 31, 0, 2, 6, Color(0.15, 0.15, 0.15))
	for y in range(6, 13):
		var half := 3 + (y - 6)
		_rect(img, 32 - half, y, half * 2, 1, Color(0.3, 0.34, 0.3))
	_circ(img, 32, 14, 3, Color(1, 0.95, 0.6))
	_ell(img, 32, 16, 7, 2, Color(1, 0.9, 0.5, 0.35))
	return img


static func _orb(c: Color, r: float) -> Image:
	var img := _img()
	_circ(img, 32, 32, r, c)
	_circ(img, 32, 32, r * 0.5, c.lightened(0.5))
	return img


static func _map_item() -> Image:
	var img := _img()
	_rect(img, 18, 50, 28, 13, Color(0.2, 0.35, 0.75))
	for i in 4:
		_rect(img, 20, 52 + i * 3, 24, 1, Color(0.85, 0.9, 1.0))
	_rect(img, 30, 50, 1, 13, Color(0.85, 0.9, 1.0))
	_rect(img, 14, 48, 6, 15, Color(0.15, 0.27, 0.6))
	return img


static func _flat(c: Color, s: int) -> Image:
	var img := _img()
	var rng := _rng(s)
	for y in 64:
		for x in 64:
			var n := rng.randf_range(-0.02, 0.02)
			var v := c + Color(n, n, n)
			if x == 0 or y == 0:
				v = c.darkened(0.25)
			img.set_pixel(x, y, v)
	return img


static func _barrel() -> Image:
	var img := _img()
	var g := Color(0.2, 0.35, 0.22)
	_rect(img, 22, 34, 20, 29, g)
	_ell(img, 32, 34, 10, 2, g.lightened(0.2))
	_rect(img, 22, 39, 20, 2, g.darkened(0.4))
	_rect(img, 22, 56, 20, 2, g.darkened(0.4))
	_rect(img, 26, 35, 3, 28, g.lightened(0.25))
	_rect(img, 30, 44, 7, 7, Color(0.95, 0.8, 0.1))
	_rect(img, 32, 45, 3, 3, Color(0.1, 0.1, 0.1))
	return img


# ---------------------------------------------------------------- enemies

## Sentry (orange armored grunt) and Warden (heavy blue enforcer).
## Poses: stand walk0 walk1 aim fire pain die dead.
static func _trooper(kind: String, pose: String) -> Image:
	var heavy := kind == "warden"
	var body := Color(0.28, 0.34, 0.6) if heavy else Color(0.66, 0.44, 0.2)
	var trim := Color(0.75, 0.75, 0.8) if heavy else Color(0.3, 0.22, 0.12)
	var visor := Color(1.0, 0.25, 0.2) if heavy else Color(0.3, 1.0, 0.95)
	var dark := body.darkened(0.45)
	var img := _img()
	if pose == "dead":
		_rect(img, 12, 56, 40, 7, dark)
		_rect(img, 16, 53, 28, 6, body)
		_rect(img, 42, 51, 11, 9, body.lightened(0.1))
		_rect(img, 44, 54, 7, 2, visor.darkened(0.7))
		_rect(img, 6, 59, 10, 4, GUN)
		_rect(img, 20, 54, 8, 2, trim)
		return img
	if pose == "pain":
		img = _trooper(kind, "stand")
		_tint(img, Color(1, 0.35, 0.25), 0.5)
		return img
	if pose == "die":
		var stand := _trooper(kind, "pain")
		img.blit_rect(stand, Rect2i(0, 0, 64, 52), Vector2i(0, 12))
		_tint(img, Color(0.1, 0.05, 0.05), 0.35)
		for p in [Vector2i(20, 20), Vector2i(41, 24), Vector2i(30, 16), Vector2i(36, 34)]:
			_rect(img, p.x, p.y, 2, 2, Color(1, 0.9, 0.3))
		return img
	var w := 3 if heavy else 0
	var lo := 0
	var ro := 0
	if pose == "walk0":
		lo = -3
		ro = 2
	elif pose == "walk1":
		lo = 2
		ro = -3
	# legs and boots
	_rect(img, 23 - w + lo, 44, 7, 17, dark)
	_rect(img, 34 + w + ro, 44, 7, 17, dark)
	_rect(img, 22 - w + lo, 59, 9, 5, GUN)
	_rect(img, 33 + w + ro, 59, 9, 5, GUN)
	# torso
	_rect(img, 19 - w, 24, 26 + w * 2, 21, body)
	_rect(img, 24, 27, 16, 9, body.lightened(0.15))
	_rect(img, 30, 29, 4, 4, trim)
	_rect(img, 19 - w, 42, 26 + w * 2, 3, trim)
	if heavy:
		_rect(img, 12, 21, 11, 8, trim)
		_rect(img, 41, 21, 11, 8, trim)
	# head
	_rect(img, 29, 22, 6, 3, dark)
	_rect(img, 26, 9, 12, 14, body.lightened(0.08))
	_rect(img, 25, 7, 14, 4, dark)
	_rect(img, 27, 14, 10, 4, visor)
	_rect(img, 29, 15, 6, 2, Color.WHITE.lerp(visor, 0.4))
	# arms and weapon
	if pose == "aim" or pose == "fire":
		_rect(img, 16 - w, 26, 7, 12, dark)
		_rect(img, 41 + w, 26, 7, 12, dark)
		_rect(img, 21, 34, 22, 6, dark)
		if heavy:
			_rect(img, 24, 28, 16, 14, GUN)
		else:
			_rect(img, 27, 30, 10, 12, GUN)
		_circ(img, 32, 34, 3, Color(0.02, 0.02, 0.02))
		if pose == "fire":
			_circ(img, 32, 34, 8, Color(1, 0.75, 0.2))
			_circ(img, 32, 34, 4, Color(1, 1, 0.85))
	else:
		_rect(img, 13 - w, 25, 6, 19, dark)
		_rect(img, 45 + w, 25, 6, 19, dark)
		_rect(img, 13 - w, 43, 6, 4, GUN)
		_rect(img, 46 + w, 40, 4, 15, GUN)
	return img


## Hound: a fast, low, four-legged machine. Same pose names as troopers.
static func _hound(pose: String) -> Image:
	var body := Color(0.36, 0.37, 0.42)
	var dark := body.darkened(0.45)
	var eye := Color(1, 0.15, 0.1)
	var img := _img()
	if pose == "dead":
		_ell(img, 32, 59, 18, 4, dark)
		_ell(img, 30, 57, 12, 3.5, body)
		_circ(img, 41, 56, 2, eye.darkened(0.7))
		_rect(img, 14, 60, 6, 2, body)
		return img
	if pose == "pain":
		img = _hound("stand")
		_tint(img, Color(1, 0.4, 0.3), 0.5)
		return img
	if pose == "die":
		var src := _hound("pain")
		img.blit_rect(src, Rect2i(0, 0, 64, 56), Vector2i(0, 8))
		_tint(img, Color(0.1, 0.05, 0.05), 0.35)
		return img
	var lo := 0
	var ro := 0
	if pose == "walk0":
		lo = -2
		ro = 2
	elif pose == "walk1":
		lo = 2
		ro = -2
	var crouch := 3 if pose == "aim" else 0
	_rect(img, 24 - ro, 47, 4, 14, dark.darkened(0.3))
	_rect(img, 36 - lo, 47, 4, 14, dark.darkened(0.3))
	_ell(img, 32, 45 + crouch, 15, 8, dark)
	_rect(img, 19 + lo, 47, 5, 15, body)
	_rect(img, 40 + ro, 47, 5, 15, body)
	_rect(img, 18 + lo, 60, 7, 3, dark)
	_rect(img, 39 + ro, 60, 7, 3, dark)
	_rect(img, 24, 29 + crouch, 2, 7, dark)
	_rect(img, 38, 29 + crouch, 2, 7, dark)
	_ell(img, 32, 40 + crouch, 9, 7.5, body)
	_rect(img, 27, 42 + crouch, 10, 6, body.lightened(0.12))
	_circ(img, 32, 37 + crouch, 3.2 if pose == "aim" else 2.5, eye)
	_px(img, 31, 36 + crouch, Color(1, 0.8, 0.7))
	if pose == "fire":
		_rect(img, 27, 44, 10, 7, Color(0.15, 0, 0))
		for i in 4:
			_px(img, 28 + i * 3, 44, Color.WHITE)
			_px(img, 29 + i * 2, 50, Color.WHITE)
	return img


# ---------------------------------------------------------------- weapons (first person)

static func _weapon(kind: String, frame: int) -> Image:
	var img := _img()
	match kind:
		"shiv":
			if frame == 0:
				_shiv(img, 0, 0)
			else:
				_shiv(img, -10, -12)
		"sidearm":
			_rect(img, 24, 54, 16, 10, SLEEVE)
			_rect(img, 27, 26, 10, 18, GUN)
			_rect(img, 28, 26, 8, 2, GUN.lightened(0.35))
			_rect(img, 31, 24, 2, 2, Color(0.05, 0.05, 0.05))
			_rect(img, 30, 28, 4, 2, Color(0.05, 0.05, 0.05))
			_rect(img, 25, 42, 14, 14, GLOVE)
			_rect(img, 23, 45, 3, 8, GLOVE.lightened(0.1))
			if frame == 1:
				_flash(img, 32, 17, 7)
		"rifle":
			_rect(img, 21, 52, 22, 12, SLEEVE)
			_rect(img, 28, 10, 8, 22, GUN.darkened(0.2))
			_rect(img, 29, 8, 6, 2, Color(0.04, 0.04, 0.04))
			_rect(img, 24, 28, 16, 26, GUN)
			_rect(img, 25, 28, 14, 2, GUN.lightened(0.3))
			_rect(img, 40, 34, 7, 11, GUN.darkened(0.3))
			_rect(img, 22, 40, 20, 13, GLOVE)
			if frame == 1:
				_flash(img, 32, 5, 7)
		"rotary":
			_rect(img, 16, 50, 32, 14, SLEEVE)
			_rect(img, 18, 30, 28, 22, GUN)
			_rect(img, 18, 30, 28, 2, GUN.lightened(0.3))
			var spin := 0.5 if frame == 1 else 0.0
			for i in 6:
				var a := i * TAU / 6.0 + spin
				var cx := 32 + cos(a) * 7.0
				var cy := 22 + sin(a) * 5.0
				_rect(img, int(cx) - 2, int(cy), 4, 10, GUN.lightened(0.15))
				_circ(img, cx, cy, 2.5, GUN.lightened(0.25))
				_circ(img, cx, cy, 1.0, Color(0.02, 0.02, 0.02))
			_rect(img, 18, 40, 28, 12, GLOVE)
			if frame == 1:
				_flash(img, 32, 13, 9)
	return img


static func _shiv(img: Image, ox: int, oy: int) -> void:
	_rect(img, 36 + ox, 52 + oy, 14, 14, SLEEVE)
	_rect(img, 36 + ox, 40 + oy, 12, 14, GLOVE)
	_rect(img, 39 + ox, 36 + oy, 6, 5, Color(0.38, 0.24, 0.12))
	for y in range(12, 37):
		var half := 0.5 + (y - 12) / 24.0 * 2.5
		var cx := 42.0 + (36 - y) * 0.1
		for x in range(int(cx - half), int(cx + half) + 1):
			_px(img, x + ox, y + oy, Color(0.75, 0.78, 0.8) if x < cx else Color(0.55, 0.57, 0.6))


static func _flash(img: Image, cx: int, cy: int, r: int) -> void:
	_circ(img, cx, cy, r, Color(1, 0.6, 0.15))
	_circ(img, cx, cy, r * 0.6, Color(1, 0.9, 0.4))
	_circ(img, cx, cy, r * 0.3, Color.WHITE)
	_rect(img, cx - r - 3, cy, r * 2 + 6, 1, Color(1, 0.8, 0.3))
	_rect(img, cx, cy - r - 3, 1, r * 2 + 6, Color(1, 0.8, 0.3))
