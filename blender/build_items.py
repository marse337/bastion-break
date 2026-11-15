"""Pickup and prop sprites (billboards), rendered front-on with an
orthographic camera. The frame covers exactly one tile (1 x 1 units, floor
at the bottom edge), matching how the game places Sprite3D billboards.
Small pickups are tilted toward the camera so their tops read better.
"""
import math
import os

from bb_common import (ASSETS_DIR, ball, box, camera, cyl, empty, glow, mat, rad, render, reset, save_blend,
                       studio, torus)

OUT = os.path.join(ASSETS_DIR, "tex")
RES = 256


def _setup():
    reset(transparent=True, ambient=0.3)
    camera((0, -6, 0.5), (0, 0, 0.5), ortho=1.0)
    studio(key=2.2, fill=0.8, rim=1.4)


def _root(tilt=18, scale=1.4):
    r = empty("root", rot=rad(tilt, 0, 0))
    r.scale = (scale, scale, scale)
    return r


def _brass():
    return mat("brass", (0.85, 0.6, 0.25), metal=1.0, rough=0.3)


def _round(parent, x, y, z, brass, tip):
    cyl("case", 0.012, 0.05, (x, y, z + 0.025), brass, parent, verts=12)
    cyl("tip", 0.012, 0.022, (x, y, z + 0.061), tip, parent, verts=12, r2=0.002)


def ammo():
    r = _root()
    olive = mat("olive", (0.22, 0.27, 0.13), rough=0.7, noise=0.3, noise_scale=20)
    box("crate", (0.26, 0.15, 0.12), (0, 0, 0.06), olive, r, bevel=0.01)
    box("stripe", (0.262, 0.152, 0.025), (0, 0, 0.07), mat("yellow", (0.9, 0.7, 0.1), rough=0.6), r)
    brass, tip = _brass(), mat("copper", (0.7, 0.35, 0.2), metal=1.0, rough=0.3)
    for i in range(5):
        _round(r, -0.09 + i * 0.045, 0.0, 0.12, brass, tip)


def clip():
    r = _root(10)
    steel = mat("mag", (0.08, 0.08, 0.09), metal=0.7, rough=0.4)
    brass, tip = _brass(), mat("copper", (0.7, 0.35, 0.2), metal=1.0, rough=0.3)
    for i, (x, ang) in enumerate(((-0.05, -12), (0.05, 8))):
        m = empty("mag", (x, 0, 0), r, rad(0, ang, 0))
        box("body", (0.06, 0.03, 0.13), (0, 0, 0.065), steel, m, bevel=0.004)
        _round(m, 0, 0, 0.13, brass, tip)


def medkit():
    r = _root()
    white = mat("white", (0.9, 0.9, 0.86), rough=0.45)
    red = mat("red", (0.8, 0.05, 0.05), rough=0.5)
    box("case", (0.26, 0.11, 0.17), (0, 0, 0.085), white, r, bevel=0.015)
    box("crossV", (0.04, 0.01, 0.12), (0, -0.056, 0.085), red, r)
    box("crossH", (0.12, 0.01, 0.04), (0, -0.056, 0.085), red, r)
    torus("handle", 0.04, 0.008, (0, 0, 0.17), mat("grey", (0.3, 0.3, 0.32), rough=0.5), r, rot=rad(90, 0, 0))
    box("latch", (0.04, 0.02, 0.02), (0, -0.05, 0.165), mat("chrome", (0.8, 0.8, 0.82), metal=1.0, rough=0.2), r)


def food():
    r = _root()
    tin = mat("tin", (0.65, 0.66, 0.68), metal=1.0, rough=0.3)
    label = mat("label", (0.15, 0.4, 0.18), rough=0.6)
    cyl("can", 0.06, 0.11, (-0.05, 0, 0.055), tin, r, verts=32)
    cyl("label", 0.0605, 0.06, (-0.05, 0, 0.055), label, r, verts=32)
    cyl("can2", 0.06, 0.11, (0.07, -0.02, 0.06), tin, r, rot=rad(0, 90, 15), verts=32)
    cyl("label2", 0.0605, 0.06, (0.07, -0.02, 0.06), label, r, rot=rad(0, 90, 15), verts=32)
    box("bread", (0.1, 0.06, 0.05), (0.0, 0.07, 0.025), mat("bread", (0.6, 0.38, 0.15), rough=0.8), r, bevel=0.015)


def gem():
    r = _root(0)
    g = mat("gem", (0.2, 0.85, 1.0), metal=0.2, rough=0.05, emit=(0.1, 0.6, 0.8), emit_strength=0.8)
    cyl("top", 0.07, 0.06, (0, 0, 0.13), g, r, verts=8, r2=0.03, smooth=False)
    cyl("bottom", 0.07, 0.1, (0, 0, 0.05), g, r, verts=8, r2=0.0, rot=rad(180, 0, 0), smooth=False)
    ball("sparkle", 0.012, (-0.03, -0.07, 0.15), glow("spark", (1, 1, 1), 6), r)


def idol():
    r = _root(8)
    gold = mat("gold", (1.0, 0.72, 0.2), metal=1.0, rough=0.25)
    box("base", (0.16, 0.12, 0.04), (0, 0, 0.02), mat("onyx", (0.08, 0.06, 0.06), rough=0.3), r, bevel=0.008)
    cyl("robe", 0.055, 0.15, (0, 0, 0.115), gold, r, r2=0.03)
    ball("head", 0.035, (0, 0, 0.215), gold, r)
    torus("halo", 0.05, 0.006, (0, 0.01, 0.23), gold, r, rot=rad(90, 0, 0))
    for s in (-1, 1):
        cyl("arm", 0.013, 0.08, (s * 0.04, -0.02, 0.15), gold, r, rot=rad(60, s * 30, 0))
    ball("eye", 0.008, (0, -0.032, 0.22), glow("ruby", (1, 0.1, 0.1), 3), r)


def life():
    r = _root(0)
    cyl("pedestal", 0.06, 0.05, (0, 0, 0.025), mat("dark", (0.1, 0.1, 0.12), metal=0.6, rough=0.4), r, r2=0.045)
    ball("orb", 0.08, (0, 0, 0.14), mat("orb", (0.3, 0.6, 1.0), rough=0.1, emit=(0.25, 0.55, 1.0), emit_strength=2.5), r)
    ball("core", 0.04, (0, -0.02, 0.14), glow("core", (0.8, 0.95, 1.0), 6), r)
    torus("ring", 0.11, 0.006, (0, 0, 0.14), glow("ringglow", (0.5, 0.8, 1.0), 3), r, rot=rad(70, 20, 0))


def _gun_rifle(parent, gun, wood):
    box("receiver", (0.22, 0.05, 0.06), (0, 0, 0), gun, parent, bevel=0.006)
    cyl("barrel", 0.012, 0.2, (-0.2, 0, 0.01), gun, parent, axis="X")
    box("guard", (0.12, 0.045, 0.04), (-0.15, 0, 0.0), gun, parent, bevel=0.006)
    box("stock", (0.14, 0.04, 0.07), (0.17, 0, -0.01), wood, parent, bevel=0.01)
    box("mag", (0.04, 0.03, 0.09), (-0.04, 0, -0.07), gun, parent, rot=rad(0, -12, 0), bevel=0.004)
    box("sight", (0.03, 0.01, 0.025), (0.0, 0, 0.04), gun, parent)


def rifle_item():
    r = _root(25)
    holder = empty("gun", (0, 0, 0.07), r, rad(0, 0, 8))
    _gun_rifle(holder, mat("gun", (0.08, 0.08, 0.09), metal=0.7, rough=0.4), mat("wood", (0.32, 0.18, 0.08), rough=0.6))


def _gun_rotary(parent, gun, red, spin=0.0):
    for i in range(6):
        a = i * math.tau / 6 + spin
        cyl("barrel", 0.011, 0.3, (-0.17, math.cos(a) * 0.028, math.sin(a) * 0.028), gun, parent, axis="X", verts=12)
    for x in (-0.3, -0.12):
        cyl("clamp", 0.045, 0.02, (x, 0, 0), gun, parent, axis="X")
    cyl("drum", 0.06, 0.14, (0.04, 0, 0), gun, parent, axis="X")
    box("motor", (0.12, 0.08, 0.09), (0.16, 0, 0), gun, parent, bevel=0.01)
    box("stripe", (0.122, 0.082, 0.02), (0.16, 0, 0.02), red, parent)
    torus("grip", 0.05, 0.01, (0.05, 0, 0.07), gun, parent, rot=rad(90, 0, 0))


def rotary_item():
    r = _root(25)
    holder = empty("gun", (0.02, 0, 0.07), r, rad(0, 0, 10))
    _gun_rotary(holder, mat("gun", (0.1, 0.1, 0.11), metal=0.8, rough=0.35), mat("red", (0.6, 0.08, 0.05), rough=0.5))


def keycard(color):
    def build():
        r = _root(0)
        card = empty("card", (0, 0, 0.08), r, rad(-15, 10, 0))
        box("body", (0.13, 0.008, 0.085), (0, 0, 0), mat("card", color, rough=0.4, emit=color, emit_strength=0.3), card, bevel=0.004)
        box("stripe", (0.131, 0.009, 0.015), (0, 0, 0.02), mat("black", (0.02, 0.02, 0.02)), card)
        box("chip", (0.03, 0.01, 0.022), (-0.03, -0.001, -0.015), mat("gold", (1.0, 0.75, 0.25), metal=1, rough=0.3), card)
        box("photo", (0.03, 0.01, 0.035), (0.04, -0.001, -0.012), mat("white", (0.9, 0.9, 0.85)), card)
        torus("ring", 0.018, 0.003, (-0.075, 0, 0.035), mat("chrome", (0.8, 0.8, 0.82), metal=1, rough=0.2), card, rot=rad(90, 0, 0))
    return build


def prison_map():
    r = _root(35)
    paper = mat("blueprint", (0.12, 0.25, 0.65), rough=0.8)
    ink = glow("ink", (0.85, 0.92, 1.0), 1.2)
    box("sheet", (0.26, 0.18, 0.004), (0.02, 0, 0.004), paper, r)
    for i in range(5):
        box("hline", (0.22, 0.004, 0.003), (0.02, -0.07 + i * 0.035, 0.007), ink, r)
    for x in (-0.07, 0.0, 0.08):
        box("vline", (0.004, 0.14, 0.003), (x, 0, 0.007), ink, r)
    box("room", (0.05, 0.04, 0.003), (0.1, 0.05, 0.008), glow("mark", (1.0, 0.3, 0.2), 2.0), r)
    cyl("roll", 0.025, 0.2, (-0.13, 0, 0.025), paper, r, axis="Y")
    cyl("rollend", 0.026, 0.004, (-0.13, -0.1, 0.025), ink, r, axis="Y")


def pillar():
    stone = mat("pillar", (0.42, 0.41, 0.4), rough=0.85, noise=0.3, noise_scale=12)
    trim = mat("trim", (0.32, 0.31, 0.3), rough=0.8, noise=0.2, noise_scale=20)
    box("base", (0.36, 0.36, 0.08), (0, 0, 0.04), trim, bevel=0.015)
    box("cap", (0.36, 0.36, 0.08), (0, 0, 0.96), trim, bevel=0.015)
    cyl("shaft", 0.13, 0.84, (0, 0, 0.5), stone, verts=40)
    for z in (0.11, 0.89):
        torus("ring", 0.135, 0.015, (0, 0, z), trim)


def lamp():
    metal = mat("shade", (0.2, 0.28, 0.22), metal=0.7, rough=0.4)
    cyl("cord", 0.006, 0.12, (0, 0, 0.94), mat("cord", (0.05, 0.05, 0.05)), verts=8)
    cyl("shade", 0.03, 0.08, (0, 0, 0.84), metal, r2=0.13, rot=rad(180, 0, 0), verts=32)
    ball("bulb", 0.035, (0, 0, 0.8), glow("bulb", (1.0, 0.9, 0.55), 6))
    torus("rim", 0.13, 0.005, (0, 0, 0.8), metal)


def barrel():
    r = _root(4, 1.0)
    paint = mat("paint", (0.12, 0.25, 0.14), metal=0.5, rough=0.5, noise=0.4, noise_scale=8)
    cyl("body", 0.15, 0.42, (0, 0, 0.21), paint, r, verts=40)
    for z in (0.06, 0.21, 0.36):
        torus("rib", 0.152, 0.008, (0, 0, z), paint, r)
    cyl("lid", 0.14, 0.01, (0, 0, 0.425), mat("lid", (0.2, 0.22, 0.2), metal=0.7, rough=0.4), r, verts=40)
    box("label", (0.1, 0.01, 0.09), (0, -0.148, 0.21), mat("hazard", (0.95, 0.75, 0.05), rough=0.5), r)
    ball("sym", 0.025, (0, -0.155, 0.21), mat("black", (0.02, 0.02, 0.02)), r, scale=(1, 0.2, 1))


def plasma():
    ball("core", 0.045, (0, 0, 0.5), glow("pcore", (1.0, 0.95, 0.7), 8))
    ball("glow", 0.08, (0, 0, 0.5), glow("pglow", (1.0, 0.3, 0.05), 4))
    for i in range(8):
        a = i * math.tau / 8
        cyl("spike", 0.02, 0.09, (math.cos(a) * 0.09, 0, 0.5 + math.sin(a) * 0.09), glow("pspike", (1.0, 0.45, 0.1), 3),
            r2=0.0, rot=(0, -a + math.pi / 2, 0))


def blast(frame):
    def build():
        import random
        rng = random.Random(9)
        size = (0.14, 0.26, 0.34)[frame]
        fire = glow("fire", (1.0, 0.55, 0.1), (6, 4, 1.5)[frame])
        hot = glow("hot", (1.0, 0.95, 0.6), (8, 4, 0.5)[frame])
        smoke = mat("smoke", (0.08, 0.07, 0.07), rough=1.0)
        if frame < 2:
            ball("hot", size * 0.5, (0, -0.1, 0.5), hot)
        for i in range(10):
            a = rng.uniform(0, math.tau)
            r = rng.uniform(0.3, 1.0) * size
            p = (math.cos(a) * r, rng.uniform(-0.05, 0.05), 0.5 + math.sin(a) * r)
            ball("puff", size * rng.uniform(0.35, 0.6), p, smoke if (frame == 2 and i % 2) or i > 7 else fire)
    return build


BUILDERS = {
    "ammo": ammo, "clip": clip, "medkit": medkit, "food": food, "gem": gem, "idol": idol,
    "life": life, "rifle": rifle_item, "rotary": rotary_item,
    "key_red": keycard((0.85, 0.1, 0.08)), "key_blue": keycard((0.12, 0.35, 0.95)),
    "map": prison_map, "key_gold": keycard((0.95, 0.68, 0.08)),
    "plasma": plasma, "blast_0": blast(0), "blast_1": blast(1), "blast_2": blast(2), "pillar": pillar, "lamp": lamp, "barrel": barrel,
}


def build(only=()):
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        _setup()
        fn()
        render(os.path.join(OUT, name + ".png"), RES)
        print("rendered", name)
    _setup()
    pillar()
    save_blend("item_example_pillar")
