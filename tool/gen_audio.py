#!/usr/bin/env python3
"""Gera os SFX e a música do Bullet Veil proceduralmente (16-bit mono WAV, 44.1kHz).

Uso: python3 tool/gen_audio.py assets/audio

Música em 3 loops SINCRONIZADOS (mesmo compasso, tocados juntos no jogo):
  music_base  — pulso + baixo + pad + arpejo esparso (sempre audível)
  music_layer — hats/caixa/arpejo 16avos; volume segue a FÚRIA (rank)
  music_boss  — loop próprio de tensão, crossfade quando o chefe entra
"""
import math
import os
import sys
import wave

import numpy as np

SR = 44100
OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/audio'
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)

# Grade musical em amostras inteiras: loop fecha perfeito, sem drift.
SPB = 20000            # amostras por batida (~132.3 BPM)
BAR = SPB * 4
LOOP = BAR * 8         # 640_000 amostras = 14.51s


def write(name, sig, fade_tail=True):
    sig = np.clip(sig, -1.0, 1.0)
    if fade_tail:  # SFX nunca estalam no fim; música precisa fechar o loop seca
        tail = min(len(sig), int(SR * 0.005))
        sig[-tail:] *= np.linspace(1.0, 0.0, tail)
    data = (sig * 32767).astype('<i2').tobytes()
    with wave.open(os.path.join(OUT, name), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)
    print(f'  {name:18s} {len(sig) / SR * 1000:7.0f}ms  {len(data) / 1024:6.1f}KB')


def t(dur):
    return np.linspace(0, dur, int(SR * dur), endpoint=False)


def env(n, attack=0.005, curve=4.0):
    a = int(SR * attack)
    e = np.exp(-curve * np.linspace(0, 1, n))
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    return e


def onepole_hp(x, coef=0.85):
    y = np.empty_like(x)
    px = py = 0.0
    for i in range(len(x)):
        py = coef * (py + x[i] - px)
        px = x[i]
        y[i] = py
    return y


def onepole_lp(x, a=0.2):
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def mix(*layers):
    n = max(len(x) for x in layers)
    out = np.zeros(n)
    for x in layers:
        out[:len(x)] += x
    return out


def bell(freq, dur, curve=5.0, harm=0.35, detune=2.01):
    ts = t(dur)
    s = np.sin(2 * np.pi * freq * ts)
    s += harm * np.sin(2 * np.pi * freq * detune * ts)
    s += 0.15 * np.sin(2 * np.pi * freq * 3.01 * ts) * np.exp(-12 * ts / dur)
    return s * env(len(ts), 0.002, curve=curve) / (1 + harm + 0.15)


def saw(freq, n):
    ph = (np.arange(n) * freq / SR) % 1.0
    return 2.0 * ph - 1.0


def sweep(f0, f1, dur, curve=1.0):
    """Seno com frequência varrendo f0→f1 (exponencial-ish)."""
    ts = t(dur)
    k = np.linspace(0, 1, len(ts)) ** curve
    f = f0 * (f1 / f0) ** k
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


# ═════════════════════════════════ SFX ═════════════════════════════════════

print('TIRO (baixo no mix — toca 12x/s, não pode furar o ouvido)')
for i, (f0, f1) in enumerate([(760, 340), (700, 320), (820, 360)]):
    dur = 0.055
    n = int(SR * dur)
    body = sweep(f0, f1, dur)
    airy = onepole_hp(rng.standard_normal(n), 0.9) * 0.18
    sig = onepole_lp(0.8 * body + airy, 0.35) * env(n, 0.001, curve=10.0) * 0.5
    write(f'shot_{i + 1}.wav', sig)

print('GRAZE (tick cristalino — ensina a mecânica sozinho)')
for i, f in enumerate([2960.0, 3320.0]):
    dur = 0.045
    sig = np.sin(2 * np.pi * f * t(dur))
    sig += 0.4 * np.sin(2 * np.pi * f * 1.502 * t(dur))
    write(f'graze_{i + 1}.wav', sig * env(len(sig), 0.001, curve=16.0) * 0.4)

print('MEDALHA (escada pentatônica — a corrente que se ouve subir)')
# 8 degraus casando com _medalSteps: E5 G5 A5 B5 D6 E6 G6 A6
for i, s in enumerate([0, 3, 5, 7, 10, 12, 15, 17]):
    freq = 659.26 * (2 ** (s / 12))
    write(f'medal_{i + 1}.wav', bell(freq, 0.30, curve=7.0) * 0.5)

print('EXPLOSÕES')
for i, seed_off in enumerate(range(3)):  # variantes pequenas
    dur = 0.26
    n = int(SR * dur)
    boom = sweep(300 + seed_off * 40, 55, dur) * 0.6
    dust = onepole_lp(rng.standard_normal(n), 0.22) * 1.5
    sig = (boom + dust) * env(n, 0.001, curve=7.5) * 0.62
    write(f'expl_small_{i + 1}.wav', sig)

dur = 0.5
n = int(SR * dur)
sig = (sweep(240, 42, dur) * 0.7 + onepole_lp(rng.standard_normal(n), 0.16) * 1.8)
write('expl_med.wav', sig * env(n, 0.001, curve=5.0) * 0.7)

# chefe: sequência de estouros encadeados + sub final
dur = 1.5
n = int(SR * dur)
buf = np.zeros(n)
for i, off in enumerate([0.0, 0.14, 0.27, 0.42, 0.62]):
    bn = int(SR * 0.3)
    b = (sweep(280 - i * 30, 48, 0.3) * 0.6
         + onepole_lp(rng.standard_normal(bn), 0.2) * 1.4) * env(bn, 0.001, 6.0)
    o = int(SR * off)
    buf[o:o + bn] += b * (0.5 + 0.12 * i)
sub = sweep(90, 30, 1.0) * env(int(SR * 1.0), 0.002, 3.0) * 0.9
o = int(SR * 0.55)
buf[o:] += sub[:n - o]
write('expl_boss.wav', buf * 0.62)

print('CÁPSULAS / PICKUPS')
# power: blip duplo subindo
sig = mix(bell(660, 0.10, curve=10.0), 0.9 * np.concatenate(
    [np.zeros(int(SR * 0.055)), bell(990, 0.12, curve=9.0)]))
write('power.wav', sig * 0.5)

# cápsula genérica (bomba+1 etc.): blip único mais grave
write('cap.wav', bell(520, 0.14, curve=9.0) * 0.5)

# troca de arma: acorde-carimbo + varredura de ar
n = int(SR * 0.22)
chord = mix(bell(523.25, 0.22, 6.0), bell(659.26, 0.20, 6.5), bell(784.0, 0.18, 7.0))
air = onepole_hp(rng.standard_normal(n), 0.93) * env(n, 0.004, 5.0) * 0.25
write('weapon.wav', mix(chord * 0.4, air))

# arma subiu de nível: 3 notas rápidas + brilho
dur = 0.5
buf = np.zeros(int(SR * dur))
for i, f in enumerate([523.25, 659.26, 880.0]):
    note = bell(f, 0.28, curve=6.0)
    o = int(SR * i * 0.07)
    buf[o:o + len(note)] += note * 0.42
write('weaponup.wav', buf)

# 1UP: jingle sagrado — pentatônica rápida com eco
dur = 0.85
buf = np.zeros(int(SR * dur))
for i, s in enumerate([0, 4, 7, 12, 16]):
    f = 523.25 * (2 ** (s / 12))
    note = bell(f, 0.32, curve=5.0)
    o = int(SR * i * 0.075)
    buf[o:o + len(note)] += note * 0.4
echo = np.concatenate([np.zeros(int(SR * 0.11)), buf[:-int(SR * 0.11)]]) * 0.3
write('oneup.wav', mix(buf, echo) * 0.9)

print('BOMBA / ESCUDO / MORTE')
# bomba: sucção reversa → estouro com sub
pre_n = int(SR * 0.22)
pre = onepole_lp(rng.standard_normal(pre_n), 0.3) * np.linspace(0, 1, pre_n) ** 2
blast_n = int(SR * 0.95)
blast = (sweep(150, 34, 0.95) * 0.8
         + onepole_lp(rng.standard_normal(blast_n), 0.12) * 2.0) * env(blast_n, 0.001, 4.0)
write('bomb.wav', np.concatenate([pre * 0.5, blast * 0.85]))

# escudo estourando: zap vítreo + thud
n = int(SR * 0.4)
zap = np.sin(2 * np.pi * 1150 * t(0.4) * (1 + 0.3 * np.sin(2 * np.pi * 38 * t(0.4))))
glass = onepole_hp(rng.standard_normal(n), 0.9) * env(n, 0.001, 12.0) * 0.5
write('shield.wav', mix(zap * env(n, 0.002, 8.0) * 0.5, glass,
                        sweep(200, 70, 0.25) * env(int(SR * 0.25), 0.001, 7.0) * 0.5) * 0.7)

# morte do jogador: estouro + "power down" caindo
n = int(SR * 1.1)
boom = (sweep(260, 40, 0.5) * 0.7
        + onepole_lp(rng.standard_normal(int(SR * 0.5)), 0.15) * 1.8) * env(int(SR * 0.5), 0.001, 5.0)
fall_t = t(0.75)
fall = np.sin(2 * np.pi * np.cumsum(560 * np.exp(-3.2 * fall_t) *
                                    (1 + 0.12 * np.sin(2 * np.pi * 26 * fall_t))) / SR)
fall *= env(len(fall_t), 0.01, 3.0) * 0.5
buf = np.zeros(n)
buf[:len(boom)] += boom * 0.8
buf[int(SR * 0.28):int(SR * 0.28) + len(fall)] += fall
write('death.wav', buf * 0.85)

print('CHEFE')
# alarme: sirene 2 tons ×3
cyc = []
for _ in range(3):
    for f in (622.0, 466.0):
        n = int(SR * 0.16)
        tone = np.sin(2 * np.pi * f * t(0.16)) + 0.35 * np.sin(2 * np.pi * f * 2 * t(0.16))
        e = np.ones(n)
        e[:300] = np.linspace(0, 1, 300)
        e[-600:] = np.linspace(1, 0.2, 600)
        cyc.append(onepole_lp(tone, 0.5) * e * 0.5)
write('alarm.wav', np.concatenate(cyc))

# virada de fase do chefe: impacto + riser
imp_n = int(SR * 0.3)
imp = (sweep(220, 50, 0.3) * 0.7 + onepole_lp(rng.standard_normal(imp_n), 0.2) * 1.3) * env(imp_n, 0.001, 6.0)
ris_n = int(SR * 0.55)
ris = onepole_hp(rng.standard_normal(ris_n), 0.88) * np.linspace(0.1, 1, ris_n) ** 1.6 * 0.5
ris += sweep(220, 880, 0.55) * np.linspace(0.05, 0.4, ris_n)
write('phase.wav', mix(imp * 0.8, np.concatenate([np.zeros(int(SR * 0.12)), ris * 0.55])))

print('SNIPER / TALLY')
# trava de mira do sniper: dois blips ameaçadores descendo
buf = np.zeros(int(SR * 0.3))
for i, f in enumerate([880.0, 660.0]):
    n = int(SR * 0.1)
    tone = (np.sin(2 * np.pi * f * t(0.1))
            + 0.4 * np.sin(2 * np.pi * f * 2.01 * t(0.1)))
    o = int(SR * i * 0.13)
    buf[o:o + n] += onepole_lp(tone, 0.45) * env(n, 0.002, 8.0) * 0.5
write('lock.wav', buf)

# tick de contagem do tally
n = int(SR * 0.05)
sig = np.sin(2 * np.pi * 1250 * t(0.05)) * env(n, 0.001, 13.0) * 0.45
write('tick.wav', sig)

# fanfarra de setor limpo: subida triunfal com eco
dur = 1.2
buf = np.zeros(int(SR * dur))
for i, s in enumerate([0, 5, 9, 12, 17]):
    f = 587.33 * (2 ** (s / 12))  # ré maior — vitória
    note = bell(f, 0.5, curve=4.0)
    o = int(SR * i * 0.09)
    buf[o:o + len(note)] += note * 0.4
echo = np.concatenate([np.zeros(int(SR * 0.14)), buf[:-int(SR * 0.14)]]) * 0.35
write('stageclear.wav', mix(buf, echo) * 0.8)

print('UI / FIM DE JOGO')
n = int(SR * 0.07)
sig = (np.sin(2 * np.pi * 1400 * t(0.07)) * 0.6
       + onepole_hp(rng.standard_normal(n), 0.9) * 0.35) * env(n, 0.001, 14.0) * 0.4
write('ui_tap.wav', sig)

dur = 1.3
buf = np.zeros(int(SR * dur))
for i, s in enumerate([0, -3, -6, -10]):
    f = 349.23 * (2 ** (s / 12))
    note = bell(f, dur - i * 0.16, curve=3.0, harm=0.5)
    o = int(SR * i * 0.16)
    buf[o:o + len(note)] += note * 0.34
write('gameover.wav', buf * 0.7)

for i, f in enumerate([440.0, 554.4, 659.3]):
    write(f'count_{i + 1}.wav', bell(f, 0.35, curve=6.0) * 0.5)
write('count_go.wav', mix(bell(880.0, 0.6, 3.0), 0.5 * bell(1318.5, 0.5, 4.0)) * 0.55)

# ═══════════════════════════════ MÚSICA ════════════════════════════════════
# Ré menor sombrio. Grade inteira em amostras → loop perfeito.

CHORDS = [  # (baixo, [pad], [arp]) por 2 compassos
    (73.42, [146.83, 174.61, 220.00], [293.66, 349.23, 440.00]),   # Dm
    (58.27, [116.54, 146.83, 174.61], [233.08, 293.66, 349.23]),   # Bb
    (98.00, [196.00, 233.08, 293.66], [392.00, 466.16, 587.33]),   # Gm
    (110.00, [138.59, 164.81, 220.00], [277.18, 329.63, 440.00]),  # A (tensão)
]


def kick(vol=0.5):
    n = 4200
    ts = np.arange(n) / SR
    f = 155 * np.exp(-28 * ts) + 44
    s = np.sin(2 * np.pi * np.cumsum(f) / SR)
    click = np.zeros(n)
    click[:220] = rng.standard_normal(220) * 0.4
    return (s + onepole_lp(click, 0.4)) * env(n, 0.0008, 8.0) * vol


def bass_note(freq, n, bright=0.18, vol=0.34):
    body = onepole_lp(saw(freq, n) + 0.4 * saw(freq * 1.004, n), bright)
    return body * env(n, 0.004, 5.0) * vol


def place(buf, sig, at):
    end = min(len(buf), at + len(sig))
    if end > at:
        buf[at:end] += sig[:end - at]


print('MÚSICA (base ~14.5s / camada de fúria / tema de chefe)')

# ── music_base ──
base = np.zeros(LOOP)
for beat in range(32):
    place(base, kick(0.5), beat * SPB)

for ci, (root, _, _) in enumerate(CHORDS):
    start = ci * 2 * BAR
    accents = [1.0, 0.55, 0.8, 0.55]
    for e8 in range(16):  # 8avos em 2 compassos
        f = root * 2 if e8 % 4 == 2 else root
        place(base, bass_note(f, 9000, vol=0.34 * accents[e8 % 4]), start + e8 * (SPB // 2))

for ci, (_, pad, _) in enumerate(CHORDS):
    start = ci * 2 * BAR
    n = 2 * BAR
    voice = np.zeros(n)
    for f in pad:
        voice += saw(f, n) + saw(f * 1.006, n)
    voice = onepole_lp(voice, 0.06)
    e = np.ones(n)
    a = int(n * 0.12)
    e[:a] = np.linspace(0, 1, a)
    e[-int(n * 0.08):] = np.linspace(1, 0, int(n * 0.08))
    place(base, voice * e * 0.10, start)

for ci, (_, _, arp) in enumerate(CHORDS):
    start = ci * 2 * BAR
    seq = [arp[0], arp[2], arp[1], arp[2]] * 2
    for b, f in enumerate(seq):
        note = bell(f, 0.18, curve=7.0) * 0.15
        place(base, note, start + b * SPB)
        place(base, note * 0.4, start + b * SPB + 7500)  # eco

peak = np.max(np.abs(base))
write('music_base.wav', base / peak * 0.88, fade_tail=False)

# ── music_layer (entra com a FÚRIA) ──
layer = np.zeros(LOOP)
hat_len = 1300
for s16 in range(128):
    h = onepole_hp(rng.standard_normal(hat_len), 0.92) * env(hat_len, 0.0005, 18.0)
    place(layer, h * (0.30 if s16 % 4 in (1, 3) else 0.16), s16 * (SPB // 2) // 2)

for bar in range(8):  # caixa nos tempos 2 e 4
    for beat in (1, 3):
        n = int(SR * 0.13)
        sn = onepole_lp(onepole_hp(rng.standard_normal(n), 0.7), 0.45) * env(n, 0.001, 8.0)
        body = np.sin(2 * np.pi * 190 * t(0.06)) * env(int(SR * 0.06), 0.001, 9.0)
        place(layer, mix(sn * 0.8, body * 0.5) * 0.5, bar * BAR + beat * SPB)

for ci, (_, _, arp) in enumerate(CHORDS):  # arpejo 16avos, oitava acima
    start = ci * 2 * BAR
    seq = [arp[0] * 2, arp[1] * 2, arp[2] * 2, arp[1] * 2]
    for s16 in range(32):
        f = seq[s16 % 4]
        n = 4500
        note = onepole_lp(np.sin(2 * np.pi * f * np.arange(n) / SR)
                          + 0.25 * np.sin(2 * np.pi * 3 * f * np.arange(n) / SR), 0.35)
        place(layer, note * env(n, 0.001, 9.0) * 0.15, start + s16 * (SPB // 2))

ris_n = SPB * 2  # riser no fim do loop, anuncia a volta
ris = onepole_hp(rng.standard_normal(ris_n), 0.9) * np.linspace(0, 1, ris_n) ** 2 * 0.12
place(layer, ris, LOOP - ris_n)

peak = np.max(np.abs(layer))
write('music_layer.wav', layer / peak * 0.88, fade_tail=False)

# ── music_boss (loop próprio de 4 compassos, mais denso) ──
BLOOP = BAR * 4
boss = np.zeros(BLOOP)
for beat in range(16):
    place(boss, kick(0.55), beat * SPB)
    place(boss, kick(0.3), beat * SPB + SPB // 2)  # "and" — pulso dobrado

roots = [73.42, 103.83, 73.42, 65.41]  # D, Ab (trítono!), D, C
for bar, root in enumerate(roots):
    for e8 in range(8):
        f = root * (2 if e8 in (3, 7) else 1)
        place(boss, bass_note(f, 9000, bright=0.3, vol=0.4), bar * BAR + e8 * (SPB // 2))

for bar in (0, 2):  # carimbo dissonante D+Ab+C
    stab_n = int(SR * 0.3)
    stab = onepole_lp(saw(146.83, stab_n) + saw(207.65, stab_n) + saw(261.63, stab_n), 0.2)
    place(boss, stab * env(stab_n, 0.003, 6.0) * 0.30, bar * BAR)
    place(boss, stab * env(stab_n, 0.003, 6.0) * 0.22, bar * BAR + 3 * SPB + SPB // 2)

for s16 in range(64):
    h = onepole_hp(rng.standard_normal(hat_len), 0.92) * env(hat_len, 0.0005, 18.0)
    place(boss, h * (0.32 if s16 % 2 == 1 else 0.18), s16 * (SPB // 2) // 2 * 2)

for bar in range(4):
    for beat in (1, 3):
        n = int(SR * 0.13)
        sn = onepole_lp(onepole_hp(rng.standard_normal(n), 0.7), 0.45) * env(n, 0.001, 8.0)
        place(boss, sn * 0.45, bar * BAR + beat * SPB)

ped = np.sin(2 * np.pi * 659.26 * np.arange(BLOOP) / SR)
ped *= (0.5 + 0.5 * np.sin(2 * np.pi * 5.5 * np.arange(BLOOP) / SR)) * 0.045
boss += ped

peak = np.max(np.abs(boss))
write('music_boss.wav', boss / peak * 0.88, fade_tail=False)

total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
print(f'\n{len(os.listdir(OUT))} arquivos, {total / 1024:.0f}KB total')
