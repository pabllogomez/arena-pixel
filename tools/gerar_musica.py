"""Gera as duas músicas do jogo (composições originais, sintetizadas por código).

Uso:  python3 tools/gerar_musica.py      (requer numpy e ffmpeg)

  menu.ogg    - calma e sombria: zumbido grave, acordes lentos, sininhos e batida de coração
  batalha.ogg - tensa: baixo pulsante, bateria 8-bit e melodia em ré menor harmônica
Os dois arquivos fazem loop sem emenda (cada um é o 2º ciclo de uma renderização dupla,
então os ecos do fim já aparecem no começo).
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

TAXA = 22050
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SAIDA = os.path.join(RAIZ, "assets", "musica")
os.makedirs(SAIDA, exist_ok=True)
rng = np.random.default_rng(13)


def nota(n):
    """Número MIDI -> frequência."""
    return 440.0 * 2 ** ((n - 69) / 12)


def env(dur, ataque=0.01, queda=None, sustain=1.0):
    n = int(dur * TAXA)
    e = np.ones(n) * sustain
    a = max(1, int(ataque * TAXA))
    e[:a] = np.linspace(0, 1, a)
    if queda:
        e = e * np.exp(-np.arange(n) / (queda * TAXA))
    r = max(1, int(0.03 * TAXA))
    e[-r:] *= np.linspace(1, 0, r)
    return e


def quadrada(f, dur, duty=0.5):
    t = np.arange(int(dur * TAXA)) / TAXA
    return np.where((t * f) % 1.0 < duty, 1.0, -1.0)


def triangulo(f, dur):
    t = np.arange(int(dur * TAXA)) / TAXA
    return 2 * np.abs(2 * ((t * f) % 1.0) - 1) - 1


def serra(f, dur):
    t = np.arange(int(dur * TAXA)) / TAXA
    return 2 * ((t * f) % 1.0) - 1


def seno(f, dur):
    t = np.arange(int(dur * TAXA)) / TAXA
    return np.sin(2 * np.pi * f * t)


def passa_baixa(x, corte):
    a = np.exp(-2 * np.pi * corte / TAXA)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def ruido(dur):
    return rng.uniform(-1, 1, int(dur * TAXA))


def mistura(pista, som, inicio, vol=1.0):
    i = int(inicio * TAXA)
    fim = min(len(pista), i + len(som))
    pista[i:fim] += som[: fim - i] * vol


def eco(x, atraso, ganho, vezes=4):
    y = x.copy()
    d = int(atraso * TAXA)
    for k in range(1, vezes + 1):
        y[d * k:] += x[: len(x) - d * k] * (ganho ** k)
    return y


def recortar_loop(pista, ini, dur):
    """Pega um ciclo e mistura o fim com o trecho anterior ao início, para o loop não estalar."""
    i0 = int(ini * TAXA)
    n = int(dur * TAXA)
    x = pista[i0: i0 + n].copy()
    m = int(0.03 * TAXA)
    rampa = np.linspace(0, 1, m)
    x[-m:] = x[-m:] * (1 - rampa) + pista[i0 - m: i0] * rampa
    return x


def salvar(nome, x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.85
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        caminho = tmp.name
    with wave.open(caminho, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TAXA)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    destino = os.path.join(SAIDA, nome + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", caminho, "-c:a", "libvorbis", "-q:a", "3", destino], check=True)
    os.remove(caminho)
    print(destino, "%.1f s" % (len(x) / TAXA), "%d KB" % (os.path.getsize(destino) // 1024))


# ------------------------------------------------------------------ Menu: calma e sombria
def musica_menu():
    bpm = 60
    batida = 60 / bpm
    # Acordes (MIDI): Ré m, Si bemol, Sol m, Lá  (4 batidas cada), 3 voltas
    acordes = [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]] * 3
    dur_ciclo = len(acordes) * 4 * batida
    total = dur_ciclo * 2
    pista = np.zeros(int(total * TAXA) + TAXA)
    # Zumbido grave contínuo (Ré), uma peça só para não "recomeçar" no loop
    drone = passa_baixa(serra(nota(38), total + 1) + 0.6 * serra(nota(38) * 1.005, total + 1), 220)
    mistura(pista, drone * 0.35, 0.0)
    for volta in range(2):
        base = volta * dur_ciclo
        for i, ac in enumerate(acordes):
            t0 = base + i * 4 * batida
            for n in ac:
                pad = passa_baixa(serra(nota(n), 4 * batida) + serra(nota(n) * 1.004, 4 * batida), 700)
                mistura(pista, pad * env(4 * batida, ataque=1.2) * 0.12, t0)
            # batida de coração (dois baques) no início de cada acorde
            for k, dt in enumerate((0.0, 0.28)):
                baque = seno(55 - k * 8, 0.25) * env(0.25, 0.005, queda=0.06)
                mistura(pista, baque * (0.5 - 0.15 * k), t0 + dt)
        # Sininhos (melodia esparsa em ré menor)
        melodia = [(0, 74), (3, 77), (5, 76), (8, 74), (11, 72), (12, 69), (16, 70), (19, 69),
                   (22, 67), (24, 69), (27, 72), (29, 74), (32, 77), (35, 76), (37, 73), (40, 74), (44, 69)]
        for b, n in melodia:
            sino = (seno(nota(n), 2.5) + 0.3 * seno(nota(n) * 2.01, 2.5) + 0.15 * seno(nota(n) * 3.0, 2.5))
            mistura(pista, sino * env(2.5, 0.002, queda=0.6) * 0.18, base + b * batida)
    pista = eco(pista, 0.45, 0.35)
    return recortar_loop(pista, dur_ciclo, dur_ciclo)


# ------------------------------------------------------------------ Batalha: tensa
def musica_batalha():
    bpm = 104
    batida = 60 / bpm
    colcheia = batida / 2
    # Progressão de 2 compassos por acorde: Ré m, Si bemol, Dó, Lá (dominante com Dó#)
    progressao = [38, 34, 36, 33] * 2  # notas graves (MIDI)
    compassos = len(progressao) * 2
    dur_ciclo = compassos * 4 * batida
    total = dur_ciclo * 2
    pista = np.zeros(int(total * TAXA) + TAXA)
    # padrão do baixo (em colcheias, intervalos sobre a fundamental)
    padrao_baixo = [0, 0, 12, 0, 7, 0, 12, 10]
    # melodia (batida, nota MIDI, duração em batidas) - ré menor harmônico
    melodia = [
        (0, 62, 1), (1, 65, 1), (2, 69, 1.5), (3.5, 68, 0.5), (4, 69, 2), (6, 65, 1), (7, 64, 1),
        (8, 62, 1), (9, 65, 1), (10, 70, 2), (12, 69, 1), (13, 67, 1), (14, 65, 2),
        (16, 64, 1), (17, 67, 1), (18, 72, 1.5), (19.5, 70, 0.5), (20, 69, 2), (22, 67, 2),
        (24, 69, 1), (25, 68, 1), (26, 69, 1), (27, 71, 1), (28, 73, 2), (30, 76, 2),
        (32, 74, 1.5), (33.5, 73, 0.5), (34, 74, 1), (35, 77, 1), (36, 76, 2), (38, 74, 2),
        (40, 70, 1), (41, 69, 1), (42, 67, 1), (43, 65, 1), (44, 64, 2), (46, 65, 2),
        (48, 67, 1), (49, 69, 1), (50, 70, 1), (51, 72, 1), (52, 73, 3), (55, 69, 1),
        (56, 74, 4), (60, 69, 4),
    ]
    for volta in range(2):
        base = volta * dur_ciclo
        for c in range(compassos):
            raiz = progressao[c // 2]
            for k in range(8):
                t = base + (c * 4) * batida + k * colcheia
                n = raiz + padrao_baixo[k]
                b = passa_baixa(quadrada(nota(n), colcheia * 0.9, 0.25), 900)
                mistura(pista, b * env(colcheia * 0.9, 0.003, queda=0.12) * 0.32, t)
                # chimbal em toda colcheia
                hat = np.diff(ruido(0.04), prepend=0) * env(0.04, 0.001, queda=0.01)
                mistura(pista, hat * (0.10 if k % 2 else 0.06), t)
            for bt in range(4):
                t = base + (c * 4 + bt) * batida
                if bt in (0, 2):  # bumbo
                    f = 60 * np.exp(-np.arange(int(0.18 * TAXA)) / (0.04 * TAXA)) + 40
                    fase = np.cumsum(f) / TAXA
                    bumbo = np.sin(2 * np.pi * fase) * env(0.18, 0.001, queda=0.07)
                    mistura(pista, bumbo * 0.7, t)
                else:  # caixa
                    caixa = passa_baixa(ruido(0.15), 3000) * env(0.15, 0.001, queda=0.05) + \
                        seno(180, 0.15) * env(0.15, 0.001, queda=0.03) * 0.5
                    mistura(pista, caixa * 0.35, t)
        for b, n, d in melodia:
            dur = d * batida
            lead = quadrada(nota(n), dur, 0.125) * 0.6 + triangulo(nota(n) * 1.003, dur) * 0.4
            # vibrato leve nas notas longas
            if d >= 2:
                t = np.arange(len(lead)) / TAXA
                lead = lead * (1.0 + 0.05 * np.sin(2 * np.pi * 5.5 * t))
            mistura(pista, lead * env(dur, 0.01, sustain=0.9) * 0.14, base + b * batida)
    pista = eco(pista, batida * 0.75, 0.25, 3)
    return recortar_loop(pista, dur_ciclo, dur_ciclo)


salvar("menu", musica_menu())
salvar("batalha", musica_batalha())
