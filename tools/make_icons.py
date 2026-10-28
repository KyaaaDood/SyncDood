"""Genera los íconos de SyncDood (ok / syncing / error / conflict) en icons/*.ico.
Uso:  python tools/make_icons.py     (requiere Pillow)
Estilo: cuadro oscuro redondeado + letra "S" con degradado vertical (blanco -> color del estado)."""
import os
from PIL import Image, ImageDraw, ImageFont, ImageChops

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "icons")
S = 1024                      # lienzo de trabajo (se reduce con LANCZOS)
BG = (28, 28, 33, 255)        # #1C1C21
STATES = {                    # color final del degradado (abajo de la letra)
    "ok":      (34, 197, 94),    # verde
    "syncing": (47, 128, 255),   # azul
    "error":   (255, 32, 32),    # rojo
    "conflict": (255, 170, 0),   # ámbar (parpadea con el rojo cuando hay un conflicto)
}
FONTS = [
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]
font_path = next(p for p in FONTS if os.path.exists(p))

def letter_mask(ch="S"):
    f = ImageFont.truetype(font_path, 760)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.text((S / 2, S / 2), ch, font=f, anchor="mm", fill=255, stroke_width=34, stroke_fill=255)
    bbox = m.getbbox()                       # centra visualmente
    dx = S // 2 - (bbox[0] + bbox[2]) // 2
    dy = S // 2 - (bbox[1] + bbox[3]) // 2 + 6
    return ImageChops.offset(m, dx, dy), bbox

def render(color):
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle((28, 28, S - 28, S - 28), radius=230, fill=255)
    img.paste(BG, (0, 0), m)
    mask, bbox = letter_mask()
    top, bot = bbox[1] + 6, bbox[3] + 6
    grad = Image.new("RGBA", (S, S))
    px = grad.load()
    for y in range(S):
        t = min(1, max(0, (y - top) / (bot - top)))
        t = t ** 0.85
        c = tuple(int(255 + (color[i] - 255) * t) for i in range(3)) + (255,)
        for x in range(S):
            px[x, y] = c
    img.paste(grad, (0, 0), mask)
    return img

sizes = [256, 128, 64, 48, 32, 24, 16]
os.makedirs(OUT, exist_ok=True)
for name, col in STATES.items():
    big = render(col)
    big.save(os.path.join(OUT, name + ".ico"), format="ICO",
             sizes=[(s, s) for s in sizes])
    big.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))
    print("ok", name)
