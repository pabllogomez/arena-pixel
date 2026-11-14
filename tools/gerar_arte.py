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

# ---------------------------------------------------------------- Guarda real do Rei
# Elmo cinza, escudo grande na frente (lado direito; o jogo espelha) nas cores do time
GUARDA = [
    "................", "................", "....kkkkk.......", "...kmmssmk......",
    "...kmmmmmk.kkkk.", "...kmddddmkkXXXk", "...kkeeekkXYYXXk", "....keeekXYwYXXk",
    "...kXXXXXkXYYXXk", "..kXXYYYXkkXXXk.", "..kXXYYYXXk.kkk.", "...kXXXXXk......",
    "...kkkkkkk......",
]
GUARDA_PERNAS = [
    ["...kndnk.knk....", "...kndnk.knk....", "...kkkkk.kkk...."],
    ["..knk...knnk....", ".knk.....knk....", ".kkk.....kkk...."],
]
for time in (1, 2):
    folha([grade(GUARDA + p, time) for p in GUARDA_PERNAS]).save(os.path.join(SPR, f"guarda_{time}.png"))

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

# ---------------------------------------------------------------- Masmorra: cores extras
M = {
    "pedra": (46, 42, 50), "pedra_clara": (62, 57, 64), "pedra_escura": (31, 28, 35),
    "rejunte": (19, 17, 22), "musgo": (52, 70, 44), "musgo_claro": (74, 96, 58),
    "madeira": (78, 56, 40), "madeira_clara": (98, 72, 50), "madeira_escura": (48, 34, 26),
    "ferro": (70, 72, 80), "ferro_claro": (110, 112, 120),
    "osso": (196, 186, 160), "osso_sombra": (140, 130, 110),
    "fundo": (24, 22, 28), "fundo_claro": (32, 29, 36), "fundo_rejunte": (15, 14, 18),
}


def cor(nome, a=255):
    return M[nome] + (a,)


random.seed(7)


# ---------------------------------------------------------------- Tiles (atlas 3x1)
def tile_parede():
    img = Image.new("RGBA", (16, 16), cor("rejunte"))
    # dois blocos de pedra por fileira, fileiras desencontradas
    for linha, (y0, desloc) in enumerate([(0, 0), (8, 8)]):
        for bx in range(-8, 16, 16):
            x0 = bx + desloc
            for y in range(y0 + 1, y0 + 7):
                for x in range(max(0, x0 + 1), min(16, x0 + 15)):
                    c = "pedra"
                    if y == y0 + 1 or x == x0 + 1:
                        c = "pedra_clara"
                    elif y == y0 + 6 or x == x0 + 14:
                        c = "pedra_escura"
                    img.putpixel((x, y), cor(c))
    for _ in range(6):
        img.putpixel((random.randrange(16), random.randrange(16)), cor("pedra_escura"))
    return img


def tile_plataforma():
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for x in range(16):
        img.putpixel((x, 0), cor("rejunte"))
        img.putpixel((x, 1), cor("madeira_clara"))
        img.putpixel((x, 2), cor("madeira"))
        img.putpixel((x, 3), cor("madeira"))
        img.putpixel((x, 4), cor("madeira_escura"))
        img.putpixel((x, 5), cor("rejunte"))
    for x in (5, 11):  # junta entre tábuas
        for y in range(1, 5):
            img.putpixel((x, y), cor("madeira_escura"))
    for x in (2, 13):  # pregos de ferro e suportes
        img.putpixel((x, 2), cor("ferro_claro"))
        for y in range(6, 9):
            img.putpixel((x, y), cor("ferro"))
    return img


def tile_chao():
    img = tile_parede()
    for x in range(16):
        img.putpixel((x, 0), cor("rejunte"))
        img.putpixel((x, 1), cor("pedra_clara"))
        # musgo/limo escorrendo pelo topo
        if random.random() < 0.6:
            img.putpixel((x, 1), cor("musgo"))
            if random.random() < 0.5:
                img.putpixel((x, 2), cor("musgo"))
            if random.random() < 0.25:
                img.putpixel((x, 3), cor("musgo"))
        if random.random() < 0.2:
            img.putpixel((x, 1), cor("musgo_claro"))
    return img


folha([tile_parede(), tile_plataforma(), tile_chao()]).save(os.path.join(SPR, "tiles.png"))

# ---------------------------------------------------------------- Esqueleto acorrentado pelos braços (16x24)
ESQUELETO = [
    "mm............mm",
    "mmo..........omm",
    "..o..........o..",
    "...o........o...",
    "...o........o...",
    "....o.oooo.o....",
    "....o.kook.o....",
    "....o.oooo.o....",
    "....o.okko.o....",
    "....o..oo..o....",
    "....o..oo..o....",
    ".....oooooo.....",
    "......oOOo......",
    ".....oOooOo.....",
    "......oOOo......",
    ".....oOooOo.....",
    "......oOOo......",
    ".......oo.......",
    "......oooo......",
    ".....oo..oo.....",
    ".....o....o.....",
    ".....o....o.....",
    ".....o....o.....",
    "....oo....oo....",
]
CORES_ESQ = {"m": cor("ferro_claro"), "o": cor("osso"), "O": cor("osso_sombra"), "k": cor("rejunte")}


def esqueleto():
    img = Image.new("RGBA", (16, 24), (0, 0, 0, 0))
    for y, l in enumerate(ESQUELETO):
        for x, ch in enumerate(l):
            if ch in CORES_ESQ:
                img.putpixel((x, y), CORES_ESQ[ch])
    return img


# ---------------------------------------------------------------- Fundo 480x270 (masmorra)
LF, AF = 480, 270
fundo = Image.new("RGBA", (LF, AF), cor("fundo"))
for y in range(AF):
    for x in range(LF):
        lin = y // 10
        off = 10 if lin % 2 else 0
        if y % 10 == 9 or (x + off) % 20 == 19:
            fundo.putpixel((x, y), cor("fundo_rejunte"))
        elif random.random() < 0.05:
            fundo.putpixel((x, y), cor("fundo_claro"))
# manchas de umidade escorrendo
for _ in range(14):
    x0 = random.randrange(LF)
    y0 = random.randrange(0, AF // 2)
    for y in range(y0, min(AF, y0 + random.randint(20, 70))):
        for dx in range(random.randint(1, 3)):
            if 0 <= x0 + dx < LF and random.random() < 0.7:
                r, g, b, a = fundo.getpixel((x0 + dx, y))
                fundo.putpixel((x0 + dx, y), (max(r - 5, 0), min(g + 2, 255), max(b - 3, 0), a))
# celas com grades (nichos escuros)
for cx in (70, 240, 410):
    larg, alt, topo = 64, 70, 70
    for y in range(topo, topo + alt):
        for x in range(cx - larg // 2, cx + larg // 2):
            dx = x - cx
            arco = topo + 12 - int(math.sqrt(max(0, (larg // 2) ** 2 - dx * dx)) * 12 / (larg // 2))
            if y >= arco:
                fundo.putpixel((x, y), (12, 11, 15, 255))
    for x in range(cx - larg // 2 + 4, cx + larg // 2 - 2, 7):
        for y in range(topo + 6, topo + alt):
            fundo.putpixel((x, y), cor("ferro"))
            fundo.putpixel((x + 1, y), (40, 41, 47, 255))
    for x in range(cx - larg // 2, cx + larg // 2):
        for y in (topo + 24, topo + alt - 8):
            fundo.putpixel((x, y), cor("ferro"))
# esqueletos acorrentados pelos braços, com correntes até o alto
esq = esqueleto()
for ex, ey in ((150, 60), (325, 50), (44, 150), (436, 140), (240, 175)):
    fundo.paste(esq, (ex - 8, ey), esq)
    for lado in (0, 15):
        for y in range(max(0, ey - 34), ey):
            if (y // 2) % 2 == 0:
                fundo.putpixel((ex - 8 + lado, y), cor("ferro"))
            else:
                fundo.putpixel((ex - 8 + lado, y), (45, 46, 52, 255))
# correntes soltas penduradas
for _ in range(8):
    x = random.randrange(10, LF - 10)
    comp = random.randint(20, 60)
    for y in range(0, comp):
        fundo.putpixel((x, y), cor("ferro") if (y // 2) % 2 == 0 else (45, 46, 52, 255))
    fundo.putpixel((x - 1, comp), cor("ferro"))
    fundo.putpixel((x + 1, comp), cor("ferro"))
    fundo.putpixel((x - 1, comp - 1), cor("ferro"))
    fundo.putpixel((x + 1, comp - 1), cor("ferro"))
# escurece em direção ao chão
for y in range(AF):
    f = 1.0 - 0.35 * (y / AF)
    for x in range(LF):
        r, g, b, a = fundo.getpixel((x, y))
        fundo.putpixel((x, y), (int(r * f), int(g * f), int(b * f), a))
fundo.save(os.path.join(SPR, "fundo.png"))

# ---------------------------------------------------------------- Tocha (4 quadros 8x16: chama animada + suporte)
def tocha(q):
    img = Image.new("RGBA", (8, 16), (0, 0, 0, 0))
    formas = [
        ["...y....", "..yoy...", "..yoy...", ".yoroy..", ".yorry..", "..yrry..", "...rr..."],
        ["....y...", "...yoy..", "..yoy...", ".yorry..", ".yorroy.", "..yrry..", "...rr..."],
        ["...y....", "...yo...", "..yooy..", "..yorry.", ".yorroy.", "..yrry..", "...rr..."],
        ["..y.....", "..yoy...", "..yooy..", ".yorry..", ".yorry..", "..yrr...", "...rr..."],
    ]
    cores = {"y": (255, 205, 117, 255), "o": (239, 125, 87, 255), "r": (177, 62, 83, 255)}
    for y, l in enumerate(formas[q]):
        for x, ch in enumerate(l):
            if ch in cores:
                img.putpixel((x, y + 1), cores[ch])
    for y in range(8, 11):  # cesto
        for x in range(2, 6):
            img.putpixel((x, y), cor("madeira_escura") if y > 8 else cor("ferro"))
    for y in range(11, 15):  # cabo
        img.putpixel((3, y), cor("madeira"))
        img.putpixel((4, y), cor("madeira_escura"))
    for x in range(2, 7):  # suporte na parede
        img.putpixel((x, 13), cor("ferro"))
    return img


folha([tocha(q) for q in range(4)]).save(os.path.join(SPR, "tocha.png"))

# ---------------------------------------------------------------- Pingo (quadro 0) + respingo (quadros 1-3), 8x8
def pingo(q):
    img = Image.new("RGBA", (8, 8), (0, 0, 0, 0))
    agua, brilho = (110, 150, 170, 220), (190, 220, 235, 255)
    if q == 0:
        img.putpixel((3, 3), brilho)
        img.putpixel((3, 4), agua)
        img.putpixel((3, 5), agua)
    elif q == 1:
        for x, y in ((2, 6), (4, 6), (1, 5), (5, 5), (3, 7)):
            img.putpixel((x, y), agua)
    elif q == 2:
        for x, y in ((1, 6), (5, 6), (0, 5), (6, 5)):
            img.putpixel((x, y), agua)
    else:
        for x, y in ((0, 7), (6, 7)):
            img.putpixel((x, y), (110, 150, 170, 120))
    return img


folha([pingo(q) for q in range(4)]).save(os.path.join(SPR, "pingo.png"))

# ---------------------------------------------------------------- Itens
# Orbe de item (todos iguais; o efeito só é revelado ao pegar): 2 quadros 12x12
ITEM = [
    "....kkkk....",
    "..kkppppkk..",
    ".kppwwwwppk.",
    ".kpwkkkwppk.",
    "kppkppkkwppk",
    "kpppppkkpppk",
    "kppppkkppppk",
    "kppppkkppppk",
    ".kpppppppppk",
    ".kppppkkppk.",
    "..kkppppkk..",
    "....kkkk....",
]
CORES_ITEM_A = {"k": (26, 28, 44, 255), "p": (93, 39, 93, 255), "w": (244, 244, 244, 255)}
CORES_ITEM_B = {"k": (26, 28, 44, 255), "p": (177, 62, 83, 255), "w": (255, 205, 117, 255)}


def item(cores):
    img = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    for y, l in enumerate(ITEM):
        for x, ch in enumerate(l):
            if ch in cores:
                img.putpixel((x, y), cores[ch])
    # o "?" é desenhado com 'k' dentro do orbe: troca por branco para destacar
    for y, l in enumerate(ITEM):
        for x, ch in enumerate(l):
            if ch == "k" and 2 <= x <= 9 and 3 <= y <= 9:
                img.putpixel((x, y), cores["w"])
    return img


folha([item(CORES_ITEM_A), item(CORES_ITEM_B)]).save(os.path.join(SPR, "item.png"))


# Bola de troca de classe: esfera com seta circular (↻), 2 quadros 16x16
def bola(q):
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y in range(16):
        for x in range(16):
            d = math.hypot(x - 7.5, y - 7.5)
            if d < 7.5:
                luz = 1.0 - 0.5 * (math.hypot(x - 5, y - 5) / 11)
                base = (65, 166, 246) if q == 0 else (115, 239, 247)
                img.putpixel((x, y), tuple(int(c * luz) for c in base) + (255,))
            if 6.6 <= d < 7.5:
                img.putpixel((x, y), (26, 28, 44, 255))
    # seta circular branca
    for a in range(40, 330, 8):
        r = math.radians(a + (0 if q == 0 else 45))
        x, y = 7.5 + 4 * math.cos(r), 7.5 + 4 * math.sin(r)
        img.putpixel((int(round(x)), int(round(y))), (244, 244, 244, 255))
    ponta = math.radians(330 + (0 if q == 0 else 45))
    px, py = 7.5 + 4 * math.cos(ponta), 7.5 + 4 * math.sin(ponta)
    for dx, dy in ((0, 0), (-1, 0), (0, -1), (1, 1), (-1, -1)):
        xx, yy = int(round(px)) + dx, int(round(py)) + dy
        if 0 <= xx < 16 and 0 <= yy < 16:
            img.putpixel((xx, yy), (244, 244, 244, 255))
    return img


folha([bola(0), bola(1)]).save(os.path.join(SPR, "bola.png"))

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


def whoosh(nome, dur=0.16, volume=0.2, taxa=22050):
    """Ruído passado por um filtro que vai abrindo (som de arrancada)."""
    n = int(taxa * dur)
    y = 0.0
    amostras = []
    for i in range(n):
        t = i / n
        y += (0.15 + 0.6 * t) * (random.uniform(-1, 1) - y)
        env = min(1.0, t / 0.15) * (1 - t) ** 1.5
        amostras.append(int(max(-1.0, min(1.0, y * 2.0)) * env * volume * 32767))
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
som("bloqueio.wav", [(0, 0, 0.03), (1500, 900, 0.05), (700, 500, 0.08)], 0.2)
som("acerto.wav", [(220, 80, 0.08)], 0.2)
som("morte.wav", [(0, 0, 0.1), (300, 50, 0.3)])
som("nivel.wav", [(523, 523, 0.08), (784, 784, 0.08), (1047, 1047, 0.2)], 0.18)
som("item.wav", [(700, 1400, 0.08), (1400, 2100, 0.12)], 0.14)
som("bola.wav", [(300, 900, 0.15), (900, 300, 0.15), (300, 1200, 0.25)], 0.16)
som("pingo.wav", [(1800, 1400, 0.05), (1400, 1100, 0.08)], 0.05)
whoosh("dash.wav")
som("pouso.wav", [(0, 0, 0.05), (120, 40, 0.18)], 0.3)
som("porta.wav", [(800, 200, 0.1), (200, 800, 0.1)], 0.12)
som("vitoria.wav", [(523, 523, 0.12), (659, 659, 0.12), (784, 784, 0.12), (1047, 1047, 0.45)])

print("Arte e sons gerados em", os.path.join(RAIZ, "assets"))
