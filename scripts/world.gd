class_name World
extends Node3D
## Builds a floor from a text grid (see levels.gd) and runs the simulation:
## doors, sliding secret walls, enemies, pickups, hitscan and gunfire noise.
## One tile = one world unit. Tile (x, y) covers X in [x, x+1], Z in [y, y+1].

const TEX_NAMES := ["stone", "metal", "rust", "sigil", "exit"]
const WALL_CHARS := {"#": 0, "B": 1, "W": 2, "F": 3, "E": 4}
const EXIT_TEX := 4
const ITEM_CHARS := {"a": "ammo", "m": "medkit", "f": "food", "t": "gem", "T": "idol", "x": "life", "g": "rifle", "c": "rotary", "r": "key_red", "u": "key_blue", "k": "key_gold", "M": "map"}
const ENEMY_CHARS := {"s": "sentry", "h": "hound", "w": "warden", "O": "overseer"}
const DECO_CHARS := {"o": "pillar", "b": "barrel", "l": "lamp"}
const DOOR_CHARS := {"D": "", "R": "red", "U": "blue", "G": "gold"}
const PUSH_CHARS := {"P": 0, "Q": 1}
const TREASURE := ["gem", "idol", "life"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const INF := 1 << 20
const KILL_SCRIP := {"sentry": 1, "hound": 1, "warden": 3, "overseer": 40}
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
var items: Array[Dictionary] = []
var reservations := {}
var player: Player
var start_pos := Vector2(1.5, 1.5)
var start_angle := 0.0
var boss: Enemy = null
var projectiles: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var exited := false
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
			elif ENEMY_CHARS.has(c):
				enemy_specs.append([t, ENEMY_CHARS[c]])
			elif ITEM_CHARS.has(c):
				_spawn_item(ITEM_CHARS[c], p)
			elif DECO_CHARS.has(c):
				_make_sprite(DECO_CHARS[c], p)
				if c != "l":
					blockers[_i(t)] = 1
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
		reserve(e.tile, e)
	player = Player.new()
	add_child(player)
	start_pos = start
	start_angle = deg_to_rad(float(level.get("angle", 0.0)))
	player.setup(self, start_pos, start_angle)
	_make_environment()
	_compute_rooms(Vector2i(floori(start.x), floori(start.y)))
	Game.kills_total = enemies.size()
	Game.secrets_total = pushwalls.size()
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
			if tid < 0:
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


func _spawn_item(type: String, p: Vector2) -> void:
	items.append({"type": type, "pos": p, "node": _make_sprite(type, p)})


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
		if e.is_alive():
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
	for e in enemies:
		if e.state == Enemy.IDLE and seen.has(e.tile):
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
	_tick_projectiles(delta)
	_tick_effects(delta)
	if not player.dead:
		_check_pickups()


func _door_occupied(d: Door) -> bool:
	if _player_overlaps(d.tile):
		return true
	for e in enemies:
		if e.is_alive():
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
			if _can_push_into(t + dir):
				pw.dir = dir
				pw.state = 1
				Game.secrets += 1
				play_sfx("push", Vector2(t.x + 0.5, t.y + 0.5))
				play_sfx("secret")
				Game.message.emit("You found a secret!")
			else:
				play_sfx("denied")
			return
	if in_bounds(t) and walls[_i(t)] == EXIT_TEX and not exited:
		exited = true
		_wall_mats[EXIT_TEX].albedo_texture = Tex.tex("exit_on")
		play_sfx("exit")
		main.on_level_exit()


## Hitscan attack. The shiv is silent; guns wake up nearby enemies.
func player_attack(w: int) -> void:
	if w == Game.Weapon.SHIV:
		play_sfx("shiv")
		var e := _find_target(1.4)
		if e != null:
			if Game.has_perk("ghost") and e.state == Enemy.IDLE:
				e.take_damage(e.hp + 1)
				Game.give_ammo(2)
				Game.message.emit("Silent takedown")
				return
			var shock := Game.upgrade_level("shock_shiv") > 0
			e.take_damage(randi_range(8, 22) * (2 if shock else 1), shock)
		return
	play_sfx(["", "sidearm", "rifle", "rotary"][w])
	make_noise(player_tile())
	var target := _find_target(30.0)
	if target == null:
		return
	var d := target.pos.distance_to(player.pos)
	var falloff := 0.025 if Game.has_perk("deadeye") else 0.05
	var chance := 1.0 if d < 3.5 else clampf(1.0 - (d - 3.5) * falloff, 0.1, 1.0)
	if randf() > chance:
		return
	var dmg := randi_range(5, 16)
	if w == Game.Weapon.SIDEARM and Game.upgrade_level("ricochet") > 0:
		dmg = int(dmg * 1.4)
	var close := 3.5 if Game.has_perk("point_blank") else 2.0
	if d < close:
		dmg *= 2
	elif d > 10.0:
		dmg = int(dmg * 0.6)
	target.take_damage(dmg, d < close and Game.has_perk("point_blank"))


func _find_target(max_range: float) -> Enemy:
	var best: Enemy = null
	var bestd := INF * 1.0
	for e in enemies:
		if not e.is_alive():
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
	release(e.tile, e)
	release(e.target, e)
	play_sfx("die", e.pos)
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


func _treasure_mult() -> int:
	return 2 if Game.has_perk("treasure_hunter") else 1


## Roguelite respawn: back to the floor's start with gear intact and a short
## window of invulnerability. Dead enemies stay dead.
func respawn_player() -> void:
	player.pos = start_pos
	player.angle = start_angle
	player.dead = false
	player.invulnerable = 2.5
	player.cam.rotation.z = 0.0
	for p in projectiles:
		p.node.queue_free()
	projectiles.clear()
	Game.health = Game.MAX_HEALTH
	if Game.ammo < Game.START_AMMO:
		Game.ammo = Game.START_AMMO
		if Game.current_weapon == Game.Weapon.SHIV and Game.auto_shiv:
			Game.current_weapon = Game.best_gun()
			Game.auto_shiv = false
	_rebuild_field()


func _check_pickups() -> void:
	for it in items.duplicate():
		if it.pos.distance_to(player.pos) < 0.6 and _try_pickup(it.type):
			it.node.queue_free()
			items.erase(it)


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
		if frame >= 3:
			fx.node.queue_free()
			effects.erase(fx)
		else:
			fx.node.texture = Tex.tex("blast_%d" % frame)


func play_sfx(sfx_name: String, at = null) -> void:
	main.play_sfx(sfx_name, at)
