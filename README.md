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

Gamepads and joysticks work too, in the browser and locally. As soon as one is plugged in or used, the touch controls hide and every on-screen hint switches to pad buttons. Touching the screen, or pressing a key or mouse button, switches back. In a browser, press any pad button once so the browser reports the pad.

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
| Purge Protocol: workbench / rocket / mine / brace | C / R / F / B |

| Action | Gamepad |
|---|---|
| Move / strafe | Left stick |
| Turn | Right stick |
| Run | LT / click the left stick |
| Fire | RT |
| Open doors, flip exit switch | A / X |
| Weapons | LB / RB |
| Map (large / small) | Back / D-pad up |
| Pause | START (Back on the pause screen quits to the title) |
| Purge Protocol: workbench / rocket / mine / brace | Y / D-pad left / down / right |
| Menus | Stick or D-pad to choose, A to confirm, B to go back. Title: Y opens the mode list, LB / RB change difficulty. Cell: X switches protocol |

## Modes
- **Escape run (roguelite, ENTER on the title screen):**
  - **The Cell:** a run starts in Rook's cell, where banked Iron Scrip buys permanent upgrades: Hidden Stash, Acoustic Dampener, Cartographer, Shock Shiv, Ricochet Sidearm and Spare Clone. Press **P** (touch: MODE) to pick an Escape Protocol before you start.
  - **Floors:** Floors 1 and 2 (Holding Cells / red keycard, The Foundry / blue keycard) are generated fresh every run. Floor 3 is the hand-made Overseer arena.
  - **Lives:** you start with 1 life (2 with Spare Clone). Dying with a spare life respawns you at the floor start with your gear, and dead enemies stay dead. With no lives left, the run is over.
  - **Iron Scrip:** earned from kills, treasure, cleared floors, perfect tallies and beating the boss. It's saved as you earn it, so a failed run still pays.
  - **Perks:** each perfect tally category (100% kills, secrets, treasure or hostages, or beating par) earns a pick-1-of-3 perk at the Smuggler's Terminal for the rest of the run. Choose with A / D or the arrows and ENTER, press 1-3, or click a card.
  - **Floor tally:** the floor-cleared screen counts up one category at a time (bars, PERFECT and UNDER PAR stamps), then the bonus, score, Iron Scrip and perk picks. SPACE or ENTER skips to the end.
- **Game modes:** chosen from the GAME MODE dropdown on the title screen (click the box or press M; arrows change it; ENTER or PLAY starts). Every mode below except the classic campaign goes through the Cell first: choose upgrades with A / D / W / S and ENTER (START RUN is selected by default), and P switches protocol. **Escape Protocols (run modes):**
  - **Standard Escape:** two generated floors, then the Overseer's arena.
  - **Ghost Protocol:** start with 0 ammo, the Ghost of 4471 perk and every map revealed. Three generated floors with no boss. Each exit opens only once every hostage on the floor is free, and each hostage gives +6 ammo and 2,000 points.
  - **Iron Gauntlet:** endless 24×24 sectors with no keycards. The elevator opens at 75% kills or when every hostage is free, and two ammo boxes always wait beside it. Every 3rd sector has a Sub-Overseer, and every 2nd sector gives a free perk pick. The run ends when you run out of lives.
  - **Arsenal Scramble:** slots 2–4 are issued a random gun at the start of every floor (Sidearm or Slugger, Auto Rifle / Nail Carbine / Masterwork, Rotary or Arc Discharger).
  - **Daily Lockdown:** today's seed, the same for every player, with Cell upgrades switched off. Every room whose guards all die without any of them being alerted by gunfire adds +0.2x to your score multiplier. Shooting a hostage resets it to x1.0. Your best score for each day is saved on your device.
  - **Purge Protocol:** the Standard Escape floors, with score x1.5 and a hunter on every floor (below). Pick it from the GAME MODE dropdown on the title screen.
- **Classic campaign (C on the title screen):** the three hand-made floors with classic rules: 3 lives, and dying restarts the floor with a Sidearm and 10 rounds.

## Purge Protocol: the Hunter Warden
- **The hunt:** 45 seconds into every floor a siren warns you ("PURGE IN 10 SECONDS"), then the Hunter Warden steps out of the starting elevator. It can't be shot dead. It marches toward you along the shortest path at 75% of your walking speed, so running always outpaces it. If it reaches arm's length it grabs you, and that costs a life.
- **Stun it:** 30 damage in quick succession (any weapon, the shiv included) jams its leg servos for 4 seconds. While it's stunned you can walk straight through it. The bar at the top of the screen is its stun meter.
- **Doors:** it never opens doors. It batters closed ones down in 2.5 seconds, keycard doors included, and the door is gone for good. Closing a door in its face buys you time.
- **Noise magnet:** if your gunfire reaches it (the same rule that wakes guards), it surges to 110% of your walking speed for 3 seconds. The shiv is silent, and Muffled Shots, the Acoustic Dampener, the Masterwork and the Nail Carbine all shrink the radius.
- **Rocket pods:** each floor has two wall-mounted ROCKET PODs, shown in green on the map. When the Hunter is in a pod's line of sight (within 16 tiles), press USE on the pod to fire a homing rocket. That scraps the Hunter for the rest of the floor and pays +5,000 points, an ammo box and 3 scrap.
- **Warnings:** a countdown bar until it's released, heavy footsteps that get louder as it closes in (heard through walls), and a pulsing red diamond on the map at all times (blue while it's stunned).
- **If it catches you:** the clone wakes at the elevator, the Hunter goes back inside, its 45-second timer restarts, and a free clip waits at the start.
- **Crafting:** every guard you kill drops scrap (Sentry or Hound 1, Warden 2, Bounty Warden or Sub-Overseer 4, Overseer 6). A briefing before the first Purge floor walks through this in three animated steps. Press **C** (touch: CRAFT) to open the workbench, which pauses the game; choose with A / D and ENTER, or press 1-3:

  | Gadget | Scrap | Key | Effect |
  |---|---|---|---|
  | Breach Rocket | 6 | R | Fired down the crosshair. A hit scraps the Hunter for the floor; the blast deals 60 damage to guards. |
  | Shock Mine | 3 | F | Dropped at your feet. When the Hunter comes within reach it's stunned for 6 seconds; a guard walking onto it takes 40 damage. |
  | Door Brace | 2 | B | Clamps the door you face (two per door). Each brace makes the Hunter batter that door for 6 seconds longer. The bar swings down onto its clamps with sparks, rattles while the Hunter pounds the door, and snaps off and clatters to the floor when it gives way (a snapped brace is gone for good). |

## Procedural floors (`scripts/level_gen.gd`)
- **Rooms and doors:** binary space partitioning splits the map into rectangular rooms divided by 1-tile walls. Every split gets a door, so rooms connect only through doors, which block sound and Hounds. The Foundry adds extra loop doors.
- **Keycard and exit:** the exit is a dead-end room on the map edge behind the floor's keycard door. The key sits in the deepest other room, and the prison map is 1–3 rooms from the start.
- **Secret stash:** another dead-end room becomes a stash sealed by a sliding wall, placed only where the 2-tile slide leaves room to step around the block. Floor 1's stash holds an extra life and the Auto Rifle; Floor 2's holds the Rotary Cannon.
- **Guards near the start:** rooms next to the start get 1–2 sentries facing away from the door, so the opening kills can be silent shiv backstabs.
- **Cover:** rooms 7×7 or larger get pillars.
- **Checks:** every floor is checked with the same validator as the hand-made maps and regenerated with a new seed if it fails.

## Room features (generated floors)
- **Calibration range:** a CALIBRATE console at the end of a long room. Use it while no guards are hunting you and Rook is locked at the window for 8 seconds with a free 12-round calibration clip. Red targets slide across at three distances, mixed with hostage cutouts. Hit every red target without clipping a cutout, then take **one** reward: 16 rounds, full health or +2,500.
- **Security terminal:** use the OVERRIDE screen to hear and see a 3-colour sequence, then throw the red, blue and gold breakers on the room's walls in that order. A wrong breaker sets off an alarm pulse (as loud as a sidearm shot) and resets the sequence. Solving it opens a purple vault door with an Iron Scrip cache, a prototype mod crate and a gem.
- **Hostage standoff:** a guard stands at the far end of a room facing the doorway, with two hostages tied up in the line of fire and an idol or extra life behind it. Sneak in through the room's other door, or let the guard see you and step back so it walks out past the hostages.
- **Hound lock-in (Foundry floors):** the prison map and two gems sit in the middle of a big room with two pillars. Taking any of them seals the doors for 12 seconds and opens three Hound cages.
- **Confiscation Locker (floors 1–2 of Standard, Ghost and Daily runs):** feed it your Auto Rifle and finish the floor without it. A Masterwork Auto Rifle (25% faster, 30% quieter, 1 ammo every 2nd shot) waits for you on the next floor.
- **Bounty Warden (once per run):** a Crimson Warden in a side room, marked on the map with a skull from the start. It ignores distant gunfire and won't leave its room until it has seen you. After each 5-shot burst it vents for 1.5 seconds and takes triple damage. It drops a Perk Chip (an extra perk pick after the floor) and 12 rounds.

## Game rules
- **Weapons:** four slots that share one ammo pool, capped at 99:
  - **Slot 1:** Shiv (silent melee). Its prototype is the **Breaching Baton**: slower, 1.8-tile reach, and it knocks Sentries and Hounds back a tile.
  - **Slot 2:** Sidearm. Its prototype is the **Directorate Slugger**: 2 ammo for two bullets, and enemies within 3.5 tiles always flinch.
  - **Slot 3:** Auto Rifle. Its prototypes are the **Nail Carbine** (nails carry on to the enemy behind but stop at hostages, half the noise) and the **Masterwork** (from the Confiscation Locker).
  - **Slot 4:** Rotary Cannon. Its prototype is the **Arc Discharger**: locks onto the closest enemy within 4 tiles and jumps to a second one for half damage, never hits hostages, and won't fire without a target.

  Prototypes come from **mod crates** (secret stashes and contraband vaults). Picking one up equips it, and pressing the slot's key again switches between the guns in that slot. The mouse wheel and the touch SWAP button step through everything you carry. Both melee weapons cut hostages free and pry open secret walls.
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
| `scripts/hunter.gd` | Purge Protocol's Hunter Warden (stun meter, door battering, noise surge) |
| `scripts/sprite_cards.gd` | Base for the animated card screens: `perk_cards.gd`, `upgrade_cards.gd`, `craft_cards.gd` |
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
| `scripts/playtest.gd` | Automated in-game play tests (`--playtest=brace`) |
| `scripts/gamepad_input.gd` | Gamepad support: menu buttons become key presses, hides the touch controls while a pad is in use |

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

## Play tests
Automated play tests run inside the real game, print one `PLAYTEST PASS` or
`PLAYTEST FAIL` line per check, and exit with code 1 if anything failed. They
never touch the save.

```
Godot_v4.7-stable_mono_win64_console.exe --path . -- --run --protocol=purge --seed=1 --no-save --no-pad --playtest=brace --playtest-shots=shots
```

- `brace` (`scripts/playtest.gd`, 20 checks):
  - bracing with no door in front is refused and costs nothing;
  - a brace swings down, lands with sparks and settles flat;
  - a second brace fits, and a third is refused;
  - a braced door still opens for Rook, and the bars slide with it;
  - the Hunter snaps the braces at 6 s and 12 s, both land on the floor, and the door breaks at 14.5 s.

  `--playtest-shots=DIR` (the folder must exist) saves a screenshot of each stage.

## Debug options
Pass these after `--`. `--tap=action@seconds,...` presses an input action once at a set time (for example `--tap=weapon_1@0.4,fire@0.7`). For example:
`--autostart --level=3 --god --alert --arsenal --retro --pos=9.5,3.5,0 --shot=out.png --shot-after=5 --quit`.
`--validate` checks every map for unreachable tiles, bad door frames and an
unreachable exit.

`--touch` shows the phone controls on desktop. `--no-pad` ignores any gamepad
plugged into the machine. `--pad=BUTTON@SEC,AXIS:VALUE@SEC,...` fakes gamepad
input, e.g. `--pad=y@1,down@1.3` or `--pad=ly:-1@1,rt:1@2,rt:0@2.2` (buttons:
a b x y start back lb rb up down left right l3; axes: lx ly rx ry lt rt).

Roguelite flags:
- `--run --seed=N --level=N`: jump straight into a run floor. Debug runs never write to the real save.
- `--protocol=ghost|gauntlet|scramble|daily`: the run's protocol (use with `--run`).
- `--goto=range|terminal|breaker|locker|lockin|bounty|standoff|exit`: start in front of a room feature.
- `--give=baton,slugger,nail,masterwork,arc`: with `--arsenal`, also hand out prototypes.
- `--no-save`: never write `user://meta.cfg`.
- `--modes-open`: open the title screen's game mode list at launch (for screenshots).
- `--tally`: clear the floor at once with made-up stats, to see the tally screen.
- `--briefing`: show the Purge briefing even with `--run`.
- `--keys=KEY@SEC,...`: press real keys after SEC seconds, e.g. `--keys=D@1,Enter@1.5`.
- `--protocol=purge --hunter-at=SEC`: release the Hunter Warden after SEC seconds instead of 45.
- `--scrap=N`, `--gadgets` (two of each), `--craft` (open the workbench at the start): crafting tests.
- `--goto=pod|hunterview`: stand at a rocket pod, or somewhere with a view of the elevator.
- `--goto=cage --spring-lockin`: watch a Hound lock-in from inside the room; it springs 1.5 s in.
- `--debug-hunter`: print the Hunter's state twice a second, plus every on-screen message (works with `--headless`).
- `--cell`: open the Cell shop.
- `--perk`: open the perk terminal.
- `--gen-test=N`: generate N floors per theme, validate them and print a sample map.

Note: normal runs save Iron Scrip to `user://meta.cfg`. Launches with `--run` or `--no-save` don't.
