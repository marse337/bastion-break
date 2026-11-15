class_name Minimap
extends Control
## Top-right automap. Rooms you have entered are drawn bright. Once the
## floor's PRISON MAP is picked up, every room appears and the ones you
## haven't entered yet are drawn in blue. Secret rooms stay hidden until
## you walk into them. Tab toggles a large view.

const SMALL := Rect2(352, 4, 124, 84)
const LARGE := Rect2(60, 20, 360, 200)

const C_VISITED := Color(0.72, 0.75, 0.82)
const C_UNVISITED := Color(0.22, 0.34, 0.58)
const C_WALL := Color(0.33, 0.33, 0.38)
const C_DOOR := Color(0.95, 0.6, 0.2)
const C_EXIT := Color(0.2, 1.0, 0.35)
const C_HOSTAGE := Color(1.0, 0.45, 0.85)

var world: World = null
var expanded := false
var _colors := PackedColorArray()
var _refresh_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rect()


func toggle_size() -> void:
	expanded = not expanded
	_apply_rect()


func _apply_rect() -> void:
	var r := LARGE if expanded else SMALL
	position = r.position
	size = r.size


func tick(delta: float, w: World) -> void:
	if w != world:
		world = w
		_refresh_t = 0.0
	visible = world != null
	if world == null:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0 or world.map_dirty:
		_refresh_t = 0.25
		world.map_dirty = false
		_rebuild_colors()
	queue_redraw()


func _room_shown(r: int) -> bool:
	if r < 0:
		return false
	return world.room_visited[r] or (Game.has_map and not world.room_secret[r])


func _rebuild_colors() -> void:
	var w := world.width
	var h := world.height
	_colors.resize(w * h)
	var shown := PackedByteArray()
	shown.resize(w * h)
	for i in w * h:
		var r := world.room_of[i]
		if _room_shown(r):
			shown[i] = 1
			_colors[i] = C_VISITED if world.room_visited[r] else C_UNVISITED
		else:
			_colors[i] = Color(0, 0, 0, 0)
	for y in h:
		for x in w:
			var i := y * w + x
			if shown[i] == 1:
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and shown[ny * w + nx] == 1:
						near = true
			if not near:
				continue
			var t := Vector2i(x, y)
			if world.doors.has(t):
				var d: Door = world.doors[t]
				_colors[i] = C_DOOR if d.key == "" else {"red": Color(0.95, 0.2, 0.15), "blue": Color(0.3, 0.5, 1.0), "gold": Color(1.0, 0.8, 0.15), "vault": Color(0.75, 0.3, 1.0)}[d.key]
			elif world.walls[i] == World.EXIT_TEX:
				_colors[i] = C_EXIT
			elif world.walls[i] >= 0 or world.room_of[i] == -1:
				_colors[i] = C_WALL


func _draw() -> void:
	if world == null or _colors.size() != world.width * world.height:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.72))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.46, 0.6), false, 1.0)
	var ts := minf((size.x - 8.0) / world.width, (size.y - 8.0) / world.height)
	var origin := (size - Vector2(world.width, world.height) * ts) / 2.0
	for y in world.height:
		for x in world.width:
			var c := _colors[y * world.width + x]
			if c.a > 0.0:
				draw_rect(Rect2(origin + Vector2(x, y) * ts, Vector2(ts, ts)), c)
	for hg in world.hostages:
		if hg.is_bound() and _room_shown(world.room_of[hg.tile.y * world.width + hg.tile.x]):
			draw_rect(Rect2(origin + Vector2(hg.tile) * ts, Vector2(ts, ts)).grow(0.5), C_HOSTAGE)
	# The Bounty Warden is marked with a skull from the start.
	if world.crimson != null and world.crimson.is_alive():
		var c: Vector2 = origin + world.crimson.pos * ts
		var r := maxf(ts * 1.3, 3.0)
		draw_circle(c, r, Color(0.95, 0.9, 0.85))
		draw_rect(Rect2(c + Vector2(-r * 0.55, r * 0.5), Vector2(r * 1.1, r * 0.6)), Color(0.95, 0.9, 0.85))
		draw_circle(c + Vector2(-r * 0.4, -0.1 * r), r * 0.28, Color(0.7, 0.05, 0.05))
		draw_circle(c + Vector2(r * 0.4, -0.1 * r), r * 0.28, Color(0.7, 0.05, 0.05))
	# Purge Protocol: rocket pods (green, red once spent), mines, and the
	# Hunter Warden as a pulsing red diamond - always shown, map or not.
	for t in world.pods:
		var pc: Vector2 = origin + (Vector2(t) + Vector2(0.5, 0.5)) * ts
		draw_rect(Rect2(pc - Vector2.ONE * maxf(ts, 2.5) * 0.7, Vector2.ONE * maxf(ts, 2.5) * 1.4), Color(0.6, 0.15, 0.1) if world.pods[t].used else Color(0.3, 1.0, 0.4))
	for m in world.mines:
		draw_circle(origin + (Vector2(m.tile) + Vector2(0.5, 0.5)) * ts, maxf(ts * 0.5, 1.5), Color(0.4, 0.85, 1.0))
	if world.hunter != null and world.hunter.is_alive():
		var hc: Vector2 = origin + world.hunter.pos * ts
		var hr := maxf(ts * 1.4, 3.5) * (1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.012))
		var hcol := Color(0.4, 0.8, 1.0) if world.hunter.is_stunned() else Color(1.0, 0.1, 0.05)
		draw_colored_polygon(PackedVector2Array([hc + Vector2(0, -hr), hc + Vector2(hr, 0), hc + Vector2(0, hr), hc + Vector2(-hr, 0)]), hcol)
		draw_circle(hc, hr * 0.35, Color(0.1, 0.0, 0.0))
	var p: Vector2 = origin + world.player.pos * ts
	var f: Vector2 = world.player.forward()
	var side := Vector2(-f.y, f.x)
	var s := maxf(ts * 1.1, 2.5)
	draw_colored_polygon(PackedVector2Array([p + f * s * 1.4, p - f * s * 0.8 + side * s * 0.9, p - f * s * 0.8 - side * s * 0.9]), Color(1, 0.9, 0.2))
	if not Game.has_map:
		draw_string(get_theme_default_font(), Vector2(4, size.y - 3), "no map", HORIZONTAL_ALIGNMENT_LEFT, -1, 6, Color(0.6, 0.6, 0.7))
