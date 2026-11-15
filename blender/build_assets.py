"""Builds every Bastion Break asset with Blender.

Usage (from the project folder):
    blender -b --factory-startup -P blender/build_assets.py -- [textures] [items] [weapons] [enemies]

With no category names everything is built. PNGs go to assets/, editable
.blend scenes (with keyframed animations for enemies) go to blender/scenes/.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import importlib  # noqa: E402

STEPS = ["textures", "items", "weapons", "enemies"]

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
wanted = [a for a in argv if a in STEPS] or list(STEPS)
only = [a for a in argv if a not in STEPS]
for name in wanted:
    t0 = time.time()
    print(f"=== building {name}")
    importlib.import_module("build_" + name).build(only)
    print(f"=== {name} done in {time.time() - t0:.1f}s")
