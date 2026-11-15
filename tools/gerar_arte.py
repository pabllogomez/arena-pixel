"""Gera a arte provisória (pixel art) e os efeitos sonoros do jogo.

Uso:  python3 tools/gerar_arte.py
Requer: Pillow (pip install pillow)

Tudo aqui é provisório: substitua os PNG/WAV em assets/ pelos definitivos
mantendo o tamanho de quadro e a ordem dos quadros:
  lutadores (<classe>_1.png / _2.png = time 1 / 2): quadros de 20x20 numa linha única
    (19 quadros = 380x20; o mesmo mapa está em Lutador.QUADROS, em scripts/lutador.gd):
      0-3 parado (respiração) | 4-9 correr | 10-11 pulo | 12-13 queda
      14-17 ataque (próprio de cada classe) | 18 dano (impacto)
    O personagem olha para a direita (o jogo espelha); os pés ficam na linha 19.
    Para trocar por arte à mão: mantenha 20x20 por quadro e esta ordem.
  lacaio/gosma_N: 0-1 andando, 16x16 (N = faixa de nível do monstro)
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


# ---------------------------------------------------------------- Lutadores (20x20)
TAM = 20  # lado do quadro dos lutadores (Lutador.TAM_QUADRO)
CORTE = 8  # linhas 0-7 do corpo = cabeça; 8-13 = tronco; pernas ocupam 14-19

# Ordem dos quadros na folha (uma linha única). Mesmo mapa de Lutador.QUADROS.
ANIMACOES = [("parado", 4), ("correr", 6), ("pulo", 2), ("queda", 2), ("ataque", 4), ("dano", 1)]


def ponto_linha(x0, y0, x1, y1):
    """Pixels de uma linha (Bresenham)."""
    x0, y0, x1, y1 = round(x0), round(y0), round(x1), round(y1)
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        pts.append((x0, y0))
        if x0 == x1 and y0 == y1:
            return pts
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def vetor(ang, t):
    r = math.radians(ang)
    return math.cos(r) * t, math.sin(r) * t


class Peca:
    """Conjunto de pixels {(x, y): letra} desenhado por cima do corpo (braço e arma)."""

    def __init__(self):
        self.px = {}

    def p(self, x, y, ch):
        self.px[(round(x), round(y))] = ch

    def linha(self, a, b, ch):
        for x, y in ponto_linha(a[0], a[1], b[0], b[1]):
            self.p(x, y, ch)

    def ao_longo(self, h, ang, t0, t1, ch):
        a = (h[0] + vetor(ang, t0)[0], h[1] + vetor(ang, t0)[1])
        b = (h[0] + vetor(ang, t1)[0], h[1] + vetor(ang, t1)[1])
        self.linha(a, b, ch)

    def ponta(self, h, ang, t):
        return h[0] + vetor(ang, t)[0], h[1] + vetor(ang, t)[1]

    def braco(self, ombro, mao, manga="X"):
        self.linha(ombro, mao, manga)
        self.linha((ombro[0], ombro[1] + 1), (mao[0], mao[1] + 1), manga)
        self.p(mao[0], mao[1], "e")
        self.p(mao[0] + 1, mao[1], "e")

    def deslocada(self, dx, dy):
        n = Peca()
        n.px = {(x + dx, y + dy): c for (x, y), c in self.px.items()}
        return n


def espada(h, ang, comp=7):
    a = Peca()
    a.ao_longo(h, ang, 1, 3, "j")           # punho
    a.ao_longo(h, ang, 3, 3 + comp, "s")    # lâmina
    a.ao_longo(h, ang, 4, 2 + comp, "w")    # brilho
    nx, ny = -math.sin(math.radians(ang)), math.cos(math.radians(ang))
    gx, gy = a.ponta(h, ang, 3)
    a.linha((gx - nx * 2, gy - ny * 2), (gx + nx * 2, gy + ny * 2), "y")  # guarda
    return a


def machado(h, ang, L=6):
    a = Peca()
    a.ao_longo(h, ang, -2, L, "j")
    nx, ny = -math.sin(math.radians(ang)), math.cos(math.radians(ang))
    for t, larg in ((L - 2, 2), (L - 1, 4), (L, 4), (L + 1, 3), (L + 2, 1)):
        bx, by = a.ponta(h, ang, t)
        for k in range(1, larg + 1):
            a.p(bx + nx * k, by + ny * k, "w" if k == larg else "s")
        a.p(bx, by, "m")
    return a


def cajado(h, ang, brilho=0, t1=9):
    a = Peca()
    a.ao_longo(h, ang, -4, t1, "j")
    ox, oy = a.ponta(h, ang, t1 + 1)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            a.p(ox + dx, oy + dy, "a")
    a.p(ox, oy, "w")
    if brilho >= 1:
        for dx, dy in ((-2, 0), (2, 0), (0, -2), (0, 2)):
            a.p(ox + dx, oy + dy, "w")
    if brilho >= 2:
        for dx, dy in ((-2, -2), (2, -2), (-2, 2), (2, 2), (3, 0), (-3, 0), (0, 3), (0, -3)):
            a.p(ox + dx, oy + dy, "a")
    return a


def cetro(h, ang, brilho=0):
    a = Peca()
    a.ao_longo(h, ang, -3, 7, "y")
    ox, oy = a.ponta(h, ang, 8)
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        a.p(ox + dx, oy + dy, "r")
    a.p(ox, oy, "w")
    a.p(ox, oy - 1, "y")
    a.p(ox - 1, oy, "y")
    if brilho >= 1:
        for dx, dy in ((-2, -2), (3, -2), (-2, 3), (3, 3)):
            a.p(ox + dx, oy + dy, "y")
    if brilho >= 2:
        for dx, dy in ((0, -3), (1, 4), (-3, 0), (4, 1)):
            a.p(ox + dx, oy + dy, "w")
    return a


def arco(bx, by, puxa=0, flecha=False, ang_dy=0):
    """Arco vertical com a barriga para a direita; a corda recua `puxa` pixels."""
    a = Peca()
    for d in range(-6, 7):
        a.p(bx + round(2.4 * (1 - (d / 6.5) ** 2)), by + d, "j")
    a.p(bx + 1, by - 5, "j")
    a.p(bx + 1, by + 5, "j")
    ponta_c = (bx, by - 6)
    ponta_b = (bx, by + 6)
    meio = (bx - puxa, by)
    a.linha(ponta_c, meio, "w")
    a.linha(meio, ponta_b, "w")
    if flecha:
        a.linha((meio[0], meio[1]), (bx + 4, by), "s")
        a.p(bx + 4, by, "w")
        a.p(meio[0], meio[1] - 1, "y")
        a.p(meio[0], meio[1] + 1, "y")
    return a


def estrela(cx, cy, ch="w"):
    p = Peca()
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        p.p(cx + dx, cy + dy, ch)
    return p


def _mescla(*pecas):
    n = Peca()
    for p in pecas:
        n.px.update(p.px)
    return n



def contorno(grade_, peca, sobre=(".",)):
    """Contorno 'k' ao redor dos pixels de `peca`, só onde a grade está livre (ou em `sobre`)."""
    for (x, y) in list(peca.px):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < TAM and 0 <= ny < TAM and (nx, ny) not in peca.px and grade_[ny][nx] in sobre:
                grade_[ny][nx] = "k"


def pe(p, hip, foot, c, dobra=0):
    """Perna de calça: do quadril até o pé (+ a ponta do pé para a frente)."""
    meio = ((hip[0] + foot[0]) / 2.0 + dobra, (hip[1] + foot[1]) / 2.0)
    p.linha(hip, meio, c)
    p.linha(meio, foot, c)
    p.p(foot[0] + 1, foot[1], c)


def pernas_peca(c, pose):
    """Pernas (linhas 14-19). pose: parado | corre0..5 | pulo0..1 | queda0..1 | dano."""
    p = Peca()
    if pose == "parado":
        pe(p, (6, 0), (6, 4), c)
        pe(p, (11, 0), (11, 4), c)
    elif pose.startswith("corre"):
        k = int(pose[5:])
        for hx, fase in ((6, 0.0), (11, math.pi)):
            f = 2 * math.pi * k / 6 + fase
            f %= 2 * math.pi
            x = -3.0 * math.cos(f)
            lev = 3.0 * math.sin(f) if f < math.pi else 0.0
            pe(p, (hx, 0), (hx + round(x), 4 - round(lev * 0.9)), c, 1 if lev > 0.5 else 0)
    elif pose == "pulo0":
        pe(p, (6, 0), (5, 3), c, -1)
        pe(p, (11, 0), (13, 3), c, 1)
    elif pose == "pulo1":
        pe(p, (6, 0), (5, 2), c, -2)
        pe(p, (11, 0), (12, 2), c, 1)
    elif pose == "queda0":
        pe(p, (6, 0), (4, 4), c)
        pe(p, (11, 0), (13, 4), c)
    elif pose == "queda1":
        pe(p, (6, 0), (3, 4), c)
        pe(p, (11, 0), (14, 3), c)
    elif pose == "dano":
        pe(p, (6, 0), (4, 4), c)
        pe(p, (11, 0), (10, 4), c)
    return p


def manto_peca(pose):
    """Parte de baixo da túnica longa (mago/rei); mexe com a corrida e o pulo."""
    p = Peca()
    esq, dir_, ped = 0, 0, []
    if pose.startswith("corre"):
        k = int(pose[5:])
        esq = (-1, 0, 1, 1, 0, -1)[k]
        dir_ = (1, 0, -1, 1, 0, -1)[k]
        ped = [(14, 4)] if k in (0, 1) else ([(5, 4)] if k in (3, 4) else [])
    elif pose.startswith("pulo"):
        esq, dir_ = (0, 0) if pose == "pulo0" else (1, 1)
    elif pose.startswith("queda"):
        esq, dir_ = (-1, 1) if pose == "queda0" else (-2, 2)
    elif pose == "dano":
        esq, dir_ = -2, 0
    altura = 5 if pose.startswith("pulo") and pose == "pulo1" else (4 if pose.startswith("pulo") else 5)
    if pose.startswith("queda"):
        altura = 4
    for i in range(altura):
        e = 5 - (i + 1) // 2 + (esq if i >= 2 else 0)
        d = 12 + (i + 1) // 2 + (dir_ if i >= 2 else 0)
        for x in range(e, d + 1):
            p.p(x, i, "X")
    for x, y in ped:
        p.p(x, y + 1, "k")
        p.p(x + 1, y + 1, "k")
    return p


# ---- Corpos (14 linhas x 20 colunas, virados para a direita; sem o braço da frente nem a arma).
# Letras: as da paleta P; X/Y = cor do time; E = olho (cor muda no quadro de dano).
CLASSES = {
    "recruta": {
        "corpo": [
            "....................",
            "......kkkkkkk.......",
            ".....khhhhhhhk......",
            "....khhhjhhhhhk.....",
            "....khhhhhhhhhk.....",
            "....kheeeeeeehk.....",
            "....kheeeEeEehk.....",
            ".....keeeeeeek......",
            "......kXXXXXXk......",
            ".....kXXXYXXXXk.....",
            "....kXXXXXXXXXXk....",
            "....kXXXXXXXXXXk....",
            "....khhhhhhhhhhk....",
            ".....kXXXXXXXXk.....",
        ],
        "calca": "h", "olho": "k", "ombro": (12, 10), "manga": "X", "perna": "pernas",
    },
    "arqueiro": {
        "corpo": [
            "....................",
            ".....kkkkkkkk.......",
            "....kggggggggk......",
            "...kgggggggggkk.....",
            "...kggeeeeeeegk.....",
            "...kgeeeEeEeegk.....",
            "...kgeeeeeeeegk.....",
            "....kgeeeeeegk......",
            "......kXXXXXXk......",
            ".....kXXXYXXXXk.....",
            "....kXXXXXXXXXXk....",
            "....kXXXXXXXXXXk....",
            "....khhhhhhhhhhk....",
            ".....kXXXXXXXXk.....",
        ],
        "calca": "h", "olho": "k", "ombro": (12, 10), "manga": "X", "perna": "pernas",
    },
    "orc": {
        "corpo": [
            "....................",
            ".....kkkkkkkkk......",
            "....kgggggggggk.....",
            "...kgggggggggggk....",
            "...kgggggggggggk....",
            "...kgggggEgggEgk....",
            "...kgggggggggggk....",
            "....kggggwggwggk....",
            ".....kkXXXXXXkk.....",
            "...kkgXXXXXXXXgk....",
            "..kgkgXXXXXXXXXXk...",
            "..kggkXXXXXXXXXXk...",
            "...kkkhhhhhhhhhhk...",
            ".....kXXXXXXXXXk....",
        ],
        "calca": "h", "olho": "r", "ombro": (13, 10), "manga": "g", "perna": "pernas",
    },
    "mago": {
        "corpo": [
            ".......kk...........",
            "......kXXk..........",
            ".....kXXXXk.........",
            "....kXXYXXXk........",
            "..kkkkkkkkkkkkk.....",
            ".....kweeeeek.......",
            ".....kweEeEek.......",
            ".....kwwwwwwk.......",
            "......kwwwwk........",
            ".....kXXwwXXk.......",
            "....kXXXXXXXXk......",
            "....kXXXXXXXXXk.....",
            "....kXXYYYYXXXk.....",
            "....kXXXXXXXXXk.....",
        ],
        "calca": "X", "olho": "k", "ombro": (11, 10), "manga": "X", "perna": "manto",
    },
    "rei": {
        "corpo": [
            "....................",
            "......k.k.k.k.......",
            "......kykykyk.......",
            ".....kyyyryyyk......",
            ".....kkkkkkkkk......",
            "...kXkeeeeeeek......",
            "...kXkeeeEeEek......",
            "...kXkwwwwwwwk......",
            "...kXXkwwwwwk.......",
            "..kXXkyyyyyyyk......",
            "..kXXkyyyYyyyyk.....",
            "..kXXkyyyyyyyyk.....",
            "..kXXkoooooooyk.....",
            "..kXXkyyyyyyyyk.....",
        ],
        "calca": "X", "olho": "k", "ombro": (11, 10), "manga": "o", "perna": "manto",
    },
}
for _d in CLASSES.values():
    assert len(_d["corpo"]) == 14 and all(len(l) == TAM for l in _d["corpo"]), _d


def arma(nome, pose):
    """Braço da frente + arma de cada classe em cada pose ("guarda" ou "ataque0..3").
    Devolve (Peca, deslocamento da cabeça (dx, dy), deslocamento do tronco (dx, dy))."""
    d = CLASSES[nome]
    om, manga = d["ombro"], d["manga"]
    a = Peca()
    cab, tro = (0, 0), (0, 0)
    n = int(pose[6:]) if pose.startswith("ataque") else -1
    if nome == "recruta":
        mao, ang, comp = {-1: ((15, 10), -72, 7), 0: ((12, 8), -118, 6), 1: ((13, 8), -58, 6),
                          2: ((14, 10), 0, 3), 3: ((14, 11), 40, 4)}[n]
        a.braco(om, mao, manga)
        a = _mescla(espada(mao, ang, comp), a)
        cab, tro = {-1: ((0, 0), (0, 0)), 0: ((-1, 0), (0, 0)), 1: ((0, 0), (0, 0)), 2: ((1, 0), (1, 0)), 3: ((1, 0), (0, 0))}[n]
    elif nome == "orc":
        mao, ang, esc = {-1: ((15, 11), -80, 6), 0: ((13, 7), -105, 5), 1: ((14, 5), -55, 5),
                         2: ((15, 9), 25, 3), 3: ((15, 11), 50, 3)}[n]
        a.braco(om, mao, manga)
        a = _mescla(machado(mao, ang, esc), a)
        cab, tro = {-1: ((0, 0), (0, 0)), 0: ((-1, 0), (-1, 0)), 1: ((0, 0), (0, 0)), 2: ((1, 1), (1, 0)), 3: ((1, 1), (1, 0))}[n]
    elif nome == "arqueiro":
        om2 = (11, 10)
        if n == -1:
            a.braco(om, (15, 10), manga)
            a = _mescla(arco(16, 10), a)
        else:
            by, puxa, flecha, mao2 = {0: (9, 5, True, (11, 9)), 1: (9, 1, False, (10, 9)),
                                      2: (9, 0, False, (11, 10)), 3: (10, 0, False, (12, 10))}[n]
            a.braco(om, (16, by), manga)
            b2 = Peca()
            b2.braco(om2, mao2, manga)
            a = _mescla(arco(17, by, puxa, flecha), a, b2) if n != 3 else _mescla(arco(16, by), a)
        cab, tro = {-1: ((0, 0), (0, 0)), 0: ((0, 0), (-1, 0)), 1: ((0, 0), (0, 0)), 2: ((0, 0), (0, 0)), 3: ((0, 0), (0, 0))}[n]
    elif nome == "mago":
        if n == -1:
            mao, ang, br = (15, 10), -85, 0
        else:
            mao, ang, br = {0: ((13, 9), -120, 0), 1: ((15, 9), -15, 1), 2: ((15, 9), -8, 2), 3: ((14, 9), -45, 1)}[n]
        a.braco(om, mao, manga)
        t1 = 9 if n in (-1, 0, 3) else 3
        a = _mescla(cajado(mao, ang, br, t1), a)
        cab, tro = {-1: ((0, 0), (0, 0)), 0: ((-1, 0), (0, 0)), 1: ((1, 0), (1, 0)), 2: ((1, 0), (1, 0)), 3: ((0, 0), (0, 0))}[n]
    elif nome == "rei":
        mao, ang, br = {-1: ((15, 10), -85, 0), 0: ((15, 11), -70, 0), 1: ((15, 7), -80, 1), 2: ((15, 5), -88, 2), 3: ((15, 9), -75, 1)}[n]
        a.braco(om, mao, manga)
        a = _mescla(cetro(mao, ang, br), a)
        cab, tro = {-1: ((0, 0), (0, 0)), 0: ((0, 1), (0, 0)), 1: ((0, 0), (0, 0)), 2: ((0, -1), (0, 0)), 3: ((0, 0), (0, 0))}[n]
    return a, cab, tro


def impacto_dano(nome):
    """Estrelinha de impacto na frente do rosto no quadro de dano."""
    p = Peca()
    for dx, dy, ch in ((0, 0, "w"), (1, 0, "w"), (-1, 0, "w"), (0, 1, "w"), (0, -1, "w"),
                       (2, 2, "y"), (-2, -2, "y"), (2, -2, "y"), (-2, 2, "y")):
        p.p(16 + dx, 5 + dy, ch)
    return p


def compor(nome, pose_perna, arma_pose="guarda", dy_cab=0, dy_tro=0, dano=False):
    d = CLASSES[nome]
    g = [["."] * TAM for _ in range(TAM)]

    def colocar(peca, dx=0, dy=0, texto=None):
        for (x, y), ch in peca.px.items():
            x, y = x + dx, y + dy
            if 0 <= x < TAM and 0 <= y < TAM:
                g[y][x] = ch

    # pernas (calça ou túnica) com contorno automático
    if d["perna"] == "pernas":
        pp = pernas_peca(d["calca"], pose_perna)
    else:
        pp = manto_peca(pose_perna)
    pp = pp.deslocada(0, 14)
    colocar(pp)
    contorno(g, pp)
    arm, (cdx, cdy), (tdx, tdy) = arma(nome, arma_pose)
    if dano:
        cdx, cdy, tdx, tdy = -2, 1, -1, 0
    # tronco e cabeça (desenhados à mão)
    olho = "w" if dano else d["olho"]
    for faixa, dx, dy in ((range(CORTE, 14), tdx, dy_tro + tdy), (range(0, CORTE), cdx, dy_cab + tdy + cdy)):
        for r in faixa:
            for c, ch in enumerate(d["corpo"][r]):
                if ch == ".":
                    continue
                x, y = c + dx, r + dy
                if 0 <= x < TAM and 0 <= y < TAM:
                    g[y][x] = olho if ch == "E" else ch
    # braço da frente e arma
    colocar(arm, tdx, dy_tro + tdy)
    ar2 = arm.deslocada(tdx, dy_tro + tdy)
    contorno(g, ar2)
    if dano:
        colocar(impacto_dano(nome))
    return ["".join(l) for l in g]


def quadros_lutador(nome):
    """Lista de 19 quadros (ver ANIMACOES): parado 0-3 | correr 4-9 | pulo 10-11 | queda 12-13 | ataque 14-17 | dano 18."""
    q = []
    # parado: respiração sutil (cabeça e tronco descem em momentos diferentes)
    for dc, dt in ((0, 0), (1, 0), (1, 1), (0, 1)):
        q.append(compor(nome, "parado", "guarda", dc, dt))
    for k in range(6):
        q.append(compor(nome, f"corre{k}", "guarda", 0, 1 if k in (0, 3) else 0))
    q.append(compor(nome, "pulo0", "guarda", 0, 0))
    q.append(compor(nome, "pulo1", "guarda", 0, -1))
    q.append(compor(nome, "queda0", "guarda", 0, 0))
    q.append(compor(nome, "queda1", "guarda", -1, 0))
    for k in range(4):
        q.append(compor(nome, "parado", f"ataque{k}", 0, 0))
    q.append(compor(nome, "dano", "guarda", 0, 0, True))
    assert len(q) == sum(n for _, n in ANIMACOES)
    return q


def gerar_lutadores():
    for nome in CLASSES:
        for time in (1, 2):
            folha([grade(q, time) for q in quadros_lutador(nome)]).save(os.path.join(SPR, f"{nome}_{time}.png"))


gerar_lutadores()

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


# Coração de cura (item raro): 2 quadros 16x16 (o segundo brilha mais)
CORACAO = [
    "................",
    "...kkkk..kkkk...",
    "..kRRRRkkRRRRk..",
    ".kRWWRRRRRRRRRk.",
    ".kRWRRRRRRRRRRk.",
    ".kRRRRRRRRRRRRk.",
    ".kRRRRRRRRRRRDk.",
    "..kRRRRRRRRRDk..",
    "...kRRRRRRRDk...",
    "....kRRRRRDk....",
    ".....kRRRDk.....",
    "......kRDk......",
    ".......kk.......",
    "................",
    "................",
    "................",
]


def coracao(q):
    cores = {"k": (26, 28, 44, 255), "R": (230, 60, 80, 255) if q == 0 else (255, 100, 110, 255),
             "D": (150, 30, 60, 255), "W": (244, 244, 244, 255)}
    img = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    for y, l in enumerate(CORACAO):
        for x, ch in enumerate(l):
            if ch in cores:
                img.putpixel((x, y), cores[ch])
    return img


folha([coracao(0), coracao(1)]).save(os.path.join(SPR, "coracao.png"))

# ---------------------------------------------------------------- Ícone
icone = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
icone.alpha_composite(grade(quadros_lutador("rei")[0], 1).resize((120, 120), Image.NEAREST), (4, 4))
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
