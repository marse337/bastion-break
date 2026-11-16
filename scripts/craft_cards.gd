class_name CraftCards
extends SpriteCards
## Purge Protocol workbench: one card per gadget with a looping scene of it
## stopping the Hunter Warden, its scrap cost, how many you carry and its key.

const CARD_W := 146.0
const CARD_H := 166.0
const GAP := 8.0
const SCENE_H := 92.0

var ids: Array = []


func show_gadgets() -> void:
	var fresh := not visible
	ids = Game.GADGET_ORDER.duplicate()
	selectable = true
	sel_verb = "CRAFT"
	if fresh:
		_t = 0.0
		reset_sel()
	_clear_labels()
	var total := CARD_W * ids.size() + GAP * (ids.size() - 1)
	size = Vector2(total, CARD_H)
	position.x = (Hud.W - total) / 2.0
	for i in ids.size():
		var g: Array = Game.GADGETS[ids[i]]
		var x := i * (CARD_W + GAP)
		var name_l := _label(Vector2(x + 4, SCENE_H + 7), Vector2(CARD_W - 8, 14), 10, C_HOT)
		name_l.text = "%d  %s" % [i + 1, g[0]]
		var cost: int = g[1]
		var info := _label(Vector2(x + 4, SCENE_H + 22), Vector2(CARD_W - 8, 12), 8, C_GOLD if Game.scrap >= cost else C_BAD)
		info.text = "%d scrap    carried %d    key %s" % [cost, int(Game.gadgets[ids[i]]), g[2]]
		var desc := _label(Vector2(x + 6, SCENE_H + 36), Vector2(CARD_W - 12, CARD_H - SCENE_H - 38), 7, C_TEXT)
		desc.text = g[3]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	visible = true
	queue_redraw()


func _card_count() -> int:
	return ids.size()


func _card_rect(i: int) -> Rect2:
	return Rect2(i * (CARD_W + GAP), 0, CARD_W, CARD_H)


func _draw() -> void:
	for i in ids.size():
		var r := _card_rect(i)
		var o := r.position + Vector2(3, 3)
		var box := Rect2(o, Vector2(CARD_W - 6, SCENE_H))
		_card_frame(r, box, i == _hover)
		var t := fmod(_t + i * 0.45, LOOP)
		match ids[i]:
			"rocket": _rocket(o, t)
			"mine": _mine(o, t)
			"brace": _brace(o, t)
		draw_rect(box, C_EDGE, false, 1.0)
	_sel_marks()


func _floor(o: Vector2) -> float:
	return o.y + SCENE_H - 5


func _hunter(x: float, fy: float, h: float, pose: String, frame := 0, dir := 0, tint := Color.WHITE) -> void:
	_spr(Tex.enemy("hunter", pose, frame, dir), x, fy, h, tint)


# ---------------------------------------------------------------- scenes

func _rocket(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# The Hunter closes in, a rocket streaks out of the tube and it goes down.
	var hx := lerpf(o.x + 124, o.x + 104, _k(t, 0.0, 0.9))
	var hit := 1.2
	if t < hit:
		_hunter(hx, fy, 62, "walk", int(t * 10) % 8)
	elif t < hit + 0.5:
		_hunter(hx, fy, 62, "die", mini(int((t - hit) / 0.12), 3))
	else:
		_hunter(hx, fy, 62, "dead")
	if t > 0.8 and t < hit:
		var k := _k(t, 0.8, hit)
		_item("rocket", lerpf(o.x + 40, hx, k), fy - 30, 10)
	if t > hit and t < hit + 0.3:
		_spr(Tex.tex("blast_%d" % mini(int((t - hit) / 0.1), 2)), hx, fy - 8, 50)
	_pop("SCRAPPED  +5000", Vector2(o.x + 72, o.y + 16), t, hit + 0.1, C_GOLD, 9)
	_item("launcher", o.x + 32, o.y + SCENE_H - 4 - (2.0 if t > 0.8 and t < 0.9 else 0.0), 14)


func _mine(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A mine on the floor; the Hunter steps on it and slumps, stunned.
	var mx := o.x + 70
	var step := 1.0
	var hx := lerpf(o.x + 126, mx, _k(t, 0.0, step))
	if t < step:
		var blink := 1.0 if int(_t * 4) % 2 == 0 else 0.45
		_item("mine", mx, fy + 1, 7, Color(1, 1, 1, blink))
		_hunter(hx, fy, 62, "walk", int(t * 10) % 8, 2)
	else:
		_hunter(mx, fy, 62, "stun", int(t * 5) % 2, 0, Color(0.75, 0.9, 1.0))
		if t < step + 0.5:
			_spr(Tex.tex("arc_%d" % (int(_t * 12) % 2)), mx, fy - 14, 40)
		var left := 6.0 * (1.0 - _k(t, step, LOOP))
		_txt("STUNNED %.0fs" % ceilf(left), Vector2(mx, o.y + 14), 8, Color(0.5, 0.85, 1.0))


func _brace(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A braced door: the Hunter batters it far longer before it breaks.
	var dx := o.x + 50
	draw_rect(Rect2(dx - 14, o.y + 14, 28, fy - o.y - 14), Color(0.3, 0.34, 0.4))
	draw_rect(Rect2(dx - 14, o.y + 14, 28, fy - o.y - 14), Color(0.5, 0.55, 0.6), false, 1.0)
	_item("brace", dx, o.y + 40, 9)
	_item("brace", dx, o.y + 58, 9)
	_hunter(o.x + 96, fy, 62, "bash", int(t * 3.3) % 2, 0)
	if fmod(t, 0.6) < 0.08:
		_spark(Vector2(dx + 12, o.y + 34 + fmod(t * 37.0, 20.0)))
	# Battering timer: grey = unbraced (2.5 s), gold = with this brace (8.5 s).
	var by := o.y + 7
	_txt("2.5s", Vector2(o.x + 18, by + 7), 6, C_DIM)
	draw_rect(Rect2(o.x + 28, by + 2, 100 * 2.5 / 8.5, 3), C_DIM)
	_txt("8.5s", Vector2(o.x + 18, by + 15), 6, C_GOLD)
	draw_rect(Rect2(o.x + 28, by + 10, 100, 3), Color(0.25, 0.2, 0.05))
	draw_rect(Rect2(o.x + 28, by + 10, 100 * t / LOOP, 3), C_GOLD)


func _spark(p: Vector2) -> void:
	draw_circle(p, 2.5, Color(1, 0.85, 0.4))
	for k in 4:
		var a := k * PI / 2 + 0.4
		draw_line(p, p + Vector2.from_angle(a) * 5, Color(1, 0.9, 0.5), 1.0)
