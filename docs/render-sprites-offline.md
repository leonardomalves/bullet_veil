# Render offline: GLB → sprite sheet

> Como transformar os modelos 3D (Claude Design 3D) nos sprites que o Flame
> desenha. Escopo: bullet_veil · complementa `docs/prompt-design-assets.md`.

O Flame é 2D. Nada de GLB entra no jogo: os modelos são renderizados **fora**
do ciclo de build, de cima para baixo, em folhas de sprites que o jogo blita.
Rodar isso é manual e raro — só quando a arte muda.

## Pré-requisitos

| Ferramenta | Versão | Situação nesta máquina |
|---|---|---|
| Blender | 4.2 LTS ou superior | **não instalado** — instalar e deixar no PATH (ou passar `--blender`) |
| Python | 3.10+ | ok (3.14.6) |
| Pillow | qualquer recente | ok (12.3.0) |

## Layout

```
art/models/*.glb          ← os GLBs entram aqui (fonte, não vai pro app)
tool/sprite_manifest.py   ← o que renderizar e em que tamanho
tool/render_sprites.py    ← roda DENTRO do Blender
tool/build_sprites.py     ← orquestra o Blender e empacota as folhas
build/sprites_raw/        ← frames soltos (intermediário, já ignorado)
assets/sprites/*.png      ← saída: uma folha por modelo
assets/sprites/*.json     ← saída: manifesto de cada folha
```

## Decisões que o script assume

- **Câmera ortográfica olhando direto para baixo.** É a projeção do jogo; qualquer
  perspectiva faz a nave "inclinar" conforme sai do centro da tela.
- **Fundo transparente e sem bloom.** O halo de cada objeto continua sendo
  desenhado em código (círculo borrado). Se o bloom vier assado no sprite, o
  halo aparece duas vezes e a borda perde o corte.
- **Color management em `Standard`.** O padrão do Blender (AgX/Filmic) lava o
  neon: `#35E1F5` sai acinzentado. Com `Standard`, o hex autorado é o hex
  renderizado.
- **Caixa envolvente unida entre todos os frames.** Sem isso, um modelo que gira
  ou bate asa muda de escala frame a frame e o sprite "respira".
- **Supersample 3× com redução Lanczos.** Barato aqui, e é o que segura a
  silhueta nítida nos tamanhos pequenos (kamikaze tem 44 px de diâmetro).

## O que NÃO vira sprite

Continua em código, por cima do sprite:

| Elemento | Onde | Por quê |
|---|---|---|
| Cabine branca do inimigo | `enemy.dart` `_renderShip` | marca o centro real da colisão; tem que ser constante em toda escala |
| Ponto de colisão do jogador | `player.dart` `render` | idem — é o pixel que mata |
| Anel de graze (r=28) | `player.dart` | é regra de jogo, não decoração |
| Halo / glow | ambos | tem que somar com o blend aditivo das balas |
| Chama do motor, rastro, faíscas | ambos | animados por `dt`, não por frame de sheet |
| Flash de dano | `enemy.dart` `_flash` | trocar o `Paint` por `ColorFilter.mode(Colors.white, BlendMode.srcATop)` em vez de gastar frames |

---

## `tool/sprite_manifest.py`

```python
#!/usr/bin/env python3
"""Catálogo do que renderizar. Único lugar a editar quando a arte muda.

diameter_px  Diâmetro que o sprite ocupa na arena virtual de 720x1280, a 1x.
             Derivado do `radius` do objeto no jogo, com folga para asas/anéis
             que passam do raio de colisão.
yaw_deg      Giro em Z aplicado uma vez antes de renderizar. A câmera olha para
             -Z, então +Y do mundo é PARA CIMA na tela. O jogador aponta para
             cima (yaw 0); os inimigos apontam para baixo (yaw 180). Se o
             gerador cuspir o modelo virado, este é o botão a mexer.
mode         'static' | 'spin' | 'clip'
             spin  gira o modelo inteiro em Z ao longo de `frames`
             clip  amostra a animação que veio no GLB
spin_arc_deg Arco varrido pelo 'spin'. O NÚCLEO tem 8 segmentos iguais, então
             45 graus já fecham um loop perfeito — 1/8 dos frames.
"""

SUPERSAMPLE = 3
PADDING = 0.04  # folga da caixa envolvente, evita clipar a ponta da asa

MODELS = [
    # ── Chefes ───────────────────────────────────────────────────────────
    dict(name="boss_dreadnought", glb="boss_dreadnought.glb",
         diameter_px=180, yaw_deg=180, mode="static"),
    # 'clip' seria o ideal (as asas em foice batem), mas o GLB exportado nao
    # trouxe nenhuma animacao. As asas existem como pecas em dobradica dentro
    # de interceptor.js — animar la e reexportar reabre a opcao.
    dict(name="boss_mantis", glb="boss_mantis.glb",
         diameter_px=164, yaw_deg=180, mode="static"),
    dict(name="boss_core", glb="boss_core.glb",
         diameter_px=148, yaw_deg=180, mode="spin", frames=12,
         spin_arc_deg=45),

    # ── Elite ────────────────────────────────────────────────────────────
    dict(name="enemy_elite", glb="enemy_elite.glb",
         diameter_px=104, yaw_deg=180, mode="static"),

    # ── Frota comum ──────────────────────────────────────────────────────
    dict(name="enemy_heavy", glb="enemy_heavy.glb",
         diameter_px=84, yaw_deg=180, mode="static"),
    dict(name="enemy_freighter", glb="enemy_freighter.glb",
         diameter_px=80, yaw_deg=180, mode="static"),
    dict(name="enemy_ringer", glb="enemy_ringer.glb",
         diameter_px=72, yaw_deg=180, mode="static"),
    dict(name="enemy_spinner", glb="enemy_spinner.glb",
         diameter_px=64, yaw_deg=180, mode="static"),
    dict(name="enemy_grunt", glb="enemy_grunt.glb",
         diameter_px=52, yaw_deg=180, mode="static"),
    dict(name="enemy_kamikaze", glb="enemy_kamikaze.glb",
         diameter_px=44, yaw_deg=180, mode="static"),
    dict(name="enemy_sniper", glb="enemy_sniper.glb",
         diameter_px=52, yaw_deg=180, mode="static"),
    # yaw 0, nao 90: strafer.js ja constroi a nave com a massa no eixo X.
    # Ela voa nos dois sentidos e o modelo tem motor num extremo so — o jogo
    # espelha com canvas.scale(-1, 1) quando a velocidade e negativa.
    dict(name="enemy_runner", glb="enemy_runner.glb",
         diameter_px=48, yaw_deg=0, mode="static"),

    # ── Jogador: uma malha, cinco materiais ──────────────────────────────
    dict(name="player_aurora", glb="player_aurora.glb",
         diameter_px=64, yaw_deg=0, mode="static"),
    dict(name="player_crimson", glb="player_crimson.glb",
         diameter_px=64, yaw_deg=0, mode="static"),
    dict(name="player_gold", glb="player_gold.glb",
         diameter_px=64, yaw_deg=0, mode="static"),
    dict(name="player_voidfire", glb="player_voidfire.glb",
         diameter_px=64, yaw_deg=0, mode="static"),
    dict(name="player_spectre", glb="player_spectre.glb",
         diameter_px=64, yaw_deg=0, mode="static"),

    # ── Acessórios ───────────────────────────────────────────────────────
    dict(name="drone_wingman", glb="drone_wingman.glb",
         diameter_px=28, yaw_deg=0, mode="static"),
    # capsule.js ja faz rotation.x = -PI/2 ("letter panel faces up"), entao a
    # face da letra ja aponta para a camera. Nao precisa de pitch.
    dict(name="pickup_capsule", glb="pickup_capsule.glb",
         diameter_px=40, yaw_deg=0, mode="spin", frames=16),
    dict(name="option_satellite", glb="option_satellite.glb",
         diameter_px=24, yaw_deg=0, mode="static"),
    dict(name="pickup_medal", glb="pickup_medal.glb",
         diameter_px=24, yaw_deg=0, mode="spin", frames=16),
]


def by_name(name):
    for m in MODELS:
        if m["name"] == name:
            return m
    raise SystemExit(f"modelo desconhecido: {name}")


def frames_of(m):
    return 1 if m["mode"] == "static" else int(m.get("frames", 1))
```

---

## `tool/render_sprites.py`

```python
#!/usr/bin/env python3
"""Renderiza UM modelo em frames PNG soltos. Roda dentro do Blender:

    blender -b -P tool/render_sprites.py -- --name boss_core --root .

Não chame direto — use `tool/build_sprites.py`.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprite_manifest as man  # noqa: E402


def cli():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    p = argparse.ArgumentParser()
    p.add_argument("--name", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--preview", action="store_true",
                   help="um frame só, para conferir orientação e enquadramento")
    return p.parse_args(argv)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    # EEVEE Next (4.2+) com queda para o EEVEE antigo.
    for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_percentage = 100
    # Sem isto o neon sai lavado: AgX/Filmic reinterpretam a cor autorada.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    return scene


def build_world(scene):
    """Ambiente chapado: painel liso, aresta viva, nada de drama."""
    world = bpy.data.worlds.new("flat")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs[1].default_value = 0.35
    scene.world = world

    def sun(name, rot, energy):
        data = bpy.data.lights.new(name, type="SUN")
        data.energy = energy
        data.angle = 0.0
        obj = bpy.data.objects.new(name, data)
        obj.rotation_euler = rot
        scene.collection.objects.link(obj)

    sun("key", (0.0, 0.0, 0.0), 2.6)                    # de cima, junto da câmera
    sun("fill_a", (math.radians(55), 0.0, math.radians(35)), 0.9)
    sun("fill_b", (math.radians(-45), 0.0, math.radians(-120)), 0.6)


def import_glb(path):
    if not os.path.exists(path):
        raise SystemExit(f"GLB ausente: {path}")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    imported = [o for o in bpy.data.objects if o not in before]
    if not imported:
        raise SystemExit(f"nada importado de {path}")

    # Um empty como pai único: yaw e spin passam a ser uma linha só.
    rig = bpy.data.objects.new("RIG", None)
    bpy.context.scene.collection.objects.link(rig)
    for o in imported:
        if o.parent is None:
            o.parent = rig
            o.matrix_parent_inverse = rig.matrix_world.inverted()
    return rig, imported


def pose(rig, m, i, total):
    """Coloca o rig/cena no estado do frame [i]."""
    yaw = math.radians(m["yaw_deg"])
    if m["mode"] == "spin":
        arc = math.radians(m.get("spin_arc_deg", 360.0))
        rig.rotation_euler.z = yaw + arc * (i / total)
    else:
        rig.rotation_euler.z = yaw
    if m["mode"] == "clip":
        scene = bpy.context.scene
        start, end = scene.frame_start, scene.frame_end
        span = max(1, end - start)
        scene.frame_set(start + round(span * i / total))
    bpy.context.view_layer.update()


def world_bbox(objects):
    """Caixa envolvente em coordenadas de mundo, com animação já avaliada."""
    dg = bpy.context.evaluated_depsgraph_get()
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    found = False
    for o in objects:
        if o.type != "MESH":
            continue
        ev = o.evaluated_get(dg)
        for corner in ev.bound_box:
            p = ev.matrix_world @ Vector(corner)
            lo = Vector((min(lo[k], p[k]) for k in range(3)))
            hi = Vector((max(hi[k], p[k]) for k in range(3)))
            found = True
    if not found:
        raise SystemExit("nenhuma malha no GLB")
    return lo, hi


def union_bbox(rig, meshes, m, total):
    """Une a caixa de TODOS os frames: sem isto o sprite muda de escala."""
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for i in range(total):
        pose(rig, m, i, total)
        a, b = world_bbox(meshes)
        lo = Vector((min(lo[k], a[k]) for k in range(3)))
        hi = Vector((max(hi[k], b[k]) for k in range(3)))
    return lo, hi


def build_camera(scene, lo, hi):
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    span = max(hi.x - lo.x, hi.y - lo.y) * (1 + man.PADDING)
    depth = hi.z - lo.z

    data = bpy.data.cameras.new("cam")
    data.type = "ORTHO"
    data.ortho_scale = span
    data.clip_start = 0.01
    data.clip_end = depth + 1000.0
    cam = bpy.data.objects.new("cam", data)
    # rotation zero => olhando para -Z, ou seja, direto para baixo.
    cam.location = (cx, cy, hi.z + depth + 10.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam


def main():
    args = cli()
    m = man.by_name(args.name)
    total = 1 if args.preview else man.frames_of(m)

    scene = reset_scene()
    build_world(scene)
    rig, imported = import_glb(
        os.path.join(args.root, "art", "models", m["glb"]))
    meshes = [o for o in imported if o.type == "MESH"]

    lo, hi = union_bbox(rig, meshes, m, total)
    build_camera(scene, lo, hi)

    side = m["diameter_px"] * man.SUPERSAMPLE
    scene.render.resolution_x = side
    scene.render.resolution_y = side

    out_dir = os.path.join(args.root, "build", "sprites_raw",
                           m["name"] + ("_preview" if args.preview else ""))
    os.makedirs(out_dir, exist_ok=True)

    for i in range(total):
        pose(rig, m, i, total)
        scene.render.filepath = os.path.join(out_dir, f"frame_{i:04d}.png")
        bpy.ops.render.render(write_still=True)
        print(f"[render] {m['name']} {i + 1}/{total}")


main()
```

---

## `tool/build_sprites.py`

```python
#!/usr/bin/env python3
"""Orquestra o Blender e empacota os frames em folhas de sprite.

    python tool/build_sprites.py                    # tudo
    python tool/build_sprites.py --only boss_core   # um modelo
    python tool/build_sprites.py --only boss_core --preview
    python tool/build_sprites.py --blender "C:/Program Files/.../blender.exe"
"""
import argparse
import json
import math
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sprite_manifest as man  # noqa: E402

from PIL import Image  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENDERER = os.path.join(ROOT, "tool", "render_sprites.py")
RAW = os.path.join(ROOT, "build", "sprites_raw")
OUT = os.path.join(ROOT, "assets", "sprites")


def find_blender(explicit):
    if explicit:
        return explicit
    found = shutil.which("blender")
    if found:
        return found
    # Caminhos usuais no Windows, do mais novo para o mais velho.
    base = r"C:\Program Files\Blender Foundation"
    if os.path.isdir(base):
        for entry in sorted(os.listdir(base), reverse=True):
            exe = os.path.join(base, entry, "blender.exe")
            if os.path.exists(exe):
                return exe
    raise SystemExit(
        "Blender não encontrado. Instale o 4.2+ e ponha no PATH, "
        "ou passe --blender com o caminho do executável.")


def render(blender, name, preview):
    cmd = [blender, "-b", "-P", RENDERER, "--", "--name", name, "--root", ROOT]
    if preview:
        cmd.append("--preview")
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout[-4000:] + proc.stderr[-4000:])
        raise SystemExit(f"Blender falhou em {name}")


def pack(m, preview):
    """Junta os frames numa folha quadrada-ish e escreve o manifesto."""
    name = m["name"] + ("_preview" if preview else "")
    src = os.path.join(RAW, name)
    files = sorted(f for f in os.listdir(src) if f.endswith(".png"))
    if not files:
        raise SystemExit(f"sem frames em {src}")

    size = m["diameter_px"]
    cols = min(len(files), max(1, math.ceil(math.sqrt(len(files)))))
    rows = math.ceil(len(files) / cols)

    sheet = Image.new("RGBA", (cols * size, rows * size), (0, 0, 0, 0))
    for i, f in enumerate(files):
        frame = Image.open(os.path.join(src, f)).convert("RGBA")
        if frame.size != (size, size):
            frame = frame.resize((size, size), Image.LANCZOS)
        sheet.paste(frame, ((i % cols) * size, (i // cols) * size))

    os.makedirs(OUT, exist_ok=True)
    sheet.save(os.path.join(OUT, f"{name}.png"), optimize=True)

    meta = {
        "name": name,
        "frameWidth": size,
        "frameHeight": size,
        "cols": cols,
        "rows": rows,
        "count": len(files),
        "diameterPx": size,
        # A âncora é o centro: os render() do jogo desenham em Offset.zero.
        "anchor": [0.5, 0.5],
        "loop": m["mode"] != "static",
    }
    with open(os.path.join(OUT, f"{name}.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2)
    print(f"[pack] {name}.png  {cols}x{rows}  {len(files)} frame(s)")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--only", action="append", default=None)
    p.add_argument("--preview", action="store_true")
    p.add_argument("--blender", default=None)
    args = p.parse_args()

    blender = find_blender(args.blender)
    targets = ([man.by_name(n) for n in args.only] if args.only else man.MODELS)

    for m in targets:
        glb = os.path.join(ROOT, "art", "models", m["glb"])
        if not os.path.exists(glb):
            print(f"[skip] {m['name']}: {m['glb']} ainda não existe")
            continue
        render(blender, m["name"], args.preview)
        pack(m, args.preview)


main()
```

---

## Estado dos modelos

Os 21 GLBs já estão em `art/models/`, renomeados a partir da exportação do
Claude Design. Eles vieram de fontes three.js escritos à mão (os `.js` dentro do
zip do canvas), não de reconstrução de malha — por isso a geometria é limpa e a
convenção de eixos é declarada no cabeçalho de cada fonte: **"Forward is -Z,
y-up"**. O importador glTF do Blender manda -Z para +Y, que é o topo da tela na
câmera deste script; daí `yaw_deg=0` no jogador e `180` nos inimigos.

Dois defeitos vieram na exportação e já foram corrigidos direto no chunk JSON
dos GLBs, com o script do apêndice:

1. **Oito modelos do Grupo A vinham com acento colorido.** O jogo tinge os
   arquétipos comuns em runtime (`Enemy.color` × `BlendMode.modulate`), então
   qualquer cor assada vira tinta errada permanente. Foram normalizados para o
   mesmo cinza `#D8DCE8` que `enemy_sniper` e `enemy_runner` já traziam.
2. **As cinco skins do jogador vinham com casco preto.** A identidade da skin
   mora no casco claro (`ShipSkinData.hull`), não numa plaqueta. O casco passou
   a receber `hull`, as asas `wing`, e a tira emissiva `accent`.

Ambas as correções ainda **precisam do render de preview para conferência
visual** — são mudanças de material verificadas por leitura de JSON, não por
imagem.

## Uso

Confira a orientação de um modelo antes de gastar 24 frames nele — o `yaw_deg`
é o erro mais provável, porque depende de como o gerador orientou a malha:

```bash
python tool/build_sprites.py --only boss_core --preview
```

Se o chefe estiver de cabeça para baixo, mexa em `yaw_deg` no manifesto e
repita. Com a orientação certa:

```bash
python tool/build_sprites.py
```

Modelo que ainda não existe em `art/models/` é pulado com aviso — dá para
renderizar a arte em lotes, conforme ela for saindo.

## Ligar no jogo

1. Só **depois** que `assets/sprites/` tiver conteúdo, declarar no `pubspec.yaml`
   (o Flutter quebra o build se a pasta declarada não existir):

   ```yaml
   assets:
     - assets/audio/
     - assets/sprites/
   ```

2. Trocar o corpo de `Enemy._renderShip` / `_renderBoss` e de `Player.render`
   por um `drawImageRect` do frame corrente, **mantendo** cabine, ponto de
   colisão, anel de graze e halo desenhados por cima, como está na tabela lá em
   cima.

3. Para os modelos animados (`boss_mantis`, `boss_core`, `pickup_capsule`), o
   índice do frame sai de um acumulador de `dt` — o `_spin` que `Enemy` já
   mantém serve: `(_spin * fps) % count`.

4. `BulletAtlas` fica como está. As balas continuam procedurais, e é isso que
   segura os milhares de sprites numa chamada só de `drawRawAtlas`.

---

## Apêndice — `tool/patch_glb_materials.py`

Corrige cor de material sem abrir o Blender: o `baseColorFactor` e o
`emissiveFactor` moram no chunk JSON do GLB, então dá para reescrever no lugar.
Já foi aplicado uma vez nos 21 modelos; guardado aqui porque é idempotente e
volta a ser útil a cada exportação nova do canvas.

```python
#!/usr/bin/env python3
"""Corrige os materiais dos GLBs em art/models/, editando o chunk JSON no lugar.

    python tool/patch_glb_materials.py .

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

# Referencia copiada de enemy_sniper/enemy_runner, que ja sairam corretos.
# Lineares: o glTF guarda baseColorFactor em espaco linear, nao sRGB.
NEUTRAL_BASE = [0.6867, 0.7157, 0.807, 1.0]
NEUTRAL_EMIS = [0.8879, 0.9131, 1.0]

GROUP_A = [
    "enemy_elite", "enemy_ringer", "enemy_heavy", "enemy_freighter",
    "enemy_spinner", "enemy_grunt", "enemy_kamikaze", "pickup_capsule",
]

# hull -> corpo (material hull_black), wing -> asas (accent_plate),
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
    return json.loads(blob[20:20 + jlen].decode("utf-8")), blob[20 + jlen:]


def save(path, doc, rest):
    raw = json.dumps(doc, separators=(",", ":")).encode("utf-8")
    raw += b" " * ((4 - len(raw) % 4) % 4)   # chunk tem que fechar em 4 bytes
    body = struct.pack("<II", len(raw), 0x4E4F534A) + raw + rest
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def is_dark(c):
    return max(c[:3]) < 0.05


def is_white(c):
    return min(c[:3]) > 0.85


def neutralize(name):
    """Superficie que nao e chassi escuro nem branco proposital vira cinza;
    qualquer emissivo vira o branco de referencia."""
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
```
