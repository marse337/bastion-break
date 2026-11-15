class_name PerkCards
extends SpriteCards
## The Smuggler's Terminal perk picker: one card per offered perk, each with
## a short looping scene built from the game's own sprites that shows what
## the perk does, above its name and description.

const CARD_W := 146.0
const CARD_H := 166.0
const GAP := 8.0
const SCENE_H := 96.0

var perks: Array[String] = []


func show_perks(ids: Array[String]) -> void:
	perks = ids
	_t = 0.0
	_hover = -1
	_clear_labels()
	var total := CARD_W * ids.size() + GAP * (ids.size() - 1)
	size = Vector2(total, CARD_H)
	position.x = (Hud.W - total) / 2.0
	for i in ids.size():
		var p: Array = Game.PERKS[ids[i]]
		var x := i * (CARD_W + GAP)
		var name_l := _label(Vector2(x + 4, SCENE_H + 8), Vector2(CARD_W - 8, 14), 10, C_HOT)
		name_l.text = "%d  %s" % [i + 1, p[0]]
		var desc := _label(Vector2(x + 6, SCENE_H + 24), Vector2(CARD_W - 12, CARD_H - SCENE_H - 28), 8, C_TEXT)
		desc.text = p[1]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	visible = true
	queue_redraw()


func _card_count() -> int:
	return perks.size()


func _card_rect(i: int) -> Rect2:
	return Rect2(i * (CARD_W + GAP), 0, CARD_W, CARD_H)


func _draw() -> void:
	for i in perks.size():
		var r := _card_rect(i)
		var o := r.position + Vector2(3, 3)
		var box := Rect2(o, Vector2(CARD_W - 6, SCENE_H))
		_card_frame(r, box, i == _hover)
		# Each card runs half a beat behind the last so they don't move in lockstep.
		var t := fmod(_t + i * 0.45, LOOP)
		match perks[i]:
			"scavenger": _scavenger(o, t)
			"point_blank": _point_blank(o, t)
			"ghost": _ghost(o, t)
			"thick_hide": _thick_hide(o, t)
			"field_medic": _field_medic(o, t)
			"quick_hands": _quick_hands(o, t)
			"fleet_foot": _fleet_foot(o, t)
			"deadeye": _deadeye(o, t)
			"treasure_hunter": _treasure_hunter(o, t)
			"muffler": _muffler(o, t)
		draw_rect(box, C_EDGE, false, 1.0)


func _floor(o: Vector2) -> float:
	return o.y + SCENE_H - 6


# ---------------------------------------------------------------- scenes

func _scavenger(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# An ammo box drops in, then Rook grabs it and gets half as much again.
	var drop := _k(t, 0.0, 0.35)
	var got := t > 1.0
	if not got:
		_item("ammo", o.x + 40, lerpf(o.y + 20, fy, drop), 20)
	else:
		_pop("+8", Vector2(o.x + 30, fy - 30), t, 1.0, C_DIM, 9)
		_pop("+12", Vector2(o.x + 54, fy - 30), t, 1.0, C_GOLD, 12)
		if t > 1.0 and t < 2.2:
			draw_line(Vector2(o.x + 22, fy - 34 - _k(t, 1.0, 2.2) * 12), Vector2(o.x + 38, fy - 34 - _k(t, 1.0, 2.2) * 12), C_DIM)
	# Ammo cap gauge: 99 becomes 150.
	var gx := o.x + 104
	var top := o.y + 10
	var gh := SCENE_H - 26
	var fill := 0.45 + 0.4 * _k(t, 1.0, 1.6)
	draw_rect(Rect2(gx, top, 16, gh), Color(0.05, 0.05, 0.07))
	draw_rect(Rect2(gx + 2, top + gh * (1 - fill), 12, gh * fill - 1), C_GOLD.darkened(0.2))
	var y99 := top + gh * (1 - 0.66)
	draw_dashed_line(Vector2(gx - 4, y99), Vector2(gx + 20, y99), C_DIM, 1.0, 2.0)
	_txt("99", Vector2(gx - 12, y99 + 3), 7, C_DIM, true)
	_txt("150", Vector2(gx + 8, top - 1), 7, C_GOLD)
	draw_rect(Rect2(gx, top, 16, gh), C_EDGE, false)


func _point_blank(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A Sentry steps in close; the sidearm goes off for double damage.
	var walk := _k(t, 0.0, 0.9)
	var sx := lerpf(o.x + 120, o.x + 92, walk)
	var hit := t > 1.1 and t < 1.5
	var pose := "walk" if t < 0.9 else ("pain" if hit else "aim")
	var frame := int(t * 8) % 8 if pose == "walk" else 0
	var dir := 0
	_spr(Tex.enemy("sentry", pose, frame, dir), sx, fy, lerpf(46, 58, walk), Color(1, 0.6, 0.6) if hit else Color.WHITE)
	# Distance bracket: within 3.5 tiles.
	var by := fy + 3
	var close := walk >= 1.0
	draw_line(Vector2(o.x + 34, by), Vector2(sx, by), C_GOOD if close else C_DIM, 1.0)
	draw_line(Vector2(o.x + 34, by - 3), Vector2(o.x + 34, by + 1), C_GOOD if close else C_DIM)
	draw_line(Vector2(sx, by - 3), Vector2(sx, by + 1), C_GOOD if close else C_DIM)
	_txt("3.5 tiles", Vector2((o.x + 34 + sx) / 2.0, by - 3), 7, C_GOOD if close else C_DIM)
	var f := 1 if t > 1.0 and t < 1.12 else (2 if t > 1.12 and t < 1.25 else 0)
	_spr(Tex.tex("w_sidearm_%d" % f), o.x + 34, o.y + SCENE_H - 1, 76)
	_pop("x2 DMG", Vector2(sx, fy - 58), t, 1.1, C_BAD, 10)


func _ghost(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A Sentry with its back turned never sees the shiv coming.
	var sx := o.x + 88
	if t < 1.1:
		_spr(Tex.enemy("sentry", "stand", 0, 4), sx, fy, 56)
		_txt("unaware", Vector2(sx, o.y + 12), 7, C_DIM)
	else:
		var d := mini(int((t - 1.1) / 0.12), 3)
		var tex := Tex.enemy("sentry", "die", d, 0) if t < 1.6 else Tex.enemy("sentry", "dead", 0, 0)
		_spr(tex, sx, fy, 56)
		_pop("ONE HIT", Vector2(sx, o.y + 30), t, 1.1, C_BAD, 10)
	if t > 1.6:
		var a := _k(t, 1.6, 1.9)
		_item("clip", sx + 30, lerpf(fy - 16, fy, a), 12)
		_pop("+2 AMMO", Vector2(sx + 22, fy - 20), t, 1.7, C_GOLD, 8)
	var lunge := _k(t, 0.6, 1.0) - _k(t, 1.3, 1.8)
	var f := 2 if t > 0.85 and t < 1.2 else (1 if t > 0.7 and t < 1.3 else 0)
	_spr(Tex.tex("w_shiv_%d" % f), o.x + 30 + lunge * 22, o.y + SCENE_H - 1, 76)


func _thick_hide(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A Warden's shot lands on Rook; armour soaks a fifth of it.
	_spr(Tex.enemy("warden", "fire" if t > 0.3 and t < 0.6 else "aim", 0, 0), o.x + 116, fy, 50)
	var shot := _k(t, 0.4, 0.9)
	if t > 0.4 and t < 0.9:
		var p := Vector2(lerpf(o.x + 108, o.x + 30, shot), lerpf(fy - 32, fy - 30, shot))
		draw_line(p, p + Vector2(10, 0), Color(1, 0.8, 0.4), 2.0)
	var hit := t > 0.9
	# Shield pulse at the impact point.
	if t > 0.9 and t < 1.4:
		var a := 1.0 - _k(t, 0.9, 1.4)
		draw_arc(Vector2(o.x + 26, fy - 30), 10 + 8 * (1 - a), -PI / 2, PI / 2, 12, Color(0.4, 0.8, 1.0, a), 2.0)
	var hp := 1.0 - (0.2 if hit else 0.0)
	var ghost := 1.0 - (0.25 if hit else 0.0)
	_txt("HEALTH", Vector2(o.x + 26, o.y + 14), 7, C_DIM)
	_bar(Vector2(o.x + 6, o.y + 18), 44, 7, ghost, Color(0.4, 0.15, 0.12))
	_bar(Vector2(o.x + 6, o.y + 18), 44, 7, hp, C_GOOD.darkened(0.2))
	if hit:
		_txt("-25", Vector2(o.x + 18, o.y + 38), 8, C_DIM, true)
		_txt("-20", Vector2(o.x + 40, o.y + 38), 10, C_BAD)
	_spr(Tex.tex("w_sidearm_0"), o.x + 30, o.y + SCENE_H - 1, 64)


func _field_medic(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A medkit heals half as much again.
	_item("medkit", o.x + 36, fy, 24, Color.WHITE if t < 0.9 else Color(1, 1, 1, 0.15))
	var base := 0.35
	var normal := base + 0.25 * _k(t, 0.9, 1.2)
	var extra := normal + 0.125 * _k(t, 1.2, 1.5)
	_txt("HEALTH", Vector2(o.x + 100, o.y + 16), 7, C_DIM)
	_bar(Vector2(o.x + 72, o.y + 20), 56, 8, extra, C_GOOD)
	draw_rect(Rect2(o.x + 73, o.y + 21, 54 * clampf(normal, 0, 1), 6), Color(0.25, 0.6, 0.3))
	_pop("+25", Vector2(o.x + 86, o.y + 48), t, 0.95, C_DIM, 8)
	_pop("+37", Vector2(o.x + 112, o.y + 48), t, 1.2, C_GOOD, 11)
	if t > 0.9 and t < 1.3:
		draw_rect(Rect2(o + Vector2(1, 1), Vector2(CARD_W - 8, SCENE_H - 2)), Color(0.4, 1, 0.5, 0.15 * (1 - _k(t, 0.9, 1.3))))


func _quick_hands(o: Vector2, t: float) -> void:
	# Two timelines: the normal fire rate and 15% faster.
	var x0 := o.x + 50
	var x1 := o.x + CARD_W - 12
	var rows := [[0.5, C_DIM, "normal", o.y + 22], [0.425, C_GOLD, "quick", o.y + 40]]
	for r in rows:
		var period: float = r[0]
		var y: float = r[3]
		_txt(r[2], Vector2(o.x + 26, y + 3), 7, r[1])
		draw_line(Vector2(x0, y), Vector2(x1, y), Color(0.2, 0.2, 0.25))
		var n := 0
		while n * period <= LOOP:
			var tx := lerpf(x0, x1, n * period / LOOP)
			var lit := t >= n * period
			draw_line(Vector2(tx, y - 4), Vector2(tx, y + 4), r[1] if lit else Color(0.25, 0.25, 0.3), 2.0)
			n += 1
		var cx := lerpf(x0, x1, t / LOOP)
		draw_line(Vector2(cx, o.y + 14), Vector2(cx, o.y + 48), Color(1, 1, 1, 0.5))
	var since := fmod(t, 0.425)
	var f := 1 if since < 0.06 else (2 if since < 0.14 else 0)
	_spr(Tex.tex("w_rifle_%d" % f), o.x + 40, o.y + SCENE_H - 1, 60)
	_txt("+15% fire rate", Vector2(o.x + 104, o.y + 66), 8, C_GOLD)


func _fleet_foot(o: Vector2, t: float) -> void:
	# Top-down race down a corridor: Rook (green) pulls ahead.
	var y0 := o.y + 14
	var x0 := o.x + 14
	var x1 := o.x + CARD_W - 18
	for row in 2:
		var y := y0 + row * 26
		draw_rect(Rect2(x0 - 4, y - 8, x1 - x0 + 8, 16), Color(0.08, 0.08, 0.1))
		draw_line(Vector2(x1, y - 8), Vector2(x1, y + 8), C_HOT, 1.0)
		var spd := 1.0 if row == 0 else 1.15
		var k := clampf(t / 2.6 * spd, 0, 1)
		var p := Vector2(lerpf(x0, x1, k), y)
		var c := C_DIM if row == 0 else C_GOOD
		for s in 4:
			var tp := Vector2(lerpf(x0, x1, maxf(k - 0.04 * (s + 1), 0)), y)
			draw_circle(tp, 3.0 - s * 0.6, Color(c, 0.25))
		draw_circle(p, 4.0, c)
		_txt("normal" if row == 0 else "you", Vector2(o.x + 30, y + 15), 7, c)
	if t > 2.26:
		_txt("+15%", Vector2(x1 - 10, y0 + 46), 10, C_GOOD)


func _deadeye(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# Far shots: the normal spread scatters, Deadeye's stays tight.
	var tx := o.x + CARD_W / 2.0 - 3
	_spr(Tex.tex("target_foe"), tx, fy - 6, 34)
	var aim := Vector2(tx, fy - 26)
	draw_arc(aim, 22, 0, TAU, 32, Color(C_DIM, 0.6), 1.0)
	draw_arc(aim, 11, 0, TAU, 24, Color(C_GOLD, 0.9), 1.0)
	var rng := RandomNumberGenerator.new()
	var shots := int(t / 0.3)
	for s in mini(shots, 9):
		rng.seed = s * 7 + 1
		var wide := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1) * 22
		var tight := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1) * 11
		draw_circle(aim + wide, 1.6, C_DIM)
		draw_circle(aim + tight, 1.8, C_GOLD)
	_txt("normal", Vector2(o.x + 22, o.y + 14), 7, C_DIM)
	_txt("deadeye", Vector2(o.x + CARD_W - 30, o.y + 14), 7, C_GOLD)


func _treasure_hunter(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# Treasure pays twice: score and Iron Scrip.
	var items := ["gem", "idol"]
	_txt("pick up treasure:", Vector2(o.x + CARD_W / 2.0 - 3, o.y + 14), 7, C_DIM)
	for n in 2:
		var at := 0.5 + n * 0.9
		var x := o.x + 34 + n * 64
		if t < at:
			var bob := sin(_t * 4 + n) * 2
			_item(items[n], x, fy - 2 + bob, 26)
		else:
			_pop("SCORE x2", Vector2(x, fy - 26), t, at, C_GOLD, 9)
			_pop("SCRIP x2", Vector2(x, fy - 12), t, at + 0.15, Color(0.75, 0.8, 0.9), 8)
		if t >= at and t < at + 0.25:
			draw_circle(Vector2(x, fy - 14), 14 * _k(t, at, at + 0.25), Color(1, 0.9, 0.4, 0.4))



func _muffler(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# Gunfire noise: the grey ring is normal reach, the gold ring is muffled.
	var src := Vector2(o.x + 20, fy - 34)
	var k := _k(t, 0.3, 1.3)
	var far_r := 118.0
	var near_r := 59.0
	if t > 0.3:
		var fade := 1.0 - _k(t, 1.6, 2.4)
		draw_arc(src, far_r * k, -0.38, 0.38, 24, Color(C_DIM, 0.7 * fade), 1.0)
		draw_arc(src, near_r * k, -0.7, 0.7, 24, Color(C_GOLD, fade), 2.0)
		if t > 0.8:
			_txt("normal", Vector2(src.x + far_r * k - 18, o.y + 20), 7, Color(C_DIM, fade))
			_txt("muffled", Vector2(src.x + near_r * k - 8, o.y + 20), 7, Color(C_GOLD, fade))
	# Near guard hears it either way; far guard keeps dozing.
	var near_alert := t > 0.3 + 0.5 * (40.0 / near_r)
	_spr(Tex.enemy("sentry", "aim" if near_alert else "stand", 0, 0 if near_alert else 2), o.x + 58, fy, 40)
	if near_alert:
		_txt("!", Vector2(o.x + 58, fy - 42), 10, C_BAD)
	_spr(Tex.enemy("sentry", "stand", 0, 6), o.x + 118, fy, 40)
	if t > 1.0:
		_txt("zzz", Vector2(o.x + 118, fy - 44), 8, C_GOOD)
	var f := 1 if t > 0.3 and t < 0.42 else 0
	_spr(Tex.tex("w_sidearm_%d" % f), src.x + 4, o.y + SCENE_H - 1, 60)
