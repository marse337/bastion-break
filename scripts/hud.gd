class_name Hud
extends CanvasLayer
## Status bar, first-person weapon, screen flashes, messages and the
## full-screen panels (title, pause, floor tally, game over).

const W := 480
const H := 270
const BAR_Y := 230

var values := {}
var minimap: Minimap
var damage_rect: ColorRect
var pickup_rect: ColorRect
var msg: Label
var key_red: ColorRect
var key_blue: ColorRect
var key_gold: ColorRect
var boss_panel: Control
var boss_fill: ColorRect
var boss_label: Label
var score_cap: Label
const BOSS_W := 220.0
var screen: ColorRect
var screen_title: Label
var screen_body: Label
var screen_foot: Label
var mode_select: ModeSelect
var perk_cards: PerkCards
var upgrade_cards: UpgradeCards
var craft_cards: CraftCards
var gadget_label: Label
var _world: World = null
var dmg_alpha := 0.0
var pick_alpha := 0.0
var death_alpha := 0.0
var _msg_t := 0.0


func _ready() -> void:
	layer = 1
	var root := Control.new()
	root.size = Vector2(W, H)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_rect = _rect(root, Vector2.ZERO, Vector2(W, BAR_Y), Color(0.8, 0, 0, 0))
	pickup_rect = _rect(root, Vector2.ZERO, Vector2(W, BAR_Y), Color(1, 0.85, 0.3, 0))

	minimap = Minimap.new()
	root.add_child(minimap)

	msg = _label(root, Vector2(0, 6), Vector2(W, 16), 12, Color(1, 0.9, 0.5))
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_rect(root, Vector2(0, BAR_Y), Vector2(W, H - BAR_Y), Color(0.1, 0.12, 0.18))
	_rect(root, Vector2(0, BAR_Y), Vector2(W, 2), Color(0.38, 0.44, 0.56))
	var sections := [["FLOOR", 0, 46], ["SCORE", 46, 96], ["LIVES", 142, 50], ["HEALTH", 192, 76], ["AMMO", 268, 56], ["KEYS", 324, 52], ["WEAPON", 376, 104]]
	for s in sections:
		var x: int = s[1]
		var w: int = s[2]
		if x > 0:
			_rect(root, Vector2(x, BAR_Y + 4), Vector2(1, H - BAR_Y - 8), Color(0.3, 0.35, 0.45))
		var cap := _label(root, Vector2(x, BAR_Y + 4), Vector2(w, 10), 8, Color(0.55, 0.65, 0.8))
		cap.text = s[0]
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if s[0] == "SCORE":
			score_cap = cap
		var val := _label(root, Vector2(x, BAR_Y + 14), Vector2(w, 22), 16 if s[0] != "WEAPON" else 11, Color.WHITE)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		values[s[0]] = val
	key_red = _rect(root, Vector2(329, BAR_Y + 18), Vector2(13, 12), Color.RED)
	key_blue = _rect(root, Vector2(344, BAR_Y + 18), Vector2(13, 12), Color.BLUE)
	key_gold = _rect(root, Vector2(359, BAR_Y + 18), Vector2(13, 12), Color.GOLD)

	boss_panel = Control.new()
	boss_panel.position = Vector2((W - BOSS_W) / 2.0, 24)
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(boss_panel)
	boss_label = _label(boss_panel, Vector2(0, -2), Vector2(BOSS_W, 10), 8, Color(1, 0.75, 0.6))
	boss_label.text = "THE OVERSEER"
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(boss_panel, Vector2(0, 10), Vector2(BOSS_W, 7), Color(0.05, 0.02, 0.02, 0.85))
	boss_fill = _rect(boss_panel, Vector2(1, 11), Vector2(BOSS_W - 2, 5), Color(0.85, 0.12, 0.08))
	boss_panel.visible = false

	# Purge Protocol: scrap and gadgets, just above the status bar.
	gadget_label = _label(root, Vector2(4, BAR_Y - 13), Vector2(W - 8, 12), 8, Color(0.95, 0.85, 0.6))
	gadget_label.visible = false

	screen = _rect(root, Vector2.ZERO, Vector2(W, H), Color(0.03, 0.03, 0.05, 0.94))
	screen_title = _label(screen, Vector2(0, 30), Vector2(W, 40), 30, Color(1, 0.55, 0.15))
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_body = _label(screen, Vector2(20, 80), Vector2(W - 40, 180), 11, Color(0.85, 0.88, 0.95))
	screen_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	screen_foot = _label(screen, Vector2(0, H - 42), Vector2(W, 14), 10, Color(0.85, 0.88, 0.95))
	screen_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Title screen: game mode dropdown and PLAY button. Added last so its
	# open list draws over the help text.
	mode_select = ModeSelect.new()
	screen.add_child(mode_select)
	perk_cards = PerkCards.new()
	perk_cards.position.y = 58
	screen.add_child(perk_cards)
	craft_cards = CraftCards.new()
	craft_cards.position.y = 58
	screen.add_child(craft_cards)
	upgrade_cards = UpgradeCards.new()
	upgrade_cards.position.y = 54
	screen.add_child(upgrade_cards)
	screen.visible = false


func _rect(parent: Control, p: Vector2, s: Vector2, c: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = p
	r.size = s
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _label(parent: Control, p: Vector2, s: Vector2, font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.position = p
	l.size = s
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func refresh() -> void:
	values.FLOOR.text = str(Game.level_index + 1)
	values.SCORE.text = "%06d" % Game.score
	values.LIVES.text = str(Game.lives)
	values.HEALTH.text = "%d%%" % Game.health
	values.HEALTH.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if Game.health <= 25 else Color.WHITE)
	var calib := _world != null and _world.range_state == 1
	values.AMMO.text = ("%d CAL" % _world.range_ammo) if calib else str(Game.ammo)
	values.WEAPON.text = Game.weapon_name()
	score_cap.text = "SCORE  x%.1f" % Game.score_mult if Game.is_protocol("daily") else "SCORE"
	key_red.color = Color(0.95, 0.15, 0.1) if Game.keys.red else Color(0.2, 0.08, 0.08)
	key_blue.color = Color(0.2, 0.45, 1.0) if Game.keys.blue else Color(0.07, 0.09, 0.2)
	key_gold.color = Color(1.0, 0.78, 0.15) if Game.keys.gold else Color(0.2, 0.16, 0.05)


func tick(delta: float, world: World) -> void:
	_world = world
	minimap.tick(delta, world)
	var b: Enemy = world.boss if world != null else null
	if world != null and (b == null or not b.is_alive()) and world.crimson != null and world.crimson.is_alive():
		b = world.crimson
	boss_panel.visible = b != null and b.state != Enemy.IDLE and b.is_alive()
	if boss_panel.visible:
		boss_label.text = b.display_name()
		if world.range_state == 1:
			boss_panel.visible = false
		boss_fill.size.x = (BOSS_W - 2.0) * clampf(float(b.hp) / b.max_hp, 0.0, 1.0)
	boss_fill.color = Color(0.85, 0.12, 0.08)
	var purge := world != null and Game.is_protocol("purge")
	if purge and not boss_panel.visible and world.range_state != 1:
		_purge_bar(world)
	gadget_label.visible = purge and not world.player.dead
	if gadget_label.visible:
		var keys := not TouchControls.active
		var parts := ["SCRAP %d" % Game.scrap]
		for id in Game.GADGET_ORDER:
			var g: Array = Game.GADGETS[id]
			parts.append(("%s %s %d" % [g[2], g[0].split(" ")[1].to_upper(), int(Game.gadgets[id])]) if keys else ("%s %d" % [g[0].split(" ")[1].to_upper(), int(Game.gadgets[id])]))
		if keys:
			parts.append("C craft")
		gadget_label.text = "    ".join(parts)
	dmg_alpha = maxf(0.0, dmg_alpha - delta * 1.8)
	pick_alpha = maxf(0.0, pick_alpha - delta * 2.5)
	damage_rect.color.a = maxf(dmg_alpha, death_alpha)
	pickup_rect.color.a = pick_alpha
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			msg.text = ""


## Purge Protocol bar: countdown to the Hunter's release, then its stun meter.
func _purge_bar(world: World) -> void:
	var h: Hunter = world.hunter
	if world.hunter_done:
		return
	boss_panel.visible = true
	if h == null:
		var left := maxf(0.0, world.hunter_delay - world.hunter_clock)
		boss_label.text = "HUNTER RELEASED IN %d:%02d" % [int(left) / 60, int(left) % 60]
		boss_fill.size.x = (BOSS_W - 2.0) * clampf(left / world.hunter_delay, 0.0, 1.0)
		boss_fill.color = Color(0.9, 0.55, 0.1) if left > 10.0 else Color(1.0, 0.15, 0.1)
		return
	if not h.is_alive():
		boss_panel.visible = false
		return
	if h.is_stunned():
		boss_label.text = "HUNTER STUNNED - GO!"
		boss_fill.size.x = (BOSS_W - 2.0) * clampf(h.stun_t / h.stun_len, 0.0, 1.0)
		boss_fill.color = Color(0.3, 0.75, 1.0)
	else:
		var tag := "  (ENRAGED)" if h.rage_t > 0.0 else ""
		if h.bash_door != null:
			tag = "  (BREAKING A DOOR)"
		boss_label.text = "HUNTER WARDEN - STUN METER" + tag
		boss_fill.size.x = (BOSS_W - 2.0) * clampf(h.stun_dmg / Hunter.STUN_AT, 0.0, 1.0)
		boss_fill.color = Color(1.0, 0.8, 0.2)


func flash_damage(amount: int) -> void:
	dmg_alpha = clampf(dmg_alpha + 0.15 + amount * 0.02, 0.0, 0.6)


func flash_pickup() -> void:
	pick_alpha = 0.3


func show_message(text: String) -> void:
	if "--debug-hunter" in OS.get_cmdline_user_args():
		print("MSG ", text)
	msg.text = text
	_msg_t = 2.5


## Full-screen panel. `compact` uses a smaller title and body font so long
## lists (the Cell shop, perk choices) fit.
func show_screen(title: String, body: String, compact := false) -> void:
	screen_title.text = title
	screen_title.add_theme_font_size_override("font_size", 20 if compact else 30)
	screen_title.position.y = 14 if compact else 30
	screen_body.text = body
	screen_body.add_theme_font_size_override("font_size", 9 if compact else 11)
	screen_body.position.y = 50 if compact else 80
	screen_body.size.y = 215 if compact else 180
	perk_cards.visible = false
	upgrade_cards.visible = false
	craft_cards.visible = false
	screen_foot.text = ""
	mode_select.visible = false
	screen_foot.position.y = H - 42
	screen_foot.size.y = 14
	screen_foot.add_theme_font_size_override("font_size", 10)
	screen.visible = true


## Title screen: story, the game mode dropdown, then difficulty and help.
func show_title(story: String, mode: String, help: String) -> void:
	show_screen("BASTION BREAK", story)
	screen_title.position.y = 18
	screen_body.position.y = 60
	screen_foot.text = help
	screen_foot.position.y = 166
	screen_foot.size.y = 80
	screen_foot.add_theme_font_size_override("font_size", 9)
	mode_select.show_mode(mode)


## The perk picker: title, one line of context, then animated cards.
func show_perks(subtitle: String, ids: Array[String], footer: String) -> void:
	show_screen("SMUGGLER'S TERMINAL", subtitle, true)
	screen_body.position.y = 40
	screen_foot.text = footer
	perk_cards.show_perks(ids)


## The Cell shop: a one-line header, the six upgrade cards, then the
## protocol and key help underneath.
func show_cell(header: String, footer: String) -> void:
	var keep := upgrade_cards.visible
	show_screen("CELL 4471", header, true)
	screen_body.position.y = 38
	screen_foot.text = footer
	screen_foot.position.y = 210
	screen_foot.size.y = 30
	screen_foot.add_theme_font_size_override("font_size", 8)
	upgrade_cards.visible = keep
	upgrade_cards.show_upgrades()


func hide_screen() -> void:
	screen.visible = false
	perk_cards.visible = false
	upgrade_cards.visible = false
	craft_cards.visible = false


## Purge workbench: scrap count, the three gadget cards, key help.
func show_craft(header: String, footer: String) -> void:
	var keep := craft_cards.visible
	show_screen("WORKBENCH", header, true)
	screen_body.position.y = 40
	screen_foot.text = footer
	craft_cards.visible = keep
	craft_cards.show_gadgets()
