class_name PlayTest
extends Node
## Automated play tests, run inside the real game:
##   Godot --path . -- --playtest=brace [--playtest-shots=DIR]
## Each check prints "PLAYTEST PASS|FAIL <name> ..."; the game quits with
## exit code 0 when everything passed, 1 otherwise. Never writes the save.
##
## brace: Door Brace gadget on a Purge floor -
##   * bracing with no door in front does nothing and costs nothing;
##   * a brace swings down, lands (sparks) and settles flat;
##   * a second brace fits, a third is refused;
##   * a braced door still opens for Rook and the bars ride along;
##   * the Hunter needs 6 s per brace: each one snaps off in turn and is
##     thrown to the floor, then the door breaks 2.5 s later.
##
## rocket: Breach Rocket gadget -
##   * with none crafted it is refused;
##   * fired down an empty corridor it flies and explodes at the far end;
##   * it hits a guard for exactly 60 damage;
##   * it scraps the Hunter for the floor: +5000 (x1.5 in Purge), +3 scrap,
##     an ammo drop, and the Hunter stays gone.
##
## mine: Shock Mine gadget -
##   * dropped under Rook it arms on that tile (a second there is refused);
##   * a guard stepping on it takes exactly 40 damage and the mine is used up;
##   * the Hunter sets it off and is stunned for 6 s;
##   * a stunned Hunter can't set off a second mine - it goes off as soon
##     as the Hunter walks on.
##
## all: every suite above, one after another on the same floor.

var main: Node
var _fails := 0
var _passes := 0
var _shots := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--playtest-shots="):
			_shots = a.substr(17)
	run.call_deferred()


func run() -> void:
	var which := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--playtest="):
			which = a.substr(11)
	main.god_mode = true
	match which:
		"brace":
			await _brace_tests()
		"rocket":
			await _rocket_tests()
		"mine":
			await _mine_tests()
		"all":
			await _brace_tests()
			await _rocket_tests()
			await _mine_tests()
		_:
			_check("known playtest", false, "no playtest called '%s'" % which)
	print("PLAYTEST DONE  %d passed, %d failed" % [_passes, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail := "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
	print("PLAYTEST %s %s%s" % ["PASS" if ok else "FAIL", name, "  (" + detail + ")" if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Wait `sec` of game time (world.tick time, which is what the Hunter uses).
func _wait(sec: float) -> void:
	var end: float = Game.level_time + sec
	while Game.level_time < end:
		await get_tree().process_frame


func _shot(name: String) -> void:
	if _shots == "":
		return
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots.path_join(name + ".png"))
	print("PLAYTEST shot ", _shots.path_join(name + ".png"))


func _stand(w, t: Vector2i, look_at: Vector2) -> void:
	w.player.pos = Vector2(t) + Vector2(0.5, 0.5)
	w.player.angle = (look_at - w.player.pos).angle()


## A closed, unlocked door with open floor on both sides, and two free
## tiles on the near side (so the camera can step back).
func _find_door(w) -> Array:
	for t in w.doors:
		var d: Door = w.doors[t]
		if not d.unlocked or d.key != "":
			continue
		var n := Vector2i(0, 1) if d.spans_x else Vector2i(1, 0)
		var ok := true
		for q in [t + n, t + n * 2, t - n, t - n * 2]:
			if not w.in_bounds(q) or w._is_wall(q) or w.doors.has(q) or w.blockers[w._i(q)] != 0:
				ok = false
		if ok:
			return [d, n]
	return []


func _brace_tests() -> void:
	while main.state != "playing" or main.world == null:
		await get_tree().process_frame
	var w = main.world
	w.hunter_delay = 99999.0   # the Hunter only comes when this test calls it
	Game.gadgets["brace"] = 3
	await _frames(3)

	# --- 1. No door in front: refused, nothing spent.
	var wall_spot := Vector2i(-1, -1)
	var wall_dir := Vector2i.ZERO
	for y in w.height:
		for x in w.width:
			var q := Vector2i(x, y)
			if w._is_wall(q) or w.doors.has(q) or w.blockers[w._i(q)] != 0:
				continue
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if w._is_wall(q + dir) and not w.doors.has(q + dir):
					wall_spot = q
					wall_dir = dir
					break
			if wall_spot.x >= 0:
				break
		if wall_spot.x >= 0:
			break
	_stand(w, wall_spot, Vector2(wall_spot + wall_dir) + Vector2(0.5, 0.5))
	var used: bool = w.use_gadget("brace")
	_check("no door: refused", not used)
	_check("no door: brace not spent", int(Game.gadgets["brace"]) == 3, "have %d" % Game.gadgets["brace"])

	# --- 2. Brace a door: it swings down, lands and settles.
	var found := _find_door(w)
	_check("found a test door", not found.is_empty())
	if found.is_empty():
		return
	var door: Door = found[0]
	var n: Vector2i = found[1]
	var near := door.tile + n
	var dc := Vector2(door.tile) + Vector2(0.5, 0.5)
	_stand(w, near, dc)
	await _frames(2)
	var landings := []
	door.brace_landed.connect(func(at): landings.append(at))
	var effects_before: int = w.effects.size()
	used = w.use_gadget("brace")
	_check("brace: accepted", used)
	_check("brace: door has 1 brace", door.brace_count() == 1, "has %d" % door.brace_count())
	_check("brace: one spent", int(Game.gadgets["brace"]) == 2, "have %d" % Game.gadgets["brace"])
	_stand(w, near + n, dc)   # step back for the screenshots
	await _frames(3)
	var swing: float = door.braces[0].pivot.rotation.z
	_check("brace: starts raised, mid-swing", swing > 0.4, "angle %.2f" % swing)
	await _shot("brace_1_swinging")
	var tl: float = Game.level_time
	while not door.braces[0].landed and Game.level_time - tl < 0.5:
		await get_tree().process_frame
	_check("brace: landed with sparks", door.braces[0].landed and landings.size() == 1 and w.effects.size() > effects_before,
		"landed %s, landings %d, effects %d -> %d" % [door.braces[0].landed, landings.size(), effects_before, w.effects.size()])
	await _shot("brace_2_landed")
	await _wait(0.5)
	var rest: float = door.braces[0].pivot.rotation.z
	_check("brace: settled flat", absf(rest) < 0.02, "angle %.3f" % rest)

	# --- 3. Second brace fits, third is refused.
	_stand(w, near, dc)
	await _frames(2)
	used = w.use_gadget("brace")
	_check("second brace: accepted", used and door.brace_count() == 2)
	await _wait(0.7)
	_stand(w, near + n, dc)
	await _shot("brace_3_two_braces")
	_stand(w, near, dc)
	await _frames(2)
	used = w.use_gadget("brace")
	_check("third brace: refused", not used and door.brace_count() == 2)
	_check("third brace: not spent", int(Game.gadgets["brace"]) == 1, "have %d" % Game.gadgets["brace"])

	# --- 4. Rook can still open a braced door; the bars go with it.
	door.open()
	await _wait(1.0)
	var bar: Node3D = door.braces[0].node
	_check("braced door opens for Rook", door.passable())
	_check("braces slide with the door", bar.get_parent() == door.slab and bar.global_position.distance_to(Vector3(dc.x, bar.global_position.y, dc.y)) > 0.5)
	door.close()
	while door.state != Door.CLOSED:
		await get_tree().process_frame

	# --- 5. The Hunter: 6 s per brace, each snaps off, then the door breaks.
	_stand(w, near + n, dc)
	w._spawn_hunter()
	var h: Hunter = w.hunter
	var far := door.tile - n
	h.tile = far
	h.target = far
	h.pos = Vector2(far) + Vector2(0.5, 0.5)
	w._rebuild_hunt_field()
	var start := -1.0
	var snaps := []
	var broke_at := -1.0
	var shot_bash := false
	var shot_snap := false
	var landed := []   # per snapped brace: was it lying on the floor 1.5 s later?
	var pieces := []   # the debris entry each snap produced
	var timeout: float = Game.level_time + 30.0
	while Game.level_time < timeout:
		await get_tree().process_frame
		if start < 0.0 and h.bash_door == door:
			start = Game.level_time
		if start < 0.0:
			continue
		var el: float = Game.level_time - start
		if not is_instance_valid(door) or not w.doors.has(door.tile):
			broke_at = el
			break
		if not shot_bash and el > 1.0:
			shot_bash = true
			await _shot("brace_4_hunter_bashing")
		if snaps.size() < 2 - door.brace_count():
			snaps.append(el)
			pieces.append(w.brace_debris.back() if not w.brace_debris.is_empty() else {})
			if not shot_snap:
				shot_snap = true
				await _wait(0.25)
				await _shot("brace_5_snapped")
		if landed.size() < snaps.size() and el > snaps[landed.size()] + 1.5:
			var piece: Dictionary = pieces[landed.size()]
			landed.append(not piece.is_empty() and is_instance_valid(piece.node) and piece.node.position.y < 0.1
				and piece.node.position.distance_to(Vector3(dc.x, 0.06, dc.y)) > 0.3)
		pass
	_check("hunter: starts battering the braced door", start >= 0.0)
	_check("hunter: door holds past the unbraced 2.5 s", broke_at < 0.0 or broke_at > 5.0, "broke at %.1f" % broke_at)
	_check("hunter: first brace snaps at ~6 s", snaps.size() >= 1 and absf(snaps[0] - 6.0) < 0.5, "snaps %s" % str(snaps))
	_check("hunter: second brace snaps at ~12 s", snaps.size() >= 2 and absf(snaps[1] - 12.0) < 0.5, "snaps %s" % str(snaps))
	_check("hunter: door breaks at ~14.5 s", absf(broke_at - 14.5) < 0.6, "broke at %.1f" % broke_at)
	_check("snapped braces were thrown to the floor", landed == [true, true], "landed %s" % str(landed))
	await _wait(0.3)
	await _shot("brace_6_door_broken")


# ================================================================ shared helpers

func _ready_world():
	while main.state != "playing" or main.world == null:
		await get_tree().process_frame
	var w = main.world
	w.hunter_delay = 99999.0   # the Hunter only comes when a test calls it
	await _frames(3)
	return w


## Remove any Hunter so a test can spawn a fresh one.
func _reset_hunter(w) -> void:
	if w.hunter != null:
		w.enemies.erase(w.hunter)
		w.hunter.queue_free()
		w.hunter = null
	w.hunter_done = false


func _spawn_hunter_at(w, t: Vector2i) -> Hunter:
	_reset_hunter(w)
	w._spawn_hunter()
	var h: Hunter = w.hunter
	h.tile = t
	h.target = t
	h.pos = Vector2(t) + Vector2(0.5, 0.5)
	w._rebuild_hunt_field()
	return h


## Move guard `e` onto tile `t` and give it plenty of HP to measure damage.
func _place_guard(w, e: Enemy, t: Vector2i) -> void:
	w.release(e.tile, e)
	w.release(e.target, e)
	e.tile = t
	e.target = t
	e.pos = Vector2(t) + Vector2(0.5, 0.5)
	e.hp = 999
	e.max_hp = 999


func _free_tile(w, q: Vector2i) -> bool:
	if not w.in_bounds(q) or w._is_wall(q) or w.doors.has(q) or w.blockers[w._i(q)] != 0 or w.pushwall_at(q) != null:
		return false
	for e in w.enemies:
		if e.is_alive() and (e.tile == q or e.target == q):
			return false
	return true


## `n` free tiles in a straight line with nothing alive near it (the corridor
## a test plays out in). Returns [start, dir] or [].
func _find_line(w, n: int, avoid := 1.0) -> Array:
	for y in w.height:
		for x in w.width:
			for dir in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var ok := true
				for k in n:
					if not _free_tile(w, Vector2i(x, y) + dir * k):
						ok = false
						break
				if not ok:
					continue
				var mid := Vector2(Vector2i(x, y) + dir * (n / 2)) + Vector2(0.5, 0.5)
				for e in w.enemies:
					if e.is_alive() and e.pos.distance_to(mid) < avoid + n / 2.0:
						ok = false
						break
				if ok:
					return [Vector2i(x, y), dir]
	return []


func _guard(w) -> Enemy:
	for e in w.enemies:
		if e.is_alive() and e != w.hunter and not e.is_boss and e.kind in ["sentry", "hound", "warden"]:
			return e
	return null


# ================================================================ rocket

func _rocket_tests() -> void:
	var w = await _ready_world()
	_reset_hunter(w)

	# --- 1. None crafted: refused.
	Game.gadgets["rocket"] = 0
	_check("rocket: refused with none crafted", not w.use_gadget("rocket") and w.rockets.is_empty())

	var line := _find_line(w, 6)
	_check("rocket: found a test corridor", not line.is_empty())
	if line.is_empty():
		return
	var a: Vector2i = line[0]
	var dir: Vector2i = line[1]
	var ahead := Vector2(a + dir * 5) + Vector2(0.5, 0.5)
	Game.gadgets["rocket"] = 3

	# --- 2. Empty corridor: flies, then blows up at the end of its flight.
	_stand(w, a, ahead)
	await _frames(2)
	var fx_before: int = w.effects.size()
	_check("rocket: fired", w.use_gadget("rocket") and w.rockets.size() == 1)
	_check("rocket: one spent", int(Game.gadgets["rocket"]) == 2, "have %d" % Game.gadgets["rocket"])
	await _wait(0.1)
	var flew: bool = not w.rockets.is_empty() and w.rockets[0].pos.distance_to(w.player.pos) > 0.6
	_check("rocket: flies down the corridor", flew)
	await _shot("rocket_1_in_flight")
	var t0: float = Game.level_time
	while not w.rockets.is_empty() and Game.level_time - t0 < 5.0:
		await get_tree().process_frame
	_check("rocket: explodes at the end of its flight", w.rockets.is_empty() and w.effects.size() > fx_before)
	await _shot("rocket_2_wall_blast")

	# --- 3. A guard in the way takes exactly 60.
	var g := _guard(w)
	_check("rocket: found a guard to test on", g != null)
	if g != null:
		_place_guard(w, g, a + dir * 4)
		_stand(w, a, Vector2(a + dir * 4) + Vector2(0.5, 0.5))
		await _frames(2)
		w.use_gadget("rocket")
		await _wait(1.0)
		_check("rocket: guard takes 60 damage", g.hp == 999 - 60, "hp %d" % g.hp)
		g.take_damage(9999, true)   # out of the way of the next test
		await _wait(0.6)

	# --- 4. The Hunter: scrapped for the floor.
	var h := _spawn_hunter_at(w, a + dir * 5)
	_stand(w, a, h.pos)
	await _frames(2)
	var score0: int = Game.score
	var scrap0: int = Game.scrap
	var items0: int = w.items.size()
	w.use_gadget("rocket")
	await _wait(0.12)
	await _shot("rocket_3_at_hunter")
	await _wait(0.6)
	_check("rocket: Hunter scrapped", not h.is_alive() and w.hunter_done)
	var want := int(round(5000 * Game.score_mult))
	_check("rocket: +5000 score (x%.1f in this protocol)" % Game.score_mult, Game.score - score0 == want, "+%d, want +%d" % [Game.score - score0, want])
	_check("rocket: +3 scrap", Game.scrap - scrap0 == 3, "+%d" % (Game.scrap - scrap0))
	var drop := false
	for i in range(items0, w.items.size()):
		if w.items[i].type == "ammo" and w.items[i].pos.distance_to(h.pos) < 1.0:
			drop = true
	_check("rocket: Hunter drops ammo", drop)
	await _shot("rocket_4_hunter_scrapped")
	await _wait(2.0)
	_check("rocket: Hunter stays gone", w.hunter_done and not h.is_alive())


# ================================================================ mine

func _mine_tests() -> void:
	var w = await _ready_world()
	_reset_hunter(w)
	for m in w.mines.duplicate():
		w._remove_mine(m)
	var line := _find_line(w, 6)
	_check("mine: found a test corridor", not line.is_empty())
	if line.is_empty():
		return
	var a: Vector2i = line[0]
	var dir: Vector2i = line[1]
	var far := Vector2(a + dir * 5) + Vector2(0.5, 0.5)
	Game.gadgets["mine"] = 4

	# --- 1. Drop one under Rook; a second on the same tile is refused.
	_stand(w, a + dir * 2, far)
	await _frames(2)
	_check("mine: dropped under Rook", w.use_gadget("mine") and w.mines.size() == 1 and w.mines[0].tile == a + dir * 2)
	_check("mine: one spent", int(Game.gadgets["mine"]) == 3, "have %d" % Game.gadgets["mine"])
	_check("mine: second on the same tile refused", not w.use_gadget("mine") and w.mines.size() == 1 and int(Game.gadgets["mine"]) == 3)
	_stand(w, a, Vector2(a + dir * 2) + Vector2(0.5, 0.5))
	await _shot("mine_1_armed")

	# --- 2. A guard walks onto it: exactly 40 damage, mine used up.
	var g := _guard(w)
	_check("mine: found a guard to test on", g != null)
	if g != null:
		_place_guard(w, g, a + dir * 2)
		await _wait(0.1)
		_check("mine: guard takes 40 damage", g.hp == 999 - 40, "hp %d" % g.hp)
		_check("mine: used up by the guard", w.mines.is_empty())
		g.take_damage(9999, true)
		await _wait(0.6)

	# --- 3 + 4. Two mines in the Hunter's path: the first stuns it for 6 s,
	# the second waits until it walks on, then stuns it again.
	_stand(w, a + dir * 2, far)
	await _frames(2)
	w.use_gadget("mine")
	_stand(w, a + dir * 3, far)
	await _frames(2)
	w.use_gadget("mine")
	_check("mine: two armed in the corridor", w.mines.size() == 2)
	_stand(w, a, far)
	var h := _spawn_hunter_at(w, a + dir * 5)
	var stuns := []        # time each stun began
	var unstun := -1.0
	var was := false
	var shot_stun := false
	var mines_during := -1
	var t0: float = Game.level_time
	while Game.level_time - t0 < 20.0 and stuns.size() < 2:
		await get_tree().process_frame
		var el: float = Game.level_time - t0
		var now: bool = h.is_stunned()
		if now and not was:
			stuns.append(el)
		if was and not now and unstun < 0.0:
			unstun = el
		if now and stuns.size() == 1 and el > stuns[0] + 3.0 and mines_during < 0:
			mines_during = w.mines.size()
		if now and not shot_stun and stuns.size() == 1 and el > stuns[0] + 0.3:
			shot_stun = true
			await _shot("mine_2_hunter_stunned")
		was = now
	_check("mine: Hunter sets off the first mine", stuns.size() >= 1, "stuns %s" % str(stuns))
	_check("mine: stun lasts 6 s", stuns.size() >= 1 and absf(unstun - stuns[0] - 6.0) < 0.3, "stunned at %s, free at %.2f" % [str(stuns), unstun])
	_check("mine: second mine waits while the Hunter is stunned", mines_during == 1, "mines left mid-stun %d" % mines_during)
	_check("mine: second mine stuns it again once it walks on", stuns.size() == 2 and stuns[1] > unstun and stuns[1] - unstun < 2.0, "stuns %s, free at %.2f" % [str(stuns), unstun])
	_check("mine: both mines used up", w.mines.is_empty())
	_reset_hunter(w)
