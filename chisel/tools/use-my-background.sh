#!/bin/bash
# Ставит вашу картинку фоновой иконкой пустого окна.
# По умолчанию берёт ~/Documents/background icon.png
#
#   ./tools/use-my-background.sh
#   ./tools/use-my-background.sh "/путь/к/картинке.png"

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-$HOME/Documents/background icon.png}"
SRC="${SRC/#\~/$HOME}"          # путь в кавычках вида "~/Documents/…" zsh не раскрывает

if [[ ! -f "$SRC" ]]; then
    echo "Не найден файл: $SRC" >&2
    exit 1
fi

# sips не умеет SVG — такие файлы сначала отрисовывает Quick Look.
if ! sips -g pixelWidth "$SRC" >/dev/null 2>&1; then
    RENDER_DIR="$(mktemp -d)"
    qlmanage -t -s 2048 -o "$RENDER_DIR" "$SRC" >/dev/null 2>&1 || true
    RENDERED="$(find "$RENDER_DIR" -name '*.png' | head -1)"
    if [[ -z "$RENDERED" ]]; then
        echo "Не получилось отрисовать $SRC" >&2
        exit 1
    fi
    SRC="$RENDERED"
fi

# 1024 по длинной стороне: с запасом для Retina, дальше приложение масштабирует само.
sips -Z 1024 "$SRC" --out Resources/background.png >/dev/null
echo "Запасная картинка в сборке обновлена: Resources/background.png"

# И сразу ставим её текущей — приложение берёт картинку отсюда, пересборка не нужна.
LIVE="$HOME/Library/Application Support/Chisel"
mkdir -p "$LIVE"
cp Resources/background.png "$LIVE/background.png"
echo "Поставлена в приложение: $LIVE/background.png"
echo "Если Chisel открыт — перезапустите его."
