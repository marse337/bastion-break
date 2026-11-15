extends Node
## Persistent session state (autoload "Game"): score, lives, health, ammo,
## weapons, keys, per-floor statistics, roguelite run state (perks) and the
## saved meta-progression (Iron Scrip and Cell upgrades).

signal message(text: String)

enum Weapon { SHIV, SIDEARM, RIFLE, ROTARY }

## Every weapon. Each lives in one of the 4 slots (keys 1-4); a slot can hold
## a base weapon plus prototypes, and pressing the slot key again switches
## between them. All guns share one ammo pool.
##   delay: seconds between shots   auto: hold to fire   cost: ammo per shot
##   noise: gunfire noise multiplier   reach: melee range in tiles
const WEAPONS := {
	"shiv": {"slot": 0, "name": "SHIV", "delay": 0.42, "auto": false, "reach": 1.4},
	"baton": {"slot": 0, "name": "BATON", "delay": 0.66, "auto": false, "reach": 1.8,
		"desc": "Breaching Baton: slower swings, 1.8-tile reach, knocks Sentries and Hounds back a tile."},
	"sidearm": {"slot": 1, "name": "SIDEARM", "delay": 0.28, "auto": false},
	"slugger": {"slot": 1, "name": "SLUGGER", "delay": 0.42, "auto": false, "cost": 2,
		"desc": "Directorate Slugger: 2 ammo for two bullets per shot; always makes enemies flinch within 3.5 tiles."},
	"rifle": {"slot": 2, "name": "AUTO RIFLE", "delay": 0.13, "auto": true},
	"masterwork": {"slot": 2, "name": "MASTERWORK", "delay": 0.104, "auto": true, "noise": 0.7, "half_cost": true,
		"desc": "Masterwork Auto Rifle: 25% faster, 30% quieter, uses 1 ammo every 2nd shot."},
	"nail": {"slot": 2, "name": "NAIL CARBINE", "delay": 0.16, "auto": true, "noise": 0.5, "pierce": true,
		"desc": "Nail Carbine: nails punch through to the enemy behind (never past a hostage); half the noise."},
	"rotary": {"slot": 3, "name": "ROTARY", "delay": 0.075, "auto": true},
	"arc": {"slot": 3, "name": "ARC DISCHARGER", "delay": 0.11, "auto": true, "arc": true,
		"desc": "Arc Discharger: locks onto the closest enemy within 4 tiles and jumps to a second; never hits hostages."},
}
const SLOT_BASE := ["shiv", "sidearm", "rifle", "rotary"]
## Prototypes that can turn up in mod crates and contraband vaults.
const PROTOTYPES := ["baton", "slugger", "nail", "arc"]

## Escape Protocols: run modes chosen in the Cell. id: [name, description]
const PROTOCOLS := {
	"escape": ["Standard Escape", "Two generated floors, then the Overseer's arena."],
	"ghost": ["Ghost Protocol", "0 ammo, the Ghost perk and every map revealed. Exits open only when all hostages are free; each gives +6 ammo and 2,000 points."],
	"gauntlet": ["Iron Gauntlet", "Endless small floors, no keycards. Exit opens at 75% kills or all hostages freed. Sub-Overseer every 3rd floor, free perk every 2nd."],
	"scramble": ["Arsenal Scramble", "Slots 2-4 are issued random prototype guns at the start of every floor."],
	"daily": ["Daily Lockdown", "Today's seed, Cell upgrades off. Rooms cleared without a gunfire alert add +0.2x score multiplier; hitting a hostage resets it."],
	"purge": ["Purge Protocol", "45 s into every floor an unkillable Hunter Warden leaves the elevator. Stun it, rocket it from wall pods, and craft gadgets from guard scrap (C). Score x1.5."],
}
const PROTOCOL_ORDER := ["escape", "ghost", "gauntlet", "scramble", "daily", "purge"]

## Purge Protocol gadgets, crafted from scrap. id: [name, scrap cost, key, description]
const GADGETS := {
	"rocket": ["Breach Rocket", 6, "R", "Fire straight ahead. One hit scraps the Hunter Warden for this floor; it also blasts guards."],
	"mine": ["Shock Mine", 3, "F", "Drop it at your feet. The Hunter Warden is stunned for 6 s when it steps on it; guards take 40 damage."],
	"brace": ["Door Brace", 2, "B", "Clamp the door you face. The Hunter Warden needs 6 s more to batter it down."],
}
const GADGET_ORDER := ["rocket", "mine", "brace"]
const PURGE_DELAY := 45.0
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
var slot_guns: Array = [["shiv"], ["sidearm"], [], []]
var slot_active: Array = SLOT_BASE.duplicate()
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
var protocol := "escape"
## The protocol picked in the Cell (saved between sessions).
var protocol_choice := "escape"
## Daily Lockdown: score multiplier and the best score per day.
var score_mult := 1.0
var daily_best := {}
## Once-per-run events.
var bounty_floor := -1
var locker_pending := false
## Extra perk picks waiting for the next terminal (Perk Chips, Gauntlet floors).
var bonus_perks := 0
## Purge Protocol: scrap from guards, and crafted gadgets carried.
var scrap := 0
var gadgets := {"rocket": 0, "mine": 0, "brace": 0}

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
		protocol_choice = cfg.get_value("game", "protocol", "escape")
		if not PROTOCOLS.has(protocol_choice):
			protocol_choice = "escape"
	var meta := ConfigFile.new()
	if meta.load(META_PATH) == OK:
		scrip = meta.get_value("meta", "scrip", 0)
		upgrades = meta.get_value("meta", "upgrades", {})
		daily_best = meta.get_value("meta", "daily_best", {})


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "retro", retro)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("game", "protocol", protocol_choice)
	cfg.save(SETTINGS_PATH)


func save_meta() -> void:
	# Test runs (--no-save, or any --run / --goto debug launch) never touch the real save.
	var args := OS.get_cmdline_user_args()
	if "--no-save" in args or "--run" in args:
		return
	var meta := ConfigFile.new()
	meta.set_value("meta", "scrip", scrip)
	meta.set_value("meta", "upgrades", upgrades)
	meta.set_value("meta", "daily_best", daily_best)
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


func is_protocol(id: String) -> bool:
	return is_run() and protocol == id


func upgrade_level(id: String) -> int:
	if not is_run() or protocol == "daily":
		return 0
	return int(upgrades.get(id, 0))


## Today's date as a number (YYYYMMDD): the Daily Lockdown seed.
func today_key() -> int:
	var d := Time.get_date_dict_from_system()
	return int(d.year) * 10000 + int(d.month) * 100 + int(d.day)


func daily_best_today() -> int:
	return int(daily_best.get(str(today_key()), 0))


## Saves the score if it beats today's best. Returns true on a new best.
func record_daily_score() -> bool:
	if not is_protocol("daily") or score <= daily_best_today():
		return false
	daily_best[str(today_key())] = score
	save_meta()
	return true


## Floor theme for run floor `index` under the current protocol.
func run_floor_theme(index: int) -> String:
	if protocol == "ghost":
		return ["cells", "foundry", "foundry"][index]
	if protocol == "gauntlet":
		if index % 3 == 2:
			return "gauntlet_boss"
		return "gauntlet_cells" if index % 2 == 0 else "gauntlet_foundry"
	return RUN_FLOORS[index]


func run_floor_count() -> int:
	return 999 if protocol == "gauntlet" else RUN_FLOORS.size()


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
	if is_protocol("ghost"):
		return 0
	return [10, 16, 24][clampi(upgrade_level("stash"), 0, 2)] if is_run() else START_AMMO


## Purge Protocol: turns scrap into a gadget. Returns false if you can't afford it.
func craft(id: String) -> bool:
	var cost: int = GADGETS[id][1]
	if scrap < cost:
		return false
	scrap -= cost
	gadgets[id] = int(gadgets[id]) + 1
	return true


func noise_radius() -> int:
	var r := NOISE_RADIUS - 8 * upgrade_level("dampener")
	r = r / 2 if has_perk("muffler") else r
	return int(r * float(weapon_stat("noise", 1.0)))


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


func new_run(proto := "escape") -> void:
	mode = "run"
	protocol = proto
	run_seed = today_key() * 7 if proto == "daily" else randi() % 1000000000
	perks.clear()
	if proto == "ghost":
		perks.append("ghost")
	score_mult = 1.5 if proto == "purge" else 1.0
	locker_pending = false
	bonus_perks = 0
	scrap = 0
	gadgets = {"rocket": 0, "mine": 0, "brace": 0}
	# One Bounty Warden per run, on floor 1 or 2 (floor 2 in the Gauntlet).
	bounty_floor = 1 if proto == "gauntlet" else (run_seed % 2)
	run_scrip = 0
	level_index = 0
	score = 0
	lives = 1 + upgrade_level("spare_life")
	next_life_at = EXTRA_LIFE_EVERY
	reset_loadout()


func new_game(start_level := 0) -> void:
	mode = "classic"
	protocol = "escape"
	score_mult = 1.0
	bounty_floor = -1
	locker_pending = false
	bonus_perks = 0
	level_index = start_level
	score = 0
	lives = 3
	next_life_at = EXTRA_LIFE_EVERY
	reset_loadout()


func reset_loadout() -> void:
	health = MAX_HEALTH
	ammo = start_ammo()
	slot_guns = [["shiv"], ["sidearm"], [], []]
	slot_active = SLOT_BASE.duplicate()
	_sync_owned()
	current_weapon = Weapon.SHIV if ammo == 0 else Weapon.SIDEARM
	auto_shiv = ammo == 0


func begin_level() -> void:
	keys = {"red": false, "blue": false, "gold": false}
	has_map = (is_run() and level_index == 0 and upgrade_level("cartographer") > 0) or is_protocol("ghost")
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
	if n > 0 and (is_protocol("daily") or is_protocol("purge")):
		n = int(round(n * score_mult))
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


func give_weapon(w: int, bonus_ammo: int, id := "") -> void:
	if id == "":
		id = SLOT_BASE[w]
	var is_new := not owned[w]
	if not id in slot_guns[w]:
		slot_guns[w].append(id)
	if is_new or id != SLOT_BASE[w]:
		slot_active[w] = id
	_sync_owned()
	ammo = mini(max_ammo(), ammo + bonus_ammo)
	if is_new and (w > current_weapon or current_weapon == Weapon.SHIV):
		current_weapon = w
		auto_shiv = false


## Removes one weapon (the Confiscation Locker takes the Auto Rifle).
func take_weapon(id: String) -> void:
	var w: int = WEAPONS[id].slot
	slot_guns[w].erase(id)
	if slot_active[w] == id:
		slot_active[w] = slot_guns[w][0] if not slot_guns[w].is_empty() else SLOT_BASE[w]
	_sync_owned()
	if current_weapon == w and not owned[w]:
		current_weapon = best_gun() if ammo > 0 else Weapon.SHIV


func owns(id: String) -> bool:
	return id in slot_guns[WEAPONS[id].slot]


## A random prototype the player doesn't have yet ("" when they have them all).
func roll_prototype() -> String:
	var pool := []
	for id in PROTOTYPES:
		if not owns(id):
			pool.append(id)
	return "" if pool.is_empty() else pool.pick_random()


## Arsenal Scramble: slots 2-4 get freshly issued random guns each floor.
func scramble_loadout() -> void:
	var picks := [["sidearm", "slugger"], ["rifle", "nail", "masterwork"], ["rotary", "arc"]]
	for k in 3:
		var id: String = picks[k].pick_random()
		slot_guns[k + 1] = [id]
		slot_active[k + 1] = id
	_sync_owned()
	if current_weapon != Weapon.SHIV:
		current_weapon = Weapon.SIDEARM


func _sync_owned() -> void:
	for i in 4:
		owned[i] = not slot_guns[i].is_empty()


## Id of the weapon active in `slot` (default: the one in hand).
func weapon_id(slot := -1) -> String:
	return slot_active[current_weapon if slot < 0 else slot]


func weapon_stat(key: String, default = null):
	return WEAPONS[weapon_id()].get(key, default)


func weapon_name() -> String:
	return WEAPONS[weapon_id()].name


func switch_to_shiv() -> void:
	current_weapon = Weapon.SHIV
	auto_shiv = true


func best_gun() -> int:
	for w in [Weapon.ROTARY, Weapon.RIFLE, Weapon.SIDEARM]:
		if owned[w]:
			return w
	return Weapon.SHIV
