#!/usr/bin/env python3
"""
Рисует иконку Chisel (стамеска на тёмно-коричневом квадрате) и собирает .icns.

Это ЗАПАСНОЙ вариант иконки: если у вас есть оригинальный logo.png,
используйте tools/use-my-logo.sh — он соберёт .icns прямо из него.

Запуск:  python3 tools/make_icon.py
Требует: pillow
"""
import os
import struct
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(HERE, "..", "Resources"))

S = 2048          # рабочий холст (2x супер-сэмплинг от 1024)
OUT = 1024        # итоговый размер мастер-PNG

# — палитра, снятая с оригинального логотипа —
FRAME_FILL = (62, 36, 21, 255)       # тёмно-коричневый фон плитки
FRAME_EDGE = (229, 190, 124, 255)    # песочная рамка
STEEL = (156, 160, 164, 255)
STEEL_HI = (196, 200, 204, 255)
STEEL_TOP = (216, 219, 222, 255)
STEEL_LO = (126, 130, 134, 255)
TIP = (240, 242, 244, 255)
FERRULE = (244, 246, 247, 255)
GOLD = (255, 198, 46, 255)
GOLD_LO = (226, 168, 22, 255)
WOOD = (142, 74, 19, 255)
WOOD_HI = (166, 90, 24, 255)
WOOD_LO = (107, 54, 12, 255)
CAP = (245, 145, 30, 255)
CAP_LO = (224, 124, 18, 255)


def rr(d, x0, y0, x1, y1, r, fill):
    d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill)


def draw_chisel(img):
    """Стамеска рисуется горизонтально (жало слева), потом слой поворачивается."""
    d = ImageDraw.Draw(img)
    L = 1600.0                 # длина инструмента по оси
    x0 = (S - L) / 2.0         # 224
    cy = S / 2.0

    def X(u):
        return x0 + u * L

    # — жало (скошенный кончик) —
    d.polygon([(X(0.000), cy - 78), (X(0.068), cy - 78),
               (X(0.068), cy + 78), (X(0.040), cy + 78)], fill=TIP)

    # — полотно —
    d.polygon([(X(0.058), cy - 78), (X(0.430), cy - 78),
               (X(0.430), cy + 78), (X(0.058), cy + 78)], fill=STEEL)
    d.rectangle([X(0.058), cy - 78, X(0.430), cy - 30], fill=STEEL_HI)
    d.rectangle([X(0.058), cy - 78, X(0.430), cy - 64], fill=STEEL_TOP)
    d.rectangle([X(0.058), cy + 46, X(0.430), cy + 78], fill=STEEL_LO)

    # — шейка (ступенька снизу перед обоймой) —
    d.rectangle([X(0.410), cy - 78, X(0.486), cy + 38], fill=STEEL)
    d.rectangle([X(0.410), cy - 78, X(0.486), cy - 46], fill=STEEL_HI)

    # — белая обойма —
    rr(d, X(0.462), cy - 96, X(0.566), cy + 96, 16, FERRULE)
    # — золотое кольцо у полотна —
    rr(d, X(0.554), cy - 102, X(0.612), cy + 102, 16, GOLD)
    d.rectangle([X(0.554), cy + 60, X(0.612), cy + 100], fill=GOLD_LO)

    # — деревянная рукоять —
    rr(d, X(0.596), cy - 108, X(0.890), cy + 108, 34, WOOD)
    d.rectangle([X(0.608), cy - 96, X(0.878), cy - 50], fill=WOOD_HI)
    d.rectangle([X(0.608), cy + 52, X(0.878), cy + 102], fill=WOOD_LO)
    for u in (0.678, 0.758):
        d.rectangle([X(u), cy - 12, X(u + 0.055), cy + 4], fill=WOOD_LO)

    # — золотое кольцо у торца —
    rr(d, X(0.876), cy - 104, X(0.942), cy + 104, 16, GOLD)
    d.rectangle([X(0.876), cy + 62, X(0.942), cy + 102], fill=GOLD_LO)

    # — оранжевый торец —
    rr(d, X(0.916), cy - 100, X(1.000), cy + 100, 52, CAP)
    d.rectangle([X(0.916), cy + 46, X(0.982), cy + 98], fill=CAP_LO)


def build_master():
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(base)
    d.rounded_rectangle([272, 272, 1776, 1776], radius=400,
                        fill=FRAME_FILL, outline=FRAME_EDGE, width=48)

    tool = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_chisel(tool)
    tool = tool.rotate(-45, resample=Image.BICUBIC, center=(S / 2, S / 2))

    base.alpha_composite(tool)
    return base.resize((OUT, OUT), Image.LANCZOS)


# — сборка .icns: современные типы принимают PNG как есть —
ICNS_TYPES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic13", 256), (b"ic08", 256), (b"ic14", 512),
    (b"ic09", 512), (b"ic10", 1024),
]


def build_icns(master, path):
    import io
    chunks = b""
    for code, size in ICNS_TYPES:
        buf = io.BytesIO()
        master.resize((size, size), Image.LANCZOS).save(buf, format="PNG")
        data = buf.getvalue()
        chunks += code + struct.pack(">I", len(data) + 8) + data
    with open(path, "wb") as f:
        f.write(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    os.makedirs(RES, exist_ok=True)
    master = build_master()
    master.save(os.path.join(RES, "icon-1024.png"))
    master.resize((256, 256), Image.LANCZOS).save(os.path.join(RES, "icon-256.png"))
    build_icns(master, os.path.join(RES, "Chisel.icns"))
    print("ok:", RES)


if __name__ == "__main__":
    sys.exit(main())
