class_name LevelGen
extends RefCounted
## Procedural floor generator for roguelite runs.
##
## The map is split recursively (binary space partitioning) by 1-tile walls
## into rectangular rooms, and every split gets a door, so rooms only ever
## connect through doors: closed doors block gunfire noise and Hounds.
## On top of that layout:
##   * the exit is a dead-end room on the map edge whose only door takes the
##     floor's keycard; the keycard sits in the deepest other room;
##   * another dead-end room becomes a secret stash sealed by a sliding wall,
##     only where the 2-tile slide leaves space to step around the block;
##   * rooms next to the start get sentries facing away from their door, so
##     the opening kills can be silent shiv backstabs;
##   * big rooms get pillars to break line of sight.
## Output uses the same text format as levels.gd, so the validator and world
## builder work on it unchanged.

const THEMES := {
	"cells": {
		"name": "Holding Cells", "size": Vector2i(38, 28), "min_room": 3, "max_room": 7,
		"wall": "#", "accent": "F", "accent_rate": 0.04, "key": "red", "loops": 0.2,
		"enemies": [["s", 0.75], ["h", 0.15], ["w", 0.1]], "density": 0.04, "max_per_room": 2,
		"secret_loot": ["x", "g"], "par": 150, "min_wardens": 0,
	},
	"foundry": {
		"name": "The Foundry", "size": Vector2i(44, 32), "min_room": 5, "max_room": 11,
		"wall": "B", "accent": "W", "accent_rate": 0.3, "key": "blue", "loops": 0.55,
		"enemies": [["s", 0.5], ["h", 0.25], ["w", 0.25]], "density": 0.04, "max_per_room": 4,
		"secret_loot": ["c", "x"], "par": 180, "min_wardens": 2,
	},
}
const KEY_CHARS := {"red": ["R", "r"], "blue": ["U", "u"], "gold": ["G", "k"]}
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var th: Dictionary
var rng := RandomNumberGenerator.new()
var w := 0
var h := 0
var g: Array = []
var leaves: Array[Rect2i] = []
var splits: Array = []
var room_of := PackedInt32Array()
var doors: Array = []      # [pos, room_a, room_b, active]
var adj: Array = []        # room -> [[neighbor, door index], ...]
var blocked := {}
var facings := {}


## Generates a floor for `theme`. Retries with new seeds until the result
## passes Levels.validate().
static func generate(theme: String, seed_value: int) -> Dictionary:
	for attempt in 60:
		var gen := LevelGen.new()
		var lvl := gen._build(theme, seed_value + attempt * 7919, attempt < 45)
		if not lvl.is_empty() and Levels.validate(lvl).is_empty():
			return lvl
	push_error("LevelGen: could not generate '%s', using a hand-made floor" % theme)
	return Levels.LEVELS[0]


func _build(theme: String, seed_value: int, need_secret: bool) -> Dictionary:
	th = THEMES[theme]
	rng.seed = seed_value
	w = th.size.x
	h = th.size.y
	for y in h:
		var row := []
		row.resize(w)
		row.fill("#")
		g.append(row)
	_split(Rect2i(1, 1, w - 2, h - 2))
	room_of.resize(w * h)
	room_of.fill(-1)
	for i in leaves.size():
		var r := leaves[i]
		adj.append([])
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				g[y][x] = "."
				room_of[y * w + x] = i
	for sp in splits:
		if not _place_split_doors(sp):
			return {}

	# --- start room: the one closest to a random corner
	var corner := Vector2(1 if rng.randf() < 0.5 else w - 2, 1 if rng.randf() < 0.5 else h - 2)
	var start := 0
	for i in leaves.size():
		if Vector2(leaves[i].get_center()).distance_to(corner) < Vector2(leaves[start].get_center()).distance_to(corner):
			start = i
	var dist := _room_distances(start)

	# --- exit: deepest dead-end room touching the map edge, behind a keycard door
	var exit_room := -1
	for i in leaves.size():
		if i != start and adj[i].size() == 1 and _touches_border(leaves[i]) and dist[i] >= 2:
			if exit_room < 0 or dist[i] > dist[exit_room]:
				exit_room = i
	if exit_room < 0:
		return {}
	var key_name: String = th.key
	var exit_door: Vector2i = doors[adj[exit_room][0][1]][0]
	g[exit_door.y][exit_door.x] = KEY_CHARS[key_name][0]
	var sw := _exit_switch_tile(leaves[exit_room])
	g[sw.y][sw.x] = "E"

	# --- secret stash behind a sliding wall
	var secret_room := -1
	var secret_cands := []
	for i in leaves.size():
		if i == start or i == exit_room or adj[i].size() != 1:
			continue
		var plan := _secret_plan(i)
		if not plan.is_empty():
			secret_cands.append(plan)
	if not secret_cands.is_empty():
		var plan: Dictionary = secret_cands[rng.randi_range(0, secret_cands.size() - 1)]
		secret_room = plan.room
		var p: Vector2i = plan.door
		g[p.y][p.x] = "P"
		doors[plan.door_index][3] = false
		var other: int = adj[secret_room][0][0]
		adj[secret_room].clear()
		for k in range(adj[other].size() - 1, -1, -1):
			if adj[other][k][0] == secret_room:
				adj[other].remove_at(k)
		blocked[p + plan.dir] = true
		blocked[p + plan.dir * 2] = true
	elif need_secret:
		return {}
	dist = _room_distances(start)

	# --- player start, facing the way out of the first room
	var sc := leaves[start].get_center()
	g[sc.y][sc.x] = "@"
	blocked[sc] = true
	var first_door: Vector2i = doors[adj[start][0][1]][0]
	var angle := rad_to_deg(Vector2(first_door - sc).angle())

	# --- keycard in the deepest reachable room, prison map in a nearby one
	var key_room := -1
	var map_room := -1
	for i in leaves.size():
		if i in [start, exit_room, secret_room] or dist[i] < 0:
			continue
		if key_room < 0 or dist[i] > dist[key_room]:
			key_room = i
	if key_room < 0:
		return {}
	var map_cands := []
	for i in leaves.size():
		if not (i in [start, exit_room, secret_room, key_room]) and dist[i] >= 1 and dist[i] <= 3:
			map_cands.append(i)
	if not map_cands.is_empty():
		map_room = map_cands[rng.randi_range(0, map_cands.size() - 1)]
	if not _put(leaves[key_room], KEY_CHARS[key_name][1]):
		return {}
	if map_room >= 0:
		_put(leaves[map_room], "M")

	# --- props first (pillars for cover), then enemies and loot
	for i in leaves.size():
		if i != secret_room and i != start:
			_decorate(leaves[i], i)
	var wardens := 0
	var sentries: Array[Vector2i] = []
	for i in leaves.size():
		if i == start or i == secret_room:
			continue
		var r := leaves[i]
		var n := roundi(r.get_area() * float(th.density))
		if dist[i] == 1:
			n = clampi(n, 1, 2)
		n = clampi(n, 1 if i == exit_room else 0, th.max_per_room)
		for _k in n:
			var kind := "s" if dist[i] <= 1 else _pick_enemy()
			if kind == "h" and adj[i].size() < 2:
				kind = "s"
			var t := _free_tile(r)
			if t.x < 0:
				break
			g[t.y][t.x] = kind
			if kind == "w":
				wardens += 1
			elif kind == "s" and dist[i] >= 2:
				sentries.append(t)
			if dist[i] == 1:
				facings[t] = _inward_from_start_side(i, dist)
	while wardens < int(th.min_wardens) and not sentries.is_empty():
		var t: Vector2i = sentries.pop_back()
		g[t.y][t.x] = "w"
		wardens += 1
	for i in leaves.size():
		if i == secret_room or i == start:
			continue
		var r := leaves[i]
		var dead_end: bool = adj[i].size() == 1
		if rng.randf() < 0.45: _put(r, "a")
		if rng.randf() < 0.15: _put(r, "m")
		if rng.randf() < 0.2: _put(r, "f")
		if rng.randf() < (0.5 if dead_end else 0.22): _put(r, "t")
		if rng.randf() < 0.07: _put(r, "T")
		if i == exit_room: _put(r, "m")
	if secret_room >= 0:
		for c in th.secret_loot + ["t", "t", "T"]:
			_put(leaves[secret_room], c)

	# --- wall dressing
	for y in h:
		for x in w:
			if g[y][x] != "#":
				continue
			if _next_to_floor(Vector2i(x, y)) and rng.randf() < float(th.accent_rate):
				g[y][x] = th.accent
			else:
				g[y][x] = th.wall
	var rows := PackedStringArray()
	for y in h:
		rows.append("".join(PackedStringArray(g[y])))
	return {"name": th.name, "angle": angle, "par": th.par, "map": Array(rows), "facings": facings, "seed": seed_value}


# ------------------------------------------------------------------ layout

func _split(r: Rect2i) -> void:
	var mn: int = th.min_room
	var mx: int = th.max_room
	var can_x := r.size.x >= mn * 2 + 1
	var can_y := r.size.y >= mn * 2 + 1
	var too_big := r.size.x > mx or r.size.y > mx
	if not (can_x or can_y) or (not too_big and rng.randf() < 0.35):
		leaves.append(r)
		return
	var split_x := can_x
	if can_x and can_y:
		if r.size.x > r.size.y + 2:
			split_x = true
		elif r.size.y > r.size.x + 2:
			split_x = false
		else:
			split_x = rng.randf() < 0.5
	if split_x:
		var s := rng.randi_range(r.position.x + mn, r.end.x - 1 - mn)
		splits.append([true, s, r.position.y, r.end.y - 1])
		_split(Rect2i(r.position.x, r.position.y, s - r.position.x, r.size.y))
		_split(Rect2i(s + 1, r.position.y, r.end.x - s - 1, r.size.y))
	else:
		var s := rng.randi_range(r.position.y + mn, r.end.y - 1 - mn)
		splits.append([false, s, r.position.x, r.end.x - 1])
		_split(Rect2i(r.position.x, r.position.y, r.size.x, s - r.position.y))
		_split(Rect2i(r.position.x, s + 1, r.size.x, r.end.y - s - 1))


func _room(t: Vector2i) -> int:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return -1
	return room_of[t.y * w + t.x]


func _place_split_doors(sp: Array) -> bool:
	var is_x: bool = sp[0]
	var across := Vector2i(1, 0) if is_x else Vector2i(0, 1)
	var cands: Array[Vector2i] = []
	for k in range(sp[2], sp[3] + 1):
		var p := Vector2i(sp[1], k) if is_x else Vector2i(k, sp[1])
		if _room(p - across) >= 0 and _room(p + across) >= 0:
			cands.append(p)
	if cands.is_empty():
		return false
	var first := cands[rng.randi_range(0, cands.size() - 1)]
	_add_door(first, across)
	if rng.randf() < float(th.loops):
		var pair := [_room(first - across), _room(first + across)]
		for _try in 6:
			var c := cands[rng.randi_range(0, cands.size() - 1)]
			var cp := [_room(c - across), _room(c + across)]
			if (c - first).length_squared() >= 9 and cp != pair:
				_add_door(c, across)
				break
	return true


func _add_door(p: Vector2i, across: Vector2i) -> void:
	var a := _room(p - across)
	var b := _room(p + across)
	g[p.y][p.x] = "D"
	doors.append([p, a, b, true])
	adj[a].append([b, doors.size() - 1])
	adj[b].append([a, doors.size() - 1])


func _room_distances(from: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(leaves.size())
	dist.fill(-1)
	dist[from] = 0
	var queue := [from]
	while not queue.is_empty():
		var r: int = queue.pop_front()
		for e in adj[r]:
			if dist[e[0]] < 0:
				dist[e[0]] = dist[r] + 1
				queue.append(e[0])
	return dist


func _touches_border(r: Rect2i) -> bool:
	return r.position.x == 1 or r.position.y == 1 or r.end.x == w - 1 or r.end.y == h - 1


func _exit_switch_tile(r: Rect2i) -> Vector2i:
	if r.end.x == w - 1:
		return Vector2i(w - 1, r.position.y + r.size.y / 2)
	if r.position.x == 1:
		return Vector2i(0, r.position.y + r.size.y / 2)
	if r.end.y == h - 1:
		return Vector2i(r.position.x + r.size.x / 2, h - 1)
	return Vector2i(r.position.x + r.size.x / 2, 0)


## A dead-end room can be a secret stash if its door can become a sliding
## wall: the two tiles it slides into must be inside the room, with room to
## step around the block afterwards.
func _secret_plan(i: int) -> Dictionary:
	var r := leaves[i]
	if r.size.x < 3 or r.size.y < 3:
		return {}
	var di: int = adj[i][0][1]
	var p: Vector2i = doors[di][0]
	var dir := Vector2i.ZERO
	for d in DIRS:
		if _room(p + d) == i:
			dir = d
	var perp := Vector2i(dir.y, dir.x)
	if _room(p + dir) != i or _room(p + dir * 2) != i:
		return {}
	for side in [perp, -perp]:
		if _room(p + dir + side) == i and _room(p + dir * 2 + side) == i:
			return {"room": i, "door": p, "door_index": di, "dir": dir}
	return {}


func _inward_from_start_side(i: int, dist: PackedInt32Array) -> Vector2i:
	for e in adj[i]:
		if dist[e[0]] < dist[i]:
			var p: Vector2i = doors[e[1]][0]
			for d in DIRS:
				if _room(p + d) == i:
					return d
	return DIRS[rng.randi_range(0, 3)]


# ------------------------------------------------------------------ contents

func _near_door(p: Vector2i) -> bool:
	for d in DIRS:
		var q: Vector2i = p + d
		if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and "DRUGPE".contains(g[q.y][q.x]):
			return true
	return false


func _next_to_floor(p: Vector2i) -> bool:
	for d in DIRS:
		if _room(p + d) >= 0:
			return true
	return false


func _free_tile(r: Rect2i) -> Vector2i:
	for _t in 40:
		var p := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if g[p.y][p.x] == "." and not blocked.has(p) and not _near_door(p):
			return p
	return Vector2i(-1, -1)


func _put(r: Rect2i, c: String) -> bool:
	var p := _free_tile(r)
	if p.x < 0:
		return false
	g[p.y][p.x] = c
	return true


func _pick_enemy() -> String:
	var roll := rng.randf()
	for e in th.enemies:
		roll -= float(e[1])
		if roll <= 0.0:
			return e[0]
	return "s"


func _decorate(r: Rect2i, _i: int) -> void:
	var c := r.get_center()
	if r.size.x >= 7 and r.size.y >= 7:
		var cells: Array[Vector2i] = [c]
		if r.size.x >= 9 and r.size.y >= 9:
			cells = [c, c + Vector2i(-1, 0), c + Vector2i(0, -1), c + Vector2i(-1, -1)]
		for p in cells:
			if g[p.y][p.x] == ".":
				g[p.y][p.x] = "o"
				blocked[p] = true
		var lamp := c + Vector2i(0, 2)
		if g[lamp.y][lamp.x] == ".":
			g[lamp.y][lamp.x] = "l"
	elif r.get_area() >= 12 and g[c.y][c.x] == ".":
		g[c.y][c.x] = "l"
	if rng.randf() < 0.25:
		var corner := Vector2i(r.position.x if rng.randf() < 0.5 else r.end.x - 1, r.position.y if rng.randf() < 0.5 else r.end.y - 1)
		if g[corner.y][corner.x] == "." and not _near_door(corner):
			g[corner.y][corner.x] = "b"
