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
	await _wait(0.12)
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
