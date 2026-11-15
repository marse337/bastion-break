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
const BOSS_W := 220.0
var screen: ColorRect
var screen_title: Label
var screen_body: Label
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
	var bl := _label(boss_panel, Vector2(0, -2), Vector2(BOSS_W, 10), 8, Color(1, 0.75, 0.6))
	bl.text = "THE OVERSEER"
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rect(boss_panel, Vector2(0, 10), Vector2(BOSS_W, 7), Color(0.05, 0.02, 0.02, 0.85))
	boss_fill = _rect(boss_panel, Vector2(1, 11), Vector2(BOSS_W - 2, 5), Color(0.85, 0.12, 0.08))
	boss_panel.visible = false

	screen = _rect(root, Vector2.ZERO, Vector2(W, H), Color(0.03, 0.03, 0.05, 0.94))
	screen_title = _label(screen, Vector2(0, 30), Vector2(W, 40), 30, Color(1, 0.55, 0.15))
	screen_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_body = _label(screen, Vector2(20, 80), Vector2(W - 40, 180), 11, Color(0.85, 0.88, 0.95))
	screen_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	screen_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	values.AMMO.text = str(Game.ammo)
	values.WEAPON.text = Game.WEAPON_NAMES[Game.current_weapon]
	key_red.color = Color(0.95, 0.15, 0.1) if Game.keys.red else Color(0.2, 0.08, 0.08)
	key_blue.color = Color(0.2, 0.45, 1.0) if Game.keys.blue else Color(0.07, 0.09, 0.2)
	key_gold.color = Color(1.0, 0.78, 0.15) if Game.keys.gold else Color(0.2, 0.16, 0.05)


func tick(delta: float, world: World) -> void:
	minimap.tick(delta, world)
	var b: Enemy = world.boss if world != null else null
	boss_panel.visible = b != null and b.state != Enemy.IDLE and b.is_alive()
	if boss_panel.visible:
		boss_fill.size.x = (BOSS_W - 2.0) * clampf(float(b.hp) / b.max_hp, 0.0, 1.0)
	dmg_alpha = maxf(0.0, dmg_alpha - delta * 1.8)
	pick_alpha = maxf(0.0, pick_alpha - delta * 2.5)
	damage_rect.color.a = maxf(dmg_alpha, death_alpha)
	pickup_rect.color.a = pick_alpha
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			msg.text = ""


func flash_damage(amount: int) -> void:
	dmg_alpha = clampf(dmg_alpha + 0.15 + amount * 0.02, 0.0, 0.6)


func flash_pickup() -> void:
	pick_alpha = 0.3


func show_message(text: String) -> void:
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
	screen.visible = true


func hide_screen() -> void:
	screen.visible = false
