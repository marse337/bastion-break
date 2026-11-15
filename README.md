# Bastion Break

An original retro grid-based first-person shooter for Godot 4.7, built in the
style of early-90s maze shooters. The name, story, characters, art, sounds and
levels are all original. The art is modeled and animated in Blender by scripts
in `blender/`, and the sound effects are generated in code.

**Story:** you are Rook, prisoner 4471 of the Iron Directorate, escaping the
Bastion one floor at a time.

## Play in the browser
**https://marse337.github.io/bastion-break/** works on desktop and on phones and tablets (hold the device sideways).

On touch screens:
- **Move:** drag on the left side of the screen. Push the stick all the way to run.
- **Turn:** drag anywhere on the right side.
- **Buttons:** FIRE, USE and SWAP (weapon). **II** pauses and **[ ]** goes fullscreen.
- **Map:** tap the map to enlarge it.
- **Menus:** use the buttons along the bottom of each screen.

Every push to `main` re-exports the game with standard (non-.NET) Godot 4.7 and publishes it to GitHub Pages (`.github/workflows/deploy-web.yml`). The .NET editor can't export to the web, but the game is pure GDScript, so the standard build works.

## Run locally
Open the folder in Godot 4.7 and press F5, or run:

```
Godot_v4.7-stable_mono_win64.exe --path .
```

## Controls
| Action | Keys |
|---|---|
| Move / strafe | W S A D (arrows: move + turn) |
| Turn | Mouse |
| Run | Shift |
| Fire | Left click / Ctrl |
| Open doors, flip exit switch | E / Space / right click |
| Weapons | 1-4 / mouse wheel |
| Map (large / small) | Tab |
| HD / retro pixels | F2 (saved between sessions) |
| Fullscreen | F11 |
| Pause | Esc |

## Modes
- **Escape run (roguelite, ENTER on the title screen):**
  - **The Cell:** a run starts in Rook's cell, where banked Iron Scrip buys permanent upgrades: Hidden Stash, Acoustic Dampener, Cartographer, Shock Shiv, Ricochet Sidearm and Spare Clone.
  - **Floors:** Floors 1 and 2 (Holding Cells / red keycard, The Foundry / blue keycard) are generated fresh every run. Floor 3 is the hand-made Overseer arena.
  - **Lives:** you start with 1 life (2 with Spare Clone). Dying with a spare life respawns you at the floor start with your gear, and dead enemies stay dead. With no lives left, the run is over.
  - **Iron Scrip:** earned from kills, treasure, cleared floors, perfect tallies and beating the boss. It's saved as you earn it, so a failed run still pays.
  - **Perks:** each perfect tally category (100% kills, secrets, treasure or hostages, or beating par) earns a pick-1-of-3 perk at the Smuggler's Terminal for the rest of the run.
- **Classic campaign (C on the title screen):** the three hand-made floors with classic rules: 3 lives, and dying restarts the floor with a Sidearm and 10 rounds.

## Procedural floors (`scripts/level_gen.gd`)
- **Rooms and doors:** binary space partitioning splits the map into rectangular rooms divided by 1-tile walls. Every split gets a door, so rooms connect only through doors, which block sound and Hounds. The Foundry adds extra loop doors.
- **Keycard and exit:** the exit is a dead-end room on the map edge behind the floor's keycard door. The key sits in the deepest other room, and the prison map is 1–3 rooms from the start.
- **Secret stash:** another dead-end room becomes a stash sealed by a sliding wall, placed only where the 2-tile slide leaves room to step around the block. Floor 1's stash holds an extra life and the Auto Rifle; Floor 2's holds the Rotary Cannon.
- **Guards near the start:** rooms next to the start get 1–2 sentries facing away from the door, so the opening kills can be silent shiv backstabs.
- **Cover:** rooms 7×7 or larger get pillars.
- **Checks:** every floor is checked with the same validator as the hand-made maps and regenerated with a new seed if it fails.

## Game rules
- **Weapons:** Shiv (silent melee), Sidearm (semi-auto), Auto Rifle, Rotary Cannon. All guns share one ammo pool, capped at 99.
- **Noise:** gunfire alerts enemies through open space and open doors. Closed doors block the sound, and the shiv makes none.
- **Enemies:** Sentry (basic gunner, drops ammo), Hound (fast melee and can't open doors), Warden (armored burst-fire, drops the Auto Rifle).
- **Boss:** Floor 3's Overseer has a rotary-cannon arm and shoulder launchers that fire dodgeable plasma bolts. It sees in all directions and drops the gold keycard to the exit vault. A health bar appears once it spots you.
- **Secrets:** some walls hide a stash. Secret walls have faint scrape marks and a cracked seam. Stab one with the **shiv** to pry it loose (pressing USE on it only tells you it sounds hollow).
- **Hostages:** fellow prisoners are tied to posts around each floor (2 on generated Cells floors, 3 on Foundry floors, 2–3 on each hand-made floor). Cut them free with the **shiv** for +1,000 points and 5 Iron Scrip, and they hand you 6 rounds or patch you up for 15 health. Stray gunfire kills them (−2,000 points). Tied-up hostages show as pink squares on the map in rooms you can see.
- **Tally:** shows found / total for kills, secrets, treasure and hostages freed. Each 100% category (and beating par) is worth a bonus and, in runs, a perk pick.
- **Automap:** the top-right map shows the rooms you've entered. Pick up a floor's **prison map** to reveal every room, with unentered ones shown in blue. Secret rooms stay hidden until you find them.
- **Scoring:** treasure, kills, an extra life every 50,000 points, and end-of-floor bonuses for 100% kills, secrets and treasure plus time under par.

## Project layout
| File | Purpose |
|---|---|
| `scripts/main.gd` | Game flow, viewport, input, sound playback |
| `scripts/world.gd` | Builds a level from text and runs doors, secrets, pickups, hitscan and noise |
| `scripts/player.gd` | Movement, collision, weapons |
| `scripts/enemy.gd` | Enemy AI state machine and stats table |
| `scripts/hostage.gd` | Tied-up prisoners you cut free with the shiv |
| `scripts/door.gd` | Sliding doors |
| `scripts/levels.gd` | **Level maps** (ASCII; legend at the top of the file) and the validator |
| `scripts/textures.gd` | Procedural pixel art |
| `scripts/sfx.gd` | Procedural sound effects |
| `scripts/hud.gd` | Status bar and screens |
| `scripts/minimap.gd` | Automap (rooms entered / revealed by the prison map) |
| `scripts/game_state.gd` | Autoload `Game`: score, lives, ammo, keys, stats, perks, Iron Scrip and upgrades (saved to `user://meta.cfg`) |
| `scripts/level_gen.gd` | Procedural floor generator for runs |
| `scripts/touch_controls.gd` | On-screen stick, buttons and menu buttons for phones |

## Art pipeline (Blender)
Every wall, item, weapon and enemy frame is built from primitives by Python
scripts and rendered with Eevee:

```
& "C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" -b --factory-startup -P blender/build_assets.py -- [textures] [items] [weapons] [enemies] [names...]
```

- `blender/build_textures.py`: 512px walls, doors, floor and ceiling (real geometry rendered top-down; tiles seamlessly).
- `blender/build_items.py`: pickup and prop billboards.
- `blender/build_weapons.py`: first-person hands and weapons (idle and fire frames).
- `blender/build_enemies.py`: jointed enemy models with keyframed poses. Stand and walk are rendered from 8 angles; aim, fire, pain and die are rendered from the front. Each enemy's editable scene, with its animation timeline, is saved to `blender/scenes/<kind>.blend`.

Output goes to `assets/`. After re-rendering, open the project in Godot (or run
`--headless --import`) to pick up the changes. If an asset is missing, the game
falls back to its old procedural art.

## Debug options
Pass these after `--`. `--tap=action@seconds,...` presses an input action once at a set time (for example `--tap=weapon_1@0.4,fire@0.7`). For example:
`--autostart --level=3 --god --alert --arsenal --retro --pos=9.5,3.5,0 --shot=out.png --shot-after=5 --quit`.
`--validate` checks every map for unreachable tiles, bad door frames and an
unreachable exit.

`--touch` shows the phone controls on desktop.

Roguelite flags:
- `--run --seed=N --level=N`: jump straight into a run floor.
- `--cell`: open the Cell shop.
- `--perk`: open the perk terminal.
- `--gen-test=N`: generate N floors per theme, validate them and print a sample map.

Note: runs save Iron Scrip to `user://meta.cfg`, so test runs add to your real save.
