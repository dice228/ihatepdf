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

TAN = (224, 188, 133, 255)        # силуэт инструмента
BORDER = (221, 184, 120, 255)     # обводка плитки
FILL_TOP = (68, 42, 27, 255)      # плитка светлее сверху
FILL_BOTTOM = (40, 24, 15, 255)
GAP = (0, 0, 0, 0)                # разрезы силуэта: прозрачные насквозь


def draw_chisel(img):
    """Инструмент рисуется горизонтально (жало слева), слой потом поворачивается."""
    d = ImageDraw.Draw(img)
    L = 1690.0
    x0 = (S - L) / 2.0
    cy = S / 2.0

    def X(u):
        return x0 + u * L

    # — полотно со скошенным жалом —
    d.polygon([(X(0.000), cy - 84), (X(0.082), cy - 84),
               (X(0.082), cy + 84), (X(0.048), cy + 84)], fill=TAN)
    d.rectangle([X(0.065), cy - 84, X(0.430), cy + 84], fill=TAN)

    # — шейка перед обоймой: ступенька снизу —
    d.rectangle([X(0.415), cy - 84, X(0.500), cy + 44], fill=TAN)

    # — обойма и рукоять одним телом —
    d.rounded_rectangle([X(0.470), cy - 110, X(0.928), cy + 110], radius=38, fill=TAN)

    # — торец —
    d.rounded_rectangle([X(0.886), cy - 104, X(1.000), cy + 104], radius=54, fill=TAN)

    # — разрезы: два кольца обоймы и поясок у торца —
    for u in (0.508, 0.552, 0.878):
        d.rectangle([X(u), cy - 116, X(u + 0.009), cy + 116], fill=GAP)


def tool_layer():
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_chisel(layer)
    return layer.rotate(-45, resample=Image.BICUBIC, center=(S / 2, S / 2))


def tile():
    """Плитка с вертикальным градиентом и песочной обводкой."""
    gradient = Image.new("RGBA", (S, S))
    pixels = gradient.load()
    for y in range(S):
        t = y / (S - 1)
        color = tuple(int(FILL_TOP[i] + (FILL_BOTTOM[i] - FILL_TOP[i]) * t) for i in range(4))
        for x in range(S):
            pixels[x, y] = color

    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([272, 272, 1776, 1776], radius=400, fill=255)

    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    base.paste(gradient, mask=mask)
    ImageDraw.Draw(base).rounded_rectangle([272, 272, 1776, 1776], radius=400,
                                           outline=BORDER, width=48)
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
