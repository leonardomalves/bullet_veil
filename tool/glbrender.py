#!/usr/bin/env python3
"""Rasteriza um GLB em vista ortografica de cima, sem Blender.

Os modelos do Bullet Veil sao low-poly, sem textura, com material de cor
chapada + emissivo. Isso e o caso mais simples de rasterizacao que existe:
z-buffer, sombreamento flat, projecao ortografica. Nao precisa de motor 3D.

Convencao: glTF e y-up com "forward = -Z". A camera do jogo olha direto para
baixo, ou seja, ao longo de -Y. Logo:
    tela X = glTF X      tela Y = glTF Z      profundidade = glTF Y
Com isso o nariz (-Z) cai no TOPO da tela, que e o que o jogador quer ver.
"""
import json
import math
import struct

# ── glTF ────────────────────────────────────────────────────────────────────

_CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
       5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
_NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load_glb(path):
    with open(path, "rb") as f:
        blob = f.read()
    off = 12
    doc, bin_chunk = None, b""
    while off < len(blob):
        clen, ctype = struct.unpack("<II", blob[off:off + 8])
        data = blob[off + 8:off + 8 + clen]
        if ctype == 0x4E4F534A:
            doc = json.loads(data.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_chunk = data
        off += 8 + clen
    return doc, bin_chunk


def read_accessor(doc, buf, index):
    acc = doc["accessors"][index]
    fmt, size = _CT[acc["componentType"]]
    n = _NC[acc["type"]]
    count = acc["count"]
    bv = doc["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or (size * n)
    out = []
    for i in range(count):
        o = base + i * stride
        out.append(struct.unpack_from("<" + fmt * n, buf, o))
    return out


# ── matrizes 4x4 (linha-maior, vetor-coluna) ────────────────────────────────

def mat_identity():
    return [1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1.0]


def mat_mul(a, b):
    out = [0.0] * 16
    for r in range(4):
        for c in range(4):
            out[r * 4 + c] = sum(a[r * 4 + k] * b[k * 4 + c] for k in range(4))
    return out


def mat_from_node(node):
    if "matrix" in node:
        m = node["matrix"]          # glTF entrega coluna-maior
        return [m[0], m[4], m[8], m[12],
                m[1], m[5], m[9], m[13],
                m[2], m[6], m[10], m[14],
                m[3], m[7], m[11], m[15]]
    t = node.get("translation", [0, 0, 0])
    r = node.get("rotation", [0, 0, 0, 1])   # quaternion xyzw
    s = node.get("scale", [1, 1, 1])
    x, y, z, w = r
    rot = [
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    ]
    for c in range(3):
        for r_ in range(3):
            rot[r_ * 4 + c] *= s[c]
    rot[3], rot[7], rot[11] = t[0], t[1], t[2]
    return rot


def xform(m, p):
    x, y, z = p
    return (m[0] * x + m[1] * y + m[2] * z + m[3],
            m[4] * x + m[5] * y + m[6] * z + m[7],
            m[8] * x + m[9] * y + m[10] * z + m[11])


def xform_dir(m, p):
    x, y, z = p
    return (m[0] * x + m[1] * y + m[2] * z,
            m[4] * x + m[5] * y + m[6] * z,
            m[8] * x + m[9] * y + m[10] * z)


# ── coleta de triangulos ────────────────────────────────────────────────────

def collect(path, yaw_deg=0.0):
    """Devolve (triangulos, bbox). Cada triangulo: (p0, p1, p2, material).
    Ja em espaco de TELA: (sx, sy, depth)."""
    doc, buf = load_glb(path)
    scene = doc.get("scenes", [{}])[doc.get("scene", 0)]
    tris = []

    ca, sa = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))

    def to_screen(p):
        # glTF (x, y, z) -> tela (x, z, profundidade y), com yaw no plano.
        sx, sy, d = p[0], p[2], p[1]
        return (sx * ca - sy * sa, sx * sa + sy * ca, d)

    def walk(idx, parent):
        node = doc["nodes"][idx]
        world = mat_mul(parent, mat_from_node(node))
        if "mesh" in node:
            for prim in doc["meshes"][node["mesh"]].get("primitives", []):
                if prim.get("mode", 4) != 4:
                    continue
                pos = read_accessor(doc, buf, prim["attributes"]["POSITION"])
                nrm = (read_accessor(doc, buf, prim["attributes"]["NORMAL"])
                       if "NORMAL" in prim["attributes"] else None)
                idxs = ([i[0] for i in read_accessor(doc, buf, prim["indices"])]
                        if "indices" in prim else list(range(len(pos))))
                mat = prim.get("material", -1)
                for k in range(0, len(idxs) - 2, 3):
                    a, b, c = idxs[k], idxs[k + 1], idxs[k + 2]
                    p = [to_screen(xform(world, pos[i])) for i in (a, b, c)]
                    if nrm:
                        n = xform_dir(world, nrm[a])
                    else:
                        n = (0.0, 1.0, 0.0)
                    tris.append((p[0], p[1], p[2], mat, n))
        for ch in node.get("children", []):
            walk(ch, world)

    for root in scene.get("nodes", []):
        walk(root, mat_identity())

    lo = [min(t[i][k] for t in tris for i in range(3)) for k in range(3)]
    hi = [max(t[i][k] for t in tris for i in range(3)) for k in range(3)]
    return tris, (lo, hi), doc


# ── material ────────────────────────────────────────────────────────────────

def lin_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055


def material_colors(doc):
    out = []
    for m in doc.get("materials", []):
        base = m.get("pbrMetallicRoughness", {}).get(
            "baseColorFactor", [1, 1, 1, 1])
        emis = m.get("emissiveFactor", [0, 0, 0])
        out.append((base[:3], emis))
    return out


# ── rasterizador ────────────────────────────────────────────────────────────

def render(path, size, yaw_deg=0.0, ss=3, padding=0.04, bbox=None):
    """PNG RGBA quadrado de lado `size`, com supersample `ss`."""
    from PIL import Image

    tris, own_bbox, doc = collect(path, yaw_deg)
    lo, hi = bbox or own_bbox
    span = max(hi[0] - lo[0], hi[1] - lo[1]) * (1 + padding)
    cx, cy = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2

    W = size * ss
    scale = W / span
    mats = material_colors(doc)

    # A luz vem de cima (da camera). Ambiente alto de proposito: o alvo e
    # painel chapado, nao volume dramatico.
    AMBIENT, KEY = 0.62, 0.38

    zbuf = [-1e30] * (W * W)
    px = bytearray(W * W * 4)

    for (p0, p1, p2, mi, n) in tris:
        def proj(p):
            return ((p[0] - cx) * scale + W / 2, (p[1] - cy) * scale + W / 2, p[2])
        a, b, c = proj(p0), proj(p1), proj(p2)

        minx = max(0, int(math.floor(min(a[0], b[0], c[0]))))
        maxx = min(W - 1, int(math.ceil(max(a[0], b[0], c[0]))))
        miny = max(0, int(math.floor(min(a[1], b[1], c[1]))))
        maxy = min(W - 1, int(math.ceil(max(a[1], b[1], c[1]))))
        if minx > maxx or miny > maxy:
            continue

        area = (b[0] - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (b[1] - a[1])
        if abs(area) < 1e-9:
            continue
        inv = 1.0 / area

        base, emis = (mats[mi] if 0 <= mi < len(mats) else ([1, 1, 1], [0, 0, 0]))
        ln = math.sqrt(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) or 1.0
        lam = max(0.0, n[1] / ln)           # luz ao longo de +Y (de cima)
        shade = AMBIENT + KEY * lam
        rgb = []
        for k in range(3):
            v = base[k] * shade + emis[k]
            rgb.append(int(round(255 * lin_to_srgb(v))))

        for y in range(miny, maxy + 1):
            for x in range(minx, maxx + 1):
                fx, fy = x + 0.5, y + 0.5
                w0 = ((b[0] - a[0]) * (fy - a[1]) - (fx - a[0]) * (b[1] - a[1])) * inv
                w1 = ((fx - a[0]) * (c[1] - a[1]) - (c[0] - a[0]) * (fy - a[1])) * inv
                if w0 < 0 or w1 < 0 or w0 + w1 > 1:
                    continue
                d = a[2] + w1 * (b[2] - a[2]) + w0 * (c[2] - a[2])
                o = y * W + x
                if d <= zbuf[o]:
                    continue
                zbuf[o] = d
                q = o * 4
                px[q] = rgb[0]
                px[q + 1] = rgb[1]
                px[q + 2] = rgb[2]
                px[q + 3] = 255

    img = Image.frombytes("RGBA", (W, W), bytes(px))
    return img.resize((size, size), Image.LANCZOS) if ss > 1 else img
