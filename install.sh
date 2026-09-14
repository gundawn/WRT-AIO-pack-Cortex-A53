#!/bin/sh
set -u

printf '%s\n' "========================================"
printf '%s\n' " OpenWrt Universal Installer"
printf '%s\n' "========================================"
printf '\n'

PACKAGES_UPDATE_STATUS="ошибка"
PACKAGES_STATUS="ошибка"
AURORA_STATUS="ошибка"
SINGBOX_STATUS="ошибка"
NETSHIFT_STATUS="ошибка"
BASE_RU_STATUS="ошибка"
CRON_STATUS="ошибка"

if [ "$(id -u)" != "0" ]; then
    printf '%s\n' "[ОШИБКА] Скрипт необходимо запускать от root."
    exit 1
fi

printf '%s\n' "[1/9] Проверка OpenWrt..."

if [ ! -f /etc/openwrt_release ]; then
    printf '%s\n' "[ОШИБКА] /etc/openwrt_release не найден."
    exit 1
fi

. /etc/openwrt_release

DIST_VERSION="${DISTRIB_RELEASE:-}"
DIST_ARCH="${DISTRIB_ARCH:-}"
DIST_TARGET="${DISTRIB_TARGET:-}"

if [ -z "$DIST_ARCH" ]; then
    printf '%s\n' "[ОШИБКА] Не удалось определить архитектуру OpenWrt."
    exit 1
fi

APK_BIN="$(command -v apk 2>/dev/null || true)"
OPKG_BIN="$(command -v opkg 2>/dev/null || true)"

if [ -n "$APK_BIN" ] && [ "$APK_BIN" != "/opt/bin/apk" ]; then
    PKG_MGR="$APK_BIN"
    PKG_EXT="apk"

elif [ -n "$OPKG_BIN" ] && [ "$OPKG_BIN" != "/opt/bin/opkg" ]; then
    PKG_MGR="$OPKG_BIN"
    PKG_EXT="ipk"

else
    printf '%s\n' "[ОШИБКА] Не найден системный apk или opkg."
    exit 1
fi

printf '%s\n' "[OK] OpenWrt: ${DIST_VERSION:-неизвестно}"
printf '%s\n' "[OK] Архитектура: $DIST_ARCH"
printf '%s\n' "[OK] Target: ${DIST_TARGET:-неизвестно}"
printf '%s\n' "[OK] Пакетный менеджер: $(basename "$PKG_MGR")"
printf '%s\n' "[OK] Формат пакета: .$PKG_EXT"
printf '\n'

TMP_DIR="/tmp/openwrt-installer"

rm -rf "$TMP_DIR"

if ! mkdir -p "$TMP_DIR"; then
    printf '%s\n' "[ОШИБКА] Не удалось создать временную директорию."
    exit 1
fi

cleanup() {
    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}

trap cleanup EXIT

fetch_file() {
    URL="$1"
    OUTPUT="$2"

    rm -f "$OUTPUT"

    if command -v wget >/dev/null 2>&1; then

        if wget -qO "$OUTPUT" \
            --timeout=20 \
            "$URL" 2>/dev/null &&
           [ -s "$OUTPUT" ]; then
            return 0
        fi

        rm -f "$OUTPUT"

        if wget -qO "$OUTPUT" \
            --no-check-certificate \
            --timeout=20 \
            "$URL" 2>/dev/null &&
           [ -s "$OUTPUT" ]; then
            return 0
        fi

        rm -f "$OUTPUT"
    fi

    if command -v curl >/dev/null 2>&1; then

        if curl -fsSL \
            --connect-timeout 20 \
            --max-time 120 \
            "$URL" \
            -o "$OUTPUT" 2>/dev/null &&
           [ -s "$OUTPUT" ]; then
            return 0
        fi

        rm -f "$OUTPUT"

        if curl -fsSLk \
            --connect-timeout 20 \
            --max-time 120 \
            "$URL" \
            -o "$OUTPUT" 2>/dev/null &&
           [ -s "$OUTPUT" ]; then
            return 0
        fi

        rm -f "$OUTPUT"
    fi

    return 1
}

if ! command -v wget >/dev/null 2>&1 &&
   ! command -v curl >/dev/null 2>&1; then
    printf '%s\n' "[ОШИБКА] Не найден wget или curl."
    exit 1
fi

AURORA_URL="https://openwrt.eamonxg.fun/install.sh"
NETSHIFT_URL="https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/install.sh"
GITHUB_API="https://api.github.com/repos/shtorm-7/sing-box-extended/releases/latest"

printf '%s\n' "[2/9] Обновление списков пакетов..."

if "$PKG_MGR" update; then
    PACKAGES_UPDATE_STATUS="обновлены"
    printf '%s\n' "[OK] Списки пакетов обновлены"
else
    printf '%s\n' "[ОШИБКА] Не удалось обновить списки пакетов"
fi

printf '\n'

printf '%s\n' "[3/9] Обновление установленных пакетов..."

if "$PKG_MGR" upgrade; then
    PACKAGES_STATUS="обновлены"
    printf '%s\n' "[OK] Установленные пакеты обновлены"
else
    printf '%s\n' "[ОШИБКА] Не удалось обновить установленные пакеты"
fi

printf '\n'

printf '%s\n' "[4/9] Установка русского языка LuCI..."

if [ "$PKG_EXT" = "apk" ]; then
    "$PKG_MGR" add luci-i18n-base-ru
else
    "$PKG_MGR" install luci-i18n-base-ru
fi

LUCI_RESULT=$?

if [ "$LUCI_RESULT" -eq 0 ]; then
    BASE_RU_STATUS="установлен"
    printf '%s\n' "[OK] Русский язык LuCI установлен"
else
    printf '%s\n' "[ОШИБКА] Не удалось установить luci-i18n-base-ru"
fi

printf '\n'

printf '%s\n' "[5/9] Установка темы Aurora..."

AURORA_SCRIPT="$TMP_DIR/aurora-install.sh"

if fetch_file "$AURORA_URL" "$AURORA_SCRIPT"; then

    if sh "$AURORA_SCRIPT"; then
        AURORA_STATUS="установлена"
        printf '%s\n' "[OK] Тема Aurora установлена"
    else
        printf '%s\n' "[ОШИБКА] Aurora вернула ошибку"
    fi

else
    printf '%s\n' "[ОШИБКА] Не удалось скачать установщик Aurora"
fi

printf '\n'

printf '%s\n' "[6/9] Получение последнего релиза sing-box-extended..."

RELEASE_JSON="$TMP_DIR/release.json"
TAG=""

if fetch_file "$GITHUB_API" "$RELEASE_JSON"; then

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

printf '%s\n' "[7/9] Загрузка и установка sing-box-extended..."

if [ -n "$TAG" ]; then

    ASSET_MATCHES="$(
        grep -o \
            '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
            "$RELEASE_JSON" |
        sed 's/.*"\(https:[^"]*\)"/\1/' |
        grep -E \
            "/sing-box-extended_[^/]*_openwrt_${DIST_ARCH}\.${PKG_EXT}$" ||
        true
    )"

    ASSET_COUNT="$(
        printf '%s\n' "$ASSET_MATCHES" |
        sed '/^[[:space:]]*$/d' |
        wc -l |
        tr -d ' '
    )"

    case "$ASSET_COUNT" in

        1)
            ASSET="$ASSET_MATCHES"
            ;;

        0)
            printf '%s\n' \
                "[ОШИБКА] Подходящий пакет sing-box-extended не найден."
            printf '%s\n' \
                "[INFO] Требуется: sing-box-extended_*_openwrt_${DIST_ARCH}.${PKG_EXT}"
            ASSET=""
            ;;

        *)
            printf '%s\n' \
                "[ОШИБКА] Найдено несколько подходящих пакетов: $ASSET_COUNT"
            printf '%s\n' "[INFO] Установка отменена для безопасности."
            printf '%s\n' "$ASSET_MATCHES"
            ASSET=""
            ;;

    esac

    if [ -n "$ASSET" ]; then

        PKG_FILE="$TMP_DIR/$(basename "$ASSET")"

        printf '%s\n' "[INFO] Пакет: $(basename "$ASSET")"

        if fetch_file "$ASSET" "$PKG_FILE"; then

            INSTALL_RESULT=0

            if [ "$PKG_EXT" = "apk" ]; then
                "$PKG_MGR" add \
                    --allow-untrusted \
                    "$PKG_FILE" ||
                    INSTALL_RESULT=$?
            else
                "$PKG_MGR" install \
                    "$PKG_FILE" ||
                    INSTALL_RESULT=$?
            fi

            if [ "$INSTALL_RESULT" -eq 0 ]; then

                if command -v sing-box >/dev/null 2>&1 &&
                   sing-box version >/dev/null 2>&1; then

                    SINGBOX_STATUS="установлен"
                    printf '%s\n' "[OK] sing-box-extended установлен"

                else
                    printf '%s\n' "[ОШИБКА] Проверка sing-box не пройдена"
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

printf '%s\n' "[8/9] Установка NetShift..."

NETSHIFT_SCRIPT="$TMP_DIR/netshift-install.sh"

if fetch_file "$NETSHIFT_URL" "$NETSHIFT_SCRIPT"; then

    if sh "$NETSHIFT_SCRIPT"; then
        NETSHIFT_STATUS="установлен"
        printf '%s\n' "[OK] NetShift установлен"
    else
        printf '%s\n' "[ОШИБКА] NetShift вернул ошибку"
    fi

else
    printf '%s\n' "[ОШИБКА] Не удалось скачать установщик NetShift"
fi

printf '\n'

printf '%s\n' "[9/9] Настройка ежедневной перезагрузки в 05:00..."

CRON_FILE="/etc/crontabs/root"
CRON_LINE="0 5 * * * /sbin/reboot"

if [ ! -f "$CRON_FILE" ]; then
    if ! touch "$CRON_FILE"; then
        printf '%s\n' "[ОШИБКА] Не удалось создать $CRON_FILE"
    else
        printf '%s\n' "[OK] Файл cron создан"
    fi
fi

if [ -f "$CRON_FILE" ]; then
    if grep -qF "$CRON_LINE" "$CRON_FILE" 2>/dev/null; then
        CRON_STATUS="уже настроена"
        printf '%s\n' "[OK] Задача уже существует в cron"
    else
        if printf '%s\n' "$CRON_LINE" >> "$CRON_FILE"; then
            CRON_STATUS="настроена (05:00)"
            printf '%s\n' "[OK] Ежедневная перезагрузка в 05:00 добавлена"
        else
            CRON_STATUS="ошибка"
            printf '%s\n' "[ОШИБКА] Не удалось записать задачу в cron"
        fi
    fi

    if [ "$CRON_STATUS" != "ошибка" ]; then
        if /etc/init.d/cron enable >/dev/null 2>&1 &&
           /etc/init.d/cron restart >/dev/null 2>&1; then
            printf '%s\n' "[OK] cron активирован и перечитал расписание"
        else
            CRON_STATUS="ошибка"
            printf '%s\n' "[ОШИБКА] Не удалось активировать cron"
        fi
    fi
fi

printf '\n'

printf '%s\n' "========================================"
printf '%s\n' " РЕЗУЛЬТАТ УСТАНОВКИ"
printf '%s\n' "========================================"
printf '%-20s %s\n' "OpenWrt:" "${DIST_VERSION:-неизвестно}"
printf '%-20s %s\n' "Архитектура:" "$DIST_ARCH"
printf '%-20s %s\n' "Target:" "${DIST_TARGET:-неизвестно}"
printf '%-20s %s\n' "Пакетный менеджер:" "$(basename "$PKG_MGR")"
printf '%-20s %s\n' "Списки пакетов:" "$PACKAGES_UPDATE_STATUS"
printf '%-20s %s\n' "Пакеты:" "$PACKAGES_STATUS"
printf '%-20s %s\n' "Русский LuCI:" "$BASE_RU_STATUS"
printf '%-20s %s\n' "Тема Aurora:" "$AURORA_STATUS"
printf '%-20s %s\n' "sing-box:" "$SINGBOX_STATUS"
printf '%-20s %s\n' "NetShift:" "$NETSHIFT_STATUS"
printf '%-20s %s\n' "Перезагрузка:" "$CRON_STATUS"
printf '%s\n' "========================================"