class_name TallyPanel
extends Control
## The floor-cleared tally, revealed in waves: each category slides in and
## counts up with its bar, perfect ones get a stamp, then the bonus, score,
## Iron Scrip and perk picks roll in. SPACE or ENTER skips to the end.

signal sound(sfx_name: String)

const ROW_Y := 44.0
const ROW_H := 17.0
const NAME_X := 92.0
const BAR_X := 168.0
const BAR_W := 112.0
const PCT_X := 288.0
const CNT_X := 326.0
const STAMP_X := 404.0
const SUM_Y := 146.0
const SUM_H := 16.0

const ROW_START := 0.35
const ROW_GAP := 0.6
const COUNT := 0.45

const C_TEXT := Color(0.85, 0.88, 0.95)
const C_DIM := Color(0.55, 0.58, 0.65)
const C_HOT := Color(1, 0.55, 0.15)
const C_GOLD := Color(1.0, 0.8, 0.25)
const C_GOOD := Color(0.4, 1.0, 0.5)
const C_BAD := Color(1.0, 0.35, 0.3)

var d: Dictionary = {}
var _t := 0.0
var _end := 1.0
var _fired: Dictionary = {}
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	size = Vector2(Hud.W, Hud.H)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## data: rows ([name, have, total, pct, note]), time, par, bonus,
## score_before, score, run (bool), scrip, perks.
func show_tally(data: Dictionary) -> void:
	d = data
	_t = 0.0
	_fired.clear()
	_end = _sum_start() + (4 if d.run else 2) * 0.5 + 0.3
	visible = true
	queue_redraw()


func done() -> bool:
	return _t >= _end


func skip() -> void:
	_t = _end
	for k in ["row0", "row1", "row2", "row3", "row4", "sum0", "sum1", "sum2", "sum3"]:
		_fired[k] = true
	sound.emit("exit")
	queue_redraw()


func _sum_start() -> float:
	return ROW_START + ROW_GAP * 5 + 0.2


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	queue_redraw()


## 0 -> 1 as _t goes from a to b, eased out.
func _k(a: float, b: float) -> float:
	var x := clampf((_t - a) / (b - a), 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _once(key: String, at: float, sfx: String) -> void:
	if _t >= at and not _fired.has(key):
		_fired[key] = true
		if sfx != "":
			sound.emit(sfx)


func _text(s: String, p: Vector2, fsize: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string_outline(_font, p, s, align, w, fsize, 3, Color(0, 0, 0, c.a))
	draw_string(_font, p, s, align, w, fsize, c)


static func commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _clock(sec: int) -> String:
	return "%d:%02d" % [sec / 60, sec % 60]


func _stamp(s: String, p: Vector2, start: float, c: Color) -> void:
	if _t < start:
		return
	# Slams in large and settles.
	var k := _k(start, start + 0.25)
	var fsize := int(lerpf(16, 9, k))
	var col := c
	col.a = k
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var r := Rect2(p.x - w / 2 - 4, p.y - fsize + 1, w + 8, fsize + 3)
	draw_rect(r, Color(c.r * 0.25, c.g * 0.25, c.b * 0.1, 0.9 * k))
	draw_rect(r, col, false, 1.0)
	_text(s, Vector2(p.x - w / 2, p.y), fsize, col)


func _draw() -> void:
	if d.is_empty():
		return
	var rows: Array = d.rows
	# Category rows: kills, secrets, treasure, hostages.
	for i in rows.size():
		var row: Array = rows[i]
		var s := ROW_START + ROW_GAP * i
		if _t < s:
			continue
		var y := ROW_Y + i * ROW_H
		var a := _k(s, s + 0.2)
		var dx := (1.0 - a) * -20.0
		var kc := _k(s, s + COUNT)
		var pct := roundi(lerpf(0, row[3], kc))
		var perfect: bool = row[3] >= 100
		_text(row[0], Vector2(NAME_X + dx, y + 10), 10, Color(C_TEXT, a))
		draw_rect(Rect2(BAR_X + dx, y + 3, BAR_W, 8), Color(0.05, 0.05, 0.08, a))
		var fill := C_GOLD if perfect and kc >= 1.0 else C_HOT
		draw_rect(Rect2(BAR_X + dx + 1, y + 4, (BAR_W - 2) * pct / 100.0, 6), Color(fill, a))
		draw_rect(Rect2(BAR_X + dx, y + 3, BAR_W, 8), Color(0.3, 0.35, 0.45, a), false, 1.0)
		_text("%d%%" % pct, Vector2(PCT_X + dx, y + 10), 10, Color(C_GOLD if perfect and kc >= 1.0 else C_TEXT, a))
		var cnt := "%d / %d" % [roundi(lerpf(0, row[1], kc)), row[2]]
		if row[4] != "":
			cnt += "  " + row[4]
		_text(cnt, Vector2(CNT_X + dx, y + 10), 8, Color(C_DIM, a))
		if perfect:
			_once("row%d" % i, s + COUNT, "secret")
			_stamp("PERFECT", Vector2(STAMP_X, y + 11), s + COUNT, C_GOLD)
		else:
			_once("row%d" % i, s + COUNT, "push")
	# Time against par: the bar fills as the clock runs, green while under par.
	var ts := ROW_START + ROW_GAP * 4
	if _t >= ts:
		var y := ROW_Y + 4 * ROW_H + 4
		var a := _k(ts, ts + 0.2)
		var dx := (1.0 - a) * -20.0
		var t: int = d.time
		var par: int = d.par
		var span := maxf(maxf(t, par) * 1.15, 1.0)
		var shown := roundi(lerpf(0, t, _k(ts, ts + COUNT)))
		_text("Time", Vector2(NAME_X + dx, y + 10), 10, Color(C_TEXT, a))
		draw_rect(Rect2(BAR_X + dx, y + 3, BAR_W, 8), Color(0.05, 0.05, 0.08, a))
		var under := minf(shown, par)
		draw_rect(Rect2(BAR_X + dx + 1, y + 4, (BAR_W - 2) * under / span, 6), Color(C_GOOD, a))
		if shown > par:
			draw_rect(Rect2(BAR_X + dx + 1 + (BAR_W - 2) * par / span, y + 4, (BAR_W - 2) * (shown - par) / span, 6), Color(C_BAD, a))
		var px := BAR_X + dx + 1 + (BAR_W - 2) * par / span
		draw_line(Vector2(px, y + 1), Vector2(px, y + 13), Color(C_GOLD, a), 1.0)
		draw_rect(Rect2(BAR_X + dx, y + 3, BAR_W, 8), Color(0.3, 0.35, 0.45, a), false, 1.0)
		_text(_clock(shown), Vector2(PCT_X + dx, y + 10), 10, Color(C_GOOD if shown <= par else C_BAD, a))
		_text("par " + _clock(par), Vector2(CNT_X + dx, y + 10), 8, Color(C_GOLD, a))
		if t < par:
			_once("row4", ts + COUNT, "secret")
			_stamp("UNDER PAR", Vector2(STAMP_X, y + 11), ts + COUNT, C_GOOD)
		else:
			_once("row4", ts + COUNT, "push")
	# How the bonus works, so the numbers below make sense.
	var hs := _sum_start() - 0.1
	if _t >= hs:
		var hint := "Every 100% category: +10,000.   Beating par: +50 per second saved."
		if d.run:
			hint += "   Each also earns a perk pick."
		_text(hint, Vector2(0, ROW_Y + 5 * ROW_H + 15), 7, Color(C_DIM, _k(hs, hs + 0.3)), HORIZONTAL_ALIGNMENT_CENTER, Hud.W)
	# Totals, one after another.
	var s0 := _sum_start()
	var lines := [["Bonus", "bonus"], ["Score", "score"]]
	if d.run:
		lines.append(["Iron Scrip this floor", "scrip"])
		lines.append(["Perk picks", "perks"])
	for j in lines.size():
		var s := s0 + j * 0.5
		if _t < s:
			continue
		var y := SUM_Y + j * SUM_H
		var a := _k(s, s + 0.2)
		var kc := _k(s, s + 0.45)
		var key: String = lines[j][1]
		var val := ""
		var col := C_TEXT
		match key:
			"bonus":
				val = "+" + commas(roundi(lerpf(0, d.bonus, kc)))
				col = C_GOLD if d.bonus > 0 else C_DIM
			"score":
				val = commas(roundi(lerpf(d.score_before, d.score, kc)))
				col = Color.WHITE
			"scrip":
				val = commas(roundi(lerpf(0, d.scrip, kc)))
				col = C_GOLD
			"perks":
				val = str(d.perks) + ("   - you choose them next" if d.perks > 0 else "")
				col = C_HOT if d.perks > 0 else C_DIM
		_once("sum%d" % j, s, "pickup" if key != "perks" or d.perks > 0 else "")
		_text(lines[j][0], Vector2(0, y + 10), 10, Color(C_DIM, a), HORIZONTAL_ALIGNMENT_RIGHT, Hud.W / 2.0 - 8)
		_text(val, Vector2(Hud.W / 2.0 + 8, y + 10), 11 if key == "score" else 10, Color(col, a))
	# Prompt.
	var blink := 0.6 + 0.4 * sin(_t * 5.0)
	if done():
		_text("ENTER or SPACE - continue", Vector2(0, 222), 10, Color(C_TEXT, blink), HORIZONTAL_ALIGNMENT_CENTER, Hud.W)
	else:
		_text("SPACE - skip", Vector2(0, 222), 8, Color(C_DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, Hud.W)
