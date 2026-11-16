extends Node
## Top-level game flow: title, the Cell (meta shop), floors, death/respawn,
## tallies, the perk terminal, run over and victory. Owns the 3D viewport,
## the HUD and sound playback.
##
## Debug command-line options (after `--` on the Godot command line):
##   --autostart (classic)  --run (roguelite run)  --seed=N  --level=N
##   --difficulty=N  --god  --alert  --arsenal  --retro  --hold=action[,action]
##   --pos=x,y,deg  --shot=path.png  --shot-after=sec  --quit  --validate
##   --gen-test=N (generate N floors per theme and validate them)

const VIEW_W := 480
const VIEW_H := 230
const WEAPON_SIZE := 170.0

var state := "title"
var world: World = null
var hud: Hud
var viewport: SubViewport
var view_rect: TextureRect
var weapon_rect: TextureRect
var sounds := {}
var god_mode := false
var death_timer := 0.0
var shot_path := ""
var shot_timer := -1.0
var current_level: Dictionary = {}
var pending_perks := 0
var perk_choices: Array[String] = []
var _args := PackedStringArray()
var touch: TouchControls
var _taps: Array = []


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	_setup_input()
	for k in Sfx.KINDS:
		sounds[k] = Sfx.make(k)
	# The 3D view renders into its own viewport whose pixel size depends on
	# the display mode (native resolution for HD, 480x230 for retro), then
	# gets stretched over the top of the screen.
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.audio_listener_enable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	view_rect = TextureRect.new()
	view_rect.texture = viewport.get_texture()
	view_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view_rect.stretch_mode = TextureRect.STRETCH_SCALE
	view_rect.position = Vector2.ZERO
	view_rect.size = Vector2(VIEW_W, VIEW_H)
	view_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view_rect)
	# The first-person weapon is drawn inside the 3D viewport so it gets the
	# same resolution (and pixelation in retro mode) as the world.
	var weapon_layer := CanvasLayer.new()
	viewport.add_child(weapon_layer)
	weapon_rect = TextureRect.new()
	weapon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_rect.stretch_mode = TextureRect.STRETCH_SCALE
	weapon_layer.add_child(weapon_rect)
	get_window().size_changed.connect(_apply_display_mode)
	_apply_display_mode()
	hud = Hud.new()
	add_child(hud)
	Game.message.connect(hud.show_message)
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 3
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.main = self
	touch_layer.add_child(touch)
	if TouchControls.active:
		_apply_display_mode()

	god_mode = "--god" in _args
	if "--retro" in _args:
		Game.retro = true
		_apply_display_mode()
	var start_level := 0
	var seed_override := -1
	for a in _args:
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
			if shot_timer < 0.0:
				shot_timer = 1.5
		elif a.begins_with("--shot-after="):
			shot_timer = float(a.substr(13))
		elif a.begins_with("--level="):
			start_level = maxi(int(a.substr(8)) - 1, 0)
		elif a.begins_with("--seed="):
			seed_override = int(a.substr(7))
		elif a.begins_with("--difficulty="):
			Game.difficulty = clampi(int(a.substr(13)), 0, 2)
		elif a.begins_with("--tap="):
			# --tap=action@seconds[,action@seconds...]: press an action for one frame later on.
			for part in a.substr(6).split(","):
				var bits := part.split("@")
				_taps.append([bits[0], float(bits[1])])
		elif a.begins_with("--hold="):
			for act in a.substr(7).split(","):
				Input.action_press(act)
		elif a.begins_with("--gen-test="):
			_gen_test(int(a.substr(11)))
			get_tree().quit()
			return
	if "--validate" in _args:
		_validate_levels()
		get_tree().quit()
		return
	if "--run" in _args:
		var proto := "escape"
		for a in _args:
			if a.begins_with("--protocol="):
				proto = a.substr(11)
		Game.new_run(proto)
		if seed_override >= 0:
			Game.run_seed = seed_override
			Game.bounty_floor = 1 if Game.protocol == "gauntlet" else seed_override % 2
		Game.level_index = clampi(start_level, 0, Game.RUN_FLOORS.size() - 1)
		load_level()
	elif "--cell" in _args:
		show_cell()
	elif "--perk" in _args:
		Game.new_run()
		pending_perks = 2
		_show_perk_choice()
	elif "--autostart" in _args:
		start_classic(clampi(start_level, 0, Levels.LEVELS.size() - 1))
	else:
		show_title()


func _setup_input() -> void:
	_bind("move_forward", [KEY_W, KEY_UP])
	_bind("move_back", [KEY_S, KEY_DOWN])
	_bind("strafe_left", [KEY_A])
	_bind("strafe_right", [KEY_D])
	_bind("turn_left", [KEY_LEFT])
	_bind("turn_right", [KEY_RIGHT])
	_bind("run", [KEY_SHIFT])
	_bind("fire", [KEY_CTRL], [MOUSE_BUTTON_LEFT])
	_bind("use", [KEY_E, KEY_SPACE], [MOUSE_BUTTON_RIGHT])
	_bind("weapon_1", [KEY_1])
	_bind("weapon_2", [KEY_2])
	_bind("weapon_3", [KEY_3])
	_bind("weapon_4", [KEY_4])
	_bind("pause", [KEY_ESCAPE, KEY_P])
	_bind("confirm", [KEY_ENTER, KEY_KP_ENTER])
	_bind("craft", [KEY_C])
	_bind("gadget_rocket", [KEY_R])
	_bind("gadget_mine", [KEY_F])
	_bind("gadget_brace", [KEY_B])


func _bind(action: String, keys: Array, buttons: Array = []) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var mb := InputEventMouseButton.new()
		mb.button_index = b
		InputMap.action_add_event(action, mb)


# ================================================================ screens

func show_title() -> void:
	_free_world()
	state = "title"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_screen("BASTION BREAK",
		"You are Rook, prisoner 4471 of the Iron Directorate.\n" +
		"Break out of the Bastion, one floor at a time.\n\n" +
		(_touch_help() if TouchControls.active else _keyboard_help()))
	hud.show_title_badge(("NEW!  %s PURGE PROTOCOL: an unkillable Hunter Warden stalks you") %
		("tap" if TouchControls.active else "H -"))


func _keyboard_help() -> String:
	return ("ENTER - new escape run (%s)       C - classic campaign\n" % Game.PROTOCOLS[Game.protocol_choice][0] +
		"\n" +  # the orange Purge line (hud.title_badge) sits here
		"Difficulty:  %s   (press 1 / 2 / 3)\n" % Game.DIFFICULTY_NAMES[Game.difficulty] +
		"WASD / arrows - move & turn     Mouse - turn     Shift - run\n" +
		"Left click / Ctrl - fire     E / Space / right click - open & use\n" +
		"1-4 / mouse wheel - weapons     Tab - map     Esc - pause\n" +
		"F2 - HD / retro pixels (now: %s)     F11 - fullscreen" % ("RETRO" if Game.retro else "HD"))


func _touch_help() -> String:
	return ("Escape run: %s\n\n" % Game.PROTOCOLS[Game.protocol_choice][0] +
		"Difficulty:  %s\n\n" % Game.DIFFICULTY_NAMES[Game.difficulty] +
		"Left thumb: move (push far to run)     Right side: drag to turn\n" +
		"Tap the map to enlarge it")


## Called the first time a touch arrives on a device that wasn't detected
## as touch-driven, so the screens switch to touch help.
func on_touch_activated() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply_display_mode()
	if state == "title":
		show_title()


func _capture_mouse() -> void:
	if not TouchControls.active:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Between runs: Rook's cell, where banked Iron Scrip buys permanent upgrades.
func show_cell() -> void:
	_free_world()
	state = "cell"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var proto: Array = Game.PROTOCOLS[Game.protocol_choice]
	var header := "Iron Scrip: %d          Protocol: %s" % [Game.scrip, proto[0].to_upper()]
	var foot: String = proto[1]
	if Game.protocol_choice == "daily":
		foot += "  Today's best: %d" % Game.daily_best_today()
	if not TouchControls.active:
		foot += "\n1-6 or click: buy     P protocol     ENTER start     Esc back"
	hud.show_cell(header, foot)
	if not hud.upgrade_cards.picked.is_connected(_on_upgrade_card):
		hud.upgrade_cards.picked.connect(_on_upgrade_card)


func _on_upgrade_card(i: int) -> void:
	if state != "cell":
		return
	play_sfx("weapon" if Game.buy_upgrade(Game.UPGRADE_ORDER[i]) else "denied")
	show_cell()


func _show_perk_choice() -> void:
	state = "perk"
	perk_choices = Game.perk_offer()
	if perk_choices.is_empty():
		pending_perks = 0
		_next_level()
		return
	var sub := "Your clean work earned a contraband perk (%d left to pick)." % pending_perks
	var foot := "" if TouchControls.active else "Press 1 - %d or click a card" % perk_choices.size()
	hud.show_perks(sub, perk_choices, foot)
	if not hud.perk_cards.picked.is_connected(_on_perk_card):
		hud.perk_cards.picked.connect(_on_perk_card)


func _on_perk_card(i: int) -> void:
	if state == "perk":
		_pick_perk(i)


func _pick_perk(i: int) -> void:
	if i >= perk_choices.size():
		return
	Game.perks.append(perk_choices[i])
	hud.show_message("Perk gained: " + Game.PERKS[perk_choices[i]][0])
	pending_perks -= 1
	if pending_perks > 0:
		_show_perk_choice()
	else:
		_next_level()


func _pause_text() -> String:
	var t := "Esc - resume\nQ - quit to title\n\nF2 - toggle HD / retro pixels\nF11 - fullscreen\nTab - large map"
	if Game.is_run():
		t += "\n\nProtocol: " + Game.PROTOCOLS[Game.protocol][0]
		if Game.is_protocol("daily"):
			t += "   (multiplier x%.1f)" % Game.score_mult
		t += "\nRun perks: "
		if Game.perks.is_empty():
			t += "none yet"
		else:
			var names := PackedStringArray()
			for p in Game.perks:
				names.append(Game.PERKS[p][0])
			t += ", ".join(names)
		t += "\nIron Scrip this run: %d" % Game.run_scrip
	return t


# ================================================================ flow

func start_classic(level := 0) -> void:
	Game.new_game(level)
	load_level()


func start_run() -> void:
	Game.new_run(Game.protocol_choice)
	load_level()


func level_count() -> int:
	return Game.run_floor_count() if Game.is_run() else Levels.LEVELS.size()


func _level_for(index: int) -> Dictionary:
	if not Game.is_run():
		return Levels.LEVELS[index]
	var theme: String = Game.run_floor_theme(index)
	if theme == "boss":
		return Levels.LEVELS[2]
	var opts := {
		"index": index,
		"bounty": index == Game.bounty_floor,
		"locker": index < 2 and Game.protocol in ["escape", "ghost", "daily"],
	}
	var lvl := LevelGen.generate(theme, Game.run_seed + index * 1013, opts)
	if Game.protocol == "gauntlet":
		lvl = lvl.duplicate()
		lvl.name = "Sector %d" % (index + 1)
	return lvl


func load_level() -> void:
	_free_world()
	Game.begin_level()
	var floor_note := ""
	if Game.is_protocol("scramble"):
		Game.scramble_loadout()
		floor_note = "Prototypes issued: %s, %s, %s" % [Game.WEAPONS[Game.weapon_id(1)].name, Game.WEAPONS[Game.weapon_id(2)].name, Game.WEAPONS[Game.weapon_id(3)].name]
	if Game.locker_pending:
		Game.locker_pending = false
		Game.give_weapon(Game.Weapon.RIFLE, 0, "masterwork")
		floor_note = "The locker returned a MASTERWORK AUTO RIFLE"
	current_level = _level_for(Game.level_index)
	world = World.new()
	world.name = "World"
	world.main = self
	viewport.add_child(world)
	world.build(current_level)
	for a in _args:
		if a.begins_with("--pos="):
			var p := a.substr(6).split(",")
			world.player.pos = Vector2(float(p[0]), float(p[1]))
			world.player.angle = deg_to_rad(float(p[2]))
	for a in _args:
		if a.begins_with("--scrap="):
			Game.scrap = int(a.substr(8))
		elif a == "--gadgets":
			Game.gadgets = {"rocket": 2, "mine": 2, "brace": 2}
		elif a == "--craft":
			_open_craft.call_deferred()
	for a in _args:
		if a.begins_with("--goto="):
			print("goto ", a.substr(7), ": ", world.debug_goto(a.substr(7)))
	if "--quit" in _args and shot_path == "":
		get_tree().quit.call_deferred()
	if "--alert" in _args:
		world.alert_all()
	if "--arsenal" in _args:
		for s in 4:
			Game.give_weapon(s, 0)
		for a in _args:
			if a.begins_with("--give="):
				for id in a.substr(7).split(","):
					Game.give_weapon(Game.WEAPONS[id].slot, 0, id)
		Game.ammo = Game.max_ammo()
		Game.current_weapon = Game.Weapon.ROTARY
	state = "playing"
	hud.hide_screen()
	hud.death_alpha = 0.0
	_capture_mouse()
	hud.show_message("FLOOR %d: %s" % [Game.level_index + 1, world.level_name.to_upper()])
	if floor_note != "":
		get_tree().create_timer(2.6).timeout.connect(func(): if world != null: hud.show_message(floor_note))


func _free_world() -> void:
	if world != null:
		viewport.remove_child(world)
		world.queue_free()
		world = null


func on_player_died() -> void:
	state = "dying"
	death_timer = 2.2
	play_sfx("player_die")


func _after_death() -> void:
	if Game.lives > 0:
		Game.lives -= 1
		if Game.is_run():
			# Roguelite: a clone wakes at the floor start with Rook's gear.
			world.respawn_player()
			state = "playing"
			hud.death_alpha = 0.0
			hud.show_message("Clone vat: Rook is back. Lives left: %d" % Game.lives)
		else:
			Game.restart_after_death()
			load_level()
	elif Game.is_run():
		Game.save_meta()
		state = "runover"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_screen("RUN OVER",
			"%s: Rook fell on floor %d.\n\nScore: %d%s\nIron Scrip earned this run: %d   (banked: %d)\n\nPress ENTER to return to the Cell" %
			[Game.PROTOCOLS[Game.protocol][0], Game.level_index + 1, Game.score, _daily_line(), Game.run_scrip, Game.scrip])
	else:
		state = "gameover"
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_screen("GAME OVER", "The Directorate keeps its prisoners.\n\nFinal score: %d\n\nPress ENTER" % Game.score)


func on_level_exit() -> void:
	state = "tally"
	var kp := _pct(Game.kills, Game.kills_total)
	var sp := _pct(Game.secrets, Game.secrets_total)
	var tp := _pct(Game.treasure, Game.treasure_total)
	var hp := _pct(Game.hostages, Game.hostages_total)
	var par: int = current_level.get("par", 120)
	var t := int(Game.level_time)
	var bonus := 0
	var perfect := 0
	for p in [kp, sp, tp, hp]:
		if p >= 100:
			bonus += 10000
			perfect += 1
	if t < par:
		bonus += (par - t) * 50
		perfect += 1
	Game.add_score(bonus)
	var extra := ""
	if Game.is_run():
		Game.earn_scrip(10 + perfect * 10)
		Game.save_meta()
		pending_perks = perfect + Game.bonus_perks
		Game.bonus_perks = 0
		if Game.is_protocol("gauntlet") and (Game.level_index + 1) % 2 == 0:
			pending_perks += 1
		extra = "\nIron Scrip this floor: %d" % Game.floor_scrip
		if perfect > 0:
			extra += "\nPerfect categories: %d" % perfect
		if pending_perks > 0:
			extra += "\nPerk picks: %d" % pending_perks
	hud.show_screen("FLOOR %d CLEARED" % (Game.level_index + 1),
		"Kills       %3d%%   (%d / %d)\nSecrets     %3d%%   (%d / %d)\nTreasure    %3d%%   (%d / %d)\nHostages    %3d%%   (%d / %d freed%s)\n\n" % [
			kp, Game.kills, Game.kills_total, sp, Game.secrets, Game.secrets_total, tp, Game.treasure, Game.treasure_total,
			hp, Game.hostages, Game.hostages_total, ", %d lost" % Game.hostages_lost if Game.hostages_lost > 0 else ""] +
		"Time  %d:%02d     Par  %d:%02d\n" % [t / 60, t % 60, par / 60, par % 60] +
		"Bonus  %d     Score  %d%s\n\nPress ENTER to continue" % [bonus, Game.score, extra], true)


## Daily Lockdown: records the score and returns a line for the end screen.
func _daily_line() -> String:
	if not Game.is_protocol("daily"):
		return ""
	var best := Game.record_daily_score()
	return "   (x%.1f multiplier)\n%s today's best: %d" % [Game.score_mult, "NEW" if best else "", Game.daily_best_today()]


func _pct(a: int, b: int) -> int:
	return 100 if b == 0 else int(round(100.0 * a / b))


func _next_level() -> void:
	Game.level_index += 1
	if Game.level_index < level_count():
		load_level()
		return
	_free_world()
	state = "victory"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if Game.is_run():
		Game.earn_scrip(50)
		Game.save_meta()
		var how := "Every hostage is free and Rook slips out unseen." if Game.is_protocol("ghost") else "The Overseer has fallen and Rook walks free."
		hud.show_screen("ESCAPED!",
			"%s\n\nScore: %d%s\nIron Scrip earned this run: %d   (banked: %d)\n\nPress ENTER to return to the Cell" %
			[how, Game.score, _daily_line(), Game.run_scrip, Game.scrip])
	else:
		hud.show_screen("YOU BROKE OUT!",
			"The Overseer has fallen and Rook walks free.\n\nFinal score: %d\n\nPress ENTER" % Game.score)


func _validate_levels() -> void:
	for i in Levels.LEVELS.size():
		var errs := Levels.validate(Levels.LEVELS[i])
		if errs.is_empty():
			print("Level %d OK" % (i + 1))
		else:
			for e in errs:
				printerr("Level %d: %s" % [i + 1, e])


func _gen_test(n: int) -> void:
	for theme in LevelGen.THEMES:
		var ok := 0
		var fallback := 0
		var counts := {"range": 0, "puzzle": 0, "lockins": 0, "standoff": 0, "C": 0, "L": 0, "K": 0}
		for i in n:
			var lvl := LevelGen.generate(theme, 1000 + i * 31, {"index": i % 6, "bounty": i % 2 == 0, "locker": true})
			if not lvl.has("seed"):
				fallback += 1
			elif Levels.validate(lvl).is_empty():
				ok += 1
			for k in ["range", "puzzle", "lockins"]:
				if lvl.has(k):
					counts[k] += 1
			var text := "".join(PackedStringArray(lvl.map))
			for k in ["C", "L", "K"]:
				if text.contains(k):
					counts[k] += 1
		print("%s: %d / %d valid, %d fallbacks, features %s" % [theme, ok, n, fallback, counts])
	var sample := LevelGen.generate("foundry", 1234, {"bounty": true, "locker": true})
	for row in sample.map:
		print(row)
	print(sample.get("range"), " ", sample.get("puzzle"), " ", sample.get("lockins"))


# ================================================================ loop & input

func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	for tp in _taps.duplicate():
		tp[1] -= delta
		if tp[1] <= 0.0:
			if Input.is_action_pressed(tp[0]):
				Input.action_release(tp[0])
				_taps.erase(tp)
			else:
				Input.action_press(tp[0])
				tp[1] = 0.05
	match state:
		"playing":
			if Game.is_protocol("purge") and Input.is_action_just_pressed("craft"):
				_open_craft()
			else:
				if Game.is_protocol("purge"):
					for id in Game.GADGET_ORDER:
						if Input.is_action_just_pressed("gadget_" + id):
							world.use_gadget(id)
				world.tick(delta)
		"dying":
			world.tick(delta)
			death_timer -= delta
			hud.death_alpha = clampf(1.0 - death_timer / 2.2, 0.0, 0.85)
			if death_timer <= 0.0:
				_after_death()
	_update_weapon()
	hud.tick(delta, world)
	hud.refresh()
	if shot_timer > 0.0:
		shot_timer -= delta
		if shot_timer <= 0.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			print("Saved screenshot to ", shot_path)
			if "--quit" in _args:
				get_tree().quit()


## Sizes the 3D viewport for HD (native pixels) or retro (480x230) mode.
func _apply_display_mode() -> void:
	var win := Vector2(get_window().size)
	var s := maxf(1.0, minf(win.x / 480.0, win.y / 270.0))
	if TouchControls.active:
		s = minf(s, 2.0)  # phones: cap the 3D render size to keep the frame rate up
	if Game.retro:
		viewport.size = Vector2i(VIEW_W, VIEW_H)
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		weapon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		viewport.size = Vector2i(roundi(VIEW_W * s), roundi(VIEW_H * s))
		viewport.msaa_3d = Viewport.MSAA_4X
		view_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		weapon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if world != null:
		world.apply_filter()


func toggle_retro() -> void:
	Game.retro = not Game.retro
	Game.save_settings()
	_apply_display_mode()
	hud.show_message("Display: " + ("RETRO PIXELS" if Game.retro else "HD"))


func _update_weapon() -> void:
	var show := world != null and state in ["playing", "dying", "paused", "tally", "perk"] and not world.player.dead
	weapon_rect.visible = show
	if not show:
		return
	weapon_rect.texture = Tex.tex("w_%s_%d" % [Game.weapon_id(), world.player.weapon_frame()])
	var k := viewport.size.y / float(VIEW_H)
	var bob := world.player.bob
	var off := Vector2(cos(bob * 0.5) * 6.0, absf(sin(bob * 0.5)) * 6.0) if world.player.moving and state == "playing" else Vector2.ZERO
	weapon_rect.size = Vector2(WEAPON_SIZE, WEAPON_SIZE) * k
	weapon_rect.position = (Vector2(VIEW_W / 2.0 - WEAPON_SIZE / 2.0, VIEW_H - WEAPON_SIZE + 4.0) + off) * k


func _number_pressed(event: InputEvent) -> int:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return -1
	var k: int = event.physical_keycode
	if k >= KEY_1 and k <= KEY_9:
		return k - KEY_1
	return -1


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F2:
			toggle_retro()
		elif event.physical_keycode == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.physical_keycode == KEY_TAB and world != null:
			hud.minimap.toggle_size()
	if state == "playing":
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			world.player.turn(event.relative.x * world.player.mouse_sens)
		elif event is InputEventMouseButton and event.pressed:
			if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_capture_mouse()
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				world.player.cycle_weapon(-1)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				world.player.cycle_weapon(1)
	var num := _number_pressed(event)
	match state:
		"title":
			if event.is_action_pressed("confirm"):
				show_cell()
			elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_C:
				start_classic(0)
			elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
				# Shortcut to the Purge Protocol: pick it and go to the Cell.
				Game.protocol_choice = "purge"
				Game.save_settings()
				play_sfx("pickup")
				show_cell()
			elif num >= 0 and num < 3:
				Game.difficulty = num
				Game.save_settings()
				show_title()
		"cell":
			if event.is_action_pressed("confirm"):
				start_run()
			elif event.is_action_pressed("pause"):
				show_title()
			elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_P:
				var order := Game.PROTOCOL_ORDER
				Game.protocol_choice = order[(order.find(Game.protocol_choice) + 1) % order.size()]
				Game.save_settings()
				play_sfx("pickup")
				show_cell()
			elif num >= 0 and num < Game.UPGRADE_ORDER.size():
				if Game.buy_upgrade(Game.UPGRADE_ORDER[num]):
					play_sfx("weapon")
				else:
					play_sfx("denied")
				show_cell()
		"perk":
			if num >= 0:
				_pick_perk(num)
		"craft":
			if num >= 0 and num < Game.GADGET_ORDER.size():
				_craft(num)
			elif event.is_action_pressed("pause") or event.is_action_pressed("craft"):
				_close_craft()
		"playing":
			if event.is_action_pressed("pause"):
				state = "paused"
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				hud.show_screen("PAUSED", _pause_text())
		"paused":
			if event.is_action_pressed("pause"):
				state = "playing"
				hud.hide_screen()
				_capture_mouse()
			elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_Q:
				if Game.is_run():
					Game.save_meta()
				show_title()
		"tally":
			if event.is_action_pressed("confirm"):
				if Game.is_run() and pending_perks > 0:
					_show_perk_choice()
				else:
					_next_level()
		"runover":
			if event.is_action_pressed("confirm"):
				show_cell()
		"gameover":
			if event.is_action_pressed("confirm"):
				show_title()
		"victory":
			if event.is_action_pressed("confirm"):
				if Game.is_run():
					show_cell()
				else:
					show_title()


# ---------------------------------------------------------------- purge workbench

func _open_craft() -> void:
	state = "craft"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_craft()
	if not hud.craft_cards.picked.is_connected(_on_craft_card):
		hud.craft_cards.picked.connect(_on_craft_card)


func _show_craft() -> void:
	var foot := "" if TouchControls.active else "1-3 or click: craft     C / Esc: back to the hunt"
	hud.show_craft("Scrap: %d      (guards drop scrap when they die)" % Game.scrap, foot)


func _craft(i: int) -> void:
	var id: String = Game.GADGET_ORDER[i]
	if Game.craft(id):
		play_sfx("craft")
		hud.show_message("Crafted a %s" % Game.GADGETS[id][0])
	else:
		play_sfx("denied")
	_show_craft()


func _on_craft_card(i: int) -> void:
	if state == "craft":
		_craft(i)


func _close_craft() -> void:
	state = "playing"
	hud.hide_screen()
	_capture_mouse()


## A non-positional sound at a set volume (the Hunter's footsteps).
func play_sfx_db(sfx_name: String, db: float) -> void:
	if not sounds.has(sfx_name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = sounds[sfx_name]
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_sfx(sfx_name: String, at = null) -> void:
	if not sounds.has(sfx_name):
		return
	if at == null or world == null:
		var p := AudioStreamPlayer.new()
		p.stream = sounds[sfx_name]
		p.volume_db = -6.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	else:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = sounds[sfx_name]
		p3.unit_size = 5.0
		p3.max_distance = 40.0
		p3.position = Vector3(at.x, 0.5, at.y)
		world.add_child(p3)
		p3.finished.connect(p3.queue_free)
		p3.play()
