extends Node
## Persistent session state (autoload "Game"): score, lives, health, ammo,
## weapons, keys, per-floor statistics, roguelite run state (perks) and the
## saved meta-progression (Iron Scrip and Cell upgrades).

signal message(text: String)

enum Weapon { SHIV, SIDEARM, RIFLE, ROTARY }

const WEAPON_NAMES := ["SHIV", "SIDEARM", "AUTO RIFLE", "ROTARY"]
const DIFFICULTY_NAMES := ["TRUSTEE (easy)", "INMATE (normal)", "LIFER (hard)"]
const MAX_HEALTH := 100
const MAX_AMMO := 99
const MAX_LIVES := 9
const EXTRA_LIFE_EVERY := 50000
const START_AMMO := 10
const NOISE_RADIUS := 28

## In-run perks, earned at the end-of-floor terminal. id: [name, description]
const PERKS := {
	"scavenger": ["Scavenger", "Ammo cap 150, and ammo pickups give 50% more."],
	"point_blank": ["Point-Blank Executioner", "Double damage out to 3.5 tiles (was 2), and close hits always make enemies flinch."],
	"ghost": ["Ghost of 4471", "Shiv attacks on unaware enemies kill instantly and drop +2 ammo."],
	"thick_hide": ["Thick Hide", "Take 20% less damage."],
	"field_medic": ["Field Medic", "Healing pickups restore 50% more."],
	"quick_hands": ["Quick Hands", "All weapons fire 15% faster."],
	"fleet_foot": ["Fleet Foot", "Move 15% faster."],
	"deadeye": ["Deadeye", "Long-range accuracy falls off half as fast."],
	"treasure_hunter": ["Treasure Hunter", "Treasure is worth double score and double Iron Scrip."],
	"muffler": ["Muffled Shots", "Gunfire carries half as far."],
}

## Permanent Cell upgrades bought with Iron Scrip. id: [name, description, costs per level]
const UPGRADES := {
	"stash": ["Hidden Stash", "Start runs with more ammo (10 / 16 / 24).", [40, 90]],
	"dampener": ["Acoustic Dampener", "Your gunfire travels 8 fewer tiles.", [60]],
	"cartographer": ["Cartographer", "Floor 1 of every run starts with its map revealed.", [50]],
	"shock_shiv": ["Shock Shiv", "Shiv deals double damage and always makes enemies flinch.", [70]],
	"ricochet": ["Ricochet Sidearm", "Sidearm deals 40% more damage.", [60]],
	"spare_life": ["Spare Clone", "Start runs with 2 lives instead of 1.", [120]],
}
const UPGRADE_ORDER := ["stash", "dampener", "cartographer", "shock_shiv", "ricochet", "spare_life"]

## Floors of a roguelite run: two generated themes, then the hand-made boss arena.
const RUN_FLOORS := ["cells", "foundry", "boss"]

const SETTINGS_PATH := "user://settings.cfg"
const META_PATH := "user://meta.cfg"

var difficulty := 1
var level_index := 0
var score := 0
var lives := 3
var health := MAX_HEALTH
var ammo := START_AMMO
var owned: Array[bool] = [true, true, false, false]
var current_weapon := Weapon.SIDEARM
var auto_shiv := false
var keys := {"red": false, "blue": false, "gold": false}
var next_life_at := EXTRA_LIFE_EVERY
var level_start_score := 0
var has_map := false

## Display setting: false = HD (native resolution), true = chunky retro pixels.
var retro := false

## "classic" = the three hand-made floors with classic rules; "run" = roguelite.
var mode := "classic"
var run_seed := 0
var perks: Array[String] = []
var scrip := 0
var run_scrip := 0
var floor_scrip := 0
var upgrades := {}

var kills := 0
var kills_total := 0
var secrets := 0
var secrets_total := 0
var treasure := 0
var treasure_total := 0
var hostages := 0
var hostages_total := 0
var hostages_lost := 0
var level_time := 0.0


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		retro = cfg.get_value("display", "retro", false)
		difficulty = cfg.get_value("game", "difficulty", 1)
	var meta := ConfigFile.new()
	if meta.load(META_PATH) == OK:
		scrip = meta.get_value("meta", "scrip", 0)
		upgrades = meta.get_value("meta", "upgrades", {})


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "retro", retro)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.save(SETTINGS_PATH)


func save_meta() -> void:
	var meta := ConfigFile.new()
	meta.set_value("meta", "scrip", scrip)
	meta.set_value("meta", "upgrades", upgrades)
	meta.save(META_PATH)


## Texture filter for 3D materials and sprites in the current display mode.
func filter_3d() -> int:
	if retro:
		return BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


# ------------------------------------------------------------------ runs & meta

func is_run() -> bool:
	return mode == "run"


func has_perk(id: String) -> bool:
	return is_run() and id in perks


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0)) if is_run() else 0


func upgrade_cost(id: String) -> int:
	var costs: Array = UPGRADES[id][2]
	var lv := int(upgrades.get(id, 0))
	return costs[lv] if lv < costs.size() else -1


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or scrip < cost:
		return false
	scrip -= cost
	upgrades[id] = int(upgrades.get(id, 0)) + 1
	save_meta()
	return true


## Iron Scrip is banked the moment it is earned and saved at floor ends,
## deaths and run ends, so nothing is lost when a run fails.
func earn_scrip(n: int) -> void:
	if not is_run() or n <= 0:
		return
	scrip += n
	run_scrip += n
	floor_scrip += n


func max_ammo() -> int:
	return 150 if has_perk("scavenger") else MAX_AMMO


func start_ammo() -> int:
	return [10, 16, 24][clampi(upgrade_level("stash"), 0, 2)] if is_run() else START_AMMO


func noise_radius() -> int:
	var r := NOISE_RADIUS - 8 * upgrade_level("dampener")
	return r / 2 if has_perk("muffler") else r


func damage_taken_scale() -> float:
	return 0.8 if has_perk("thick_hide") else 1.0


## Three random perks the player doesn't own yet.
func perk_offer() -> Array[String]:
	var pool: Array[String] = []
	for id in PERKS:
		if not id in perks:
			pool.append(id)
	pool.shuffle()
	return pool.slice(0, 3)


func new_run() -> void:
	mode = "run"
	run_seed = randi()
	perks.clear()
	run_scrip = 0
	level_index = 0
	score = 0
	lives = 1 + upgrade_level("spare_life")
	next_life_at = EXTRA_LIFE_EVERY
	reset_loadout()


func new_game(start_level := 0) -> void:
	mode = "classic"
	level_index = start_level
	score = 0
	lives = 3
	next_life_at = EXTRA_LIFE_EVERY
	reset_loadout()


func reset_loadout() -> void:
	health = MAX_HEALTH
	ammo = start_ammo()
	owned = [true, true, false, false]
	current_weapon = Weapon.SIDEARM
	auto_shiv = false


func begin_level() -> void:
	keys = {"red": false, "blue": false, "gold": false}
	has_map = is_run() and level_index == 0 and upgrade_level("cartographer") > 0
	kills = 0
	kills_total = 0
	secrets = 0
	secrets_total = 0
	treasure = 0
	treasure_total = 0
	hostages = 0
	hostages_total = 0
	hostages_lost = 0
	floor_scrip = 0
	level_time = 0.0
	level_start_score = score


## Classic mode: the player died with lives to spare, so the floor restarts
## and anything earned on it is lost.
func restart_after_death() -> void:
	score = level_start_score
	reset_loadout()


func add_score(n: int) -> void:
	score += n
	while score >= next_life_at:
		next_life_at += EXTRA_LIFE_EVERY
		if lives < MAX_LIVES:
			lives += 1
			message.emit("EXTRA LIFE!")


func heal(n: int) -> bool:
	if health >= MAX_HEALTH:
		return false
	if has_perk("field_medic"):
		n = int(n * 1.5)
	health = mini(MAX_HEALTH, health + n)
	return true


func give_ammo(n: int) -> bool:
	if ammo >= max_ammo():
		return false
	if has_perk("scavenger"):
		n = int(ceil(n * 1.5))
	var was_empty := ammo == 0
	ammo = mini(max_ammo(), ammo + n)
	if was_empty and auto_shiv:
		current_weapon = best_gun()
		auto_shiv = false
	return true


func give_weapon(w: int, bonus_ammo: int) -> void:
	var is_new := not owned[w]
	owned[w] = true
	ammo = mini(max_ammo(), ammo + bonus_ammo)
	if is_new and (w > current_weapon or current_weapon == Weapon.SHIV):
		current_weapon = w
		auto_shiv = false


func switch_to_shiv() -> void:
	current_weapon = Weapon.SHIV
	auto_shiv = true


func best_gun() -> int:
	for w in [Weapon.ROTARY, Weapon.RIFLE, Weapon.SIDEARM]:
		if owned[w]:
			return w
	return Weapon.SHIV
