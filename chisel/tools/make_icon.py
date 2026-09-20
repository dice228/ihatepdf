#!/usr/bin/env python3
"""
Рисует запасные картинки Chisel: иконку приложения и фон пустого окна.
Стиль монохромный — песочный силуэт инструмента на тёмной плитке с обводкой.

Это ЗАПАСНОЙ вариант. Свои файлы ставятся так:
  иконка — tools/use-my-logo.sh, затем пересборка;
  фон    — прямо в приложении, меню «Файл» → «Фоновая картинка…».

Запуск:  python3 tools/make_icon.py     (нужен pillow)
"""
import io
import os
import struct
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.abspath(os.path.join(HERE, "..", "Resources"))

S = 2048          # рабочий холст (2x супер-сэмплинг от 1024)
OUT = 1024

# Плитка: тёплый коричневый градиент под золотой рамкой с бликом.
FILL_TOP = (74, 45, 29, 255)
FILL_BOTTOM = (42, 23, 16, 255)
BORDER_TOP = (242, 227, 176, 255)
BORDER_BOTTOM = (201, 160, 94, 255)

# Инструмент.
STEEL = (169, 173, 177, 255)
STEEL_HI = (201, 205, 209, 255)
STEEL_TOP = (222, 225, 228, 255)
STEEL_LO = (138, 142, 146, 255)
TIP = (242, 244, 246, 255)
FERRULE = (248, 250, 251, 255)
GOLD = (255, 198, 46, 255)
GOLD_LO = (224, 168, 28, 255)
WOOD = (138, 69, 18, 255)
WOOD_HI = (166, 90, 24, 255)
WOOD_LO = (95, 50, 12, 255)
CAP = (245, 145, 30, 255)
CAP_LO = (222, 124, 18, 255)


def draw_chisel(img):
    """Инструмент рисуется горизонтально (жало слева), слой потом поворачивается."""
    d = ImageDraw.Draw(img)
    L = 1690.0
    x0 = (S - L) / 2.0
    cy = S / 2.0

    def X(u):
        return x0 + u * L

    # — жало: скошенный белый кончик —
    d.polygon([(X(0.000), cy - 84), (X(0.070), cy - 84),
               (X(0.070), cy + 84), (X(0.040), cy + 84)], fill=TIP)

    # — полотно —
    d.rectangle([X(0.058), cy - 84, X(0.430), cy + 84], fill=STEEL)
    d.rectangle([X(0.058), cy - 84, X(0.430), cy - 32], fill=STEEL_HI)
    d.rectangle([X(0.058), cy - 84, X(0.430), cy - 68], fill=STEEL_TOP)
    d.rectangle([X(0.058), cy + 50, X(0.430), cy + 84], fill=STEEL_LO)

    # — шейка перед обоймой —
    d.rectangle([X(0.415), cy - 84, X(0.500), cy + 44], fill=STEEL)
    d.rectangle([X(0.415), cy - 84, X(0.500), cy - 50], fill=STEEL_HI)

    # — белая обойма —
    d.rounded_rectangle([X(0.470), cy - 100, X(0.566), cy + 100], radius=16, fill=FERRULE)

    # — золотое кольцо у полотна —
    d.rounded_rectangle([X(0.552), cy - 106, X(0.614), cy + 106], radius=16, fill=GOLD)
    d.rectangle([X(0.552), cy + 62, X(0.614), cy + 104], fill=GOLD_LO)

    # — деревянная рукоять —
    d.rounded_rectangle([X(0.598), cy - 110, X(0.892), cy + 110], radius=36, fill=WOOD)
    d.rectangle([X(0.610), cy - 98, X(0.880), cy - 52], fill=WOOD_HI)
    d.rectangle([X(0.610), cy + 54, X(0.880), cy + 104], fill=WOOD_LO)
    for u in (0.680, 0.760):
        d.rectangle([X(u), cy - 12, X(u + 0.052), cy + 4], fill=WOOD_LO)

    # — золотое кольцо у торца —
    d.rounded_rectangle([X(0.878), cy - 106, X(0.944), cy + 106], radius=16, fill=GOLD)
    d.rectangle([X(0.878), cy + 64, X(0.944), cy + 104], fill=GOLD_LO)

    # — оранжевый торец —
    d.rounded_rectangle([X(0.918), cy - 102, X(1.000), cy + 102], radius=54, fill=CAP)
    d.rectangle([X(0.918), cy + 48, X(0.986), cy + 100], fill=CAP_LO)


def tool_layer():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_chisel(layer)
    return layer.rotate(-45, resample=Image.BICUBIC, center=(S / 2, S / 2))


def vertical_gradient(top, bottom):
    image = Image.new("RGBA", (S, S))
    pixels = image.load()
    for y in range(S):
        t = y / (S - 1)
        color = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
        for x in range(S):
            pixels[x, y] = color
    return image


def tile():
    """Плитка: коричневый градиент внутри, золотая рамка с бликом снаружи."""
    outer = [272, 272, 1776, 1776]
    width = 48
    inner = [outer[0] + width, outer[1] + width, outer[2] - width, outer[3] - width]

    fill_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(fill_mask).rounded_rectangle(inner, radius=400 - width, fill=255)

    ring_mask = Image.new("L", (S, S), 0)
    ring = ImageDraw.Draw(ring_mask)
    ring.rounded_rectangle(outer, radius=400, fill=255)
    ring.rounded_rectangle(inner, radius=400 - width, fill=0)

    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.paste(vertical_gradient(FILL_TOP, FILL_BOTTOM), mask=fill_mask)
    base.paste(vertical_gradient(BORDER_TOP, BORDER_BOTTOM), mask=ring_mask)
    return base


def build_master():
    base = tile()
    base.alpha_composite(tool_layer())
    return base.resize((OUT, OUT), Image.LANCZOS)


def build_background():
    """Для пустого окна — один силуэт, без плитки."""
    tool = tool_layer()
    return tool.crop(tool.getbbox()).resize((512, 512), Image.LANCZOS)


# — сборка .icns: современные типы принимают PNG как есть —
ICNS_TYPES = [
    (b"icp4", 16), (b"icp5", 32), (b"ic11", 32), (b"ic12", 64),
    (b"ic07", 128), (b"ic13", 256), (b"ic08", 256), (b"ic14", 512),
    (b"ic09", 512), (b"ic10", 1024),
]


def build_icns(master, path):
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
    build_background().save(os.path.join(RES, "background.png"))
    print("ok:", RES)


if __name__ == "__main__":
    sys.exit(main())
