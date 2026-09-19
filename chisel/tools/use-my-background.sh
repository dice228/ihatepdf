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

# 1024 по длинной стороне: с запасом для Retina, дальше приложение масштабирует само.
sips -Z 1024 "$SRC" --out Resources/background.png >/dev/null
echo "Фоновая иконка обновлена: Resources/background.png"
echo "Пересоберите приложение: ./build.sh"
