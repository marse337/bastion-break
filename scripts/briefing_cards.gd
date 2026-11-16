class_name BriefingCards
extends SpriteCards
## Purge Protocol briefing: three animated steps that teach crafting -
## kill guards for scrap, press C at the workbench, use gadgets with R / F / B.

const CARD_W := 146.0
const CARD_H := 140.0
const GAP := 8.0
const SCENE_H := 80.0
const STEPS := [
	["1  Kill guards for scrap", "Every guard drops scrap: Sentry or Hound 1, Warden 2, bosses 4-6."],
	["2  Press C to craft", "The workbench pauses the game. Spend scrap on gadgets."],
	["3  Use them: R  F  B", "Rocket scraps the Hunter for the floor, a mine stuns it, a brace holds a door."],
]


func show_steps() -> void:
	_t = 0.0
	_hover = -1
	_clear_labels()
	var total := CARD_W * 3 + GAP * 2
	size = Vector2(total, CARD_H)
	position.x = (Hud.W - total) / 2.0
	for i in 3:
		var x := i * (CARD_W + GAP)
		var name_l := _label(Vector2(x + 4, SCENE_H + 7), Vector2(CARD_W - 8, 14), 10, C_HOT)
		name_l.text = STEPS[i][0]
		var desc := _label(Vector2(x + 6, SCENE_H + 22), Vector2(CARD_W - 12, CARD_H - SCENE_H - 24), 7, C_TEXT)
		desc.text = STEPS[i][1]
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	visible = true
	queue_redraw()


func _card_count() -> int:
	return 3


func _card_rect(i: int) -> Rect2:
	return Rect2(i * (CARD_W + GAP), 0, CARD_W, CARD_H)


func _draw() -> void:
	for i in 3:
		var r := _card_rect(i)
		var o := r.position + Vector2(3, 3)
		var box := Rect2(o, Vector2(CARD_W - 6, SCENE_H))
		_card_frame(r, box, false)
		var t := fmod(_t, LOOP)
		match i:
			0: _kill(o, t)
			1: _bench(o, t)
			2: _use(o, _t)
		draw_rect(box, C_EDGE, false, 1.0)
		if i < 2:
			# Arrow to the next step.
			var ax := r.end.x + GAP / 2.0
			var ay := r.position.y + SCENE_H / 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(ax - 3, ay - 5), Vector2(ax + 3, ay), Vector2(ax - 3, ay + 5)]), C_HOT)


func _floor(o: Vector2) -> float:
	return o.y + SCENE_H - 5


## A keyboard key cap; `down` sinks it as if pressed.
func _key(s: String, c: Vector2, down: bool, hot := true) -> void:
	var r := Rect2(c - Vector2(9, 9 - (2 if down else 0)), Vector2(18, 16))
	draw_rect(Rect2(r.position + Vector2(0, 2), r.size), Color(0.1, 0.1, 0.12))
	draw_rect(r, C_HOT if down else (Color(0.85, 0.85, 0.9) if hot else Color(0.4, 0.42, 0.48)))
	draw_string(_font, Vector2(r.position.x, r.position.y + 12), s, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 10, Color.BLACK)


func _kill(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	var gx := o.x + 96
	var shot := 0.7
	if t < shot:
		_spr(Tex.enemy("sentry", "walk", int(t * 10) % 4, 2), gx, fy, 46)
	elif t < shot + 0.5:
		_spr(Tex.enemy("sentry", "die", mini(int((t - shot) / 0.12), 3), 0), gx, fy, 46)
	else:
		_spr(Tex.enemy("sentry", "dead", 0, 0), gx, fy, 46)
	if t > shot - 0.1 and t < shot + 0.05:
		_flash(Vector2(o.x + 24, fy - 26), 6)
	# The scrap pops out of the body and flies up to the counter.
	var have := 0
	if t > shot + 0.4:
		var k := _k(t, shot + 0.4, shot + 1.2)
		var p := Vector2(gx, fy - 6).lerp(Vector2(o.x + 34, o.y + 16), k)
		p.y -= sin(k * PI) * 14
		if k < 1.0:
			_item("scrap", p.x, p.y + 6, 10)
		else:
			have = 1
	_item("scrap", o.x + 16, o.y + 21, 10)
	_txt("SCRAP %d" % (2 + have), Vector2(o.x + 46, o.y + 19), 9, C_GOLD if have > 0 else C_TEXT)
	_pop("+1 SCRAP", Vector2(gx, o.y + 30), t, shot + 0.5, C_GOLD, 8)


func _bench(o: Vector2, t: float) -> void:
	var cx := o.x + 70
	# C is pressed, the workbench opens, scrap becomes a mine.
	var press := 0.4
	_key("C", Vector2(o.x + 18, o.y + 20), t > press and t < press + 0.25)
	var open := _k(t, press + 0.2, press + 0.5)
	if open <= 0.0:
		_txt("press C", Vector2(cx + 10, o.y + 44), 9, C_DIM)
		return
	var r := Rect2(cx - 40 * open, o.y + 10, 90 * open, 62)
	draw_rect(r, Color(0.12, 0.13, 0.18))
	draw_rect(r, C_HOT, false, 1.0)
	if open < 1.0:
		return
	_txt("WORKBENCH  (paused)", Vector2(cx + 5, o.y + 20), 6, C_HOT)
	var items := [["rocket", 6], ["mine", 3], ["brace", 2]]
	var pick := 1
	for k in 3:
		var x := cx - 26 + k * 30
		var hot: bool = k == pick and t > 1.5
		if hot:
			draw_rect(Rect2(x - 12, o.y + 25, 24, 34), Color(0.35, 0.2, 0.05))
		_item(items[k][0], x, o.y + 48, 12)
		_txt("%d" % items[k][1], Vector2(x, o.y + 57), 7, C_GOLD)
	var scrap := 5 if t < 1.7 else 2
	_txt("scrap %d" % scrap, Vector2(cx + 5, o.y + 69), 7, C_GOLD if t < 1.7 else C_TEXT)
	_pop("+1 MINE", Vector2(cx + 4, o.y + 40), t, 1.7, C_GOOD, 8)


func _use(o: Vector2, tt: float) -> void:
	var fy := _floor(o)
	# Cycle through the three gadgets, one second each.
	var which := int(tt) % 3
	var t := fmod(tt, 1.0)
	var keys := ["R", "F", "B"]
	var names := ["ROCKET", "MINE", "BRACE"]
	for k in 3:
		_key(keys[k], Vector2(o.x + 16 + k * 22, o.y + 16), k == which and t < 0.2, k == which)
	_txt(names[which], Vector2(o.x + 108, o.y + 20), 8, C_HOT)
	var hx := o.x + 112
	match which:
		0:
			if t < 0.55:
				_spr(Tex.enemy("hunter", "walk", int(tt * 10) % 8, 0), hx, fy, 44)
				_item("rocket", lerpf(o.x + 20, hx, _k(t, 0.15, 0.55)), fy - 20, 7)
			else:
				_spr(Tex.enemy("hunter", "die", mini(int((t - 0.55) / 0.1), 3), 0), hx, fy, 44)
				if t < 0.8:
					_spr(Tex.tex("blast_%d" % mini(int((t - 0.55) / 0.08), 2)), hx, fy - 6, 34)
		1:
			_item("mine", o.x + 70, fy + 1, 6)
			if t < 0.4:
				_spr(Tex.enemy("hunter", "walk", int(tt * 10) % 8, 2), lerpf(hx, o.x + 74, _k(t, 0.0, 0.4)), fy, 44)
			else:
				_spr(Tex.enemy("hunter", "stun", int(tt * 5) % 2, 0), o.x + 74, fy, 44, Color(0.75, 0.9, 1.0))
				_spr(Tex.tex("arc_%d" % (int(tt * 12) % 2)), o.x + 74, fy - 10, 28)
		2:
			var dx := o.x + 50
			draw_rect(Rect2(dx - 12, o.y + 30, 24, fy - o.y - 30), Color(0.3, 0.34, 0.4))
			_item("brace", dx, o.y + 46, 8)
			_item("brace", dx, o.y + 60, 8)
			_spr(Tex.enemy("hunter", "bash", int(tt * 3.3) % 2, 0), hx - 8, fy, 44)
