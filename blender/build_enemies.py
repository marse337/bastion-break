"""Enemy models, keyframed animations and directional sprite renders.

Each enemy is a jointed model built from primitives (joints are empties, so
the poses are easy to tweak in Blender). Every pose is keyframed into the
timeline and saved to blender/scenes/<kind>.blend, then rendered:

  stand, walk 0-7        -> 8 view angles (d0 = facing the viewer, then every
                            45 degrees around the model, matching the game).
                            Hounds use a 4-frame gallop.
  aim (telegraph), fire 0-1 (flash, recoil), pain (with sparks),
  die 0-3, dead          -> front view only (d0)

The hostage is a fellow prisoner tied to a post (bound 0-1, freed 0-1, dead).

Output: assets/enemies/<kind>/<pose>_<frame>_d<dir>.png
"""
import math
import os

import bpy

from bb_common import (ASSETS_DIR, ball, box, camera, cyl, empty, glow, mat, rad, render, reset, save_blend,
                       studio, torus)

RES = 384

WALK_FRAMES = {"hound": 4}
DIE_FRAMES = 4


def make_seq(kind):
    """(pose, frame, keyframe number, rendered from 8 directions?)"""
    walk = WALK_FRAMES.get(kind, 8)
    return ([("stand", 0, 1, True)]
            + [("walk", i, 10 + i * 2, True) for i in range(walk)]
            + [("aim", 0, 30, False), ("fire", 0, 32, False), ("fire", 1, 33, False), ("pain", 0, 40, False)]
            + [("die", i, 50 + i * 3, False) for i in range(DIE_FRAMES)]
            + [("dead", 0, 64, False)])


def _setup():
    reset(transparent=True, ambient=0.3, samples=16)
    camera((0, -6, 0.5), (0, 0, 0.5), ortho=1.0)
    studio(key=2.4, fill=0.9, rim=1.8)


class Rig:
    """Holds the joints of a model and applies/keys named poses."""

    def __init__(self):
        self.turn = empty("turntable")
        self.root = empty("root", parent=self.turn)
        self.joints = {}
        self.flashes = {"flash": [], "launch": [], "sparks": [], "ropes": [], "vent": []}

    def j(self, name, loc, parent, rot=(0, 0, 0)):
        e = empty(name, loc, parent, rad(*rot))
        e["rest_rot"] = list(rad(*rot))
        e["rest_loc"] = list(loc)
        self.joints[name] = e
        return e

    def apply(self, pose):
        """pose: {joint: (rx, ry, rz) degrees, "@joint": (x, y, z) offset,
        "root_loc", "root_rot", "flash": bool}."""
        for name, e in self.joints.items():
            rest = e["rest_rot"]
            d = rad(*pose.get(name, (0, 0, 0)))
            e.rotation_euler = (rest[0] + d[0], rest[1] + d[1], rest[2] + d[2])
            rl = e["rest_loc"]
            off = pose.get("@" + name, (0, 0, 0))
            e.location = (rl[0] + off[0], rl[1] + off[1], rl[2] + off[2])
        self.root.location = pose.get("root_loc", (0, 0, 0))
        self.root.rotation_euler = rad(*pose.get("root_rot", (0, 0, 0)))
        for group, objs in self.flashes.items():
            for f in objs:
                f.hide_render = not pose.get(group, False)
                f.hide_viewport = f.hide_render

    def key(self, frame):
        for e in list(self.joints.values()) + [self.root]:
            e.keyframe_insert("rotation_euler", frame=frame)
            e.keyframe_insert("location", frame=frame)
        for objs in self.flashes.values():
            for f in objs:
                f.keyframe_insert("hide_render", frame=frame)
                f.keyframe_insert("hide_viewport", frame=frame)


def _flash(rig, parent, loc, size=1.0, group="flash"):
    core = glow("flash_core", (1.0, 0.9, 0.55), 5)
    outer = glow("flash", (1.0, 0.5, 0.08), 3.5)
    holder = empty("flash", loc, parent)
    rig.flashes[group].append(holder)
    parts = [ball("flash_c", 0.03 * size, (0, 0, 0), core, holder),
             ball("flash_o", 0.06 * size, (0, -0.02, 0), outer, holder, scale=(1, 0.7, 1))]
    for i in range(6):
        a = i * math.tau / 6
        p = cyl("spike", 0.015 * size, 0.1 * size, (math.cos(a) * 0.05 * size, -0.01, math.sin(a) * 0.05 * size),
                outer, holder, r2=0.0, rot=(0, -a + math.pi / 2, 0))
        parts.append(p)
    rig.flashes[group].extend(parts)


def _sparks(rig, parent, loc):
    """Flinch feedback: a burst of hot sparks where the hit landed."""
    hot = glow("spark_hot", (1.0, 0.95, 0.6), 8)
    warm = glow("spark", (1.0, 0.6, 0.15), 5)
    holder = empty("sparks", loc, parent)
    parts = [holder, ball("spark_core", 0.022, (0, -0.01, 0), hot, holder)]
    for i in range(9):
        a = i * math.tau / 9 + 0.3
        length = 0.05 + (i % 3) * 0.025
        parts.append(cyl("streak", 0.005, length, (math.cos(a) * length * 0.6, -0.02, math.sin(a) * length * 0.6),
                         warm, holder, r2=0.0015, verts=6, rot=(0, -a + math.pi / 2, 0)))
    rig.flashes["sparks"].extend(parts)


# ================================================================== humanoids

def humanoid(kind):
    heavy = kind in ("warden", "crimson")
    w = 1.25 if heavy else 1.0
    if kind == "crimson":
        armor = mat("armor", (0.42, 0.04, 0.035), metal=0.6, rough=0.35, noise=0.25, noise_scale=10)
        trim = mat("trim", (0.12, 0.1, 0.09), metal=0.8, rough=0.35)
        visor = glow("visor", (1.0, 0.55, 0.05), 4)
    elif heavy:
        armor = mat("armor", (0.13, 0.19, 0.42), metal=0.6, rough=0.35, noise=0.25, noise_scale=10)
        trim = mat("trim", (0.62, 0.64, 0.68), metal=0.9, rough=0.3)
        visor = glow("visor", (1.0, 0.15, 0.1), 4)
    else:
        armor = mat("armor", (0.5, 0.28, 0.1), metal=0.35, rough=0.5, noise=0.3, noise_scale=10)
        trim = mat("trim", (0.16, 0.12, 0.08), metal=0.4, rough=0.5)
        visor = glow("visor", (0.2, 1.0, 0.9), 4)
    suit = mat("suit", (0.09, 0.09, 0.1), rough=0.75, noise=0.3, noise_scale=30)
    gunm = mat("gunmetal", (0.06, 0.06, 0.07), metal=0.75, rough=0.4)
    boot = mat("boot", (0.05, 0.05, 0.05), rough=0.6)

    rig = Rig()
    hips = rig.j("hips", (0, 0, 0.43), rig.root)
    box("pelvis", (0.17 * w, 0.11, 0.08), (0, 0, 0.0), suit, hips, bevel=0.015)
    box("belt", (0.19 * w, 0.125, 0.03), (0, 0, 0.03), trim, hips, bevel=0.008)
    torso = rig.j("torso", (0, 0, 0.03), hips)
    box("abdomen", (0.16 * w, 0.1, 0.09), (0, 0, 0.06), suit, torso, bevel=0.015)
    box("chest", (0.25 * w, 0.15, 0.15), (0, 0, 0.17), armor, torso, bevel=0.025)
    box("plate", (0.15 * w, 0.02, 0.08), (0, -0.08, 0.19), trim, torso, bevel=0.008)
    box("emblem", (0.03, 0.01, 0.03), (0, -0.092, 0.2), glow("emblem", (1.0, 0.7, 0.2), 1.5), torso)
    box("pack", (0.17 * w, 0.08, 0.15), (0, 0.11, 0.17), suit, torso, bevel=0.02)
    for s in (-1, 1):
        cyl("tank", 0.025, 0.13, (s * 0.045 * w, 0.16, 0.17), trim, torso)
    cyl("antenna", 0.004, 0.16, (0.06 * w, 0.12, 0.31), trim, torso, verts=6)
    _sparks(rig, torso, (0.05, -0.1, 0.2))
    if kind == "crimson":
        # Cooling vents: chest slats that glow orange-hot while it vents.
        hot = glow("vent_hot", (1.0, 0.45, 0.05), 6)
        cool = mat("vent_cool", (0.05, 0.04, 0.04), rough=0.6)
        for i in range(3):
            box("slat", (0.16 * w, 0.012, 0.016), (0, -0.081, 0.13 + i * 0.03), cool, torso)
            g = box("slat_hot", (0.15 * w, 0.014, 0.012), (0, -0.083, 0.13 + i * 0.03), hot, torso)
            rig.flashes["vent"].append(g)
        for s in (-1, 1):
            g = ball("exhaust", 0.03, (s * 0.06 * w, 0.16, 0.3), glow("steam", (1.0, 0.6, 0.2), 3), torso, scale=(1, 1, 2))
            rig.flashes["vent"].append(g)
    ball("antenna_tip", 0.01, (0.06 * w, 0.12, 0.39), visor, torso)

    head = rig.j("head", (0, 0, 0.26), torso)
    cyl("neck", 0.03, 0.05, (0, 0, 0.0), suit, head)
    ball("helmet", 0.068, (0, 0, 0.07), armor, head, scale=(1.0, 1.05, 1.1))
    box("crest", (0.025, 0.12, 0.03), (0, 0.0, 0.14), trim, head, bevel=0.008)
    box("visor", (0.1, 0.03, 0.035), (0, -0.055, 0.075), visor, head, bevel=0.01)
    box("jaw", (0.08, 0.04, 0.03), (0, -0.05, 0.03), trim, head, bevel=0.01)

    arms = {}
    for s in (-1, 1):  # -1 = right side of the model (it faces -Y), +1 = left
        tag = "R" if s < 0 else "L"
        sh = rig.j("shoulder" + tag, (s * 0.15 * w, 0, 0.22), torso)
        if heavy:
            box("pauldron", (0.11, 0.13, 0.07), (s * 0.02, 0, 0.03), trim, sh, bevel=0.02, rot=rad(0, s * -20, 0))
        else:
            ball("pad", 0.045, (0, 0, 0.0), armor, sh, scale=(1.1, 1.0, 0.9))
        cyl("upper", 0.03 * w, 0.14, (0, 0, -0.07), suit, sh)
        el = rig.j("elbow" + tag, (0, 0, -0.14), sh)
        cyl("fore", 0.034 * w, 0.13, (0, 0, -0.065), armor, el, bevel=0.0)
        ball("glove", 0.032 * w, (0, 0, -0.135), suit, el)
        arms[tag] = el
        th = rig.j("thigh" + tag, (s * 0.065 * w, 0, -0.01), hips)
        cyl("thighm", 0.044 * w, 0.2, (0, 0, -0.1), suit, th)
        kn = rig.j("knee" + tag, (0, 0, -0.2), th)
        ball("kneepad", 0.038 * w, (0, -0.02, 0.0), armor, kn)
        box("shin", (0.07 * w, 0.075, 0.17), (0, 0, -0.1), armor, kn, bevel=0.015)
        box("boot", (0.08 * w, 0.13, 0.05), (0, -0.025, -0.205), boot, kn, bevel=0.012)

    mount = rig.j("gun", (0, 0, -0.14), arms["R"], rot=(90, 0, 0))
    if heavy:
        box("gbody", (0.08, 0.3, 0.09), (0, -0.08, 0.02), gunm, mount, bevel=0.012)
        for x in (-0.022, 0.022):
            cyl("gbarrel", 0.016, 0.16, (x, -0.29, 0.03), gunm, mount, axis="Y")
        cyl("gdrum", 0.045, 0.06, (0, -0.02, -0.05), trim, mount, axis="X")
        _flash(rig, mount, (0, -0.4, 0.03), 1.3)
    else:
        box("gbody", (0.045, 0.24, 0.06), (0, -0.06, 0.02), gunm, mount, bevel=0.008)
        cyl("gbarrel", 0.011, 0.1, (0, -0.22, 0.03), gunm, mount, axis="Y")
        box("gmag", (0.03, 0.04, 0.08), (0, -0.06, -0.04), gunm, mount, bevel=0.005)
        box("gstock", (0.035, 0.08, 0.05), (0, 0.1, 0.0), trim, mount, bevel=0.008)
        _flash(rig, mount, (0, -0.3, 0.03), 1.0)
    return rig


def humanoid_pose(name, frame, count=4):
    hold = {"shoulderR": (-30, 0, 0), "elbowR": (-55, 0, 0), "shoulderL": (-40, 0, 25), "elbowL": (-70, 0, 0)}
    if name == "stand":
        return dict(hold)
    if name == "walk":
        p = frame * math.tau / count
        pose = dict(hold)
        for tag, ph in (("L", p), ("R", p + math.pi)):
            pose["thigh" + tag] = (-32 * math.sin(ph), 0, 0)
            pose["knee" + tag] = (45 * max(0.0, math.cos(ph)), 0, 0)
        pose["torso"] = (4, 0, 6 * math.sin(p))
        pose["shoulderR"] = (-30 + 6 * math.sin(p), 0, 0)
        pose["root_loc"] = (0, 0, -0.012 * abs(math.cos(p)))
        return pose
    if name in ("aim", "fire"):
        pose = {"shoulderR": (-88, 0, -10), "elbowR": (0, 0, 0), "shoulderL": (-75, 0, 35), "elbowL": (-30, 0, 0),
                "torso": (6, 0, 0), "head": (6, 0, 0), "thighL": (-12, 0, 0), "kneeL": (12, 0, 0), "thighR": (10, 0, 0)}
        if name == "fire":
            pose["shoulderR"] = (-82, 0, -10) if frame == 0 else (-76, 0, -10)
            pose["torso"] = (2, 0, 0) if frame == 0 else (-3, 0, 0)
            pose["head"] = (6, 0, 0) if frame == 0 else (0, 0, 0)
            pose["flash"] = frame == 0
        return pose
    if name == "vent":
        # Arms dropped, chest thrown open, glowing.
        return {"shoulderR": (-20, 0, -15), "elbowR": (-20, 0, 0), "shoulderL": (-10, 0, 30), "elbowL": (-15, 0, 0),
                "torso": (-10, 0, 0), "head": (-18, 0, 0), "vent": True}
    if name == "pain":
        return {"torso": (-16, 0, 10), "head": (-22, 0, 8), "shoulderR": (-15, 0, -35), "elbowR": (-25, 0, 0),
                "shoulderL": (-10, 0, 40), "elbowL": (-20, 0, 0), "thighL": (-10, 0, 0), "kneeL": (15, 0, 0),
                "sparks": True}
    if name == "die":
        a = (12, 35, 60, 82)[frame]
        return {"root_rot": (0, a, 0), "root_loc": (-0.3 * math.sin(math.radians(a)), 0, 0.027 * frame),
                "thighL": (-25, 0, 0), "kneeL": (45, 0, 0), "thighR": (-10, 0, 0), "kneeR": (30, 0, 0),
                "torso": (-10 - 5 * frame, 0, 0), "head": (-20, 0, 15),
                "shoulderR": (-20, 0, -40 - 20 * frame), "shoulderL": (-10, 0, 50 + 20 * frame)}
    if name == "dead":
        return {"root_rot": (0, 90, 0), "root_loc": (-0.4, 0, 0.075), "thighL": (-15, 0, 0), "kneeL": (25, 0, 0),
                "torso": (-5, 0, 0), "head": (-10, 0, 25), "shoulderR": (-30, 0, -70), "shoulderL": (-20, 0, 80),
                "elbowL": (-30, 0, 0)}
    return {}


# ================================================================== hound

def hound(_kind):
    plate = mat("plate", (0.3, 0.31, 0.35), metal=0.8, rough=0.35, noise=0.25, noise_scale=12)
    dark = mat("frame", (0.07, 0.07, 0.08), metal=0.6, rough=0.5)
    eye = glow("eye", (1.0, 0.12, 0.06), 6)
    accent = mat("accent", (0.6, 0.08, 0.05), rough=0.5)
    rig = Rig()
    body = rig.j("body", (0, 0, 0.3), rig.root)
    box("chest", (0.17, 0.2, 0.14), (0, -0.07, 0.01), plate, body, bevel=0.03)
    box("rear", (0.15, 0.17, 0.12), (0, 0.11, 0.0), plate, body, bevel=0.03)
    box("spine", (0.05, 0.36, 0.03), (0, 0.02, 0.08), dark, body, bevel=0.01)
    for i in range(4):
        box("vane", (0.12, 0.02, 0.03), (0, -0.12 + i * 0.075, 0.075), accent, body, bevel=0.005)
    _sparks(rig, body, (0.03, -0.18, 0.03))
    tail = rig.j("tail", (0, 0.2, 0.03), body, rot=(-40, 0, 0))
    cyl("tailm", 0.01, 0.16, (0, 0, 0.08), dark, tail, verts=8)
    ball("tailtip", 0.014, (0, 0, 0.16), eye, tail)

    head = rig.j("head", (0, -0.18, 0.06), body)
    box("skull", (0.12, 0.13, 0.09), (0, -0.04, 0.0), plate, head, bevel=0.025)
    box("snout", (0.08, 0.09, 0.045), (0, -0.13, 0.0), plate, head, bevel=0.015)
    ball("eye", 0.022, (0, -0.105, 0.035), eye, head)
    for s in (-1, 1):
        cyl("ear", 0.02, 0.07, (s * 0.04, -0.01, 0.07), dark, head, r2=0.0, rot=rad(-15, s * 15, 0))
    jaw = rig.j("jaw", (0, -0.06, -0.03), head)
    box("jawm", (0.07, 0.1, 0.025), (0, -0.06, -0.005), dark, jaw, bevel=0.008)
    for i in range(3):
        cyl("tooth", 0.006, 0.02, (-0.02 + i * 0.02, -0.1, 0.012), mat("tooth", (0.85, 0.85, 0.8)), jaw, r2=0.0, verts=6)

    for tag, x, y in (("FL", 0.075, -0.13), ("FR", -0.075, -0.13), ("BL", 0.07, 0.13), ("BR", -0.07, 0.13)):
        hip = rig.j("hip" + tag, (x, y, -0.03), body)
        ball("joint", 0.032, (0, 0, 0), dark, hip)
        cyl("upper", 0.024, 0.14, (0, 0, -0.07), plate, hip)
        kn = rig.j("knee" + tag, (0, 0, -0.14), hip)
        cyl("lower", 0.017, 0.13, (0, 0, -0.065), dark, kn)
        box("paw", (0.045, 0.06, 0.02), (0, -0.015, -0.135), dark, kn, bevel=0.006)
    return rig


def hound_pose(name, frame, count=4):
    if name == "stand":
        return {"head": (-5, 0, 0)}
    if name == "walk":
        p = frame * math.tau / count
        pose = {"body": (3 * math.sin(2 * p), 0, 0), "head": (-5 + 5 * math.sin(2 * p), 0, 0),
                "tail": (10 * math.sin(p), 0, 0), "root_loc": (0, 0, 0.012 * abs(math.sin(p)))}
        for tag, ph in (("FL", p), ("BR", p), ("FR", p + math.pi), ("BL", p + math.pi)):
            pose["hip" + tag] = (-35 * math.sin(ph), 0, 0)
            pose["knee" + tag] = (40 * max(0.0, math.cos(ph)), 0, 0)
        return pose
    if name == "aim":
        return {"@body": (0, 0.02, -0.05), "head": (18, 0, 0), "hipFL": (-20, 0, 0), "kneeFL": (45, 0, 0),
                "hipFR": (-20, 0, 0), "kneeFR": (45, 0, 0), "hipBL": (25, 0, 0), "kneeBL": (40, 0, 0),
                "hipBR": (25, 0, 0), "kneeBR": (40, 0, 0)}
    if name == "fire":
        if frame == 1:
            return {"@head": (0, -0.03, 0.01), "head": (-5, 0, 0), "jaw": (10, 0, 0), "hipFL": (-20, 0, 0),
                    "hipFR": (-20, 0, 0)}
        return {"@head": (0, -0.07, 0.02), "head": (-20, 0, 0), "jaw": (40, 0, 0), "hipFL": (-45, 0, 0),
                "hipFR": (-45, 0, 0), "hipBL": (20, 0, 0), "hipBR": (20, 0, 0)}
    if name == "pain":
        return {"body": (0, 15, 0), "head": (-25, 0, 20), "jaw": (20, 0, 0), "tail": (40, 0, 0), "sparks": True}
    if name == "die":
        a = (15, 40, 62, 82)[frame]
        return {"root_rot": (0, a, 0), "root_loc": (-0.2 * math.sin(math.radians(a)), 0, 0.022 * frame),
                "head": (-15, 0, 10 * frame), "jaw": (30, 0, 0),
                "hipFL": (-30, 0, 0), "hipBR": (30, 0, 0), "kneeFL": (40, 0, 0)}
    if name == "dead":
        return {"root_rot": (0, 90, 0), "root_loc": (-0.3, 0, 0.09), "head": (10, 0, 30), "jaw": (25, 0, 0),
                "hipFL": (-20, 0, 0), "hipFR": (15, 0, 0), "hipBL": (30, 0, 0), "kneeBR": (50, 0, 0)}
    return {}


# ================================================================== boss

def overseer(_kind):
    """The Overseer: crimson war machine with a rotary-cannon arm, a crusher
    claw, twin shoulder plasma launchers and a glowing core."""
    armor = mat("armor", (0.26, 0.05, 0.05), metal=0.6, rough=0.35, noise=0.3, noise_scale=8)
    dark = mat("frame", (0.06, 0.06, 0.07), metal=0.7, rough=0.45)
    gold = mat("gold", (0.85, 0.6, 0.2), metal=1.0, rough=0.3)
    eye = glow("eye", (1.0, 0.1, 0.05), 6)
    core = glow("core", (1.0, 0.45, 0.1), 5)
    rig = Rig()
    hips = rig.j("hips", (0, 0, 0.4), rig.root)
    box("pelvis", (0.3, 0.2, 0.1), (0, 0, 0), dark, hips, bevel=0.02)
    torso = rig.j("torso", (0, 0, 0.05), hips)
    box("belly", (0.34, 0.24, 0.1), (0, 0, 0.03), dark, torso, bevel=0.02)
    box("chest", (0.5, 0.32, 0.28), (0, 0, 0.2), armor, torso, bevel=0.04)
    box("plate", (0.3, 0.02, 0.2), (0, -0.16, 0.2), dark, torso, bevel=0.01)
    ball("core", 0.06, (0, -0.17, 0.2), core, torso)
    _sparks(rig, torso, (0.13, -0.18, 0.3))
    torus("corering", 0.075, 0.012, (0, -0.175, 0.2), gold, torso, rot=rad(90, 0, 0))
    box("collar", (0.36, 0.26, 0.05), (0, 0, 0.36), gold, torso, bevel=0.015)
    for sx in (-1, 1):
        box("vent", (0.08, 0.08, 0.14), (sx * 0.15, 0.18, 0.24), dark, torso, bevel=0.01)
        cyl("stack", 0.025, 0.16, (sx * 0.15, 0.19, 0.38), dark, torso)
        ball("ember", 0.018, (sx * 0.15, 0.19, 0.46), core, torso)
    head = rig.j("head", (0, -0.04, 0.39), torso)
    ball("dome", 0.09, (0, 0, 0.03), armor, head, scale=(1.2, 1, 0.8))
    box("brow", (0.2, 0.05, 0.03), (0, -0.075, 0.045), gold, head, bevel=0.01)
    for x in (-0.05, 0.0, 0.05):
        ball("eye", 0.018, (x, -0.085, 0.015), eye, head)
    for sx in (-1, 1):
        tag = "R" if sx < 0 else "L"
        pod = rig.j("pod" + tag, (sx * 0.19, 0.02, 0.4), torso)
        box("podbox", (0.15, 0.2, 0.11), (0, 0, 0.05), armor, pod, bevel=0.02)
        box("podtrim", (0.155, 0.04, 0.115), (0, -0.07, 0.05), gold, pod, bevel=0.01)
        for dx in (-0.035, 0.035):
            for dz in (0.025, 0.075):
                cyl("tube", 0.018, 0.04, (dx, -0.1, dz), dark, pod, axis="Y")
                ball("tubeglow", 0.012, (dx, -0.11, dz), core, pod)
        _flash(rig, pod, (0, -0.16, 0.05), 1.0, "launch")
        sh = rig.j("shoulder" + tag, (sx * 0.31, 0, 0.27), torso)
        ball("joint", 0.07, (0, 0, 0), dark, sh)
        box("upper", (0.11, 0.12, 0.18), (sx * 0.02, 0, -0.1), armor, sh, bevel=0.025)
        el = rig.j("elbow" + tag, (sx * 0.02, 0, -0.2), sh)
        if sx < 0:
            cyl("housing", 0.06, 0.14, (0, 0, -0.07), dark, el)
            torus("band", 0.062, 0.01, (0, 0, -0.12), gold, el)
            for i in range(6):
                a = i * math.tau / 6
                cyl("barrel", 0.012, 0.18, (math.cos(a) * 0.032, math.sin(a) * 0.032, -0.23), dark, el, verts=10)
            _flash(rig, el, (0, 0, -0.34), 1.3, "flash")
        else:
            box("fore", (0.13, 0.14, 0.16), (0, 0, -0.08), armor, el, bevel=0.025)
            for a in (-25, 0, 25):
                cyl("talon", 0.022, 0.12, (math.sin(math.radians(a)) * 0.05, -0.02, -0.2), gold, el, r2=0.0,
                    rot=rad(190, a, 0))
        th = rig.j("thigh" + tag, (sx * 0.12, 0, -0.02), hips)
        box("thighm", (0.12, 0.14, 0.2), (0, 0, -0.09), armor, th, bevel=0.025)
        kn = rig.j("knee" + tag, (0, 0, -0.19), th)
        ball("kneejoint", 0.05, (0, -0.02, 0), dark, kn)
        box("shin", (0.1, 0.12, 0.17), (0, 0, -0.09), dark, kn, bevel=0.02)
        box("foot", (0.15, 0.22, 0.05), (0, -0.04, -0.185), armor, kn, bevel=0.015)
    return rig


def overseer_pose(name, frame, count=4):
    base = {"shoulderR": (-20, 0, 0), "elbowR": (-30, 0, 0), "shoulderL": (-10, 0, 10), "elbowL": (-25, 0, 0)}
    if name == "stand":
        return base
    if name == "walk":
        p = frame * math.tau / count
        pose = dict(base)
        for tag, ph in (("L", p), ("R", p + math.pi)):
            pose["thigh" + tag] = (-22 * math.sin(ph), 0, 0)
            pose["knee" + tag] = (35 * max(0.0, math.cos(ph)), 0, 0)
        pose["torso"] = (3, 0, 5 * math.sin(p))
        pose["root_loc"] = (0, 0, -0.018 * abs(math.cos(p)))
        return pose
    if name in ("aim", "fire"):
        pose = dict(base)
        pose.update({"shoulderR": (-85, 0, -4), "elbowR": (0, 0, 0), "torso": (5, 0, 0), "head": (5, 0, 0)})
        if name == "fire":
            pose["shoulderR"] = (-80, 0, -4) if frame == 0 else (-74, 0, -4)
            pose["torso"] = (5, 0, 0) if frame == 0 else (1, 0, 0)
            pose["flash"] = frame == 0
        return pose
    if name == "launch":
        pose = dict(base)
        pose.update({"torso": (-10, 0, 0), "podL": (-18, 0, 0), "podR": (-18, 0, 0), "head": (-5, 0, 0),
                     "thighL": (-12, 0, 0), "kneeL": (15, 0, 0), "launch": True})
        return pose
    if name == "pain":
        return {"torso": (-12, 0, 8), "head": (-18, 0, 10), "shoulderR": (-10, 0, -30), "shoulderL": (-5, 0, 35),
                "elbowL": (-40, 0, 0), "sparks": True}
    if name == "die":
        t = (-30, -55, -72, -80)[frame]
        k = (55, 90, 112, 120)[frame]
        pose = {"thighL": (t, 0, 0), "thighR": (t, 0, 0), "kneeL": (k, 0, 0), "kneeR": (k, 0, 0),
                "torso": (15 + 15 * frame, 0, 8 * frame), "head": (20 + 10 * frame, 0, 0),
                "shoulderR": (-10, 0, -20), "shoulderL": (10, 0, 30), "root_loc": (0, 0, (-0.06, -0.12, -0.18, -0.2)[frame])}
        if frame >= 2:
            pose["root_rot"] = (0, (10, 25)[frame - 2], 0)
        return pose
    if name == "dead":
        return {"root_rot": (0, 85, 0), "root_loc": (-0.42, 0, 0.16), "thighL": (-30, 0, 0), "kneeL": (60, 0, 0),
                "torso": (10, 0, 0), "head": (30, 0, 20), "shoulderR": (-40, 0, -50), "shoulderL": (0, 0, 60)}
    return {}


# ================================================================== hostage

def hostage(_kind):
    """A fellow prisoner chained to an iron post: faded jumpsuit, bare head,
    rope coils around the chest and wrists. The ropes are a toggle group so
    the freed frames show them cut."""
    suit = mat("jumpsuit", (0.62, 0.55, 0.38), rough=0.85, noise=0.35, noise_scale=25)
    patch = mat("patch", (0.85, 0.82, 0.72), rough=0.7)
    skin = mat("skin", (0.72, 0.52, 0.4), rough=0.65, noise=0.15, noise_scale=40)
    hair = mat("hair", (0.12, 0.08, 0.06), rough=0.9)
    rope = mat("rope", (0.55, 0.42, 0.24), rough=0.95, noise=0.4, noise_scale=60)
    iron = mat("iron", (0.2, 0.2, 0.22), metal=0.8, rough=0.45, noise=0.3, noise_scale=15)
    shoe = mat("shoe", (0.1, 0.09, 0.08), rough=0.7)

    rig = Rig()
    # Iron post the hostage is tied to (static, behind them).
    cyl("post", 0.035, 0.95, (0, 0.17, 0.475), iron, rig.turn, verts=12)
    box("post_base", (0.16, 0.16, 0.03), (0, 0.17, 0.015), iron, rig.turn, bevel=0.01)
    cyl("cut_rope", 0.012, 0.12, (0.03, 0.13, 0.3), rope, rig.turn, verts=8, rot=rad(20, 0, 0))

    hips = rig.j("hips", (0, 0, 0.43), rig.root)
    box("pelvis", (0.17, 0.11, 0.09), (0, 0, 0.0), suit, hips, bevel=0.02)
    torso = rig.j("torso", (0, 0, 0.03), hips)
    box("belly", (0.16, 0.1, 0.1), (0, 0, 0.06), suit, torso, bevel=0.02)
    box("chest", (0.22, 0.13, 0.15), (0, 0, 0.17), suit, torso, bevel=0.03)
    box("number", (0.06, 0.01, 0.035), (0.05, -0.068, 0.2), patch, torso, bevel=0.004)
    for z in (0.12, 0.2):
        t = torus("rope_coil", 0.135, 0.012, (0, 0.02, z), rope, torso, rot=rad(0, 0, 0))
        t.scale = (1.0, 0.75, 1.0)
        rig.flashes["ropes"].append(t)

    head = rig.j("head", (0, 0, 0.26), torso)
    cyl("neck", 0.03, 0.05, (0, 0, 0.0), skin, head)
    ball("skull", 0.065, (0, 0, 0.075), skin, head, scale=(0.95, 1.0, 1.12))
    ball("hair", 0.066, (0, 0.012, 0.1), hair, head, scale=(0.98, 1.0, 0.75))
    for s in (-1, 1):
        ball("eye", 0.009, (s * 0.024, -0.058, 0.085), hair, head)
    gag = box("gag", (0.14, 0.03, 0.022), (0, -0.045, 0.05), patch, head, bevel=0.008)
    rig.flashes["ropes"].append(gag)

    for s in (-1, 1):
        tag = "R" if s < 0 else "L"
        sh = rig.j("shoulder" + tag, (s * 0.13, 0, 0.22), torso)
        ball("shoulderm", 0.04, (0, 0, 0), suit, sh)
        cyl("upper", 0.03, 0.14, (0, 0, -0.07), suit, sh)
        el = rig.j("elbow" + tag, (0, 0, -0.14), sh)
        cyl("fore", 0.028, 0.13, (0, 0, -0.065), suit, el)
        ball("hand", 0.03, (0, 0, -0.14), skin, el)
        if s < 0:
            w = torus("wrist_rope", 0.04, 0.01, (0, 0, -0.12), rope, el)
            rig.flashes["ropes"].append(w)
        th = rig.j("thigh" + tag, (s * 0.06, 0, -0.01), hips)
        cyl("thighm", 0.042, 0.2, (0, 0, -0.1), suit, th)
        kn = rig.j("knee" + tag, (0, 0, -0.2), th)
        cyl("shin", 0.036, 0.18, (0, 0, -0.09), suit, kn)
        box("shoe", (0.075, 0.12, 0.045), (0, -0.025, -0.2), shoe, kn, bevel=0.012)
    return rig


def hostage_pose(name, frame, count=4):
    # Kneeling with the hands tied behind the back, slumped against the post.
    kneel = {"root_loc": (0, 0.02, -0.19), "thighL": (-85, 0, 6), "thighR": (-85, 0, -6),
             "kneeL": (165, 0, 0), "kneeR": (165, 0, 0),
             "shoulderL": (35, 0, 12), "elbowL": (25, 0, 0), "shoulderR": (35, 0, -12), "elbowR": (25, 0, 0)}
    if name == "bound":
        pose = dict(kneel)
        pose["torso"] = (8 + 5 * frame, 0, -4 + 8 * frame)
        pose["head"] = (18 - 6 * frame, 0, 10 - 16 * frame)
        pose["ropes"] = True
        return pose
    if name == "freed":
        # Standing up, arms raised and waving in relief.
        wave = 25 * frame
        return {"shoulderL": (0, -150 + wave, 0), "elbowL": (0, -25, 0),
                "shoulderR": (0, 150 - wave, 0), "elbowR": (0, 25, 0),
                "torso": (-6, 0, 0), "head": (-12, 0, 0), "root_loc": (0, 0, 0.01 * frame)}
    if name == "dead":
        return {"root_rot": (0, 90, 0), "root_loc": (-0.47, -0.2, 0.06), "thighL": (-15, 0, 0), "kneeL": (25, 0, 0),
                "torso": (-5, 0, 0), "head": (-10, 0, 25), "shoulderR": (30, 0, 0), "shoulderL": (30, 0, 0),
                "ropes": True}
    return {}


KINDS = {
    "sentry": (humanoid, humanoid_pose),
    "warden": (humanoid, humanoid_pose),
    "crimson": (humanoid, humanoid_pose),
    "hound": (hound, hound_pose),
    "overseer": (overseer, overseer_pose),
    "hostage": (hostage, hostage_pose),
}

EXTRA_SEQ = {"overseer": [("launch", 0, 24, False)], "crimson": [("vent", 0, 26, False)]}
# Hostages don't fight: two struggling frames, two freed frames and a body.
SEQ_OVERRIDE = {"hostage": [("bound", 0, 1, False), ("bound", 1, 4, False), ("freed", 0, 10, False),
                            ("freed", 1, 13, False), ("dead", 0, 20, False)]}


def build(only=()):
    for kind, (make, posefn) in KINDS.items():
        if only and kind not in only:
            continue
        _setup()
        rig = make(kind)
        if kind == "overseer":
            rig.turn.scale = (0.92, 0.92, 0.92)
        sc = bpy.context.scene
        out = os.path.join(ASSETS_DIR, "enemies", kind)
        seq = SEQ_OVERRIDE.get(kind) or make_seq(kind) + EXTRA_SEQ.get(kind, [])
        walk_count = WALK_FRAMES.get(kind, 8)
        for pose, frame, kf, directional in seq:
            sc.frame_set(kf)
            rig.apply(posefn(pose, frame, walk_count))
            rig.key(kf)
            for d in (range(8) if directional else (0,)):
                # Turning the model clockwise == moving the camera counter-clockwise.
                rig.turn.rotation_euler = (0, 0, -d * math.pi / 4)
                render(os.path.join(out, f"{pose}_{frame}_d{d}.png"), RES)
            rig.turn.rotation_euler = (0, 0, 0)
        print("rendered", kind)
        sc.frame_start = 1
        sc.frame_end = max(k for _, _, k, _ in seq)
        sc.frame_set(1)
        save_blend(kind)
