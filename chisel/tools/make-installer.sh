#!/bin/bash
# Собирает установщик Chisel.
#
#   ./tools/make-installer.sh           — образ .dmg (перетащить в «Программы»)
#   ./tools/make-installer.sh --pkg     — пакет .pkg (двойной клик, ставит сам)
#   ./tools/make-installer.sh --both    — и то, и другое
#
# Подпись и нотаризация — по желанию, через переменные окружения:
#   CHISEL_SIGN_ID        — «Developer ID Application: Имя (TEAMID)» для приложения и образа
#   CHISEL_INSTALLER_ID   — «Developer ID Installer: Имя (TEAMID)» для .pkg
#   CHISEL_NOTARY_PROFILE — имя профиля notarytool в связке ключей
#
# Без них установщик соберётся, но на чужом Mac Gatekeeper потребует
# открыть приложение через правую кнопку → «Открыть» (см. README).

set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Chisel.app"
IDENTIFIER="app.chisel.video"
MAKE_DMG=1
MAKE_PKG=0

for arg in "$@"; do
    case "$arg" in
        --dmg)  MAKE_DMG=1; MAKE_PKG=0 ;;
        --pkg)  MAKE_DMG=0; MAKE_PKG=1 ;;
        --both) MAKE_DMG=1; MAKE_PKG=1 ;;
        *) echo "Неизвестный ключ: $arg" >&2; exit 1 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Установщик собирается только на macOS." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"

if [[ ! -d "$APP" ]]; then
    echo "Приложение ещё не собрано — собираю universal…"
    ./build.sh --universal
fi

# — подпись приложения —
if [[ -n "${CHISEL_SIGN_ID:-}" ]]; then
    echo "Подписываю приложение: $CHISEL_SIGN_ID"
    codesign --force --deep --timestamp --options runtime \
             --sign "$CHISEL_SIGN_ID" "$APP"
    codesign --verify --strict --verbose=1 "$APP"
fi

notarize() {  # $1 — файл установщика
    [[ -n "${CHISEL_NOTARY_PROFILE:-}" ]] || return 0
    echo "Отправляю на нотаризацию: $1"
    xcrun notarytool submit "$1" --keychain-profile "$CHISEL_NOTARY_PROFILE" --wait
    xcrun stapler staple "$1"
}

if [[ $MAKE_DMG -eq 1 ]]; then
    DMG="build/Chisel-${VERSION}.dmg"
    STAGE="$(mktemp -d)/Chisel"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"   # чтобы перетаскивать было некуда деваться

    rm -f "$DMG"
    hdiutil create -volname "Chisel" -srcfolder "$STAGE" \
                   -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$(dirname "$STAGE")"

    if [[ -n "${CHISEL_SIGN_ID:-}" ]]; then
        codesign --force --sign "$CHISEL_SIGN_ID" "$DMG"
    fi
    notarize "$DMG"
    echo "Готово: $DMG"
fi

if [[ $MAKE_PKG -eq 1 ]]; then
    PKG="build/Chisel-${VERSION}.pkg"
    rm -f "$PKG"
    if [[ -n "${CHISEL_INSTALLER_ID:-}" ]]; then
        pkgbuild --component "$APP" --install-location /Applications \
                 --identifier "$IDENTIFIER" --version "$VERSION" \
                 --sign "$CHISEL_INSTALLER_ID" "$PKG"
    else
        pkgbuild --component "$APP" --install-location /Applications \
                 --identifier "$IDENTIFIER" --version "$VERSION" "$PKG"
    fi
    notarize "$PKG"
    echo "Готово: $PKG"
fi
