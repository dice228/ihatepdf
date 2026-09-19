#!/bin/bash
# Собирает Resources/Chisel.icns из вашего PNG (по умолчанию — ~/Documents/logo.png).
# Запускать на macOS: sips и iconutil входят в систему.
#
#   ./tools/use-my-logo.sh
#   ./tools/use-my-logo.sh /путь/к/logo.png

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="${1:-$HOME/Documents/logo.png}"
if [[ ! -f "$SRC" ]]; then
    echo "Не найден файл: $SRC" >&2
    exit 1
fi

WORK="$(mktemp -d)/Chisel.iconset"
mkdir -p "$WORK"

make() { sips -z "$2" "$2" "$SRC" --out "$WORK/$1" >/dev/null; }
make icon_16x16.png        16
make icon_16x16@2x.png     32
make icon_32x32.png        32
make icon_32x32@2x.png     64
make icon_128x128.png     128
make icon_128x128@2x.png  256
make icon_256x256.png     256
make icon_256x256@2x.png  512
make icon_512x512.png     512
make icon_512x512@2x.png 1024

iconutil -c icns "$WORK" -o Resources/Chisel.icns
echo "Иконка обновлена: Resources/Chisel.icns"
echo "Пересоберите приложение: ./build.sh"
