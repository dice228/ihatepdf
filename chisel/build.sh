#!/bin/bash
# Сборка Chisel.app. Нужен только Xcode Command Line Tools (xcode-select --install),
# полноценный Xcode не требуется.
#
#   ./build.sh              — под текущий процессор
#   ./build.sh --universal  — universal binary (Apple Silicon + Intel)
#   ./build.sh --install    — после сборки положить приложение в /Applications

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Chisel"
BUNDLE="build/${APP_NAME}.app"
MIN_OS="12.0"
UNIVERSAL=0
INSTALL=0

for arg in "$@"; do
    case "$arg" in
        --universal) UNIVERSAL=1 ;;
        --install)   INSTALL=1 ;;
        *) echo "Неизвестный ключ: $arg"; exit 1 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Chisel собирается только на macOS." >&2
    exit 1
fi

if ! xcrun --find swiftc >/dev/null 2>&1; then
    echo "Не найден swiftc. Установите инструменты разработчика: xcode-select --install" >&2
    exit 1
fi

SDK="$(xcrun --show-sdk-path --sdk macosx)"
SWIFTC="$(xcrun --find swiftc)"
SOURCES=(Sources/*.swift)

rm -rf build
mkdir -p "${BUNDLE}/Contents/MacOS" "${BUNDLE}/Contents/Resources"

compile() {  # $1 = arch, $2 = выходной файл
    echo "  • компилирую для $1"
    "$SWIFTC" -O -whole-module-optimization \
        -target "$1-apple-macos${MIN_OS}" \
        -sdk "$SDK" \
        -o "$2" \
        "${SOURCES[@]}"
}

echo "Сборка ${APP_NAME}…"
if [[ $UNIVERSAL -eq 1 ]]; then
    compile arm64  "build/${APP_NAME}-arm64"
    compile x86_64 "build/${APP_NAME}-x86_64"
    lipo -create "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64" \
         -output "${BUNDLE}/Contents/MacOS/${APP_NAME}"
    rm -f "build/${APP_NAME}-arm64" "build/${APP_NAME}-x86_64"
else
    compile "$(uname -m)" "${BUNDLE}/Contents/MacOS/${APP_NAME}"
fi

cp Resources/Info.plist "${BUNDLE}/Contents/Info.plist"
cp Resources/Chisel.icns "${BUNDLE}/Contents/Resources/Chisel.icns"
printf 'APPL????' > "${BUNDLE}/Contents/PkgInfo"

# Подпись ad-hoc: без неё macOS на Apple Silicon не запустит свежесобранный бинарник.
codesign --force --sign - --timestamp=none "${BUNDLE}" >/dev/null 2>&1 || \
    echo "  ! ad-hoc подпись не прошла — приложение всё равно должно запуститься"

echo "Готово: ${BUNDLE}"

if [[ $INSTALL -eq 1 ]]; then
    rm -rf "/Applications/${APP_NAME}.app"
    cp -R "${BUNDLE}" /Applications/
    echo "Установлено: /Applications/${APP_NAME}.app"
fi
