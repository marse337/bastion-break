"""Shared helpers for the Bastion Break asset scripts (Blender 4.2+ / 5.x).

Everything is built from primitives in code so the art is fully original and
reproducible: run blender/build_assets.py to regenerate every PNG.
"""
import math
import os

import bpy
from mathutils import Vector

ASSETS_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets"))
SCENES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "scenes")


# ------------------------------------------------------------------ scene

def reset(transparent=True, ambient=0.35, samples=24):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    try:
        sc.eevee.taa_render_samples = samples
    except AttributeError:
        pass
    sc.render.film_transparent = transparent
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA" if transparent else "RGB"
    sc.render.resolution_percentage = 100
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    sc.world = world
    try:
        world.use_nodes = True
    except (AttributeError, TypeError):
        pass
    bg = world.node_tree.nodes.get("Background") if world.node_tree else None
    if bg is not None:
        bg.inputs[0].default_value = (0.42, 0.44, 0.5, 1.0)
        bg.inputs[1].default_value = ambient
    else:
        world.color = (0.42 * ambient, 0.44 * ambient, 0.5 * ambient)
    return sc


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def camera(loc, target, ortho=None, lens=50.0):
    cd = bpy.data.cameras.new("Camera")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.lens = lens
    cd.clip_start = 0.01
    cd.clip_end = 100.0
    co = link(bpy.data.objects.new("Camera", cd))
    co.location = loc
    look_at(co, target)
    bpy.context.scene.camera = co
    return co


def light(kind, energy, loc, target=(0, 0, 0), color=(1, 1, 1), size=0.5, parent=None):
    ld = bpy.data.lights.new("Light", kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    elif kind == "SUN":
        ld.angle = math.radians(3)
    lo = link(bpy.data.objects.new("Light", ld))
    lo.location = loc
    look_at(lo, target)
    if parent:
        lo.parent = parent
    return lo


def studio(key=3.2, fill=1.2, rim=2.0, center=(0, 0, 0.5)):
    """Three-point lighting from the camera side (camera looks along +Y)."""
    cx, cy, cz = center
    light("SUN", key, (cx - 2, cy - 3, cz + 3), center, (1.0, 0.96, 0.9))
    light("SUN", fill, (cx + 3, cy - 2, cz + 0.5), center, (0.75, 0.82, 1.0))
    light("SUN", rim, (cx + 1, cy + 3, cz + 2), center, (1.0, 0.9, 0.8))


def render(path, w, h=None):
    sc = bpy.context.scene
    sc.render.resolution_x = w
    sc.render.resolution_y = h or w
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def save_blend(name):
    os.makedirs(SCENES_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(SCENES_DIR, name + ".blend"), check_existing=False)


# ------------------------------------------------------------------ materials

def _principled(m):
    try:
        m.use_nodes = True
    except (AttributeError, TypeError):
        pass
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = nt.nodes.get("Material Output") or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    return nt, bsdf


def mat(name, color, metal=0.0, rough=0.6, emit=None, emit_strength=0.0, noise=0.0, noise_scale=12.0, seed=0.0):
    """Principled material. `noise` (0..1) adds grimy colour variation."""
    m = bpy.data.materials.new(name)
    nt, bsdf = _principled(m)
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    if noise > 0.0:
        tex = nt.nodes.new("ShaderNodeTexNoise")
        tex.inputs["Scale"].default_value = noise_scale
        tex.inputs["Detail"].default_value = 6.0
        if "W" in tex.inputs and seed:
            tex.noise_dimensions = "4D"
            tex.inputs["W"].default_value = seed
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        lo = tuple(c * (1.0 - noise) for c in color)
        hi = tuple(min(1.0, c * (1.0 + noise * 0.6)) for c in color)
        ramp.color_ramp.elements[0].position = 0.3
        ramp.color_ramp.elements[0].color = (*lo, 1.0)
        ramp.color_ramp.elements[1].position = 0.7
        ramp.color_ramp.elements[1].color = (*hi, 1.0)
        nt.links.new(tex.outputs["Fac"], ramp.inputs["Fac"])
        nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def glow(name, color, strength=6.0):
    return mat(name, color, rough=0.4, emit=color, emit_strength=strength)


# ------------------------------------------------------------------ primitives

def _finish(o, name, loc, rot, m, parent, bevel, smooth):
    o.name = name
    o.location = loc
    o.rotation_euler = rot
    if m is not None:
        o.data.materials.append(m)
    if parent is not None:
        o.parent = parent
    if bevel:
        mod = o.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
    if smooth:
        try:
            o.data.shade_smooth()
        except AttributeError:
            for p in o.data.polygons:
                p.use_smooth = True
    return o


def _scale_verts(o, dims):
    for v in o.data.vertices:
        v.co = Vector((v.co.x * dims[0], v.co.y * dims[1], v.co.z * dims[2]))


def box(name, dims, loc=(0, 0, 0), m=None, parent=None, bevel=0.0, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1)
    o = bpy.context.active_object
    _scale_verts(o, dims)
    return _finish(o, name, loc, rot, m, parent, bevel, False)


def cyl(name, r, depth, loc=(0, 0, 0), m=None, parent=None, axis="Z", verts=24, r2=None, rot=None, bevel=0.0, smooth=True):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth)
    o = bpy.context.active_object
    if rot is None:
        rot = {"Z": (0, 0, 0), "X": (0, math.pi / 2, 0), "Y": (math.pi / 2, 0, 0)}[axis]
    return _finish(o, name, loc, rot, m, parent, bevel, smooth)


def ball(name, r, loc=(0, 0, 0), m=None, parent=None, scale=(1, 1, 1), segs=24, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segs, ring_count=segs // 2, radius=r)
    o = bpy.context.active_object
    _scale_verts(o, scale)
    return _finish(o, name, loc, rot, m, parent, 0.0, True)


def torus(name, r_major, r_minor, loc=(0, 0, 0), m=None, parent=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=r_major, minor_radius=r_minor, major_segments=32, minor_segments=12)
    o = bpy.context.active_object
    return _finish(o, name, loc, rot, m, parent, 0.0, True)


def empty(name, loc=(0, 0, 0), parent=None, rot=(0, 0, 0)):
    o = link(bpy.data.objects.new(name, None))
    o.empty_display_size = 0.05
    o.location = loc
    o.rotation_euler = rot
    if parent is not None:
        o.parent = parent
    return o


def rad(*deg):
    return tuple(math.radians(d) for d in deg)
