class_name Levels
extends RefCounted
## Hand-made floor layouts. Each character is one tile:
##
##   Walls:   #  stone    B  metal    W  rusted plate    F  Directorate banner
##            E  exit switch (a wall you "use" to finish the floor)
##   Doors:   D  door     R  red keycard door     U  blue keycard door     G  gold keycard door
##   Secrets: P  sliding stone wall    Q  sliding metal wall
##   Start:   @  (facing set by "angle", degrees, 0 = east, 90 = south)
##   Enemies: s  sentry   h  hound    w  warden    O  the Overseer (boss, drops the gold keycard)
##   Items:   a  ammo     m  medkit   f  ration   t  gem   T  idol   x  extra life
##            g  auto rifle   c  rotary cannon   r  red keycard   u  blue keycard
##            M  prison map (reveals every non-secret room on the automap)
##   Props:   o  pillar   b  barrel   l  ceiling lamp
##   Floor:   .

const WALLS := "#BWFE"

const LEVELS := [
	{
		"name": "Holding Cells",
		"angle": 0.0,
		"par": 120,
		"map": [
			"###########F######F#############",
			"#......#..............l#.t.T#..#",
			"#.l..a.#..o..........o.#....#.x#",
			"#..@...D......s....s...D....P..#",
			"#......#..o..........o.#.t.t#..#",
			"#......#..............l#....#.c#",
			"###D###########D################",
			"#.....#.......#.#..............#",
			"#..h.M#.......#.#..............#",
			"#.f...#...a...#.#....w.........#",
			"#.....D.......D.D..............#",
			"#a....#.......#.#.......l......#",
			"###D###########.##########R#####",
			"#.......#.....s........#.......B",
			"#...r...#..............#.......B",
			"#.......D.....l........#...l...B",
			"#.......#..............#.......B",
			"#..m....#.....s......h.#.......E",
			"#.......#..............#.......B",
			"################################",
		],
	},
	{
		"name": "The Foundry",
		"angle": 0.0,
		"par": 150,
		"map": [
			"############F###############",
			"#@.....#.........#.........#",
			"#......D....w....D....s....#",
			"#..a...#.........#.........#",
			"#......#..o...o..#..o...o..#",
			"###D####.........#.........#",
			"#......WWWWWDWWWWWWWWWD#####",
			"#.h....#...........#.......#",
			"#......#.........M.#..u....#",
			"#..f...D.....s.....D.......#",
			"#......#...........#....h..#",
			"#......#..l.....l..#.......#",
			"####P###...........#########",
			"#..t.T#####U########.......#",
			"#..x..#.......#....D...s...#",
			"#.....#..s....#....#.......#",
			"#.c...#.......D....#..m....E",
			"#.....#.......#....#.......#",
			"############################",
		],
	},
	{
		"name": "Overseer's Sanctum",
		"angle": 0.0,
		"par": 180,
		"map": [
			"##################################",
			"###############M...a##############",
			"###############.a...##############",
			"#############F###D####F####F######",
			"############.................#####",
			"############..l.......h......#####",
			"############.................#####",
			"#####......#...o....o....o...BBBBB",
			"#..T#.a..a.#..s..............#...B",
			"#x..#......#.................#.t.B",
			"#...P..@...D......l....l..O..G...E",
			"#c..#......#.................#.t.B",
			"#..t#.m..f.#..s..............#...B",
			"#####......#.................BBBBB",
			"############...o....o....o...#####",
			"############.................#####",
			"############..l.......h......#####",
			"############.................#####",
			"#############F###D####F####F######",
			"###############.....##############",
			"###############m.a.m##############",
			"##################################",
		],
	},
]


## Sanity-checks a layout and returns a list of problems (empty = OK).
static func validate(level: Dictionary) -> PackedStringArray:
	var errs := PackedStringArray()
	var rows: Array = level.map
	var h := rows.size()
	var w: int = (rows[0] as String).length()
	for y in h:
		if (rows[y] as String).length() != w:
			errs.append("row %d has length %d, expected %d" % [y, (rows[y] as String).length(), w])
	if not errs.is_empty():
		return errs
	var start := Vector2i(-1, -1)
	for y in h:
		for x in w:
			var c: String = rows[y][x]
			var border := x == 0 or y == 0 or x == w - 1 or y == h - 1
			if border and not WALLS.contains(c):
				errs.append("border tile (%d,%d) is '%s', must be a wall" % [x, y, c])
			if c == "@":
				start = Vector2i(x, y)
			if c in ["D", "R", "U", "G"]:
				var horiz := WALLS.contains(rows[y][x - 1]) and WALLS.contains(rows[y][x + 1])
				var vert := WALLS.contains(rows[y - 1][x]) and WALLS.contains(rows[y + 1][x])
				if not horiz and not vert:
					errs.append("door at (%d,%d) is not framed by walls" % [x, y])
	if start.x < 0:
		errs.append("no player start '@'")
		return errs
	# Flood fill: everything except walls and solid props is walkable
	# (doors and secret walls count as passable for this check).
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var i := 0
	while i < queue.size():
		var p := queue[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h or seen.has(n):
				continue
			var c: String = rows[n.y][n.x]
			if WALLS.contains(c) or c == "o" or c == "b":
				continue
			seen[n] = true
			queue.append(n)
	var exit_ok := false
	for y in h:
		for x in w:
			var c: String = rows[y][x]
			if c == "E":
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if seen.has(Vector2i(x, y) + d):
						exit_ok = true
			elif not WALLS.contains(c) and c != "o" and c != "b" and not seen.has(Vector2i(x, y)):
				errs.append("tile (%d,%d) '%s' is unreachable" % [x, y, c])
	if not exit_ok:
		errs.append("exit switch is unreachable")
	return errs
