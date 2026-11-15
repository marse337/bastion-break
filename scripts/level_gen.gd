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
##   * big rooms get pillars to break line of sight;
##   * hostages are tied up in rooms away from the start;
##   * optional room features: a calibration range (Z console), a security
##     terminal (Y) with three breakers (1 2 3) guarding a contraband vault
##     (V door), a hostage standoff, a Hound lock-in with cages (&), the
##     Confiscation Locker (L) and the Bounty Warden's room (C).
## Output uses the same text format as levels.gd, so the validator and world
## builder work on it unchanged.

const THEMES := {
	"cells": {
		"name": "Holding Cells", "size": Vector2i(38, 28), "min_room": 3, "max_room": 7,
		"wall": "#", "accent": "F", "accent_rate": 0.04, "key": "red", "loops": 0.2,
		"enemies": [["s", 0.75], ["h", 0.15], ["w", 0.1]], "density": 0.04, "max_per_room": 2,
		"secret_loot": ["x", "g"], "par": 150, "min_wardens": 0, "hostages": 2,
	},
	"foundry": {
		"name": "The Foundry", "size": Vector2i(44, 32), "min_room": 5, "max_room": 11,
		"wall": "B", "accent": "W", "accent_rate": 0.3, "key": "blue", "loops": 0.55,
		"enemies": [["s", 0.5], ["h", 0.25], ["w", 0.25]], "density": 0.04, "max_per_room": 4,
		"secret_loot": ["c", "x"], "par": 180, "min_wardens": 2, "hostages": 3, "lockin": true,
	},
	# Iron Gauntlet: small, keycard-free floors.
	"gauntlet_cells": {
		"name": "Sector", "size": Vector2i(24, 24), "min_room": 3, "max_room": 7,
		"wall": "#", "accent": "F", "accent_rate": 0.04, "key": "", "loops": 0.3,
		"enemies": [["s", 0.7], ["h", 0.2], ["w", 0.1]], "density": 0.05, "max_per_room": 3,
		"secret_loot": ["x", "a"], "par": 90, "min_wardens": 0, "hostages": 2,
	},
	"gauntlet_foundry": {
		"name": "Sector", "size": Vector2i(24, 24), "min_room": 4, "max_room": 8,
		"wall": "B", "accent": "W", "accent_rate": 0.3, "key": "", "loops": 0.5,
		"enemies": [["s", 0.5], ["h", 0.25], ["w", 0.25]], "density": 0.05, "max_per_room": 3,
		"secret_loot": ["c", "a"], "par": 100, "min_wardens": 1, "hostages": 2, "lockin": true,
	},
	"gauntlet_boss": {
		"name": "Sector", "size": Vector2i(26, 26), "min_room": 4, "max_room": 9,
		"wall": "B", "accent": "W", "accent_rate": 0.3, "key": "", "loops": 0.5,
		"enemies": [["s", 0.6], ["h", 0.2], ["w", 0.2]], "density": 0.03, "max_per_room": 2,
		"secret_loot": ["c", "x"], "par": 120, "min_wardens": 0, "hostages": 2, "boss": "K",
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
var opts := {}
## Rooms owned by a feature: no random enemies, props or loot go there.
var reserved := {}
var no_decor := {}
var features := {}


## Generates a floor for `theme`. Retries with new seeds until the result
## passes Levels.validate().
## opts: "index" (floor number, scales Gauntlet density), "bounty" (place the
## Bounty Warden), "locker" (place the Confiscation Locker).
static func generate(theme: String, seed_value: int, opts := {}) -> Dictionary:
	for attempt in 60:
		var gen := LevelGen.new()
		gen.opts = opts
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
	if key_name != "":
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
	var taken := [start, exit_room, secret_room, key_room]
	# --- optional room features (each one is skipped if nothing fits)
	var lockin_room := -1
	if th.get("lockin", false) and rng.randf() < 0.7:
		lockin_room = _plan_lockin(taken)
	var map_cands := []
	for i in leaves.size():
		if not (i in taken) and dist[i] >= 1 and dist[i] <= 3:
			map_cands.append(i)
	if lockin_room >= 0:
		map_room = lockin_room
	elif not map_cands.is_empty():
		map_room = map_cands[rng.randi_range(0, map_cands.size() - 1)]
	taken.append(map_room)
	if key_name != "" and not _put(leaves[key_room], KEY_CHARS[key_name][1]):
		return {}
	if map_room >= 0 and map_room != lockin_room:
		_put(leaves[map_room], "M")
	if th.has("boss"):
		var big := -1
		for i in leaves.size():
			if not (i in [start, exit_room, secret_room]) and dist[i] >= 2:
				if big < 0 or leaves[i].get_area() > leaves[big].get_area():
					big = i
		if big < 0:
			return {}
		var bc := leaves[big].get_center()
		g[bc.y][bc.x] = th.boss
		blocked[bc] = true
		reserved[big] = true
		taken.append(big)
	if rng.randf() < 0.85:
		var rr := _plan_range(taken)
		if rr >= 0:
			taken.append(rr)
	if rng.randf() < 0.7:
		var vr := _plan_vault(taken)
		if vr >= 0:
			taken.append(vr)
	if rng.randf() < 0.75:
		var sr := _plan_standoff(taken, dist)
		if sr >= 0:
			taken.append(sr)
	if opts.get("bounty", false):
		var br := _plan_bounty(taken, dist)
		if br >= 0:
			taken.append(br)
	if opts.get("locker", false):
		_plan_locker(leaves[start])

	# --- props first (pillars for cover), then enemies and loot
	for i in leaves.size():
		if i != secret_room and i != start and not no_decor.has(i):
			_decorate(leaves[i], i)
	var wardens := 0
	var sentries: Array[Vector2i] = []
	var density := float(th.density) * ((1.0 + 0.08 * int(opts.get("index", 0))) if th.key == "" else 1.0)
	for i in leaves.size():
		if i == start or i == secret_room or reserved.has(i):
			continue
		var r := leaves[i]
		var n := roundi(r.get_area() * density)
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
		if i == secret_room or i == start or (reserved.has(i) and features.get("range_room", -1) == i):
			continue
		var r := leaves[i]
		var dead_end: bool = adj[i].size() == 1
		if rng.randf() < 0.45: _put(r, "a")
		if rng.randf() < 0.15: _put(r, "m")
		if rng.randf() < 0.2: _put(r, "f")
		if rng.randf() < (0.5 if dead_end else 0.22): _put(r, "t")
		if rng.randf() < 0.07: _put(r, "T")
		if i == exit_room: _put(r, "m")
		if i == exit_room and th.key == "":
			# Gauntlet: guaranteed ammo by the elevator so a boss floor never starts dry.
			_put(r, "a")
			_put(r, "a")
	# --- hostages: held in guarded rooms away from the start (never the
	# exit or the stash). They block their tile, so keep them off doorways.
	var hostage_rooms := []
	for i in leaves.size():
		if not (i in [start, exit_room, secret_room]) and dist[i] >= 1 and not reserved.has(i):
			hostage_rooms.append(i)
	for _k in int(th.hostages):
		if hostage_rooms.is_empty():
			break
		var hi: int = hostage_rooms.pop_at(rng.randi_range(0, hostage_rooms.size() - 1))
		var ht := _free_tile(leaves[hi])
		if ht.x >= 0:
			g[ht.y][ht.x] = "H"
			blocked[ht] = true
	if secret_room >= 0:
		for c in th.secret_loot + ["t", "t", "T"]:
			_put(leaves[secret_room], c)
		if rng.randf() < 0.5:
			_put(leaves[secret_room], "v")

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
	var out := {"name": th.name, "angle": angle, "par": th.par, "map": Array(rows), "facings": facings, "seed": seed_value}
	out.merge(features)
	return out


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
		if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and "DRUGPEV".contains(g[q.y][q.x]):
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


# ------------------------------------------------------------------ features

## Wall tiles that face into room `r` (orthogonally next to its floor),
## still plain wall and not next to a door or the exit switch.
func _room_walls(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var gr := r.grow(1)
	for y in range(gr.position.y, gr.end.y):
		for x in range(gr.position.x, gr.end.x):
			var p := Vector2i(x, y)
			if r.has_point(p) or g[y][x] != "#":
				continue
			var faces := false
			for d in DIRS:
				if r.has_point(p + d):
					faces = true
			if faces and not _near_door(p) and not _near_char(p, "EYZL123"):
				out.append(p)
	return out


func _near_char(p: Vector2i, chars: String) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var q := p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h and chars.contains(g[q.y][q.x]):
				return true
	return false


func _free_rooms(taken: Array) -> Array:
	var out := []
	for i in leaves.size():
		if not (i in taken):
			out.append(i)
	return out


## Calibration range: a console (Z) at one end of a long room; targets slide
## across the room at three distances while Rook stands at the window.
func _plan_range(taken: Array) -> int:
	var cands := []
	for i in _free_rooms(taken):
		var r := leaves[i]
		if (r.size.x >= 7 and r.size.y >= 3) or (r.size.y >= 7 and r.size.x >= 3):
			cands.append(i)
	cands.shuffle()
	for i in cands:
		var r := leaves[i]
		var along_x := r.size.x >= r.size.y
		var depth := r.size.x if along_x else r.size.y
		var mid := r.position.y + r.size.y / 2 if along_x else r.position.x + r.size.x / 2
		for flip in [false, true]:
			var console: Vector2i
			var spot: Vector2i
			var dir: Vector2i
			if along_x:
				console = Vector2i(r.end.x if flip else r.position.x - 1, mid)
				dir = Vector2i(-1, 0) if flip else Vector2i(1, 0)
			else:
				console = Vector2i(mid, r.end.y if flip else r.position.y - 1)
				dir = Vector2i(0, -1) if flip else Vector2i(0, 1)
			spot = console + dir
			if g[console.y][console.x] != "#" or _near_door(console) or _near_char(console, "E"):
				continue
			var far := depth - 1
			var lanes := [2, 6, 10] if far >= 10 else ([2, (2 + far) / 2, far] if far >= 6 else [2, far])
			g[console.y][console.x] = "Z"
			for k in depth:
				blocked[spot + dir * k] = true
			reserved[i] = true
			no_decor[i] = true
			features["range"] = {"console": console, "spot": spot, "dir": dir, "rect": r, "lanes": lanes}
			features["range_room"] = i
			return i
	return -1


## Security terminal: a dead-end vault (V door) whose neighbour room holds a
## terminal (Y) and three coloured breakers (1 red, 2 blue, 3 gold).
func _plan_vault(taken: Array) -> int:
	var cands := []
	for i in _free_rooms(taken):
		if adj[i].size() == 1 and leaves[i].get_area() >= 4 and not (adj[i][0][0] in taken.slice(1, 3)):
			cands.append(i)
	cands.shuffle()
	for i in cands:
		var other: int = adj[i][0][0]
		var walls := _room_walls(leaves[other])
		walls.shuffle()
		var picks: Array[Vector2i] = []
		for p in walls:
			var ok := true
			for q in picks:
				if (p - q).length_squared() < 4:
					ok = false
			if ok:
				picks.append(p)
			if picks.size() == 4:
				break
		if picks.size() < 4:
			continue
		var dp: Vector2i = doors[adj[i][0][1]][0]
		g[dp.y][dp.x] = "V"
		var chars := ["Y", "1", "2", "3"]
		for k in 4:
			g[picks[k].y][picks[k].x] = chars[k]
		var order := ["red", "blue", "gold"]
		for k in range(2, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp = order[k]
			order[k] = order[j]
			order[j] = tmp
		features["puzzle"] = order
		reserved[i] = true
		for c in ["$", "v", "t"]:
			_put(leaves[i], c)
		return i
	return -1


## Hostage standoff: a guard at the far end of a room faces the doorway with
## two hostages tied up in the line of fire and a prize behind it. A second
## door gives a way to sneak round.
func _plan_standoff(taken: Array, dist: PackedInt32Array) -> int:
	var cands := []
	for i in _free_rooms(taken):
		if adj[i].size() >= 2 and dist[i] >= 1:
			cands.append(i)
	cands.shuffle()
	for i in cands:
		var r := leaves[i]
		var p: Vector2i = doors[adj[i][0][1]][0]
		var d := Vector2i.ZERO
		for dd in DIRS:
			if r.has_point(p + dd):
				d = dd
		var depth := r.size.x if d.x != 0 else r.size.y
		var lateral := r.size.y if d.x != 0 else r.size.x
		if depth < 5 or lateral < 3:
			continue
		var perp := Vector2i(d.y, d.x)
		var guard := p + d * depth
		var h1 := p + d * 2
		var h2 := p + d * 3 + perp
		if not r.has_point(h2):
			h2 = p + d * 3 - perp
		var loot := guard + perp
		if not r.has_point(loot):
			loot = guard - perp
		var tiles := [guard, h1, h2, loot]
		var ok := true
		for t in tiles:
			if not r.has_point(t) or g[t.y][t.x] != "." or blocked.has(t) or _near_door(t):
				ok = false
		if not ok:
			continue
		g[guard.y][guard.x] = "w" if th.wall == "B" else "s"
		facings[guard] = -d
		g[h1.y][h1.x] = "H"
		g[h2.y][h2.x] = "H"
		g[loot.y][loot.x] = "x" if rng.randf() < 0.3 else "T"
		for t in tiles:
			blocked[t] = true
		reserved[i] = true
		no_decor[i] = true
		return i
	return -1


## Hound lock-in: the prison map and two gems sit on a grate in the middle of
## a big room. Taking any of them seals the doors for 12 s and opens three
## cages (&). Two pillars give room to circle-strafe.
func _plan_lockin(taken: Array) -> int:
	var cands := []
	for i in _free_rooms(taken):
		if leaves[i].size.x >= 7 and leaves[i].size.y >= 7:
			cands.append(i)
	cands.shuffle()
	for i in cands:
		var r := leaves[i]
		var c := r.get_center()
		var cages: Array[Vector2i] = []
		for t in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			if cages.size() < 3 and g[t.y][t.x] == "." and not _near_door(t):
				cages.append(t)
		if cages.size() < 3:
			continue
		for t in cages:
			g[t.y][t.x] = "&"
			blocked[t] = true
		for t in [c + Vector2i(-2, 0), c + Vector2i(2, 0)]:
			g[t.y][t.x] = "o"
			blocked[t] = true
		g[c.y][c.x] = "M"
		g[c.y - 1][c.x] = "t"
		g[c.y + 1][c.x] = "t"
		for t in [c, c + Vector2i(0, -1), c + Vector2i(0, 1)]:
			blocked[t] = true
		if not features.has("lockins"):
			features["lockins"] = []
		features["lockins"].append({"rect": r, "cages": cages})
		reserved[i] = true
		no_decor[i] = true
		return i
	return -1


## The Bounty Warden waits in a dead-end room, facing its only door.
func _plan_bounty(taken: Array, dist: PackedInt32Array) -> int:
	var cands := []
	for i in _free_rooms(taken):
		if adj[i].size() == 1 and dist[i] >= 2 and leaves[i].size.x >= 3 and leaves[i].size.y >= 3:
			cands.append(i)
	if cands.is_empty():
		return -1
	var i: int = cands[rng.randi_range(0, cands.size() - 1)]
	var r := leaves[i]
	var p: Vector2i = doors[adj[i][0][1]][0]
	var t := r.get_center()
	if g[t.y][t.x] != ".":
		return -1
	g[t.y][t.x] = "C"
	blocked[t] = true
	var to_door := Vector2(p - t)
	facings[t] = Vector2i(signi(roundi(to_door.x)), 0) if absf(to_door.x) > absf(to_door.y) else Vector2i(0, signi(roundi(to_door.y)))
	reserved[i] = true
	return i


## The Confiscation Locker hangs on a wall of the start room.
func _plan_locker(r: Rect2i) -> void:
	var walls := _room_walls(r)
	if walls.is_empty():
		return
	var p := walls[rng.randi_range(0, walls.size() - 1)]
	g[p.y][p.x] = "L"


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
