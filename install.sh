#!/bin/sh
set -u

printf '%s\n' "========================================"
printf '%s\n' " OpenWrt Universal Installer"
printf '%s\n' "========================================"
printf '\n'

PACKAGES_STATUS="ошибка"
AURORA_STATUS="ошибка"
SINGBOX_STATUS="ошибка"
NETSHIFT_STATUS="ошибка"
BASE_RU_STATUS="ошибка"

if [ "$(id -u)" != "0" ]; then
    printf '%s\n' "[ОШИБКА] Скрипт необходимо запускать от root."
    exit 1
fi

printf '%s\n' "[1/8] Проверка OpenWrt..."

if [ ! -f /etc/openwrt_release ]; then
    printf '%s\n' "[ОШИБКА] /etc/openwrt_release не найден."
    exit 1
fi

. /etc/openwrt_release

DIST_VERSION="${DISTRIB_RELEASE:-}"
DIST_ARCH="${DISTRIB_ARCH:-}"
DIST_TARGET="${DISTRIB_TARGET:-}"

if [ -z "$DIST_VERSION" ] || [ -z "$DIST_ARCH" ]; then
    printf '%s\n' "[ОШИБКА] Не удалось определить версию или архитектуру OpenWrt."
    exit 1
fi

# Определяем пакетный менеджер по фактическому наличию.
# apk -> .apk
# opkg -> .ipk
if command -v apk >/dev/null 2>&1; then
    PKG_MGR="apk"
    PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MGR="opkg"
    PKG_EXT="ipk"
else
    printf '%s\n' "[ОШИБКА] Не найден apk или opkg."
    exit 1
fi

printf '%s\n' "[OK] OpenWrt: $DIST_VERSION"
printf '%s\n' "[OK] Архитектура: $DIST_ARCH"
printf '%s\n' "[OK] Target: $DIST_TARGET"
printf '%s\n' "[OK] Пакетный менеджер: $PKG_MGR"
printf '%s\n' "[OK] Формат пакета: .$PKG_EXT"
printf '\n'

TMP_DIR="/tmp/openwrt-installer"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

cleanup() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}

trap cleanup EXIT

FETCH_TMP="$TMP_DIR/fetch.tmp"

if command -v wget >/dev/null 2>&1; then

    fetch() {
        rm -f "$FETCH_TMP"

        if wget -qO "$FETCH_TMP" \
            --no-check-certificate \
            --timeout=20 \
            "$1" 2>/dev/null &&
            [ -s "$FETCH_TMP" ]; then

            cat "$FETCH_TMP" || {
                rm -f "$FETCH_TMP"
                return 1
            }

            rm -f "$FETCH_TMP"
            return 0
        fi

        rm -f "$FETCH_TMP"

        if command -v curl >/dev/null 2>&1; then
            if curl -fsSLk \
                --connect-timeout 20 \
                --max-time 120 \
                "$1" > "$FETCH_TMP" 2>/dev/null &&
                [ -s "$FETCH_TMP" ]; then

                cat "$FETCH_TMP" || {
                    rm -f "$FETCH_TMP"
                    return 1
                }

                rm -f "$FETCH_TMP"
                return 0
            fi
        fi

        rm -f "$FETCH_TMP"
        return 1
    }

elif command -v curl >/dev/null 2>&1; then

    fetch() {
        curl -fsSLk \
            --connect-timeout 20 \
            --max-time 120 \
            "$1"
    }

else

    printf '%s\n' "[ОШИБКА] Не найден wget или curl."
    exit 1

fi

AURORA_URL="https://openwrt.eamonxg.fun/install.sh"
NETSHIFT_URL="https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/install.sh"
GITHUB_API="https://api.github.com/repos/shtorm-7/sing-box-extended/releases/latest"

printf '%s\n' "[2/8] Обновление списков пакетов..."

if "$PKG_MGR" update; then
    printf '%s\n' "[OK] Списки пакетов обновлены"
else
    printf '%s\n' "[ОШИБКА] Не удалось обновить списки пакетов"
fi

printf '\n'

printf '%s\n' "[3/8] Обновление установленных пакетов..."

if "$PKG_MGR" upgrade; then
    PACKAGES_STATUS="обновлены"
    printf '%s\n' "[OK] Установленные пакеты обновлены"
else
    printf '%s\n' "[ОШИБКА] Не удалось обновить установленные пакеты"
fi

printf '\n'

printf '%s\n' "[4/8] Установка русского языка LuCI..."

if "$PKG_MGR" install luci-i18n-base-ru; then
    BASE_RU_STATUS="установлен"
    printf '%s\n' "[OK] Русский язык LuCI установлен"
else
    printf '%s\n' "[ОШИБКА] Не удалось установить luci-i18n-base-ru"
fi

printf '\n'

printf '%s\n' "[5/8] Установка темы Aurora..."

AURORA_SCRIPT="$TMP_DIR/aurora-install.sh"

if fetch "$AURORA_URL" > "$AURORA_SCRIPT" &&
    [ -s "$AURORA_SCRIPT" ]; then

    if sh "$AURORA_SCRIPT"; then
        AURORA_STATUS="установлена"
        printf '%s\n' "[OK] Тема Aurora установлена"
    else
        printf '%s\n' "[ОШИБКА] Тема Aurora вернула ошибку"
    fi

else

    printf '%s\n' "[ОШИБКА] Не удалось скачать установщик Aurora"

fi

printf '\n'

printf '%s\n' "[6/8] Получение последнего релиза sing-box-extended..."

RELEASE_JSON="$TMP_DIR/release.json"
TAG=""

if fetch "$GITHUB_API" > "$RELEASE_JSON" &&
    [ -s "$RELEASE_JSON" ]; then

    TAG="$(
        sed -n \
            's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$RELEASE_JSON" |
        head -n 1
    )"

    if [ -n "$TAG" ]; then
        printf '%s\n' "[OK] Найден релиз: $TAG"
    else
        printf '%s\n' "[ОШИБКА] Не удалось определить версию sing-box-extended"
    fi

else

    printf '%s\n' "[ОШИБКА] Не удалось получить информацию о релизе sing-box-extended"

fi

printf '\n'

printf '%s\n' "[7/8] Загрузка и установка sing-box-extended..."

if [ -n "$TAG" ]; then

    # Ищем ТОЛЬКО OpenWrt-пакет нужного формата:
    #
    # apk  -> ..._openwrt_<arch>.apk
    # opkg -> ..._openwrt_<arch>.ipk
    #
    # compressed.tar.gz сюда попасть не может.
    ASSET_MATCHES="$(
        grep -o \
            '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
            "$RELEASE_JSON" |
        sed 's/.*"\(https:[^"]*\)"/\1/' |
        grep -E \
            "/sing-box-extended_[^/]*_openwrt_${DIST_ARCH//./\\.}\\.${PKG_EXT}$" ||
        true
    )"

    ASSET_COUNT="$(
        printf '%s\n' "$ASSET_MATCHES" |
        sed '/^[[:space:]]*$/d' |
        wc -l
    )"

    case "$ASSET_COUNT" in

        1)
            ASSET="$ASSET_MATCHES"
            ;;

        0)
            ASSET=""

            printf '%s\n' \
                "[ОШИБКА] В релизе $TAG не найден пакет:"
            printf '%s\n' \
                "         sing-box-extended_*_openwrt_${DIST_ARCH}.${PKG_EXT}"

            ;;

        *)
            ASSET=""

            printf '%s\n' \
                "[ОШИБКА] Найдено несколько подходящих пакетов:"
            printf '%s\n' "$ASSET_MATCHES"
            printf '%s\n' \
                "[ОШИБКА] Установка остановлена во избежание выбора неправильного пакета."

            ;;

    esac

    if [ -n "$ASSET" ]; then

        PKG_FILE="$TMP_DIR/$(basename "$ASSET")"

        printf '%s\n' "[INFO] Пакет: $(basename "$ASSET")"

        if fetch "$ASSET" > "$PKG_FILE" &&
            [ -s "$PKG_FILE" ]; then

            INSTALL_RESULT=0

            if [ "$PKG_MGR" = "apk" ]; then

                apk add --allow-untrusted "$PKG_FILE" ||
                    INSTALL_RESULT=$?

            else

                opkg install "$PKG_FILE" ||
                    INSTALL_RESULT=$?

            fi

            if [ "$INSTALL_RESULT" -eq 0 ]; then

                if command -v sing-box >/dev/null 2>&1 &&
                    sing-box version >/dev/null 2>&1; then

                    SINGBOX_STATUS="установлен"

                    printf '%s\n' \
                        "[OK] sing-box-extended установлен"

                else

                    printf '%s\n' \
                        "[ОШИБКА] Проверка sing-box не пройдена"

                fi

            else

                printf '%s\n' \
                    "[ОШИБКА] Не удалось установить sing-box-extended"

            fi

        else

            printf '%s\n' \
                "[ОШИБКА] Не удалось скачать sing-box-extended"

        fi

    fi

fi

printf '\n'

printf '%s\n' "[8/8] Установка NetShift..."

NETSHIFT_SCRIPT="$TMP_DIR/netshift-install.sh"

if fetch "$NETSHIFT_URL" > "$NETSHIFT_SCRIPT" &&
    [ -s "$NETSHIFT_SCRIPT" ]; then

    if sh "$NETSHIFT_SCRIPT"; then
        NETSHIFT_STATUS="установлен"
        printf '%s\n' "[OK] NetShift установлен"
    else
        printf '%s\n' "[ОШИБКА] NetShift вернул ошибку"
    fi

else

    printf '%s\n' \
        "[ОШИБКА] Не удалось скачать установщик NetShift"

fi

printf '\n'

printf '%s\n' "========================================"
printf '%s\n' " РЕЗУЛЬТАТ УСТАНОВКИ"
printf '%s\n' "========================================"

printf '%-20s %s\n' "OpenWrt:" "$DIST_VERSION"
printf '%-20s %s\n' "Архитектура:" "$DIST_ARCH"
printf '%-20s %s\n' "Пакеты:" "$PACKAGES_STATUS"
printf '%-20s %s\n' "Русский LuCI:" "$BASE_RU_STATUS"
printf '%-20s %s\n' "Тема Aurora:" "$AURORA_STATUS"
printf '%-20s %s\n' "sing-box:" "$SINGBOX_STATUS"
printf '%-20s %s\n' "NetShift:" "$NETSHIFT_STATUS"

printf '%s\n' "========================================"