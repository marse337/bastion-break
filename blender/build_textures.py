"""Wall, door, floor and ceiling textures.

Each texture is real geometry (bevelled blocks, rivets, corrugated sheets...)
laid out on the unit square and rendered top-down with an orthographic
camera, so lighting and depth are baked in. Patterns repeat with a period
that divides 1 so the textures tile seamlessly.
"""
import math
import os
import random

import bpy

from bb_common import ASSETS_DIR, ball, box, camera, cyl, glow, light, mat, rad, render, reset

OUT = os.path.join(ASSETS_DIR, "tex")
RES = 512


def _setup():
    reset(transparent=False, ambient=0.28)
    camera((0.5, 0.5, 4.0), (0.5, 0.5, 0.0), ortho=1.0)
    light("SUN", 1.8, (-0.6, 1.8, 2.0), (0.5, 0.5, 0.0), (1.0, 0.97, 0.92))
    light("SUN", 0.35, (1.8, -0.5, 1.0), (0.5, 0.5, 0.0), (0.8, 0.85, 1.0))


def _mesh_poly(name, pts, z, thickness, m):
    me = bpy.data.meshes.new(name)
    me.from_pydata([(x, y, z) for x, y in pts], [], [list(range(len(pts)))])
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(m)
    sol = o.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = thickness
    return o


# ------------------------------------------------------------------ builders

def _stone(seed=7):
    rng = random.Random(seed)
    box("mortar", (3, 3, 0.02), (0.5, 0.5, -0.01), mat("mortar", (0.11, 0.11, 0.12), rough=1.0, noise=0.4, noise_scale=40))
    shades = [0.34, 0.4, 0.46, 0.37, 0.43, 0.5]
    mats = [mat(f"stone{i}", (g, g * 0.98, g * 0.94), rough=0.9, noise=0.3, noise_scale=25, seed=i + 1) for i, g in enumerate(shades)]
    looks = {}
    rh = 0.25
    for r in range(4):
        off = 0.0 if r % 2 == 0 else 0.25
        for b in range(-1, 4):
            cx = off + b * 0.5 + 0.25
            key = (r, round(cx % 1.0, 3))
            if key not in looks:
                looks[key] = (rng.choice(mats), rng.uniform(0.04, 0.07), rng.uniform(-0.01, 0.01))
            m, hz, jitter = looks[key]
            box(f"block{r}_{b}", (0.5 - 0.022, rh - 0.022, hz), (cx + jitter, r * rh + rh / 2, hz / 2), m, bevel=0.014)


def _scuffs():
    """Subtle tell for sliding secret walls: scrape marks and a cracked seam."""
    scrape = mat("scrape", (0.62, 0.6, 0.56), rough=0.7)
    gouge = mat("gouge", (0.07, 0.07, 0.08), rough=1.0)
    for i, (x, y, a, l) in enumerate([(0.42, 0.33, 12, 0.22), (0.47, 0.3, 8, 0.18), (0.52, 0.36, 15, 0.2),
                                      (0.3, 0.12, -5, 0.25), (0.62, 0.1, 4, 0.22)]):
        box("scrape", (l, 0.006, 0.01), (x, y, 0.075), scrape, rot=(0, 0, math.radians(a)))
        box("gouge", (l * 0.8, 0.004, 0.01), (x, y - 0.006, 0.076), gouge, rot=(0, 0, math.radians(a)))
    for i in range(6):
        box("crack", (0.006, 0.045, 0.012), (0.5 + (i % 2) * 0.012, 0.28 + i * 0.04, 0.074), gouge, rot=(0, 0, math.radians(20 if i % 2 else -20)))


def _metal_base():
    plate = mat("plate", (0.3, 0.34, 0.4), metal=0.6, rough=0.45, noise=0.25, noise_scale=18)
    panel = mat("panel", (0.38, 0.42, 0.48), metal=0.65, rough=0.4, noise=0.2, noise_scale=10)
    rivet = mat("rivet", (0.62, 0.64, 0.68), metal=0.9, rough=0.3)
    box("plate", (3, 3, 0.02), (0.5, 0.5, -0.01), plate)
    for px in (0.25, 0.75):
        for py in (0.25, 0.75):
            box("panel", (0.47, 0.47, 0.03), (px, py, 0.015), panel, bevel=0.012)
            for dx in (-0.19, 0.19):
                for dy in (-0.19, 0.19):
                    ball("rivet", 0.014, (px + dx, py + dy, 0.03), rivet, scale=(1, 1, 0.6), segs=12)
    vent = mat("vent", (0.04, 0.04, 0.05), rough=0.9)
    for i in range(5):
        box("vent", (0.3, 0.025, 0.04), (0.75, 0.62 + i * 0.05, 0.02), vent)


def _rust():
    rust = mat("rust", (0.33, 0.2, 0.13), metal=0.55, rough=0.85, noise=0.75, noise_scale=6)
    box("back", (3, 3, 0.02), (0.5, 0.5, -0.05), rust)
    for i in range(-2, 15):
        rib = cyl("rib", 0.042, 3.0, (i / 12.0, 0.5, -0.03), rust, axis="Y", verts=20)
        rib.scale = (1.0, 0.3, 1.0)
    strap = mat("strap", (0.2, 0.2, 0.22), metal=0.7, rough=0.5, noise=0.3, noise_scale=20)
    bolt = mat("bolt", (0.55, 0.55, 0.58), metal=0.9, rough=0.35)
    for y in (0.04, 0.5, 0.96):
        box("strap", (3, 0.07, 0.03), (0.5, y, 0.03), strap, bevel=0.008)
        for i in range(-1, 8):
            ball("bolt", 0.012, (i / 6.0 + 1 / 12.0, y, 0.047), bolt, scale=(1, 1, 0.6), segs=10)


def _sigil():
    _stone(seed=11)
    cloth = mat("cloth", (0.42, 0.04, 0.04), rough=0.95, noise=0.35, noise_scale=30)
    gold = mat("gold", (1.0, 0.72, 0.2), metal=1.0, rough=0.3)
    banner = _mesh_poly("banner", [(0.28, 0.95), (0.72, 0.95), (0.72, 0.06), (0.5, 0.2), (0.28, 0.06)], 0.1, 0.01, cloth)
    cyl("rod", 0.015, 0.56, (0.5, 0.955, 0.12), gold, axis="X")
    for x in (0.215, 0.785):
        ball("rodcap", 0.025, (x, 0.955, 0.12), gold)
    for x in (0.3, 0.7):
        box("trim", (0.012, 0.86, 0.006), (x, 0.52, 0.113), gold)
    cx, cy, z = 0.5, 0.62, 0.115
    cyl("cog", 0.11, 0.015, (cx, cy, z), gold, verts=48)
    for i in range(10):
        a = i * math.tau / 10
        box("tooth", (0.045, 0.04, 0.015), (cx + math.cos(a) * 0.125, cy + math.sin(a) * 0.125, z), gold, rot=(0, 0, a))
    cyl("cog_in", 0.065, 0.02, (cx, cy, z + 0.002), cloth, verts=40)
    cyl("hub", 0.025, 0.025, (cx, cy, z + 0.004), gold, verts=24)
    for i, w in enumerate((0.22, 0.16, 0.1)):
        box("bar", (w, 0.025, 0.01), (cx, 0.43 - i * 0.05, z), gold, bevel=0.003)
    _ = banner


def _exit(on):
    _metal_base()
    frame = mat("frame", (0.55, 0.56, 0.6), metal=0.8, rough=0.35)
    dark = mat("dark", (0.03, 0.03, 0.04), rough=0.6)
    box("housing", (0.5, 0.82, 0.06), (0.5, 0.5, 0.05), frame, bevel=0.015)
    box("inner", (0.42, 0.74, 0.02), (0.5, 0.5, 0.085), dark)
    lamp = glow("lamp", (0.1, 1.0, 0.25) if on else (1.0, 0.12, 0.08), 2.5)
    ball("lamp", 0.045, (0.5, 0.8, 0.1), lamp)
    box("slot", (0.05, 0.36, 0.02), (0.5, 0.48, 0.095), mat("slot", (0.0, 0.0, 0.0)))
    handle = mat("handle", (0.82, 0.83, 0.86), metal=1.0, rough=0.25)
    ly = 0.64 if on else 0.32
    cyl("lever", 0.022, 0.2, (0.5, ly, 0.13), handle, axis="X")
    ball("knob", 0.035, (0.6, ly, 0.13), mat("knob", (0.85, 0.1, 0.08), rough=0.4))
    arrow = glow("arrow", (0.1, 1.0, 0.25), 2.0) if on else mat("arrow_off", (0.15, 0.2, 0.15), rough=0.5)
    for i in range(3):
        y = 0.22 + i * 0.07
        for s in (-1, 1):
            box("chev", (0.09, 0.02, 0.01), (0.5 + s * 0.12, y, 0.1), arrow, rot=(0, 0, s * math.radians(35)))
    bpy.ops.object.text_add(location=(0.5, 0.12, 0.1))
    t = bpy.context.active_object
    t.data.body = "EXIT"
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.size = 0.09
    t.data.extrude = 0.004
    t.data.materials.append(arrow)


def _door(band):
    steel = mat("steel", (0.26, 0.33, 0.36), metal=0.7, rough=0.4, noise=0.25, noise_scale=14)
    rib = mat("rib", (0.34, 0.42, 0.45), metal=0.75, rough=0.35)
    edge = mat("edge", (0.12, 0.14, 0.15), metal=0.6, rough=0.5)
    box("slab", (3, 3, 0.02), (0.5, 0.5, -0.01), steel)
    box("edgeL", (0.035, 1.0, 0.05), (0.0175, 0.5, 0.0), edge, bevel=0.005)
    box("edgeR", (0.035, 1.0, 0.05), (0.9825, 0.5, 0.0), edge, bevel=0.005)
    box("edgeT", (1.0, 0.035, 0.05), (0.5, 0.9825, 0.0), edge, bevel=0.005)
    box("edgeB", (1.0, 0.035, 0.05), (0.5, 0.0175, 0.0), edge, bevel=0.005)
    for i in range(1, 8):
        box("rib", (0.88, 0.03, 0.022), (0.5, i / 8.0, 0.011), rib, bevel=0.008)
    box("window", (0.42, 0.07, 0.03), (0.5, 0.84, 0.0), mat("wframe", (0.1, 0.1, 0.11), metal=0.5))
    box("glass", (0.38, 0.045, 0.02), (0.5, 0.84, 0.006), glow("glass", (0.25, 0.75, 0.85), 1.0))
    box("handle_plate", (0.07, 0.2, 0.02), (0.88, 0.48, 0.02), edge, bevel=0.006)
    cyl("handle", 0.014, 0.14, (0.88, 0.48, 0.04), mat("chrome", (0.8, 0.8, 0.83), metal=1.0, rough=0.2), axis="Y")
    if band:
        bm = mat("band", band, rough=0.5, emit=band, emit_strength=0.25)
        box("band", (0.9, 0.12, 0.03), (0.5, 0.5, 0.03), bm, bevel=0.006)
        box("card", (0.14, 0.09, 0.01), (0.5, 0.5, 0.05), mat("card", (0.92, 0.92, 0.88), rough=0.5))
        box("stripe", (0.14, 0.02, 0.01), (0.5, 0.515, 0.056), mat("stripe", (0.05, 0.05, 0.05)))


def _floor():
    grout = mat("grout", (0.12, 0.12, 0.12), rough=1.0)
    box("grout", (3, 3, 0.02), (0.5, 0.5, -0.01), grout)
    rng = random.Random(3)
    for ix in range(2):
        for iy in range(2):
            g = rng.uniform(0.3, 0.38)
            m = mat(f"tile{ix}{iy}", (g, g * 0.98, g * 0.95), rough=0.9, noise=0.45, noise_scale=9, seed=ix * 2 + iy + 1)
            box("tile", (0.49, 0.49, 0.02), (0.25 + ix * 0.5, 0.25 + iy * 0.5, 0.01), m, bevel=0.01)
    drain = mat("drain", (0.2, 0.2, 0.22), metal=0.8, rough=0.5)
    cyl("drain", 0.05, 0.01, (0.75, 0.25, 0.022), drain, verts=32)
    for i in range(4):
        box("slit", (0.07, 0.008, 0.01), (0.75, 0.22 + i * 0.02, 0.028), mat("slit", (0.0, 0.0, 0.0)))


def _ceiling():
    frame = mat("cframe", (0.2, 0.2, 0.22), metal=0.4, rough=0.6)
    box("frame", (3, 3, 0.02), (0.5, 0.5, -0.01), frame)
    rng = random.Random(5)
    for ix in range(2):
        for iy in range(2):
            g = rng.uniform(0.32, 0.38)
            m = mat(f"panel{ix}{iy}", (g, g, g * 1.03), rough=0.95, noise=0.3, noise_scale=40, seed=ix * 2 + iy + 3)
            box("panel", (0.46, 0.46, 0.015), (0.25 + ix * 0.5, 0.25 + iy * 0.5, 0.0), m, bevel=0.006)


def _label(text, loc, size, m):
    bpy.ops.object.text_add(location=loc)
    t = bpy.context.active_object
    t.data.body = text
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.size = size
    t.data.extrude = 0.003
    t.data.materials.append(m)
    return t


def _terminal(on):
    """Security terminal: a screen showing three coloured sequence lamps."""
    _metal_base()
    frame = mat("frame", (0.3, 0.32, 0.36), metal=0.8, rough=0.35)
    box("housing", (0.7, 0.62, 0.06), (0.5, 0.56, 0.05), frame, bevel=0.02)
    screen = glow("screen", (0.1, 0.8, 0.3) if on else (0.04, 0.25, 0.35), 0.45)
    box("screen", (0.58, 0.32, 0.02), (0.5, 0.64, 0.085), screen)
    for i, c in enumerate([(1.0, 0.12, 0.08), (0.15, 0.4, 1.0), (1.0, 0.75, 0.1)]):
        ball("seq", 0.04, (0.33 + i * 0.17, 0.42, 0.1), glow("seq%d" % i, c, 1.2))
    keys = mat("keys", (0.12, 0.12, 0.14), rough=0.5)
    for ix in range(5):
        box("key", (0.07, 0.04, 0.02), (0.3 + ix * 0.1, 0.3, 0.09), keys, bevel=0.005)
    _label("OVERRIDE" if not on else "OPEN", (0.5, 0.86, 0.1), 0.07, glow("tlabel", (0.9, 0.9, 0.8), 1.5))


def _breaker(color, on):
    """A wall breaker with a coloured lamp and a big throw lever."""
    _metal_base()
    frame = mat("frame", (0.5, 0.52, 0.55), metal=0.8, rough=0.35)
    box("box", (0.46, 0.66, 0.08), (0.5, 0.5, 0.05), frame, bevel=0.02)
    band = mat("band", color, rough=0.5)
    box("band", (0.46, 0.08, 0.085), (0.5, 0.86, 0.05), band, bevel=0.01)
    lamp = glow("lamp", color, 1.6) if on else mat("lamp_off", tuple(c * 0.25 for c in color), rough=0.4)
    ball("lamp", 0.06, (0.5, 0.72, 0.1), lamp)
    box("slot", (0.05, 0.32, 0.02), (0.5, 0.42, 0.095), mat("slot", (0.0, 0.0, 0.0)))
    handle = mat("handle", (0.82, 0.83, 0.86), metal=1.0, rough=0.25)
    ly = 0.55 if on else 0.29
    cyl("lever", 0.024, 0.22, (0.5, ly, 0.14), handle, axis="X")
    ball("knob", 0.04, (0.61, ly, 0.14), band)


def _locker():
    """The Confiscation Locker: a chute with a weapon-shaped intake."""
    _metal_base()
    olive = mat("olive", (0.25, 0.28, 0.2), metal=0.5, rough=0.5, noise=0.25, noise_scale=12)
    trim = mat("trim", (0.85, 0.6, 0.1), metal=0.6, rough=0.4)
    box("body", (0.74, 0.86, 0.07), (0.5, 0.5, 0.05), olive, bevel=0.02)
    box("hatch", (0.56, 0.2, 0.03), (0.5, 0.55, 0.09), mat("hatch", (0.05, 0.05, 0.06), rough=0.6), bevel=0.01)
    box("rifle_outline", (0.44, 0.04, 0.01), (0.5, 0.55, 0.106), trim)
    for i in range(6):
        box("hazard", (0.06, 0.12, 0.01), (0.2 + i * 0.12, 0.2, 0.09), trim if i % 2 else mat("blk", (0.02, 0.02, 0.02)))
    ball("lamp", 0.035, (0.5, 0.8, 0.1), glow("llamp", (1.0, 0.7, 0.1), 2.5))
    _label("UPGRADE", (0.5, 0.36, 0.1), 0.065, trim)


def _range():
    """Calibration pod console: a firing-window frame with a target sight."""
    _metal_base()
    frame = mat("frame", (0.35, 0.37, 0.4), metal=0.8, rough=0.35)
    box("console", (0.72, 0.5, 0.07), (0.5, 0.4, 0.05), frame, bevel=0.02)
    sight = glow("sight", (1.0, 0.35, 0.1), 2.0)
    for r_ in (0.13, 0.08):
        bpy.ops.mesh.primitive_torus_add(major_radius=r_, minor_radius=0.008, location=(0.5, 0.45, 0.095))
        bpy.context.active_object.data.materials.append(sight)
    box("cross_h", (0.36, 0.012, 0.01), (0.5, 0.45, 0.095), sight)
    box("cross_v", (0.012, 0.36, 0.01), (0.5, 0.45, 0.095), sight)
    _label("CALIBRATE", (0.5, 0.8, 0.1), 0.075, glow("rlabel", (0.95, 0.85, 0.6), 1.5))


BUILDERS = {
    "stone": lambda: _stone(),
    "metal": _metal_base,
    "rust": _rust,
    "sigil": _sigil,
    "exit": lambda: _exit(False),
    "exit_on": lambda: _exit(True),
    "stone_secret": lambda: (_stone(), _scuffs()),
    "metal_secret": lambda: (_metal_base(), _scuffs()),
    "door": lambda: _door(None),
    "door_gold": lambda: _door((0.95, 0.68, 0.08)),
    "door_red": lambda: _door((0.8, 0.1, 0.08)),
    "door_blue": lambda: _door((0.12, 0.32, 0.9)),
    "door_vault": lambda: _door((0.6, 0.2, 0.85)),
    "floor": _floor,
    "ceiling": _ceiling,
    "terminal": lambda: _terminal(False),
    "terminal_on": lambda: _terminal(True),
    "breaker_red": lambda: _breaker((0.9, 0.1, 0.07), False),
    "breaker_red_on": lambda: _breaker((0.9, 0.1, 0.07), True),
    "breaker_blue": lambda: _breaker((0.12, 0.35, 1.0), False),
    "breaker_blue_on": lambda: _breaker((0.12, 0.35, 1.0), True),
    "breaker_gold": lambda: _breaker((1.0, 0.72, 0.08), False),
    "breaker_gold_on": lambda: _breaker((1.0, 0.72, 0.08), True),
    "locker": _locker,
    "range": _range,
}


def build(only=()):
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        _setup()
        fn()
        render(os.path.join(OUT, name + ".png"), RES)
        print("rendered", name)
