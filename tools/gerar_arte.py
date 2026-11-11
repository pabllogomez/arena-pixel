"""Gera a arte provisória (pixel art) e os efeitos sonoros do jogo.

Uso:  python3 tools/gerar_arte.py
Requer: Pillow (pip install pillow)

Tudo aqui é provisório: substitua os PNG/WAV em assets/ pelos definitivos
mantendo o tamanho de quadro (16x16) e a ordem dos quadros:
  personagens: 0-1 parado | 2-5 correndo | 6 pulando | 7 caindo
  lacaio/gosma_N: 0-1 andando (N = faixa de nível do monstro)
"""
import math
import os
import random
import struct
import wave

from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPR = os.path.join(RAIZ, "assets", "sprites")
SFX = os.path.join(RAIZ, "assets", "sfx")
os.makedirs(SPR, exist_ok=True)
os.makedirs(SFX, exist_ok=True)

# Paleta de 16 cores (+ tons de pele/madeira)
P = {
    ".": None,
    "k": (26, 28, 44),     # contorno
    "p": (93, 39, 93),     # roxo
    "r": (177, 62, 83),    # vermelho
    "o": (239, 125, 87),   # laranja
    "y": (255, 205, 117),  # amarelo
    "l": (167, 240, 112),  # verde claro
    "g": (56, 183, 100),   # verde
    "t": (37, 113, 121),   # verde-azulado
    "n": (41, 54, 111),    # azul escuro
    "b": (59, 93, 201),    # azul
    "c": (65, 166, 246),   # azul claro
    "a": (115, 239, 247),  # ciano
    "w": (244, 244, 244),  # branco
    "s": (148, 176, 194),  # cinza claro
    "m": (86, 108, 134),   # cinza
    "d": (51, 60, 87),     # cinza escuro
    "e": (240, 190, 150),  # pele
    "h": (120, 72, 50),    # marrom
    "j": (160, 100, 64),   # marrom claro
}

# Cor de time: X = cor principal, Y = destaque
TIMES = {1: {"X": "b", "Y": "c"}, 2: {"X": "r", "Y": "o"}}


def grade(linhas, time=None):
    h, w = len(linhas), max(len(l) for l in linhas)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for y, linha in enumerate(linhas):
        for x, ch in enumerate(linha):
            if time and ch in TIMES[time]:
                ch = TIMES[time][ch]
            cor = P[ch]
            if cor:
                img.putpixel((x, y), cor + (255,))
    return img


def folha(quadros):
    w = sum(q.width for q in quadros)
    img = Image.new("RGBA", (w, quadros[0].height), (0, 0, 0, 0))
    x = 0
    for q in quadros:
        img.paste(q, (x, 0))
        x += q.width
    return img


def pernas(c):
    """Pernas genéricas; c = cor da calça."""
    return {
        "parado": [f"....k{c}k..k{c}k....", f"....k{c}k..k{c}k....", f"....k{c}k..k{c}k....", "...kkkk..kkkk..."],
        "passo1": [f"...k{c}k....k{c}k...", f"..k{c}k......k{c}k..", f".k{c}k.......kkk..", ".kkk............"],
        "passo2": [f".....k{c}kk{c}k.....", f".....k{c}kk{c}k.....", f".....k{c}kk{c}k.....", "....kkkkkkkk...."],
        "passo3": [f"..k{c}k.....k{c}k...", f"..k{c}k......k{c}k..", "..kkk.......k" + c + "k.", "............kkk."],
        "pulo":   [f"...k{c}k...k{c}k....", f"...k{c}kk..k{c}kk...", "....kkk...kkk...", "................"],
        "queda":  [f"..k{c}k......k{c}k..", f"..k{c}k......k{c}k..", "..kkk......kkk..", "................"],
    }


def manto():
    """Parte de baixo de túnica longa (mago/rei)."""
    return {
        "parado": ["...kXXXXXXXk....", "...kXXXXXXXk....", "..kXXXXXXXXXk...", "..kkkkkkkkkkk..."],
        "passo1": ["...kXXXXXXXk....", "..kXXXXXXXXXk...", ".kXXXXXXXXXXk...", ".kkk.kkkkkkkkk.."],
        "passo2": ["...kXXXXXXXk....", "...kXXXXXXXk....", "..kXXXXXXXXXk...", "..kkkkkkkkkkk..."],
        "passo3": ["...kXXXXXXXk....", "...kXXXXXXXXk...", "..kXXXXXXXXXXk..", "..kkkkkkkk.kkk.."],
        "pulo":   ["...kXXXXXXXk....", "..kXXXXXXXXXk...", "..kkkXXXXXkkk...", "....kkkkkkk....."],
        "queda":  ["..kXXXXXXXXXk...", ".kXXXXXXXXXXXk..", ".kkkkkkkkkkkkk..", "................"],
    }


CLASSES = {
    "arqueiro": {
        "corpo": [
            "................",
            "................",
            ".....kkkkkk.....",
            "....kggggggk.k..",
            "...kggggggggkjk.",
            "...kggeeeeeek.jk",
            "...kgeekeekek.jk",
            "...kgeeeeeek..jk",
            "....kXXXXXXk..jk",
            "...kXXXXXXXXkej.",
            "...keXXhhXXk.jk.",
            "....kXXXXXXk.k..",
        ],
        "pernas": pernas("h"),
    },
    "recruta": {
        "corpo": [
            "................",
            "................",
            ".....kkkkkk.....",
            "....khhhhhhk....",
            "...khhhhhhhhk...",
            "...kheeeeeek....",
            "...keekeekek..k.",
            "...keeeeeek..kjk",
            "....kXXXXXXk.kj.",
            "...kXXXXXXXXkej.",
            "...keXXhhXXk.j..",
            "....kXXXXXXk....",
        ],
        "pernas": pernas("h"),
    },
    "orc": {
        "corpo": [
            "................",
            "....kkkkkkk.....",
            "...kgggggggk....",
            "..kgggggggggk.k.",
            "..kggrggrgggkksk",
            "..kgggggggggkssk",
            "..kgwgggwggk.ksk",
            "...kgggggggk..jk",
            "..kXXXXXXXXXk.jk",
            ".kgXXXXXXXXXgkj.",
            ".kgkhhhhhhhkggk.",
            "..kXXXXXXXXk.k..",
        ],
        "pernas": pernas("h"),
    },
    "mago": {
        "corpo": [
            "......k.........",
            ".....kYk........",
            "....kXXXk.......",
            "...kXXXXXk...kak",
            "..kkkkkkkkkk.kak",
            "...kweeeeek...k.",
            "...kweekeek...j.",
            "...kwwwwwwk...j.",
            "....kwwwwk....j.",
            "...kXXwwXXk.kej.",
            "...kXXXXXXXkk.j.",
            "...kXXYYYXXk..j.",
        ],
        "pernas": manto(),
    },
    "rei": {
        "corpo": [
            "................",
            "....k.k.k.k.....",
            "....kykykyk.....",
            "....kyyryyk.....",
            "...kkkkkkkkk....",
            "..kXkeeeeeek....",
            "..kXkeekeekk.ky.",
            "..kXkwwwwwwk.kyk",
            "..kXXkwwwwk..kj.",
            ".kXXkyyyyyyk.kj.",
            ".kXXkyyYYyykekj.",
            ".kXXkyyyyyyk.kj.",
        ],
        "pernas": manto(),
    },
}


def personagem(dados, perna, respira=False):
    corpo = dados["corpo"][:]
    if respira:
        corpo = ["................"] + corpo[:-1]
    return corpo + dados["pernas"][perna]


for nome, dados in CLASSES.items():
    for time in (1, 2):
        quadros = [
            personagem(dados, "parado"), personagem(dados, "parado", True),
            personagem(dados, "passo1"), personagem(dados, "passo2"),
            personagem(dados, "passo3"), personagem(dados, "passo2"),
            personagem(dados, "pulo"), personagem(dados, "queda"),
        ]
        folha([grade(q, time) for q in quadros]).save(os.path.join(SPR, f"{nome}_{time}.png"))

# ---------------------------------------------------------------- Lacaio do Rei
LACAIO = [
    "................", "................", "................", "................",
    ".............k..", "......kkkk..ksk.", ".....kmmmmk..j..", ".....kmmmmmk.j..",
    ".....keekekkej..", ".....keeeek..j..", "....kXXXXXXk.j..", "....kXXXXXXkej..",
    "....kXYYYYXk.j..",
]
LACAIO_PERNAS = [
    ["....knnk.knk.j..", "....knnk.knk.j..", "....kkkk.kkk...."],
    ["...knk...knnk.j.", "..knk.....knk.j.", "..kkk.....kkk..."],
]
for time in (1, 2):
    folha([grade(LACAIO + p, time) for p in LACAIO_PERNAS]).save(os.path.join(SPR, f"lacaio_{time}.png"))

# ---------------------------------------------------------------- Monstro neutro (gosma)
GOSMA_A = [
    "................", "................", "................", "................",
    "................", "................", "......kkkk......", "....kkppppkk....",
    "...kpprppppppk..", "..kpprpppppppk..", "..kppwkppwkppk..", "..kppwkppwkppk..",
    ".kpppppppppppppk", ".kpppppppppppppk", ".knnnnnnnnnnnnnk", "..kkkkkkkkkkkkk.",
]
GOSMA_B = [
    "................", "................", "................", "................",
    "................", "................", "................", "................",
    ".....kkkkkk.....", "...kkpprpppkk...", ".kkpprppppppppk.", ".kppwkpppwkpppk.",
    "kpppwkpppwkppppk", "kppppppppppppppk", "knnnnnnnnnnnnnnk", ".kkkkkkkkkkkkkk.",
]
# Uma cor por faixa de nível: roxo -> verde -> laranja -> vermelho
for faixa, (corpo, brilho, sombra) in enumerate([("p", "r", "n"), ("g", "l", "t"), ("o", "y", "h"), ("r", "o", "p")], 1):
    troca = str.maketrans({"p": corpo, "r": brilho, "n": sombra})
    quadros = [[l.translate(troca) for l in q] for q in (GOSMA_A, GOSMA_B)]
    folha([grade(q) for q in quadros]).save(os.path.join(SPR, f"gosma_{faixa}.png"))

# ---------------------------------------------------------------- Projéteis e efeitos
grade([
    "kk.......",
    "wjjjjjjsk",
    "kk.......",
]).save(os.path.join(SPR, "flecha.png"))

folha([
    grade(["..kkkk..", ".kaaaak.", "kaawaaak", "kawwaaak", "kaaaaaak", "kaaaaaak", ".kaaaak.", "..kkkk.."]),
    grade(["..kkkk..", ".kccaak.", "kcaaaack", "kaawwaak", "kaawwaak", "kcaaaack", ".kaacck.", "..kkkk.."]),
]).save(os.path.join(SPR, "orbe.png"))

folha([
    grade(["................", "........ww......", "..........ww....", "...........ww...",
           "............w...", "............ww..", ".............w..", ".............w..",
           ".............w..", ".............w..", "............ww..", "............w...",
           "...........ww...", "..........ww....", "........ww......", "................"]),
    grade(["................", "................", "...........ss...", "............ss..",
           ".............s..", ".............ss.", "..............s.", "..............s.",
           "..............s.", "..............s.", ".............ss.", ".............s..",
           "............ss..", "...........ss...", "................", "................"]),
]).save(os.path.join(SPR, "corte.png"))

# Fumaça/brilho de surgimento (3 quadros 16x16)
def brilho(r):
    linhas = []
    for y in range(16):
        l = ""
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            l += "w" if abs(d - r) < 0.8 else ("s" if abs(d - r) < 1.6 else ".")
        linhas.append(l)
    return grade(linhas)


folha([brilho(2), brilho(4.5), brilho(7)]).save(os.path.join(SPR, "brilho.png"))

# ---------------------------------------------------------------- Tiles (atlas 3x1)
random.seed(7)


def tile_parede():
    linhas = [
        "kkkkkkkkkkkkkkkk", "kmmmmmmkmmmmmmmk", "kmddddmkmddddddk", "kmddddmkmddddddk",
        "kmddddmkmddddddk", "kdddddmkdddddddk", "kkkkkkkkkkkkkkkk", "kmmmkmmmmmmmkmmk",
        "kmddkmddddddkmdk", "kmddkmddddddkmdk", "kmddkmddddddkmdk", "kmddkmddddddkmdk",
        "kdddkdddddddkddk", "kkkkkkkkkkkkkkkk", "kmmmmmmmkmmmmmmm", "kddddddddddddddd",
    ]
    return grade(linhas)


def tile_plataforma():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for x in range(16):
        for y, c in enumerate("kyjjhk"):
            img.putpixel((x, y), P[c] + (255,))
    for x in (2, 13):
        for y in range(6, 9):
            img.putpixel((x, y), P["h"] + (255,))
    return img


def tile_chao():
    img = tile_parede()
    for x in range(16):
        img.putpixel((x, 0), P["k"] + (255,))
        img.putpixel((x, 1), P["s"] + (255,))
        img.putpixel((x, 2), P["m"] + (255,))
    return img


folha([tile_parede(), tile_plataforma(), tile_chao()]).save(os.path.join(SPR, "tiles.png"))

# ---------------------------------------------------------------- Fundo 384x216 (salão do castelo)
fundo = Image.new("RGBA", (384, 216), (30, 32, 52, 255))
for y in range(216):
    for x in range(384):
        lin = y // 8
        off = 8 if lin % 2 else 0
        borda = (y % 8 == 7) or ((x + off) % 16 == 15)
        if borda:
            fundo.putpixel((x, y), (24, 25, 41, 255))
        elif random.random() < 0.04:
            fundo.putpixel((x, y), (38, 41, 64, 255))
# janelas com luar
for jx in (64, 176, 288):
    for y in range(40, 104):
        for x in range(jx, jx + 32):
            dx = x - (jx + 16)
            topo = 40 + 16 - int(math.sqrt(max(0, 256 - dx * dx)))
            if y >= topo:
                cor = (41, 54, 111, 255) if (x + y) % 5 else (59, 93, 201, 255)
                if x in (jx, jx + 31) or y == 103 or y == topo:
                    cor = (20, 20, 34, 255)
                if x == jx + 16 or y == 72:
                    cor = (20, 20, 34, 255)
                fundo.putpixel((x, y), cor)
# estandartes
for bx, cor in ((24, P["b"]), (344, P["r"])):
    for y in range(24, 88):
        for x in range(bx, bx + 16):
            if y > 80 and abs(x - (bx + 8)) < (y - 80):
                continue
            fundo.putpixel((x, y), cor + (255,))
    for x in range(bx - 2, bx + 18):
        fundo.putpixel((x, 23), P["y"] + (255,))
fundo.save(os.path.join(SPR, "fundo.png"))

# ---------------------------------------------------------------- Ícone
icone = grade(personagem(CLASSES["rei"], "parado"), 1).resize((128, 128), Image.NEAREST)
icone.save(os.path.join(RAIZ, "icon.png"))


# ---------------------------------------------------------------- Efeitos sonoros (8-bit)
def som(nome, notas, volume=0.22, taxa=22050):
    """notas: lista de (freq_inicial, freq_final, duracao_s); freq 0 = ruído."""
    amostras = []
    for f0, f1, dur in notas:
        n = int(taxa * dur)
        fase = 0.0
        for i in range(n):
            t = i / n
            f = f0 + (f1 - f0) * t
            fase += f / taxa
            v = random.uniform(-1, 1) if f0 == 0 else (1.0 if (fase % 1.0) < 0.5 else -1.0)
            amostras.append(int(v * (1 - t) ** 1.5 * volume * 32767))
    with wave.open(os.path.join(SFX, nome), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(taxa)
        w.writeframes(b"".join(struct.pack("<h", a) for a in amostras))


som("pulo.wav", [(300, 600, 0.12)], 0.15)
som("flecha.wav", [(0, 0, 0.06), (900, 400, 0.06)], 0.12)
som("espada.wav", [(0, 0, 0.14)], 0.25)
som("magia.wav", [(200, 900, 0.25)], 0.15)
som("invocar.wav", [(300, 300, 0.08), (450, 450, 0.08), (600, 600, 0.15)], 0.15)
som("acerto.wav", [(220, 80, 0.08)], 0.2)
som("morte.wav", [(0, 0, 0.1), (300, 50, 0.3)])
som("nivel.wav", [(523, 523, 0.08), (784, 784, 0.08), (1047, 1047, 0.2)], 0.18)
som("pouso.wav", [(0, 0, 0.05), (120, 40, 0.18)], 0.3)
som("porta.wav", [(800, 200, 0.1), (200, 800, 0.1)], 0.12)
som("vitoria.wav", [(523, 523, 0.12), (659, 659, 0.12), (784, 784, 0.12), (1047, 1047, 0.45)])

print("Arte e sons gerados em", os.path.join(RAIZ, "assets"))
