#!/usr/bin/env python3
"""Gera assets/sprites/*.png + *.json a partir de art/models/*.glb."""
import json
import math
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import glbrender as R
from PIL import Image                                        # noqa: E402

ROOT = sys.argv[1]
MODELS = os.path.join(ROOT, "art", "models")
OUT = os.path.join(ROOT, "assets", "sprites")

# nome, diametro em px, yaw, frames (1 = estatico), arco do giro
MODELS_CFG = [
    ("boss_dreadnought", 180, 180, 1, 360),
    ("boss_mantis", 164, 180, 1, 360),
    ("boss_core", 148, 180, 12, 45),
    ("enemy_elite", 104, 180, 1, 360),
    ("enemy_heavy", 84, 180, 1, 360),
    ("enemy_freighter", 80, 180, 1, 360),
    ("enemy_ringer", 72, 180, 1, 360),
    ("enemy_spinner", 64, 180, 1, 360),
    ("enemy_grunt", 52, 180, 1, 360),
    ("enemy_kamikaze", 44, 180, 1, 360),
    ("enemy_sniper", 52, 180, 1, 360),
    ("enemy_runner", 48, 0, 1, 360),
    ("player_aurora", 64, 0, 1, 360),
    ("player_crimson", 64, 0, 1, 360),
    ("player_gold", 64, 0, 1, 360),
    ("player_voidfire", 64, 0, 1, 360),
    ("player_spectre", 64, 0, 1, 360),
    ("drone_wingman", 28, 0, 1, 360),
    ("option_satellite", 24, 0, 1, 360),
    ("pickup_capsule", 40, 0, 1, 360),
    ("pickup_medal", 24, 0, 1, 360),
]

os.makedirs(OUT, exist_ok=True)

for name, size, yaw, frames, arc in MODELS_CFG:
    path = os.path.join(MODELS, name + ".glb")
    if not os.path.exists(path):
        print("[skip]", name)
        continue
    t0 = time.time()

    # Caixa unida entre TODOS os frames: sem isto o sprite "respira".
    lo = [1e30] * 3
    hi = [-1e30] * 3
    angles = [yaw + arc * i / frames for i in range(frames)]
    for a in angles:
        _, (l, h), _ = R.collect(path, a)
        lo = [min(lo[k], l[k]) for k in range(3)]
        hi = [max(hi[k], h[k]) for k in range(3)]

    imgs = [R.render(path, size, yaw_deg=a, ss=3, bbox=(lo, hi))
            for a in angles]

    cols = max(1, math.ceil(math.sqrt(len(imgs))))
    rows = math.ceil(len(imgs) / cols)
    sheet = Image.new("RGBA", (cols * size, rows * size), (0, 0, 0, 0))
    for i, im in enumerate(imgs):
        sheet.paste(im, ((i % cols) * size, (i // cols) * size))
    sheet.save(os.path.join(OUT, name + ".png"), optimize=True)

    with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as fh:
        json.dump({
            "name": name, "frameWidth": size, "frameHeight": size,
            "cols": cols, "rows": rows, "count": len(imgs),
            "anchor": [0.5, 0.5], "loop": frames > 1,
        }, fh, indent=2)

    print("[ok] %-18s %3dpx x%-2d  %.1fs" % (name, size, len(imgs),
                                             time.time() - t0))
