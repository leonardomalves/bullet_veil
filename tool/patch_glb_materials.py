#!/usr/bin/env python3
"""Corrige os materiais dos GLBs em art/models/, editando o chunk JSON no lugar.

Duas correcoes:
  GRUPO A  arquetipos comuns tem que sair NEUTROS (cinza #D8DCE8): o jogo aplica
           a cor da paleta em runtime com BlendMode.modulate, e um acento assado
           vira tinta errada permanente.
  SKINS    o casco do jogador e a superficie que carrega a identidade da skin.
           Os modelos vieram com casco preto e so uma plaqueta colorida.
"""
import json
import os
import struct
import sys

ROOT = sys.argv[1]
MODELS = os.path.join(ROOT, "art", "models")

# Valores de referencia, copiados de enemy_sniper/enemy_runner, que ja sairam
# corretos. Sao lineares (o glTF armazena baseColorFactor em espaco linear).
NEUTRAL_BASE = [0.6867, 0.7157, 0.807, 1.0]
NEUTRAL_EMIS = [0.8879, 0.9131, 1.0]

GROUP_A = [
    "enemy_elite", "enemy_ringer", "enemy_heavy", "enemy_freighter",
    "enemy_spinner", "enemy_grunt", "enemy_kamikaze", "pickup_capsule",
]

# hull -> corpo principal (material hull_black), wing -> asas (accent_plate),
# accent -> tiras emissivas. Cores de ShipSkinData em lib/core/garage.dart.
SKINS = {
    "player_aurora":   ("E8F4FF", "4C6BFF", "35E1F5"),
    "player_crimson":  ("FFD7D7", "8E1B2E", "FF3B5C"),
    "player_gold":     ("FFF0C0", "E89B00", "FFC94A"),
    "player_voidfire": ("E7D6FF", "5A2E9E", "9B4DFF"),
    "player_spectre":  ("FFFFFF", "9FB6C4", "B8FFF4"),
}


def srgb_to_linear(hexstr):
    out = []
    for i in (0, 2, 4):
        c = int(hexstr[i:i + 2], 16) / 255
        out.append(c / 12.92 if c <= 0.04045
                   else ((c + 0.055) / 1.055) ** 2.4)
    return [round(v, 4) for v in out]


def load(path):
    with open(path, "rb") as f:
        blob = f.read()
    jlen, _ = struct.unpack("<II", blob[12:20])
    doc = json.loads(blob[20:20 + jlen].decode("utf-8"))
    return doc, blob[20 + jlen:]


def save(path, doc, rest):
    raw = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def is_dark(c):
    return max(c[:3]) < 0.05


def is_white(c):
    return min(c[:3]) > 0.85


def neutralize(name):
    """Qualquer superficie que nao seja o chassi escuro nem um branco proposital
    vira cinza; qualquer emissivo vira o branco de referencia."""
    path = os.path.join(MODELS, name + ".glb")
    doc, rest = load(path)
    hits = []
    for m in doc.get("materials", []):
        pbr = m.setdefault("pbrMetallicRoughness", {})
        base = pbr.get("baseColorFactor")
        if base and not is_dark(base) and not is_white(base):
            pbr["baseColorFactor"] = list(NEUTRAL_BASE)
            hits.append(m.get("name", "?") + ":base")
        emis = m.get("emissiveFactor")
        if emis and any(v > 0.001 for v in emis):
            m["emissiveFactor"] = list(NEUTRAL_EMIS)
            hits.append(m.get("name", "?") + ":emis")
    save(path, doc, rest)
    return hits


def reskin(name, hull, wing, accent):
    path = os.path.join(MODELS, name + ".glb")
    doc, rest = load(path)
    mapping = {
        "hull_black": srgb_to_linear(hull),
        "accent_plate": srgb_to_linear(wing),
    }
    hits = []
    for m in doc.get("materials", []):
        mn = m.get("name")
        if mn in mapping:
            pbr = m.setdefault("pbrMetallicRoughness", {})
            pbr["baseColorFactor"] = mapping[mn] + [1.0]
            hits.append(mn)
        elif mn == "light_strip_emissive":
            m["emissiveFactor"] = srgb_to_linear(accent)
            hits.append(mn)
    save(path, doc, rest)
    return hits


for n in GROUP_A:
    print("[neutro ]", n, "->", ", ".join(neutralize(n)))
for n, (h, w, a) in SKINS.items():
    print("[skin   ]", n, "->", ", ".join(reskin(n, h, w, a)))
