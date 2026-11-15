"""First-person weapon renders: Rook's gloved hands and orange prison sleeves
holding each weapon, seen from eye level. Each weapon gets four frames:
0 idle, 1 fire (muzzle flash / stab), 2 peak recoil, 3 recovering.
"""
import math
import os

from mathutils import Vector

from bb_common import ASSETS_DIR, ball, box, camera, cyl, empty, glow, light, mat, rad, render, reset, save_blend

OUT = os.path.join(ASSETS_DIR, "tex")
RES = 512


def _setup():
    reset(transparent=True, ambient=0.3)
    camera((0, 0, 0.17), (0, 1, -0.3), lens=38)
    light("SUN", 2.4, (-1.0, -0.5, 1.4), (0, 0.5, -0.1), (1.0, 0.95, 0.88))
    light("SUN", 0.7, (1.2, 0.0, -0.3), (0, 0.5, -0.1), (0.7, 0.8, 1.0))
    light("SUN", 1.6, (0.4, 2.0, 0.8), (0, 0.5, -0.1), (1.0, 0.85, 0.7))


def _mats():
    return {
        "gun": mat("gun", (0.07, 0.07, 0.08), metal=0.75, rough=0.38),
        "gun2": mat("gun2", (0.13, 0.13, 0.15), metal=0.7, rough=0.45),
        "glove": mat("glove", (0.08, 0.075, 0.07), rough=0.65, noise=0.3, noise_scale=30),
        "sleeve": mat("sleeve", (0.82, 0.36, 0.06), rough=0.85, noise=0.3, noise_scale=14),
        "cuff": mat("cuff", (0.18, 0.18, 0.2), rough=0.7),
        "wood": mat("wood", (0.3, 0.17, 0.08), rough=0.6, noise=0.3, noise_scale=40),
        "red": mat("red", (0.6, 0.08, 0.05), rough=0.5),
        "steel": mat("steel", (0.7, 0.72, 0.75), metal=1.0, rough=0.2),
        "dark": mat("dark", (0.01, 0.01, 0.01), rough=0.9),
    }


def limb(name, p0, p1, r, m, parent=None, r2=None):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    o = cyl(name, r, d.length, (p0 + p1) / 2, m, parent, r2=r2, verts=24)
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return o


def arm(m, hand, elbow, r=0.045):
    """Orange sleeve running from below the screen up to a gloved wrist."""
    hand, elbow = Vector(hand), Vector(elbow)
    limb("sleeve", elbow, hand + (elbow - hand).normalized() * 0.03, r, m["sleeve"], r2=r * 0.85)
    limb("cuff", hand + (elbow - hand).normalized() * 0.035, hand + (elbow - hand).normalized() * 0.015, r * 0.9, m["cuff"])


def fist(m, center, size=1.0, parent=None):
    """A gloved fist: palm block plus four curled fingers and a thumb."""
    c = Vector(center)
    box("palm", (0.05 * size, 0.055 * size, 0.07 * size), c, m["glove"], parent, bevel=0.012)
    for i in range(4):
        ball("finger", 0.014 * size, c + Vector((0.0, 0.03 * size, 0.025 * size - i * 0.017 * size)), m["glove"], parent,
             scale=(1.6, 1.0, 0.9))
    limb("thumb", c + Vector((-0.028, 0.0, 0.02)) * size, c + Vector((-0.02, 0.04, 0.03)) * size, 0.011 * size, m["glove"], parent)


def flash(at, size=1.0):
    a = Vector(at)
    core = glow("flash_core", (1.0, 0.92, 0.6), 4)
    outer = glow("flash", (1.0, 0.5, 0.08), 3)
    ball("flash_core", 0.025 * size, a, core)
    ball("flash_ball", 0.045 * size, a + Vector((0, 0.01, 0)), outer, scale=(1, 0.6, 1))
    for i in range(6):
        ang = i * math.tau / 6 + 0.3
        tip = a + Vector((math.cos(ang) * 0.09 * size, 0.03 * size, math.sin(ang) * 0.09 * size))
        limb("spike", a, tip, 0.012 * size, outer, r2=0.0)
    limb("jet", a, a + Vector((0, 0.12 * size, 0)), 0.02 * size, outer, r2=0.0)


# ------------------------------------------------------------------ weapons

KICK = (0.0, 1.0, 0.75, 0.3)


def sidearm(frame):
    m = _mats()
    kick = 0.012 * KICK[frame]
    g = empty("pistol", (0.0, 0.0 - kick, -0.005 + kick * 0.8), rot=rad(-3 - kick * 300, 0, 0))
    box("slide", (0.032, 0.18, 0.036), (0, 0.47, -0.05), m["gun"], g, bevel=0.004)
    box("frame", (0.03, 0.14, 0.026), (0, 0.46, -0.08), m["gun2"], g, bevel=0.004)
    box("grip", (0.03, 0.045, 0.1), (0, 0.405, -0.12), m["gun2"], g, rot=rad(-15, 0, 0), bevel=0.006)
    for x in (-0.009, 0.009):
        box("rsight", (0.006, 0.008, 0.01), (x, 0.385, -0.028), m["gun"], g)
    box("fsight", (0.005, 0.008, 0.01), (0, 0.55, -0.028), m["gun"], g)
    cyl("bore", 0.007, 0.004, (0, 0.561, -0.05), m["dark"], g, axis="Y")
    for i in range(6):
        box("serration", (0.033, 0.003, 0.03), (0, 0.39 + i * 0.008, -0.05), m["gun2"], g)
    fist(m, (0.004, 0.41, -0.13), 1.0, g)
    arm(m, (0.004, 0.40 - kick, -0.16), (0.07, 0.18, -0.36))
    if frame == 1:
        flash((0, 0.6, -0.05), 1.0)


def rifle(frame):
    m = _mats()
    kick = 0.015 * KICK[frame]
    g = empty("rifle", (0.02, -kick, 0), rot=rad(-2 - kick * 200, 0, 0))
    box("receiver", (0.05, 0.26, 0.06), (0, 0.48, -0.06), m["gun"], g, bevel=0.006)
    box("rail", (0.03, 0.22, 0.012), (0, 0.48, -0.024), m["gun2"], g)
    box("guard", (0.048, 0.16, 0.05), (0, 0.66, -0.06), m["gun2"], g, bevel=0.008)
    for i in range(4):
        box("vent", (0.05, 0.012, 0.02), (0, 0.6 + i * 0.035, -0.045), m["dark"], g)
    cyl("barrel", 0.011, 0.14, (0, 0.8, -0.055), m["gun"], g, axis="Y")
    cyl("brake", 0.016, 0.03, (0, 0.87, -0.055), m["gun2"], g, axis="Y")
    box("fsight", (0.006, 0.01, 0.03), (0, 0.72, -0.02), m["gun"], g)
    box("rsight", (0.022, 0.012, 0.02), (0, 0.38, -0.012), m["gun"], g)
    box("mag", (0.035, 0.05, 0.12), (0.0, 0.52, -0.14), m["gun"], g, rot=rad(12, 0, 0), bevel=0.005)
    box("grip", (0.035, 0.04, 0.09), (0, 0.42, -0.12), m["gun2"], g, rot=rad(-15, 0, 0), bevel=0.006)
    fist(m, (0.0, 0.42, -0.13), 1.0, g)
    arm(m, (0.02, 0.41 - kick, -0.16), (0.12, 0.2, -0.36))
    fist(m, (-0.012, 0.64, -0.1), 0.95, g)
    arm(m, (-0.02, 0.62 - kick, -0.12), (-0.14, 0.32, -0.38))
    if frame == 1:
        flash((0.02, 0.9, -0.055), 1.1)


def rotary(frame):
    m = _mats()
    kick = 0.008 * KICK[frame]
    spin = math.radians(30) * frame  # barrels advance 30 degrees per frame
    g = empty("rotary", (0.0, -kick, 0), rot=rad(-2, 0, 0))
    axis_z = -0.07
    for i in range(6):
        a = i * math.tau / 6 + spin
        cyl("barrel", 0.012, 0.4, (math.cos(a) * 0.038, 0.68, axis_z + math.sin(a) * 0.038), m["gun"], g, axis="Y", verts=14)
    for y in (0.56, 0.78):
        cyl("clamp", 0.056, 0.022, (0, y, axis_z), m["gun2"], g, axis="Y", verts=32)
    cyl("drum", 0.05, 0.08, (0, 0.44, axis_z), m["gun2"], g, axis="Y", verts=32)
    box("motor", (0.1, 0.09, 0.08), (0, 0.35, axis_z - 0.01), m["gun"], g, bevel=0.012)
    box("stripe", (0.102, 0.092, 0.02), (0, 0.35, axis_z + 0.02), m["red"], g)
    limb("carry", (0, 0.4, axis_z + 0.09), (0, 0.5, axis_z + 0.09), 0.01, m["steel"], g)
    for y in (0.4, 0.5):
        limb("post", (0, y, axis_z + 0.06), (0, y, axis_z + 0.09), 0.008, m["steel"], g)
    box("grip", (0.035, 0.04, 0.1), (0.0, 0.34, -0.16), m["gun2"], g, rot=rad(-10, 0, 0), bevel=0.006)
    fist(m, (0.0, 0.34, -0.17), 1.05, g)
    arm(m, (0.02, 0.33, -0.2), (0.16, 0.15, -0.38), 0.05)
    fist(m, (-0.06, 0.5, -0.1), 1.0, g)
    arm(m, (-0.07, 0.48, -0.13), (-0.2, 0.3, -0.38), 0.05)
    if frame == 1:
        flash((0, 0.87, axis_z), 1.4)


def shiv(frame):
    m = _mats()
    idle = ((0.09, 0.36, -0.15), (-15, 0, 15))
    stab = ((0.0, 0.5, -0.08), (-55, 0, -10))
    t = KICK[frame]
    pos = tuple(idle[0][i] + (stab[0][i] - idle[0][i]) * t for i in range(3))
    rot = rad(*(idle[1][i] + (stab[1][i] - idle[1][i]) * t for i in range(3)))
    h = empty("shiv", pos, rot=rot)
    blade_mat = mat("blade", (0.6, 0.62, 0.64), metal=1.0, rough=0.35, noise=0.35, noise_scale=30)
    tape = mat("tape", (0.75, 0.72, 0.6), rough=0.9, noise=0.3, noise_scale=50)
    cyl("handle", 0.016, 0.09, (0, 0, 0.0), tape, h, verts=12)
    for i in range(4):
        cyl("wrap", 0.018, 0.008, (0, 0, -0.035 + i * 0.022), tape, h, verts=12)
    blade = cyl("blade", 0.018, 0.16, (0, 0, 0.125), blade_mat, h, verts=4, r2=0.001, smooth=False)
    blade.scale = (1.0, 0.25, 1.0)
    fist(m, (0, 0, -0.005), 1.0, h)
    hand_world = h.matrix_world if False else None
    _ = hand_world
    wrist = Vector(pos) + Vector((0.01, -0.03, -0.05))
    arm(m, wrist, (0.16 - 0.08 * t, 0.12 + 0.08 * t, -0.38 + 0.02 * t))


BUILDERS = {"sidearm": sidearm, "rifle": rifle, "rotary": rotary, "shiv": shiv}


def build(only=()):
    for name, fn in BUILDERS.items():
        if only and name not in only:
            continue
        for frame in range(4):
            _setup()
            fn(frame)
            render(os.path.join(OUT, f"w_{name}_{frame}.png"), RES)
            print("rendered", name, frame)
    _setup()
    rifle(0)
    save_blend("weapon_example_rifle")
