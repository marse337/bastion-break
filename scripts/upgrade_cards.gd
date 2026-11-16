class_name UpgradeCards
extends SpriteCards
## The Cell shop: one card per permanent upgrade, each with a looping scene
## made from game sprites, its name, price or level, and what it does.

const CARD_W := 232.0
const CARD_H := 50.0
const GAP_X := 6.0
const GAP_Y := 4.0
const SCENE_W := 80.0
const SCENE_H := 44.0

var ids: Array = []
## Index of the START RUN button, selectable after the six upgrades.
var start_i := 6
var _desc: Label


func show_upgrades(desc_text := "") -> void:
	var fresh := ids.is_empty() or not visible
	ids = Game.UPGRADE_ORDER.duplicate()
	start_i = ids.size()
	selectable = true
	sel_verb = "BUY"
	if fresh:
		_t = 0.0
		reset_sel()
		_hover = start_i
	_clear_labels()
	# The protocol's description sits left of the START RUN button.
	var sr := _card_rect(start_i)
	_desc = _label(Vector2(0, sr.position.y - 1), Vector2(sr.position.x - 8, 26), 7, C_DIM, HORIZONTAL_ALIGNMENT_LEFT)
	_desc.text = desc_text
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	size = Vector2(CARD_W * 2 + GAP_X, CARD_H * 3 + GAP_Y * 2)
	position.x = (Hud.W - size.x) / 2.0
	for i in ids.size():
		var id: String = ids[i]
		var u: Array = Game.UPGRADES[id]
		var r := _card_rect(i)
		var lv := int(Game.upgrades.get(id, 0))
		var levels := (u[2] as Array).size()
		var cost := Game.upgrade_cost(id)
		var tx := r.position.x + SCENE_W + 10
		var tw := CARD_W - SCENE_W - 14
		var name_text := "%d  %s" % [i + 1, u[0]]
		if levels > 1:
			name_text += "  lv %d/%d" % [lv, levels]
		var n := _label(Vector2(tx, r.position.y + 3), Vector2(tw, 12), 9, C_HOT, HORIZONTAL_ALIGNMENT_LEFT)
		n.text = name_text
		var st := _label(Vector2(tx, r.position.y + 3), Vector2(tw, 12), 8, C_GOOD, HORIZONTAL_ALIGNMENT_RIGHT)
		if cost < 0:
			st.text = "OWNED"
		else:
			st.text = "%d scrip" % cost
			st.add_theme_color_override("font_color", C_GOLD if Game.scrip >= cost else C_BAD)
		var d := _label(Vector2(tx, r.position.y + 17), Vector2(tw, CARD_H - 19), 7, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
		d.text = u[1]
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	visible = true
	queue_redraw()


func _card_count() -> int:
	return ids.size() + 1


func _card_rect(i: int) -> Rect2:
	if i == start_i:
		return Rect2(CARD_W * 2 + GAP_X - 100, 3 * (CARD_H + GAP_Y) + 4, 100, 22)
	return Rect2((i % 2) * (CARD_W + GAP_X), (i / 2) * (CARD_H + GAP_Y), CARD_W, CARD_H)


func _verb(i: int) -> String:
	if i == start_i:
		return "START"
	return "OWNED" if Game.upgrade_cost(ids[i]) < 0 else "BUY"


## W / S: up or down a row; the bottom row drops onto START RUN.
func move_row(d: int) -> void:
	var s := selected()
	if s == start_i:
		s = start_i - 1 if d < 0 else start_i
	elif d > 0:
		s = s + 2 if s + 2 < start_i else start_i
	else:
		s = s - 2 if s >= 2 else s
	_hover = s
	queue_redraw()


## The description label is not part of any card, so never dim it.
func _process(delta: float) -> void:
	super(delta)
	if _desc != null and is_instance_valid(_desc):
		_desc.modulate.a = 1.0


func _draw() -> void:
	for i in ids.size():
		var r := _card_rect(i)
		var o := r.position + Vector2(3, 3)
		var box := Rect2(o, Vector2(SCENE_W, SCENE_H))
		_card_frame(r, box, i == _hover)
		var id: String = ids[i]
		var lv := int(Game.upgrades.get(id, 0))
		var t := fmod(_t + i * 0.4, LOOP)
		match id:
			"stash": _stash(o, t, lv)
			"dampener": _dampener(o, t)
			"cartographer": _cartographer(o, t)
			"shock_shiv": _shock_shiv(o, t)
			"ricochet": _ricochet(o, t)
			"spare_life": _spare_life(o, t)
		draw_rect(box, C_EDGE, false, 1.0)
		if Game.upgrade_cost(id) < 0:
			# Owned: a small green tick in the scene's corner.
			var c := o + Vector2(SCENE_W - 9, 8)
			draw_circle(c, 5, Color(0.1, 0.35, 0.15))
			draw_polyline(PackedVector2Array([c + Vector2(-2.5, 0), c + Vector2(-0.5, 2), c + Vector2(2.5, -2)]), C_GOOD, 1.5)
	# START RUN button.
	var sr := _card_rect(start_i)
	var glow := 0.75 + 0.25 * sin(_t * 4.0)
	draw_rect(sr, Color(0.55, 0.28, 0.05).lerp(Color(0.8, 0.42, 0.08), glow))
	draw_rect(sr, C_GOLD if selected() == start_i else C_EDGE, false, 2.0 if selected() == start_i else 1.0)
	draw_string(_font, Vector2(sr.position.x, sr.position.y + 15), "START RUN", HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, 11, Color.WHITE)
	_sel_marks()


func _floor(o: Vector2) -> float:
	return o.y + SCENE_H - 5


# ---------------------------------------------------------------- scenes

func _stash(o: Vector2, t: float, lv: int) -> void:
	var fy := _floor(o)
	# Ammo boxes stacked in the cell: one more per level, and the next one
	# dropping in faintly to show what buying it adds.
	var amounts := [10, 16, 24]
	for b in 3:
		var x := o.x + 14 + b * 18
		if b <= lv:
			_item("ammo", x, fy, 11)
		elif b == lv + 1:
			var k := _k(t, 0.6, 1.1)
			_item("ammo", x, lerpf(o.y + 10, fy, k), 11, Color(1, 1, 1, 0.35))
	_txt("%d" % amounts[lv], Vector2(o.x + 22, o.y + 13), 9, C_GOLD)
	if lv + 1 < amounts.size():
		_txt("→ %d" % amounts[lv + 1], Vector2(o.x + 52, o.y + 13), 8, Color(C_GOLD, 0.4 + 0.6 * _k(t, 1.1, 1.4)))
	_txt("start ammo", Vector2(o.x + 40, o.y + 23), 6, C_DIM)


func _dampener(o: Vector2, t: float) -> void:
	# The sidearm's noise ring: grey is normal reach, gold is dampened.
	var src := Vector2(o.x + 12, o.y + 22)
	var k := _k(t, 0.3, 1.2)
	if t > 0.3:
		var fade := 1.0 - _k(t, 1.8, 2.4)
		draw_arc(src, 62 * k, -0.3, 0.3, 20, Color(C_DIM, 0.7 * fade), 1.0)
		draw_arc(src, 40 * k, -0.42, 0.42, 20, Color(C_GOLD, fade), 2.0)
	_spr(Tex.enemy("sentry", "stand", 0, 6), o.x + 66, _floor(o), 28)
	if t > 1.0:
		_txt("zzz", Vector2(o.x + 66, o.y + 10), 7, C_GOOD)
		_txt("-8 tiles", Vector2(o.x + 38, o.y + 10), 7, C_GOLD)
	var f := 1 if t > 0.3 and t < 0.42 else 0
	_spr(Tex.tex("w_sidearm_%d" % f), o.x + 14, o.y + SCENE_H, 40)


func _cartographer(o: Vector2, t: float) -> void:
	# The floor's map fills itself in, tile by tile, before you take a step.
	var cols := 9
	var rows := 5
	var cell := 5.0
	var gx := o.x + 32
	var gy := o.y + 6
	var shown := int(_k(t, 0.2, 1.6) * cols * rows)
	var plan := [
		"#########",
		"#..#....#",
		"#..D..#.#",
		"#....##E#",
		"#########",
	]
	for n in mini(shown, cols * rows):
		var cx := n % cols
		var cy := n / cols
		var ch: String = plan[cy][cx]
		var c := Color(0.45, 0.48, 0.55) if ch == "#" else Color(0.12, 0.13, 0.16)
		if ch == "D":
			c = Color(0.85, 0.6, 0.2)
		elif ch == "E":
			c = C_GOOD
		draw_rect(Rect2(gx + cx * cell, gy + cy * cell, cell - 0.5, cell - 0.5), c)
	if t > 0.4:
		var blink := 0.5 + 0.5 * sin(_t * 8)
		draw_circle(Vector2(gx + 1.5 * cell, gy + 1.5 * cell), 1.6, Color(1, 1, 1, blink))
	_item("map", o.x + 15, _floor(o), 7)
	if t > 1.6:
		_txt("floor 1", Vector2(o.x + 54, o.y + 40), 6, C_DIM)


func _shock_shiv(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# The shiv lands with a shock: double damage and a guaranteed flinch.
	var hit := t > 0.9 and t < 1.5
	_spr(Tex.enemy("sentry", "pain" if hit else "aim", 0, 0), o.x + 56, fy, 34, Color(0.7, 0.85, 1.0) if hit else Color.WHITE)
	if hit:
		_spr(Tex.tex("arc_%d" % (int(_t * 12) % 2)), o.x + 56, fy - 6, 26)
	_pop("x2", Vector2(o.x + 40, o.y + 28), t, 0.9, Color(0.5, 0.85, 1.0), 9)
	var lunge := _k(t, 0.5, 0.9) - _k(t, 1.2, 1.7)
	var f := 2 if t > 0.75 and t < 1.1 else (1 if t > 0.6 and t < 1.2 else 0)
	_spr(Tex.tex("w_shiv_%d" % f), o.x + 18 + lunge * 14, o.y + SCENE_H, 44)


func _ricochet(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# Each sidearm round hits 40% harder.
	var hit := t > 0.5 and t < 0.9
	_spr(Tex.enemy("sentry", "pain" if hit else "aim", 0, 0), o.x + 60, fy, 34, Color(1, 0.6, 0.6) if hit else Color.WHITE)
	if t > 0.35 and t < 0.5:
		var k := _k(t, 0.35, 0.5)
		var p := Vector2(lerpf(o.x + 20, o.x + 56, k), o.y + 22)
		draw_line(p, p + Vector2(6, 0), Color(1, 0.85, 0.4), 1.5)
	_pop("+40%", Vector2(o.x + 40, o.y + 28), t, 0.5, C_BAD, 9)
	var f := 1 if t > 0.3 and t < 0.4 else (2 if t > 0.4 and t < 0.5 else 0)
	_spr(Tex.tex("w_sidearm_%d" % f), o.x + 16, o.y + SCENE_H, 44)


func _spare_life(o: Vector2, t: float) -> void:
	var fy := _floor(o)
	# A second clone joins the first: two lives at the start of every run.
	_item("life", o.x + 26, fy - 2, 22)
	var k := _k(t, 0.6, 1.0)
	if k > 0:
		_item("life", o.x + 54, fy - 2 - (1 - k) * 10, 22, Color(1, 1, 1, k))
	if t > 1.0:
		_txt("2 lives", Vector2(o.x + 40, o.y + 11), 8, C_GOOD)
	else:
		_txt("1 life", Vector2(o.x + 40, o.y + 11), 8, C_DIM)
