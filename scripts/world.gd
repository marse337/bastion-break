class_name World
extends Node3D
## Builds a floor from a text grid (see levels.gd) and runs the simulation:
## doors, sliding secret walls, enemies, pickups, hitscan and gunfire noise.
## One tile = one world unit. Tile (x, y) covers X in [x, x+1], Z in [y, y+1].

const TEX_NAMES := ["stone", "metal", "rust", "sigil", "exit", "terminal", "breaker_red", "breaker_blue", "breaker_gold", "locker", "range", "pod"]
const WALL_CHARS := {"#": 0, "B": 1, "W": 2, "F": 3, "E": 4, "Y": 5, "1": 6, "2": 7, "3": 8, "L": 9, "Z": 10}
const EXIT_TEX := 4
const TERMINAL_TEX := 5
const BREAKER_TEX := {6: "red", 7: "blue", 8: "gold"}
const LOCKER_TEX := 9
const RANGE_TEX := 10
const POD_TEX := 11
## Purge Protocol: scrap each kind of guard leaves behind.
const SCRAP := {"sentry": 1, "hound": 1, "warden": 2, "crimson": 4, "suboverseer": 4, "overseer": 6}
const ROCKET_SPEED := 10.0
const POD_RANGE := 16.0
const RANGE_TIME := 8.0
const LOCKIN_TIME := 12.0
const ITEM_CHARS := {"a": "ammo", "m": "medkit", "f": "food", "t": "gem", "T": "idol", "x": "life", "g": "rifle", "c": "rotary", "r": "key_red", "u": "key_blue", "k": "key_gold", "M": "map", "v": "mod_crate", "$": "scrip_cache"}
const ENEMY_CHARS := {"s": "sentry", "h": "hound", "w": "warden", "O": "overseer", "C": "crimson", "K": "suboverseer"}
const DECO_CHARS := {"o": "pillar", "b": "barrel", "l": "lamp"}
const DOOR_CHARS := {"D": "", "R": "red", "U": "blue", "G": "gold", "V": "vault"}
const PUSH_CHARS := {"P": 0, "Q": 1}
const TREASURE := ["gem", "idol", "life"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const INF := 1 << 20
const HOSTAGE_SCRIP := 5
const HOSTAGE_SCORE := 1000
const KILL_SCRIP := {"sentry": 1, "hound": 1, "warden": 3, "overseer": 40, "crimson": 10, "suboverseer": 15}
const DAMAGE_SCALE := [0.5, 1.0, 1.35]


class PushWall extends RefCounted:
	var origin := Vector2i.ZERO
	var tex_id := 0
	var dir := Vector2i.ZERO
	var offset := 0.0
	var steps := 0
	var state := 0  # 0 untouched, 1 sliding, 2 finished
	var node: Node3D

	func covers(t: Vector2i) -> bool:
		var base := origin + dir * steps
		if t == base:
			return true
		return state == 1 and t == base + dir


var main
var level_name := ""
var width := 0
var height := 0
var walls := PackedInt32Array()
var blockers := PackedByteArray()
var field := PackedInt32Array()
var doors := {}
var pushwalls: Array[PushWall] = []
var enemies: Array[Enemy] = []
var hostages: Array[Hostage] = []
var items: Array[Dictionary] = []
var reservations := {}
var player: Player
var start_pos := Vector2(1.5, 1.5)
var start_angle := 0.0
var boss: Enemy = null
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var brace_debris: Array[Dictionary] = []
var exited := false
var crimson: Enemy = null
# Security terminal puzzle
var puzzle_order: Array = []
var puzzle_step := 0
var puzzle_solved := false
# Calibration range: 0 ready, 1 running, 2 spent
var range_data: Dictionary = {}
var range_state := 0
var range_t := 0.0
var range_ammo := 0
var range_targets: Array = []
var range_foul := false
var _range_saved := []
# Hound lock-ins: {rect, cages, nodes, state (0 armed, 1 sealed, 2 done), t}
var lockins: Array = []
## Purge Protocol state.
var hunter: Hunter = null
var hunter_delay := Game.PURGE_DELAY
var hunter_clock := 0.0
var hunter_done := false
var _siren_done := false
var hunt_field := PackedInt32Array()
var _hunt_timer := 0.0
var _hunt_tile := Vector2i(-99, -99)
var pods := {}
var rockets: Array[Dictionary] = []
var mines: Array[Dictionary] = []
# Daily Lockdown: rooms already scored for the clean-room multiplier
var clean_rooms := {}
var _vent_hint := false
var _wall_mats: Array[StandardMaterial3D] = []
var _field_timer := 0.0
var _field_tile := Vector2i(-99, -99)

# Rooms for the automap: room_of[i] is a room id, -2 for a door tile, -1 for solid.
var room_of := PackedInt32Array()
var room_visited: Array[bool] = []
var room_secret: Array[bool] = []
var map_dirty := true


# ================================================================ building

func build(level: Dictionary) -> void:
	level_name = level.name
	var rows: Array = level.map
	height = rows.size()
	for r in rows:
		width = maxi(width, (r as String).length())
	walls.resize(width * height)
	walls.fill(-1)
	blockers.resize(width * height)
	blockers.fill(0)
	field.resize(width * height)
	var start := Vector2(1.5, 1.5)
	var door_specs := []
	var enemy_specs := []
	var cage_specs: Array[Vector2i] = []
	for y in height:
		var row: String = rows[y]
		for x in width:
			var c: String = row[x] if x < row.length() else "#"
			var t := Vector2i(x, y)
			var p := Vector2(x + 0.5, y + 0.5)
			if WALL_CHARS.has(c):
				walls[_i(t)] = WALL_CHARS[c]
			elif PUSH_CHARS.has(c):
				var pw := PushWall.new()
				pw.origin = t
				pw.tex_id = PUSH_CHARS[c]
				pushwalls.append(pw)
			elif DOOR_CHARS.has(c):
				door_specs.append([t, DOOR_CHARS[c]])
			elif c == "@":
				start = p
			elif c == "&":
				cage_specs.append(t)
			elif c == "H":
				var hg := Hostage.new()
				add_child(hg)
				hg.setup(self, t)
				hostages.append(hg)
				blockers[_i(t)] = 1
			elif ENEMY_CHARS.has(c):
				enemy_specs.append([t, ENEMY_CHARS[c]])
			elif ITEM_CHARS.has(c):
				_spawn_item(ITEM_CHARS[c], p)
			elif DECO_CHARS.has(c):
				_make_sprite(DECO_CHARS[c], p)
				if c != "l":
					blockers[_i(t)] = 1
	if Game.is_protocol("purge"):
		var door_tiles := {}
		for spec in door_specs:
			door_tiles[spec[0]] = true
		_place_pods(Vector2i(floori(start.x), floori(start.y)), door_tiles)
	_build_walls()
	_build_floor_and_ceiling()
	for spec in door_specs:
		_make_door(spec[0], spec[1])
	for pw in pushwalls:
		_make_pushwall_node(pw)
	for spec in enemy_specs:
		var e := Enemy.new()
		add_child(e)
		e.setup(self, spec[1], spec[0])
		var facings: Dictionary = level.get("facings", {})
		if facings.has(spec[0]):
			e.facing = facings[spec[0]]
		enemies.append(e)
		if e.is_boss:
			boss = e
		if e.kind == "crimson":
			crimson = e
		reserve(e.tile, e)
	player = Player.new()
	add_child(player)
	start_pos = start
	start_angle = deg_to_rad(float(level.get("angle", 0.0)))
	player.setup(self, start_pos, start_angle)
	_make_environment()
	_compute_rooms(Vector2i(floori(start.x), floori(start.y)))
	for e in enemies:
		e.home_room = room_of[_i(e.tile)]
	puzzle_order = level.get("puzzle", [])
	range_data = level.get("range", {})
	for spec in level.get("lockins", []):
		var nodes := []
		var caged := []
		for t in spec.cages:
			nodes.append(_make_sprite("cage", Vector2(t.x + 0.5, t.y + 0.5)))
			# A Hound pacing behind the bars until the lock-in springs.
			var hs := _make_sprite("cage", Vector2(t.x + 0.5, t.y + 0.5))
			hs.texture = Tex.enemy("hound", "stand", 0, 0)
			hs.pixel_size = 1.0 / hs.texture.get_height()
			caged.append(hs)
		lockins.append({"rect": spec.rect, "cages": spec.cages, "nodes": nodes, "caged": caged, "state": 0, "t": 0.0, "open_t": 0.0})
	if crimson != null:
		Game.message.emit("A BOUNTY WARDEN guards this floor (skull on the map)")
	hunt_field.resize(width * height)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hunter-at="):
			hunter_delay = float(a.substr(12))
	Game.kills_total = enemies.size()
	Game.secrets_total = pushwalls.size()
	Game.hostages_total = hostages.size()
	Game.treasure_total = 0
	for it in items:
		if it.type in TREASURE:
			Game.treasure_total += 1
	_rebuild_field()


## Splits the floor into rooms: connected open tiles, separated by doors and
## secret walls. Rooms you can't reach from the start without pushing a
## secret wall are flagged secret (the prison map won't reveal them).
func _compute_rooms(start: Vector2i) -> void:
	room_of.resize(width * height)
	room_of.fill(-1)
	var count := 0
	for y in height:
		for x in width:
			var t := Vector2i(x, y)
			if doors.has(t):
				room_of[_i(t)] = -2
	for y in height:
		for x in width:
			var t := Vector2i(x, y)
			if room_of[_i(t)] != -1 or _is_wall(t) or pushwall_at(t) != null:
				continue
			room_of[_i(t)] = count
			var queue: Array[Vector2i] = [t]
			var qi := 0
			while qi < queue.size():
				var c := queue[qi]
				qi += 1
				for d in DIRS:
					var n: Vector2i = c + d
					if in_bounds(n) and room_of[_i(n)] == -1 and not _is_wall(n) and pushwall_at(n) == null:
						room_of[_i(n)] = count
						queue.append(n)
			count += 1
	room_visited.resize(count)
	room_visited.fill(false)
	room_secret.resize(count)
	room_secret.fill(true)
	# Rooms linked to the start room through doors are not secret.
	var links := {}
	for t in doors:
		var rs := []
		for d in DIRS:
			var r := room_of[_i(t + d)] if in_bounds(t + d) else -1
			if r >= 0 and not r in rs:
				rs.append(r)
		for a in rs:
			for b in rs:
				if a != b:
					if not links.has(a):
						links[a] = []
					links[a].append(b)
	var sr := room_of[_i(start)]
	if sr >= 0:
		var stack := [sr]
		room_secret[sr] = false
		while not stack.is_empty():
			var r: int = stack.pop_back()
			for n in links.get(r, []):
				if room_secret[n]:
					room_secret[n] = false
					stack.append(n)
	map_dirty = true


func _visit_current_room() -> void:
	var t := player_tile()
	if not in_bounds(t):
		return
	var r := room_of[_i(t)]
	if r >= 0 and not room_visited[r]:
		room_visited[r] = true
		map_dirty = true


func _i(t: Vector2i) -> int:
	return t.y * width + t.x


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func _is_wall(t: Vector2i) -> bool:
	return not in_bounds(t) or walls[_i(t)] >= 0


func _mat(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = tex
	m.texture_filter = Game.filter_3d()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Adds one 1-unit-tall wall quad. `l` and `r` are the left and right
## bottom corners (X, Z) as seen by a viewer facing the quad.
static func _add_face(st: SurfaceTool, l: Vector2, r: Vector2, shade: float) -> void:
	var col := Color(shade, shade, shade)
	var tl := Vector3(l.x, 1, l.y)
	var tr := Vector3(r.x, 1, r.y)
	var br := Vector3(r.x, 0, r.y)
	var bl := Vector3(l.x, 0, l.y)
	for v in [[tl, Vector2(0, 0)], [tr, Vector2(1, 0)], [br, Vector2(1, 1)], [tl, Vector2(0, 0)], [br, Vector2(1, 1)], [bl, Vector2(0, 1)]]:
		st.set_color(col)
		st.set_uv(v[1])
		st.add_vertex(v[0])


## Adds the face of tile-cell (x, y) [offset by `o`] that looks toward `dir`.
static func _add_cell_face(st: SurfaceTool, o: Vector2, dir: Vector2i) -> void:
	var x := o.x
	var y := o.y
	if dir.x > 0:
		_add_face(st, Vector2(x + 1, y + 1), Vector2(x + 1, y), 1.0)
	elif dir.x < 0:
		_add_face(st, Vector2(x, y), Vector2(x, y + 1), 1.0)
	elif dir.y > 0:
		_add_face(st, Vector2(x, y + 1), Vector2(x + 1, y + 1), 0.72)
	else:
		_add_face(st, Vector2(x + 1, y), Vector2(x, y), 0.72)


func _build_walls() -> void:
	var tools := []
	for i in TEX_NAMES.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
		_wall_mats.append(_mat(Tex.tex(TEX_NAMES[i])))
	var used := {}
	for y in height:
		for x in width:
			var tid := walls[y * width + x]
			if tid < 0 or tid == POD_TEX:
				continue
			for d in DIRS:
				if not _is_wall(Vector2i(x, y) + d):
					_add_cell_face(tools[tid], Vector2(x, y), d)
					used[tid] = true
	for tid in used:
		var mi := MeshInstance3D.new()
		mi.mesh = tools[tid].commit()
		mi.material_override = _wall_mats[tid]
		add_child(mi)
	# Rocket pods get a mesh and material each, so a spent pod can change look.
	for t in pods:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for d in DIRS:
			if not _is_wall(t + d):
				_add_cell_face(st, Vector2(t.x, t.y), d)
		var pm := MeshInstance3D.new()
		pm.mesh = st.commit()
		pods[t].mat = _mat(Tex.tex("pod"))
		pm.material_override = pods[t].mat
		add_child(pm)


func _build_floor_and_ceiling() -> void:
	for spec in [[0.0, "floor", 0.72], [1.0, "ceiling", 0.5]]:
		var pm := PlaneMesh.new()
		pm.size = Vector2(width, height)
		var m := _mat(Tex.tex(spec[1]))
		m.vertex_color_use_as_albedo = false
		m.albedo_color = Color(spec[2], spec[2], spec[2])
		m.uv1_scale = Vector3(width, height, 1)
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		mi.material_override = m
		mi.position = Vector3(width / 2.0, spec[0], height / 2.0)
		add_child(mi)


func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.fog_enabled = true
	env.fog_light_color = Color(0.0, 0.0, 0.0)
	env.fog_density = 0.065
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _make_door(t: Vector2i, key: String) -> void:
	var along_x := _is_wall(t + Vector2i(-1, 0)) and _is_wall(t + Vector2i(1, 0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if along_x:
		_add_face(st, Vector2(1, 0.46), Vector2(0, 0.46), 0.72)
		_add_face(st, Vector2(0, 0.54), Vector2(1, 0.54), 0.72)
	else:
		_add_face(st, Vector2(0.54, 1), Vector2(0.54, 0), 1.0)
		_add_face(st, Vector2(0.46, 0), Vector2(0.46, 1), 1.0)
	var d := Door.new()
	add_child(d)
	d.setup(t, along_x, key, st.commit(), _mat(Tex.tex("door" if key == "" else "door_" + key)))
	doors[t] = d


func _make_pushwall_node(pw: PushWall) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for d in DIRS:
		_add_cell_face(st, Vector2.ZERO, d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	# Secret walls carry faint scrape marks so sharp-eyed players can spot them.
	mi.material_override = _mat(Tex.tex(TEX_NAMES[pw.tex_id] + "_secret"))
	mi.position = Vector3(pw.origin.x, 0, pw.origin.y)
	add_child(mi)
	pw.node = mi


func _make_sprite(tex_name: String, p: Vector2) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = Tex.tex(tex_name)
	s.pixel_size = 1.0 / s.texture.get_height()
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.texture_filter = Game.filter_3d()
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.position = Vector3(p.x, 0.5, p.y)
	add_child(s)
	return s


func _spawn_item(type: String, p: Vector2, tex := "", group := "") -> void:
	var it := {"type": type, "pos": p, "node": _make_sprite(type if tex == "" else tex, p)}
	if group != "":
		it["group"] = group
	items.append(it)


# ================================================================ queries

func player_tile() -> Vector2i:
	return Vector2i(floori(player.pos.x), floori(player.pos.y))


func pushwall_at(t: Vector2i) -> PushWall:
	for pw in pushwalls:
		if pw.state != 2 and pw.covers(t):
			return pw
	return null


func blocks_sight(t: Vector2i) -> bool:
	if _is_wall(t):
		return true
	var d = doors.get(t)
	if d != null and d.blocks_sight():
		return true
	return pushwall_at(t) != null


func has_los(a: Vector2, b: Vector2) -> bool:
	var diff := b - a
	var steps := int(diff.length() / 0.1)
	for i in range(1, steps):
		var p := a + diff * (float(i) / steps)
		if blocks_sight(Vector2i(floori(p.x), floori(p.y))):
			return false
	return true


func tile_blocks_player(t: Vector2i) -> bool:
	if _is_wall(t) or blockers[_i(t)] != 0:
		return true
	var d = doors.get(t)
	if d != null and not d.passable():
		return true
	return pushwall_at(t) != null


func collides(p: Vector2, r: float) -> bool:
	for y in range(floori(p.y - r), floori(p.y + r) + 1):
		for x in range(floori(p.x - r), floori(p.x + r) + 1):
			if tile_blocks_player(Vector2i(x, y)):
				return true
	return false


func player_blocked(old: Vector2, new: Vector2, r: float) -> bool:
	if collides(new, r):
		return true
	for e in enemies:
		if e.is_alive() and not (e is Hunter and e.is_stunned()):
			var dn := e.pos.distance_to(new)
			if dn < r + float(e.stats.get("radius", 0.3)) and dn < e.pos.distance_to(old):
				return true
	return false


func _player_overlaps(t: Vector2i) -> bool:
	var r := Player.RADIUS
	return absf(player.pos.x - (t.x + 0.5)) < 0.5 + r and absf(player.pos.y - (t.y + 0.5)) < 0.5 + r


# ================================================================ enemy navigation

func reserve(t: Vector2i, e: Enemy) -> void:
	reservations[t] = e


func release(t: Vector2i, e: Enemy) -> void:
	if reservations.get(t) == e:
		reservations.erase(t)


func _walkable_for_enemies(t: Vector2i) -> bool:
	if _is_wall(t) or blockers[_i(t)] != 0 or pushwall_at(t) != null:
		return false
	var d = doors.get(t)
	return d == null or d.unlocked


## Breadth-first distance map from the player; enemies walk downhill on it.
func _rebuild_field() -> void:
	field.fill(INF)
	var src := player_tile()
	if not in_bounds(src):
		return
	field[_i(src)] = 0
	var queue: Array[Vector2i] = [src]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		var v := field[_i(c)] + 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and field[_i(n)] > v and _walkable_for_enemies(n):
				field[_i(n)] = v
				queue.append(n)
	_field_tile = src
	_field_timer = 0.5


func next_step(e: Enemy) -> Vector2i:
	var cur := e.tile
	var best := cur
	var bestv := field[_i(cur)]
	if bestv >= INF:
		return cur
	var ptile := player_tile()
	var dirs := DIRS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var n: Vector2i = cur + d
		if not in_bounds(n) or n == ptile:
			continue
		var r = reservations.get(n)
		if r != null and r != e:
			continue
		var v := field[_i(n)]
		if v < bestv:
			best = n
			bestv = v
	return best


func enemy_open_door(door: Door) -> void:
	if door.unlocked and door.open():
		play_sfx("door", Vector2(door.tile.x + 0.5, door.tile.y + 0.5))


func alert_all() -> void:
	for e in enemies:
		e.alert()


## Gunfire wakes every idle enemy reachable through open space or open doors.
func make_noise(from: Vector2i) -> void:
	var seen := {from: 0}
	var queue: Array[Vector2i] = [from]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		var dist: int = seen[c]
		if dist >= Game.noise_radius():
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or _is_wall(n) or pushwall_at(n) != null:
				continue
			var door = doors.get(n)
			if door != null and door.openness < 0.25:
				continue
			seen[n] = dist + 1
			queue.append(n)
	if hunter != null and seen.has(hunter.tile):
		hunter.enrage()
	for e in enemies:
		# The Bounty Warden ignores distant gunfire; it waits for you.
		if e.state == Enemy.IDLE and seen.has(e.tile) and e.kind != "crimson":
			e.gun_alerted = true
			e.alert()


# ================================================================ simulation

## Re-applies texture filtering after the HD / retro toggle.
func apply_filter() -> void:
	var f := Game.filter_3d()
	for n in find_children("*", "", true, false):
		if n is SpriteBase3D:
			n.texture_filter = f
		elif n is MeshInstance3D and n.material_override is StandardMaterial3D:
			n.material_override.texture_filter = f


func tick(delta: float) -> void:
	Game.level_time += delta
	player.tick(delta)
	_visit_current_room()
	_field_timer -= delta
	if _field_timer <= 0.0 or player_tile() != _field_tile:
		_rebuild_field()
	for t in doors:
		var d: Door = doors[t]
		if d.tick(delta, _door_occupied(d)):
			play_sfx("door", Vector2(t.x + 0.5, t.y + 0.5))
	for pw in pushwalls:
		if pw.state == 1:
			_tick_pushwall(pw, delta)
	for e in enemies:
		e.tick(delta)
	for hg in hostages:
		hg.tick(delta)
	if range_state == 1:
		_tick_range(delta)
	_tick_lockins(delta)
	if Game.is_protocol("purge"):
		_tick_purge(delta)
	_tick_rockets(delta)
	_tick_mines()
	_tick_projectiles(delta)
	_tick_effects(delta)
	_tick_brace_debris(delta)
	if not player.dead:
		_check_pickups()


func _door_occupied(d: Door) -> bool:
	if _player_overlaps(d.tile):
		return true
	for e in enemies:
		if e is Hunter:
			if e.is_alive() and e.tile == d.tile:
				return true
		elif e.is_alive():
			if e.tile == d.tile or e.target == d.tile:
				return true
		elif Vector2i(floori(e.pos.x), floori(e.pos.y)) == d.tile:
			return true
	for it in items:
		if Vector2i(floori(it.pos.x), floori(it.pos.y)) == d.tile:
			return true
	return false


func _can_push_into(t: Vector2i) -> bool:
	if _is_wall(t) or blockers[_i(t)] != 0 or doors.has(t) or reservations.has(t):
		return false
	if _player_overlaps(t):
		return false
	for pw in pushwalls:
		if pw.covers(t):
			return false
	return true


func _tick_pushwall(pw: PushWall, delta: float) -> void:
	pw.offset += delta * 1.1
	if pw.offset >= pw.steps + 1:
		pw.steps += 1
		pw.offset = float(pw.steps)
		if pw.steps >= 2 or not _can_push_into(pw.origin + pw.dir * (pw.steps + 1)):
			pw.state = 2
			var final := pw.origin + pw.dir * pw.steps
			walls[_i(final)] = pw.tex_id
			# The tiles the wall slid through become part of the room behind it.
			var behind := room_of[_i(pw.origin + pw.dir)]
			for k in pw.steps:
				var t := pw.origin + pw.dir * k
				if room_of[_i(t)] == -1:
					room_of[_i(t)] = behind
			room_of[_i(final)] = -1
			map_dirty = true
			_field_timer = 0.0
	pw.node.position = Vector3(pw.origin.x + pw.dir.x * pw.offset, 0, pw.origin.y + pw.dir.y * pw.offset)


# ================================================================ player actions

func player_use() -> void:
	var f := player.forward()
	var dir := Vector2i(int(signf(f.x)), 0) if absf(f.x) > absf(f.y) else Vector2i(0, int(signf(f.y)))
	var t := player_tile() + dir
	var door = doors.get(t)
	if door != null:
		if not door.unlocked:
			if door.key == "vault":
				play_sfx("denied")
				Game.message.emit("Sealed vault - override the security terminal to open it")
				return
			if door.key == "":
				play_sfx("denied")
				Game.message.emit("The doors are sealed!")
				return
			if Game.keys.get(door.key, false):
				door.unlocked = true
				Game.message.emit("Used the %s keycard" % door.key)
				_field_timer = 0.0
			else:
				play_sfx("denied")
				Game.message.emit("Locked - you need the %s keycard" % door.key)
				return
		if door.state == Door.OPEN or door.state == Door.OPENING:
			if not _door_occupied(door) and door.close():
				play_sfx("door", Vector2(t.x + 0.5, t.y + 0.5))
		elif door.open():
			play_sfx("door", Vector2(t.x + 0.5, t.y + 0.5))
		return
	for pw in pushwalls:
		if pw.state == 0 and pw.origin == t:
			Game.message.emit("This wall sounds hollow... pry it open with your SHIV")
			return
	var hg := _find_hostage(1.4, true)
	if hg != null:
		Game.message.emit("Cut the ropes with your SHIV to free them")
		return
	if not in_bounds(t):
		return
	var tid := walls[_i(t)]
	if tid == POD_TEX:
		_use_pod(t)
		return
	if tid == TERMINAL_TEX:
		_use_terminal()
		return
	if BREAKER_TEX.has(tid):
		_use_breaker(BREAKER_TEX[tid], t)
		return
	if tid == LOCKER_TEX:
		_use_locker()
		return
	if tid == RANGE_TEX:
		_start_range()
		return
	if tid == EXIT_TEX and not exited:
		var why := exit_blocked_reason()
		if why != "":
			play_sfx("denied")
			Game.message.emit(why)
			return
		exited = true
		_wall_mats[EXIT_TEX].albedo_texture = Tex.tex("exit_on")
		play_sfx("exit")
		main.on_level_exit()


## Hitscan attack. Melee is silent; guns wake up nearby enemies.
## Melee (shiv or baton) also cuts hostages free and pries open secret walls.
func player_attack(w: int, bullets := 1) -> void:
	var id := Game.weapon_id()
	if range_state == 1:
		_range_shot()
		return
	if w == Game.Weapon.SHIV:
		var reach: float = Game.weapon_stat("reach", 1.4)
		var baton := id == "baton"
		play_sfx("baton" if baton else "shiv")
		var e := _find_target(reach)
		var hg := _find_hostage(reach, true)
		if hg != null and (e == null or hg.pos.distance_to(player.pos) < e.pos.distance_to(player.pos)):
			_free_hostage(hg)
			return
		if e == null:
			_shiv_wall()
			return
		if e != null:
			if Game.has_perk("ghost") and e.state == Enemy.IDLE:
				e.take_damage(e.hp + 1)
				Game.give_ammo(2)
				Game.message.emit("Silent takedown")
				return
			var shock := Game.upgrade_level("shock_shiv") > 0
			var dmg := randi_range(10, 24) if baton else randi_range(8, 22)
			e.take_damage(dmg * (2 if shock else 1), shock)
			if baton and e.is_alive() and e.kind in ["sentry", "hound"]:
				_knockback(e)
		return
	play_sfx({"slugger": "slugger", "nail": "nail", "arc": "arc", "masterwork": "rifle"}.get(id, ["", "sidearm", "rifle", "rotary"][w]))
	make_noise(player_tile())
	if id == "arc":
		_arc_attack()
		return
	for b in bullets:
		_gun_shot(id)


## One bullet down the crosshair. Hostages in front of the target take it.
## Nail Carbine nails carry on to the next enemy behind, but never past a hostage.
func _gun_shot(id: String) -> void:
	var target := _find_target(30.0)
	var hit_hostage := _find_hostage(30.0, false)
	var hd := hit_hostage.pos.distance_to(player.pos) if hit_hostage != null else INF * 1.0
	if hit_hostage != null and (target == null or hd < target.pos.distance_to(player.pos)):
		_kill_hostage(hit_hostage)
		return
	if target == null:
		return
	var d0 := target.pos.distance_to(player.pos)
	_bullet_hit(target, id)
	if Game.WEAPONS[id].get("pierce", false):
		var nxt := _find_target(30.0, target)
		if nxt != null:
			var dn := nxt.pos.distance_to(player.pos)
			if dn > d0 and dn < hd:
				_bullet_hit(nxt, id)


func _bullet_hit(target: Enemy, id: String) -> void:
	var d := target.pos.distance_to(player.pos)
	var falloff := 0.025 if Game.has_perk("deadeye") else 0.05
	var chance := 1.0 if d < 3.5 else clampf(1.0 - (d - 3.5) * falloff, 0.1, 1.0)
	if randf() > chance:
		return
	var dmg := randi_range(5, 16)
	if id == "sidearm" and Game.upgrade_level("ricochet") > 0:
		dmg = int(dmg * 1.4)
	var close := 3.5 if Game.has_perk("point_blank") else 2.0
	if d < close:
		dmg *= 2
	elif d > 10.0:
		dmg = int(dmg * 0.6)
	var flinch := (d < close and Game.has_perk("point_blank")) or (id == "slugger" and d < 3.5)
	target.take_damage(dmg, flinch)


## Arc Discharger: the closest enemy within 4 tiles in front of you, if any.
func arc_target() -> Enemy:
	var best: Enemy = null
	var bestd := 4.0
	for e in enemies:
		if not e.is_alive():
			continue
		var to := e.pos - player.pos
		var d := to.length()
		if d < bestd and absf(angle_difference(player.angle, to.angle())) < 0.6 and has_los(player.pos, e.pos):
			best = e
			bestd = d
	return best


func _arc_attack() -> void:
	var t := arc_target()
	if t == null:
		return
	var dmg := randi_range(7, 16)
	var first_pos := t.pos
	t.take_damage(dmg, true)
	_spark(first_pos)
	var second: Enemy = null
	var bd := 3.0
	for e in enemies:
		if e != t and e.is_alive():
			var dd := e.pos.distance_to(first_pos)
			if dd < bd and has_los(first_pos, e.pos):
				second = e
				bd = dd
	if second != null:
		second.take_damage(maxi(1, dmg / 2), true)
		_spark(second.pos)


func _spark(at: Vector2) -> void:
	var s := _make_sprite("arc_0", at)
	effects.append({"node": s, "t": 0.0, "prefix": "arc_", "frames": 2})


## Breaching Baton: shove a Sentry or Hound one tile away from Rook.
func _knockback(e: Enemy) -> void:
	var away := e.pos - player.pos
	var dir := Vector2i(signi(roundi(signf(away.x))), 0) if absf(away.x) > absf(away.y) else Vector2i(0, signi(roundi(signf(away.y))))
	var nt := e.tile + dir
	if not in_bounds(nt) or not _walkable_for_enemies(nt) or reservations.has(nt) or doors.has(nt) or _player_overlaps(nt):
		return
	release(e.tile, e)
	release(e.target, e)
	e.tile = nt
	e.target = nt
	e.pos = Vector2(nt.x + 0.5, nt.y + 0.5)
	reserve(nt, e)


func _find_target(max_range: float, exclude: Enemy = null) -> Enemy:
	var best: Enemy = null
	var bestd := INF * 1.0
	for e in enemies:
		if not e.is_alive() or e == exclude:
			continue
		var to := e.pos - player.pos
		var d := to.length()
		if d > max_range or d < 0.01:
			continue
		var off := absf(angle_difference(player.angle, to.angle()))
		if off <= atan2(float(e.stats.get("radius", 0.32)), d) + 0.02 and d < bestd and has_los(player.pos, e.pos):
			best = e
			bestd = d
	return best


## The bound or freed hostage in the player's line of fire, if any.
func _find_hostage(max_range: float, bound_only: bool) -> Hostage:
	var best: Hostage = null
	var bestd := INF * 1.0
	for hg in hostages:
		if not (hg.is_bound() if bound_only else hg.is_present()):
			continue
		var to := hg.pos - player.pos
		var d := to.length()
		if d > max_range or d < 0.01:
			continue
		var off := absf(angle_difference(player.angle, to.angle()))
		if off <= atan2(0.3, d) + (0.15 if bound_only else 0.0) and d < bestd and has_los(player.pos, hg.pos):
			best = hg
			bestd = d
	return best


## Shiv against a wall: pries a secret wall loose.
func _shiv_wall() -> void:
	var f := player.forward()
	var dir := Vector2i(int(signf(f.x)), 0) if absf(f.x) > absf(f.y) else Vector2i(0, int(signf(f.y)))
	var t := player_tile() + dir
	# Only when the player is close enough for the blade to reach.
	var face := Vector2(t.x + 0.5, t.y + 0.5) - Vector2(dir) * 0.5
	if absf((face - player.pos).dot(Vector2(dir))) > 0.75:
		return
	for pw in pushwalls:
		if pw.state == 0 and pw.origin == t:
			if _can_push_into(t + dir):
				pw.dir = dir
				pw.state = 1
				Game.secrets += 1
				play_sfx("push", Vector2(t.x + 0.5, t.y + 0.5))
				play_sfx("secret")
				Game.message.emit("You pried the wall loose - a secret!")
			else:
				play_sfx("denied")
			return


func _free_hostage(hg: Hostage) -> void:
	hg.free_hostage()
	Game.hostages += 1
	Game.earn_scrip(HOSTAGE_SCRIP)
	play_sfx("secret")
	main.hud.flash_pickup()
	if Game.is_protocol("ghost"):
		Game.add_score(2000)
		Game.give_ammo(6)
		var left := Game.hostages_total - Game.hostages
		Game.message.emit("Hostage freed! +6 rounds" + (" - %d to go" % left if left > 0 else " - the exit is open!"))
		return
	Game.add_score(HOSTAGE_SCORE)
	if randf() < 0.5:
		Game.ammo = mini(Game.max_ammo(), Game.ammo + 6)
		Game.message.emit("Hostage freed! They slip you 6 rounds")
	else:
		Game.health = mini(Game.MAX_HEALTH, Game.health + 15)
		Game.message.emit("Hostage freed! They patch you up (+15 health)")


func _kill_hostage(hg: Hostage) -> void:
	var was_bound := hg.is_bound()
	hg.kill()
	blockers[_i(hg.tile)] = 0
	_field_timer = 0.0
	Game.hostages_lost += 1
	Game.score = maxi(0, Game.score - 2000)
	play_sfx("die", hg.pos)
	if Game.is_protocol("daily") and Game.score_mult > 1.0:
		Game.score_mult = 1.0
		Game.message.emit("You shot a hostage! Multiplier reset to x1.0")
		return
	if was_bound:
		Game.message.emit("You shot a hostage! (-2000)")
	else:
		Game.message.emit("You shot a freed hostage! (-2000)")


func on_hostage_gone(hg: Hostage) -> void:
	blockers[_i(hg.tile)] = 0
	_field_timer = 0.0


# ================================================================ debug

## --goto=<feature>: puts the player in front of a room feature for testing.
## Returns false when this floor doesn't have it.
func debug_goto(what: String) -> bool:
	var target := Vector2i(-1, -1)
	var dir := Vector2i.ZERO
	match what:
		"cage":
			# Inside a lock-in room, 2-4 tiles from a cage, looking at it.
			if lockins.is_empty():
				return false
			var li: Dictionary = lockins[0]
			var cg: Vector2 = Vector2(li.cages[0]) + Vector2(0.5, 0.5)
			var r: Rect2i = li.rect
			for y in range(r.position.y, r.end.y):
				for x in range(r.position.x, r.end.x):
					var q := Vector2i(x, y)
					var qc := Vector2(q) + Vector2(0.5, 0.5)
					var dd := qc.distance_to(cg)
					if dd >= 2.5 and dd <= 4.0 and blockers[_i(q)] == 0 and has_los(qc, cg):
						player.pos = qc
						player.angle = (cg - qc).angle()
						return true
			return false
		"hunterview":
			# A spot 4-7 tiles from the elevator with a clear view of it.
			var st := Vector2i(floori(start_pos.x), floori(start_pos.y))
			for y in height:
				for x in width:
					var q := Vector2i(x, y)
					var dd := Vector2(q).distance_to(Vector2(st))
					if dd >= 2.5 and dd <= 9.0 and not _is_wall(q) and blockers[_i(q)] == 0 and not doors.has(q) and has_los(Vector2(q) + Vector2(0.5, 0.5), start_pos):
						player.pos = Vector2(q) + Vector2(0.5, 0.5)
						player.angle = (start_pos - player.pos).angle()
						return true
			return false
		"pod":
			for t in pods:
				target = t + pods[t].dir
				dir = -pods[t].dir
				break
		"range":
			if range_data.is_empty():
				return false
			target = range_data.spot
			dir = -range_data.dir
		"terminal", "locker", "breaker", "exit":
			var want: int = {"terminal": TERMINAL_TEX, "locker": LOCKER_TEX, "breaker": 6, "exit": EXIT_TEX}[what]
			for i in walls.size():
				if walls[i] == want:
					var wt := Vector2i(i % width, i / width)
					for d in DIRS:
						var f: Vector2i = wt + d
						if in_bounds(f) and not _is_wall(f) and blockers[_i(f)] == 0 and not doors.has(f):
							target = f
							dir = -d
							break
					break
		"lockin":
			if lockins.is_empty():
				return false
			var r: Rect2i = lockins[0].rect
			target = r.get_center() + Vector2i(0, 2)
			dir = Vector2i(0, -1)
		"bounty", "standoff":
			for e in enemies:
				if (what == "bounty" and e.kind == "crimson") or (what == "standoff" and e.facing != Vector2i.ZERO and _standoff_guard(e)):
					target = e.tile - e.facing * 0
					for k in range(4, 0, -1):
						var t := e.tile + e.facing * k
						if in_bounds(t) and not _is_wall(t) and blockers[_i(t)] == 0:
							target = t
							break
					dir = -e.facing
					break
	if target.x < 0:
		return false
	player.pos = Vector2(target.x + 0.5, target.y + 0.5)
	player.angle = Vector2(dir).angle()
	return true


func _standoff_guard(e: Enemy) -> bool:
	for hg in hostages:
		if hg.pos.distance_to(e.pos) < 3.5 and room_of[_i(hg.tile)] == room_of[_i(e.tile)]:
			return true
	return false


# ================================================================ protocols & room features

## Why the exit switch won't work yet ("" when it will).
func exit_blocked_reason() -> String:
	if Game.is_protocol("ghost") and Game.hostages < Game.hostages_total:
		return "EXIT SEALED: free every hostage first (%d / %d)" % [Game.hostages, Game.hostages_total]
	if Game.is_protocol("gauntlet"):
		var need := ceili(Game.kills_total * 0.75)
		var all_free := Game.hostages_total > 0 and Game.hostages == Game.hostages_total
		if Game.kills < need and not all_free:
			return "ELEVATOR LOCKED: %d / %d kills, or free every hostage" % [Game.kills, need]
	return ""


func _check_clean_room(r: int) -> void:
	if r < 0 or clean_rooms.has(r):
		return
	var clean := true
	for o in enemies:
		if o.home_room == r:
			if o.is_alive():
				return
			if o.gun_alerted:
				clean = false
	clean_rooms[r] = true
	if clean:
		Game.score_mult += 0.2
		Game.message.emit("Clean room! Score multiplier x%.1f" % Game.score_mult)


func _set_breaker(color: String, on: bool) -> void:
	for tid in BREAKER_TEX:
		if BREAKER_TEX[tid] == color and tid < _wall_mats.size():
			_wall_mats[tid].albedo_texture = Tex.tex("breaker_%s%s" % [color, "_on" if on else ""])


func _use_terminal() -> void:
	if puzzle_order.is_empty():
		return
	if puzzle_solved:
		Game.message.emit("Override complete. The vault is open.")
		return
	var letters := ""
	var names := PackedStringArray()
	for c in puzzle_order:
		letters += c[0]
		names.append(c.to_upper())
	play_sfx("chime_" + letters)
	Game.message.emit("OVERRIDE SEQUENCE: " + " - ".join(names))


func _use_breaker(color: String, t: Vector2i) -> void:
	if puzzle_order.is_empty() or puzzle_solved:
		return
	if puzzle_order.find(color) < puzzle_step:
		Game.message.emit("That breaker is already thrown")
		return
	if color == puzzle_order[puzzle_step]:
		puzzle_step += 1
		_set_breaker(color, true)
		play_sfx("chime_" + color[0])
		if puzzle_step >= puzzle_order.size():
			puzzle_solved = true
			for d in doors.values():
				if d.key == "vault":
					d.unlocked = true
			_wall_mats[TERMINAL_TEX].albedo_texture = Tex.tex("terminal_on")
			_field_timer = 0.0
			play_sfx("secret")
			Game.message.emit("Override accepted - the contraband vault is open!")
		else:
			Game.message.emit("Breaker %d / 3 accepted" % puzzle_step)
		return
	# Wrong breaker: a local alarm pulse (as loud as a sidearm shot) and a reset.
	puzzle_step = 0
	for c in puzzle_order:
		_set_breaker(c, false)
	play_sfx("alarm", Vector2(t.x + 0.5, t.y + 0.5))
	make_noise(player_tile())
	Game.message.emit("Wrong breaker! An alarm pulse rings out - sequence reset")


func _use_locker() -> void:
	if Game.locker_pending:
		Game.message.emit("Your Masterwork Auto Rifle will be waiting on the next floor")
	elif Game.owns("rifle"):
		Game.take_weapon("rifle")
		Game.locker_pending = true
		play_sfx("door")
		Game.message.emit("Auto Rifle confiscated - a MASTERWORK returns next floor")
	elif Game.owns("masterwork"):
		Game.message.emit("Confiscation Locker: nothing left to upgrade")
	else:
		play_sfx("denied")
		Game.message.emit("Confiscation Locker: feed it an Auto Rifle to get a Masterwork back")


# ---------------------------------------------------------------- calibration range

func _start_range() -> void:
	if range_data.is_empty():
		return
	if range_state == 2:
		Game.message.emit("The calibration pod is spent")
		return
	if range_state == 1:
		return
	for e in enemies:
		if e.is_alive() and e.state != Enemy.IDLE:
			play_sfx("denied")
			Game.message.emit("Not while guards are hunting you")
			return
	range_state = 1
	range_t = RANGE_TIME
	range_ammo = 12
	range_foul = false
	var spot: Vector2i = range_data.spot
	var dir: Vector2i = range_data.dir
	player.locked = true
	player.pos = Vector2(spot.x + 0.5, spot.y + 0.5)
	player.angle = Vector2(dir).angle()
	_range_saved = [Game.current_weapon, Game.slot_active[1]]
	Game.current_weapon = Game.Weapon.SIDEARM
	Game.slot_active[1] = "sidearm"
	var lanes: Array = range_data.lanes
	for li in lanes.size():
		var spd := 1.1 + 0.45 * li
		range_targets.append(_range_target(true, lanes[li], randf() * TAU, spd))
		if li != 1:
			range_targets.append(_range_target(false, lanes[li], randf() * TAU, -spd * 0.8))
	play_sfx("key")
	Game.message.emit("CALIBRATION: shoot the red targets, spare the hostages!")


func _range_target(foe: bool, dist: float, phase: float, speed: float) -> Dictionary:
	var node := _make_sprite("target_foe" if foe else "target_hostage", Vector2.ZERO)
	return {"node": node, "foe": foe, "d": dist, "phase": phase, "speed": speed, "down": false, "pos": Vector2.ZERO}


func _tick_range(delta: float) -> void:
	range_t -= delta
	var r: Rect2i = range_data.rect
	var dir: Vector2i = range_data.dir
	var perp := Vector2(dir.y, dir.x)
	var spot: Vector2i = range_data.spot
	var origin := Vector2(spot.x + 0.5, spot.y + 0.5)
	var lateral_center := Vector2(r.position) + Vector2(r.size) / 2.0
	var half := (r.size.y if dir.x != 0 else r.size.x) / 2.0 - 0.6
	var foes_left := 0
	for tg in range_targets:
		var base: Vector2 = origin + Vector2(dir) * tg.d
		# Lateral coordinate measured from the room's centre line.
		var lat := (lateral_center - base).dot(perp)
		var p: Vector2 = base + perp * (lat + half * sin(range_t * tg.speed + tg.phase))
		tg.pos = p
		tg.node.position = Vector3(p.x, 0.5, p.y)
		if tg.foe and not tg.down:
			foes_left += 1
	if foes_left == 0:
		_finish_range(not range_foul, "You clipped a hostage cutout" if range_foul else "")
	elif range_t <= 0.0:
		_finish_range(false, "Time's up")
	elif range_ammo <= 0 and player.fire_cd <= 0.0:
		_finish_range(false, "Out of calibration rounds")


func _range_shot() -> void:
	play_sfx("sidearm")
	var best: Dictionary = {}
	var bestd := INF * 1.0
	for tg in range_targets:
		if tg.down:
			continue
		var to: Vector2 = tg.pos - player.pos
		var d := to.length()
		if d < bestd and absf(angle_difference(player.angle, to.angle())) <= atan2(0.3, d) + 0.01:
			best = tg
			bestd = d
	if best.is_empty():
		return
	best.down = true
	best.node.visible = false
	_spark(best.pos)
	if not best.foe:
		range_foul = true
		play_sfx("denied")
		Game.message.emit("You hit a hostage cutout!")
	else:
		play_sfx("pickup")


func _finish_range(success: bool, why: String) -> void:
	range_state = 2
	player.locked = false
	for tg in range_targets:
		tg.node.queue_free()
	range_targets.clear()
	if _range_saved.size() == 2:
		Game.slot_active[1] = _range_saved[1]
		Game.current_weapon = _range_saved[0]
	if not success:
		play_sfx("denied")
		Game.message.emit("Calibration failed: " + why)
		return
	var spot: Vector2i = range_data.spot
	var dir: Vector2i = range_data.dir
	var perp := Vector2(dir.y, dir.x)
	var row := Vector2(spot.x + 0.5, spot.y + 0.5) + Vector2(dir)
	_spawn_item("ammo16", row - perp, "ammo", "range")
	_spawn_item("medkit_prize", row, "medkit", "range")
	_spawn_item("prize", row + perp, "idol", "range")
	play_sfx("secret")
	Game.message.emit("Calibration passed! Take ONE reward: ammo, full health or +2500")


# ---------------------------------------------------------------- hound lock-in

func _maybe_trigger_lockin(at: Vector2) -> void:
	for li in lockins:
		if li.state == 0 and (li.rect as Rect2i).has_point(Vector2i(floori(at.x), floori(at.y))):
			_trigger_lockin(li)


func _lockin_doors(li: Dictionary) -> Array:
	var out := []
	var gr: Rect2i = (li.rect as Rect2i).grow(1)
	for d in doors.values():
		if gr.has_point(d.tile) and not (li.rect as Rect2i).has_point(d.tile):
			out.append(d)
	return out


func _trigger_lockin(li: Dictionary) -> void:
	li.state = 1
	li.t = LOCKIN_TIME
	for d in _lockin_doors(li):
		if d.key == "":
			d.unlocked = false
			d.close()
	for hs in li.caged:
		hs.queue_free()
	li.caged.clear()
	li.open_t = 0.0
	for k in li.cages.size():
		var t: Vector2i = li.cages[k]
		li.nodes[k].texture = Tex.tex("cage_open")
		var e := Enemy.new()
		add_child(e)
		e.setup(self, "hound", t)
		e.home_room = room_of[_i(t)]
		enemies.append(e)
		reserve(t, e)
		e.alert()
		Game.kills_total += 1
	_field_timer = 0.0
	play_sfx("alarm")
	Game.message.emit("LOCK-IN! The doors seal and the cages open - survive 12 seconds")


func _tick_lockins(delta: float) -> void:
	for li in lockins:
		if li.state == 0:
			_tick_caged(li)
			if Game.level_time > 1.5 and "--spring-lockin" in OS.get_cmdline_user_args():
				_trigger_lockin(li)
			continue
		_tick_open_cages(li, delta)
		if li.state != 1:
			continue
		li.t -= delta
		if li.t <= 0.0:
			li.state = 2
			for d in _lockin_doors(li):
				if d.key == "":
					d.unlocked = true
			_field_timer = 0.0
			play_sfx("key")
			Game.message.emit("The lock-in ends - the doors unseal")


## Caged Hounds face Rook, snarl now and then, and are drawn a little
## behind the cage so the front bars stay in front of them.
func _tick_caged(li: Dictionary) -> void:
	for k in li.caged.size():
		var hs: Sprite3D = li.caged[k]
		var t: Vector2i = li.cages[k]
		var c := Vector2(t.x + 0.5, t.y + 0.5)
		var away := (c - player.pos).normalized()
		hs.position = Vector3(c.x + away.x * 0.12, 0.5, c.y + away.y * 0.12)
		var phase := fmod(Game.level_time * 0.8 + k * 0.37, 1.0)
		hs.texture = Tex.enemy("hound", "aim" if phase > 0.75 else "stand", 0, 0)


## Once a Hound has run out of its open cage, the empty cage is removed.
func _tick_open_cages(li: Dictionary, delta: float) -> void:
	li.open_t += delta
	for k in li.nodes.size():
		var node = li.nodes[k]
		if node == null or not is_instance_valid(node):
			continue
		var t: Vector2i = li.cages[k]
		var occupied := false
		for e in enemies:
			if e.is_alive() and (e.tile == t or Vector2i(floori(e.pos.x), floori(e.pos.y)) == t):
				occupied = true
		if not occupied and li.open_t > 0.3:
			_spark(Vector2(t.x + 0.5, t.y + 0.5))
			node.queue_free()
			li.nodes[k] = null


func damage_player(n: int) -> void:
	if player.dead or main.god_mode or player.invulnerable > 0.0:
		return
	n = maxi(1, int(n * DAMAGE_SCALE[Game.difficulty] * Game.damage_taken_scale()))
	Game.health = maxi(0, Game.health - n)
	main.hud.flash_damage(n)
	play_sfx("hurt")
	if Game.health <= 0:
		player.dead = true
		main.on_player_died()


func on_enemy_killed(e: Enemy) -> void:
	Game.kills += 1
	Game.add_score(e.stats.score)
	Game.earn_scrip(KILL_SCRIP.get(e.kind, 1))
	if Game.is_protocol("purge"):
		var s: int = SCRAP.get(e.kind, 1)
		Game.scrap += s
		Game.message.emit("+%d SCRAP  (%d)   C to craft" % [s, Game.scrap])
	release(e.tile, e)
	release(e.target, e)
	play_sfx("die", e.pos)
	if Game.is_protocol("daily"):
		_check_clean_room(e.home_room)
	var drop_tile := Vector2i(floori(e.pos.x), floori(e.pos.y))
	var drop_pos := Vector2(drop_tile.x + 0.5, drop_tile.y + 0.5)
	match e.kind:
		"sentry":
			_spawn_item("clip", drop_pos)
		"warden":
			_spawn_item("clip" if Game.owned[Game.Weapon.RIFLE] else "rifle", drop_pos)
		"overseer":
			_spawn_item("key_gold", drop_pos)
			for i in 4:
				_explode(e.pos + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), false)
			Game.message.emit("The Overseer is down! It dropped the GOLD keycard")
		"suboverseer":
			_spawn_item("ammo", drop_pos)
			_spawn_item("medkit", drop_pos + Vector2(0.01, 0))
			for i in 3:
				_explode(e.pos + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), false)
			Game.message.emit("The Sub-Overseer is down!")
		"crimson":
			_spawn_item("chip", drop_pos)
			_spawn_item("ammo", drop_pos + Vector2(0.01, 0))
			_spawn_item("clip", drop_pos + Vector2(-0.01, 0))
			Game.message.emit("Bounty claimed! It dropped a PERK CHIP and 12 rounds")


func _treasure_mult() -> int:
	return 2 if Game.has_perk("treasure_hunter") else 1


## Roguelite respawn: back to the floor's start with gear intact and a short
## window of invulnerability. Dead enemies stay dead.
func respawn_player() -> void:
	player.pos = start_pos
	player.angle = start_angle
	player.dead = false
	player.invulnerable = 2.5
	if range_state == 1:
		_finish_range(false, "Calibration aborted")
	player.cam.rotation.z = 0.0
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	Game.health = Game.MAX_HEALTH
	if Game.is_protocol("purge") and not hunter_done:
		# The Hunter Warden goes back in its elevator; the clock restarts and a
		# clip waits at the start so you can sprint straight off.
		if hunter != null:
			enemies.erase(hunter)
			hunter.queue_free()
			hunter = null
		hunter_clock = 0.0
		_siren_done = false
		_spawn_item("clip", start_pos + Vector2.from_angle(start_angle) * 0.7)
	if Game.ammo < Game.START_AMMO:
		Game.ammo = Game.START_AMMO
		if Game.current_weapon == Game.Weapon.SHIV and Game.auto_shiv:
			Game.current_weapon = Game.best_gun()
			Game.auto_shiv = false
	_rebuild_field()


func _check_pickups() -> void:
	for it in items.duplicate():
		if not items.has(it):
			continue
		if it.pos.distance_to(player.pos) < 0.6 and _try_pickup(it.type):
			it.node.queue_free()
			items.erase(it)
			if it.has("group"):
				# A "pick one" reward: the others vanish.
				for o in items.duplicate():
					if o.get("group", "") == it.group:
						o.node.queue_free()
						items.erase(o)
			_maybe_trigger_lockin(it.pos)


func _try_pickup(type: String) -> bool:
	var snd := "pickup"
	match type:
		"ammo":
			if not Game.give_ammo(8): return false
		"clip":
			if not Game.give_ammo(4): return false
		"medkit":
			if not Game.heal(25): return false
		"food":
			if not Game.heal(10): return false
		"gem":
			Game.treasure += 1
			Game.add_score(100 * _treasure_mult())
			Game.earn_scrip(2 * _treasure_mult())
		"idol":
			Game.treasure += 1
			Game.add_score(500 * _treasure_mult())
			Game.earn_scrip(8 * _treasure_mult())
		"life":
			Game.treasure += 1
			Game.earn_scrip(5)
			Game.health = Game.MAX_HEALTH
			Game.ammo = mini(Game.max_ammo(), Game.ammo + 25)
			Game.lives = mini(Game.MAX_LIVES, Game.lives + 1)
			Game.message.emit("EXTRA LIFE!")
			snd = "secret"
		"rifle":
			Game.give_weapon(Game.Weapon.RIFLE, 6)
			Game.message.emit("Picked up the AUTO RIFLE")
			snd = "weapon"
		"rotary":
			Game.give_weapon(Game.Weapon.ROTARY, 6)
			Game.message.emit("Picked up the ROTARY CANNON!")
			snd = "weapon"
		"mod_crate":
			var id := Game.roll_prototype()
			if id == "":
				Game.ammo = mini(Game.max_ammo(), Game.ammo + 8)
				Game.message.emit("Mod crate: you have every prototype - took 8 rounds")
			else:
				var slot: int = Game.WEAPONS[id].slot
				Game.give_weapon(slot, 6, id)
				Game.message.emit("PROTOTYPE: %s  (press %d again to switch)" % [Game.WEAPONS[id].name, slot + 1])
			snd = "weapon"
		"scrip_cache":
			Game.earn_scrip(15)
			Game.add_score(1500)
			Game.message.emit("Contraband cache: +15 Iron Scrip" if Game.is_run() else "Contraband cache: +1500")
			snd = "secret"
		"chip":
			Game.bonus_perks += 1
			Game.message.emit("PERK CHIP: an extra perk pick after this floor")
			snd = "secret"
		"ammo16":
			if not Game.give_ammo(16): return false
			Game.message.emit("Calibration reward: 16 rounds")
		"medkit_prize":
			Game.health = Game.MAX_HEALTH
			Game.message.emit("Calibration reward: full health")
		"prize":
			Game.add_score(2500)
			Game.message.emit("Calibration reward: +2500")
			snd = "secret"
		"map":
			Game.has_map = true
			map_dirty = true
			Game.message.emit("Found the PRISON MAP - floor layout revealed!")
			snd = "key"
		"key_red", "key_blue", "key_gold":
			var k := type.substr(4)
			Game.keys[k] = true
			Game.message.emit("Picked up the %s keycard" % k)
			snd = "key"
	play_sfx(snd)
	main.hud.flash_pickup()
	return true


# ================================================================ projectiles

## The Overseer's shoulder launchers: two slow plasma bolts you can dodge.
func fire_plasma(e: Enemy) -> void:
	var base := (player.pos - e.pos).angle()
	for off in [-0.13, 0.13]:
		var dir := Vector2.from_angle(base + off)
		var start: Vector2 = e.pos + dir * 0.55
		projectiles.append({"pos": start, "vel": dir * 4.5, "dmg": randi_range(10, 20), "t": 0.0,
			"node": _make_sprite("plasma", start)})
	play_sfx("launch", e.pos)


func _tick_projectiles(delta: float) -> void:
	for p in projectiles.duplicate():
		var np: Vector2 = p.pos + p.vel * delta
		p.t += delta
		if not player.dead and np.distance_to(player.pos) < 0.4:
			damage_player(p.dmg)
			_remove_projectile(p, np, false)
		elif blocks_sight(Vector2i(floori(np.x), floori(np.y))) or p.t > 8.0:
			_remove_projectile(p, p.pos, true)
		else:
			p.pos = np
			p.node.position = Vector3(np.x, 0.5, np.y)


func _remove_projectile(p: Dictionary, at: Vector2, splash: bool) -> void:
	p.node.queue_free()
	projectiles.erase(p)
	_explode(at, splash)


func _explode(at: Vector2, splash: bool) -> void:
	effects.append({"node": _make_sprite("blast_0", at), "t": 0.0})
	play_sfx("blast", at)
	if splash and not player.dead:
		var d := at.distance_to(player.pos)
		if d < 1.2:
			damage_player(int(14.0 * (1.2 - d)))


func _tick_effects(delta: float) -> void:
	for fx in effects.duplicate():
		fx.t += delta
		var frame := int(fx.t / 0.1)
		if frame >= fx.get("frames", 3):
			fx.node.queue_free()
			effects.erase(fx)
		else:
			fx.node.texture = Tex.tex(fx.get("prefix", "blast_") + str(frame))


func play_sfx(sfx_name: String, at = null) -> void:
	main.play_sfx(sfx_name, at)


# ================================================================ purge protocol

## Two rocket pods per floor, on walls that look down the longest open runs
## (away from the start), so there's always a corridor to lure the Hunter into.
func _place_pods(start: Vector2i, door_tiles: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = Game.run_seed + Game.level_index * 131
	var cands := []
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var t := Vector2i(x, y)
			var tid := walls[_i(t)]
			if tid < 0 or tid > 3:
				continue
			for d in DIRS:
				var f: Vector2i = t + d
				if _is_wall(f) or door_tiles.has(f) or pushwall_at(f) != null:
					continue
				var near_door := false
				for dd in DIRS:
					if door_tiles.has(f + dd) or door_tiles.has(t + dd):
						near_door = true
				if near_door:
					continue
				var run := 0
				var p := f
				while in_bounds(p) and not _is_wall(p) and not door_tiles.has(p) and run < 14:
					run += 1
					p += d
				if run >= 5 and absi(f.x - start.x) + absi(f.y - start.y) >= 5:
					cands.append([run + rng.randf(), t, d])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for c in cands:
		var t: Vector2i = c[1]
		var ok := true
		for q in pods:
			if absi(q.x - t.x) + absi(q.y - t.y) < 8:
				ok = false
		if ok:
			pods[t] = {"dir": c[2], "used": false, "mat": null}
			walls[_i(t)] = POD_TEX
		if pods.size() >= 2:
			break


func hunter_paused() -> bool:
	if player.dead or range_state == 1:
		return true
	for li in lockins:
		if li.state == 1:
			return true
	return false


func _tick_purge(delta: float) -> void:
	if hunter_done:
		return
	if hunter == null:
		if not hunter_paused():
			hunter_clock += delta
		var left := hunter_delay - hunter_clock
		if left <= 10.0 and not _siren_done:
			_siren_done = true
			play_sfx("siren")
			Game.message.emit("CELL BLOCK PURGE IN 10 SECONDS")
		if left <= 0.0:
			_spawn_hunter()
		return
	_hunt_timer -= delta
	if _hunt_timer <= 0.0 or player_tile() != _hunt_tile:
		_rebuild_hunt_field()
	if "--debug-hunter" in OS.get_cmdline_user_args() and Engine.get_process_frames() % 30 == 0:
		print("hunter t=%.1f tile=%s target=%s pose=%s bash=%s bash_t=%.2f stun=%.1f grab=%.2f field=%d paused=%s" % [Game.level_time, hunter.tile, hunter.target, hunter.pose, hunter.bash_door.tile if hunter.bash_door else "-", hunter.bash_t, hunter.stun_t, hunter.grab_t, hunt_field[_i(hunter.tile)], hunter_paused()])


func _spawn_hunter() -> void:
	var t := Vector2i(floori(start_pos.x), floori(start_pos.y))
	hunter = Hunter.new()
	add_child(hunter)
	hunter.setup_hunter(self, t)
	enemies.append(hunter)
	_rebuild_hunt_field()
	play_sfx("push", start_pos)
	play_sfx("boss_alert")
	Game.message.emit("THE HUNTER WARDEN HAS LEFT THE ELEVATOR")


## Distance map from Rook for the Hunter: it walks through every door
## (it batters the closed ones) but not walls, secret walls or props.
func _rebuild_hunt_field() -> void:
	hunt_field.fill(INF)
	var src := player_tile()
	_hunt_tile = src
	_hunt_timer = 0.5
	if not in_bounds(src):
		return
	hunt_field[_i(src)] = 0
	var queue: Array[Vector2i] = [src]
	var qi := 0
	while qi < queue.size():
		var c := queue[qi]
		qi += 1
		var v := hunt_field[_i(c)] + 1
		for d in DIRS:
			var n: Vector2i = c + d
			if in_bounds(n) and hunt_field[_i(n)] > v and not _is_wall(n) and blockers[_i(n)] == 0 and pushwall_at(n) == null:
				hunt_field[_i(n)] = v
				queue.append(n)


func hunt_step(h: Hunter) -> Vector2i:
	var cur := h.tile
	var best := cur
	var bestv := hunt_field[_i(cur)]
	if bestv >= INF:
		# Off the map of reachable tiles (e.g. Rook is behind a secret wall): wait.
		return cur
	for d in DIRS:
		var n: Vector2i = cur + d
		if in_bounds(n) and hunt_field[_i(n)] < bestv:
			best = n
			bestv = hunt_field[_i(n)]
	return best


## Heavy footsteps that get louder as it closes in (through walls and doors).
func hunter_stomp(h: Hunter) -> void:
	var d := h.pos.distance_to(player.pos)
	if d < 16.0:
		main.play_sfx_db("stomp", lerpf(-2.0, -30.0, d / 16.0))


func hunter_entered(_h: Hunter, _t: Vector2i) -> void:
	pass


func hunter_grab(_h: Hunter) -> void:
	damage_player(500)


func break_door(door: Door) -> void:
	var t := door.tile
	doors.erase(t)
	door.queue_free()
	_explode(Vector2(t.x + 0.5, t.y + 0.5), false)
	play_sfx("door_break", Vector2(t.x + 0.5, t.y + 0.5))
	_field_timer = 0.0
	map_dirty = true
	Game.message.emit("The Hunter Warden smashed through a door!")


## Rocket hit: the Hunter is scrapped for the rest of this floor.
func destroy_hunter() -> void:
	if hunter == null or not hunter.is_alive():
		return
	hunter.destroy()
	hunter_done = true
	for i in 3:
		_explode(hunter.pos + Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), false)
	var drop := Vector2(hunter.tile.x + 0.5, hunter.tile.y + 0.5)
	_spawn_item("ammo", drop)
	Game.add_score(5000)
	Game.scrap += 3
	Game.message.emit("HUNTER WARDEN SCRAPPED!  +5000, +8 ammo, +3 scrap")


func _use_pod(t: Vector2i) -> void:
	var pod: Dictionary = pods[t]
	if pod.used:
		play_sfx("denied")
		Game.message.emit("This rocket pod is spent")
		return
	if hunter == null or not hunter.is_alive():
		play_sfx("denied")
		Game.message.emit("Rocket pod armed - lure the Hunter Warden into its sights")
		return
	var from := Vector2(t.x + 0.5, t.y + 0.5) + Vector2(pod.dir) * 0.6
	if from.distance_to(hunter.pos) > POD_RANGE or not has_los(from, hunter.pos):
		play_sfx("denied")
		Game.message.emit("The Hunter Warden isn't in the pod's sights")
		return
	pod.used = true
	pod.mat.albedo_texture = Tex.tex("pod_empty")
	_launch_rocket(from, (hunter.pos - from).normalized(), true)


## Breach Rocket gadget: fired straight down the crosshair.
func fire_rocket() -> void:
	var f: Vector2 = player.forward()
	_launch_rocket(player.pos + f * 0.35, f, false)
	make_noise(player_tile())
	Game.message.emit("Breach Rocket away!")


func _launch_rocket(from: Vector2, dir: Vector2, homing: bool) -> void:
	rockets.append({"pos": from, "dir": dir, "homing": homing, "t": 0.0, "node": _make_sprite("rocket", from)})
	play_sfx("rocket", from)


func _tick_rockets(delta: float) -> void:
	for r in rockets.duplicate():
		r.t += delta
		if r.homing and hunter != null and hunter.is_alive():
			r.dir = (hunter.pos - r.pos).normalized()
		var np: Vector2 = r.pos + r.dir * ROCKET_SPEED * delta
		var hit := false
		for e in enemies:
			if e.is_alive() and e.pos.distance_to(np) < (0.7 if e == hunter else 0.45) and (not r.homing or e == hunter):
				hit = true
		if hit or blocks_sight(Vector2i(floori(np.x), floori(np.y))) or r.t > 4.0:
			_rocket_blast(r.pos if not hit else np)
			r.node.queue_free()
			rockets.erase(r)
		else:
			r.pos = np
			r.node.position = Vector3(np.x, 0.5, np.y)


func _rocket_blast(at: Vector2) -> void:
	for i in 2:
		_explode(at + Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2)), false)
	for e in enemies.duplicate():
		if e.is_alive() and e.pos.distance_to(at) < 1.6:
			if e == hunter:
				destroy_hunter()
			else:
				e.take_damage(60, true)


func drop_mine() -> bool:
	var t := player_tile()
	for m in mines:
		if m.tile == t:
			return false
	var p := Vector2(t.x + 0.5, t.y + 0.5)
	var node := _make_sprite("mine", p)
	node.position.y = 0.12
	node.pixel_size *= 0.5
	mines.append({"tile": t, "node": node})
	play_sfx("mine")
	return true


func _remove_mine(m: Dictionary) -> void:
	m.node.queue_free()
	mines.erase(m)
	play_sfx("stun", Vector2(m.tile.x + 0.5, m.tile.y + 0.5))


## Shock Mines: the Hunter is stunned for 6 s, guards take 40 damage.
func _tick_mines() -> void:
	for m in mines.duplicate():
		# The Hunter sets a mine off as soon as it comes within reach of it.
		if hunter != null and hunter.is_alive() and not hunter.is_stunned():
			if hunter.pos.distance_to(Vector2(m.tile.x + 0.5, m.tile.y + 0.5)) < 0.95:
				_remove_mine(m)
				_spark(hunter.pos)
				hunter.stun(6.0)
				continue
		for e in enemies:
			if e != hunter and e.is_alive() and e.tile == m.tile:
				_remove_mine(m)
				_spark(e.pos)
				e.take_damage(40, true)
				break


## Door Brace: clamps the door Rook faces (up to two braces per door).
func brace_door() -> String:
	var f := player.forward()
	var dir := Vector2i(int(signf(f.x)), 0) if absf(f.x) > absf(f.y) else Vector2i(0, int(signf(f.y)))
	var door = doors.get(player_tile() + dir)
	if door == null:
		door = doors.get(player_tile())
	if door == null:
		return "Face a door to brace it"
	if not door.add_brace():
		return "That door already has two braces"
	if not door.brace_landed.is_connected(_on_brace_landed):
		door.brace_landed.connect(_on_brace_landed)
	play_sfx("brace", Vector2(door.tile.x + 0.5, door.tile.y + 0.5))
	map_dirty = true
	return ""


## The bar slammed into its clamp: sparks and a clank.
func _on_brace_landed(at: Vector3) -> void:
	_spark(Vector2(at.x, at.z))
	play_sfx("clank", Vector2(at.x, at.z))


## The Hunter battered a brace loose: it snaps off and clatters to the floor,
## thrown away from the Hunter.
func snap_brace(door: Door, from: Vector2) -> void:
	var node := door.pop_brace()
	if node == null:
		return
	add_child(node)
	var c := Vector2(door.tile.x + 0.5, door.tile.y + 0.5)
	var away := (c - from).normalized()
	var spin := Vector3(randf_range(-6, 6), randf_range(-3, 3), randf_range(-8, 8))
	brace_debris.append({"node": node, "vel": Vector3(away.x * 2.2, 1.6, away.y * 2.2), "spin": spin, "t": 0.0})
	_spark(c + away * 0.2)
	_spark(c + away * 0.2 + Vector2(away.y, -away.x) * 0.4)
	play_sfx("clank", c)
	play_sfx("door_break", c)
	Game.message.emit("A brace snapped!  %d left on that door" % door.brace_count())


func _tick_brace_debris(delta: float) -> void:
	for d in brace_debris.duplicate():
		var node: Node3D = d.node
		d.t += delta
		if node.position.y > 0.06 or d.vel.y > 0.0:
			d.vel.y -= 9.0 * delta
			node.position += d.vel * delta
			node.rotation += d.spin * delta
			if node.position.y <= 0.06:
				# Hit the floor: one small bounce, then lie flat.
				node.position.y = 0.06
				d.vel = Vector3(d.vel.x * 0.3, absf(d.vel.y) * 0.25 if absf(d.vel.y) > 2.0 else 0.0, d.vel.z * 0.3)
				d.spin *= 0.3
				node.rotation.x = 0.0
				node.rotation.z = 0.0
		if d.t > 6.0:
			node.scale = Vector3.ONE * maxf(0.01, 1.0 - (d.t - 6.0) * 2.0)
		if d.t > 6.5:
			node.queue_free()
			brace_debris.erase(d)


## Purge gadgets (R / F / B). Returns false if nothing happened.
func use_gadget(id: String) -> bool:
	if not Game.is_protocol("purge") or player.dead:
		return false
	if int(Game.gadgets.get(id, 0)) <= 0:
		play_sfx("denied")
		Game.message.emit("No %s - press C to craft one from scrap" % Game.GADGETS[id][0])
		return false
	match id:
		"rocket":
			fire_rocket()
		"mine":
			if not drop_mine():
				Game.message.emit("There's already a mine here")
				return false
			Game.message.emit("Shock Mine armed")
		"brace":
			var why := brace_door()
			if why != "":
				play_sfx("denied")
				Game.message.emit(why)
				return false
			Game.message.emit("Door braced - the Hunter needs 6 s more to break it")
	Game.gadgets[id] = int(Game.gadgets[id]) - 1
	return true
