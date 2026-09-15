#!/bin/sh

set -u

AURORA_INSTALL_URL="https://openwrt.eamonxg.fun/install.sh"
NETSHIFT_INSTALL_URL="https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/install.sh"
SINGBOX_API_URL="https://api.github.com/repos/shtorm-7/sing-box-extended/releases/latest"

MIN_FLASH_MB=50
TMP_DIR="/tmp/wrt-aio"

PACKAGES_UPDATE_STATUS="SKIPPED"
PACKAGES_STATUS="SKIPPED"
BASE_RU_STATUS="SKIPPED"
AURORA_STATUS="SKIPPED"
SINGBOX_STATUS="SKIPPED"
NETSHIFT_STATUS="SKIPPED"
CRON_STATUS="SKIPPED"


log() {
    printf '\n[%s] %s\n' "$1" "$2"
}

ok() {
    printf '  [OK] %s\n' "$1"
}

warn() {
    printf '  [ПРЕДУПРЕЖДЕНИЕ] %s\n' "$1"
}

fail() {
    printf '  [ОШИБКА] %s\n' "$1"
}


pkg_installed() {
    package="$1"

    case "$PKG_MANAGER" in
        apk)
            apk info -e "$package" >/dev/null 2>&1
            ;;
        opkg)
            opkg status "$package" 2>/dev/null |
                grep -q '^Status:.*installed'
            ;;
    esac
}


pkg_version() {
    package="$1"

    case "$PKG_MANAGER" in
        apk)
            apk info -e "$package" 2>/dev/null |
                head -n 1 |
                sed "s/^${package}-//"
            ;;
        opkg)
            opkg status "$package" 2>/dev/null |
                sed -n 's/^Version:[[:space:]]*//p' |
                head -n 1
            ;;
    esac
}


pkg_install() {
    package="$1"

    case "$PKG_MANAGER" in
        apk)
            apk add "$package"
            ;;
        opkg)
            opkg install "$package"
            ;;
    esac
}


pkg_remove() {
    package="$1"

    case "$PKG_MANAGER" in
        apk)
            apk del "$package"
            ;;
        opkg)
            opkg remove "$package"
            ;;
    esac
}


pkg_refresh() {
    case "$PKG_MANAGER" in
        apk)
            apk update
            ;;
        opkg)
            opkg update
            ;;
    esac
}


pkg_upgrade_all() {
    case "$PKG_MANAGER" in
        apk)
            apk upgrade
            ;;
        opkg)
            UPGRADE_LIST="$(
                opkg list-upgradable 2>/dev/null |
                awk '{print $1}'
            )"

            if [ -n "$UPGRADE_LIST" ]; then
                for package in $UPGRADE_LIST; do
                    opkg upgrade "$package" || return 1
                done
            fi
            ;;
    esac
}


version_is_newer() {
    installed="$1"
    candidate="$2"

    [ -n "$installed" ] || return 0
    [ -n "$candidate" ] || return 1

    case "$PKG_MANAGER" in
        apk)
            [ "$(apk version -t "$installed" "$candidate" 2>/dev/null)" = "<" ]
            ;;
        opkg)
            opkg compare-versions "$candidate" ">" "$installed" >/dev/null 2>&1
            ;;
    esac
}


package_needs_update() {
    package="$1"

    if ! pkg_installed "$package"; then
        return 0
    fi

    installed_version="$(pkg_version "$package")"
    candidate_version=""

    case "$PKG_MANAGER" in
        apk)
            candidate_version="$(
                apk policy "$package" 2>/dev/null |
                sed -n 's/^[[:space:]]*\([0-9][^[:space:]:]*\):.*/\1/p' |
                head -n 1
            )"
            ;;
        opkg)
            candidate_version="$(
                opkg list-upgradable 2>/dev/null |
                awk -v p="$package" '$1 == p {print $3; exit}'
            )"
            ;;
    esac

    [ -n "$candidate_version" ] || return 1

    version_is_newer "$installed_version" "$candidate_version"
}


fetch_file() {
    url="$1"
    output="$2"

    rm -f "$output"

    if command -v wget >/dev/null 2>&1; then
        if wget -qO "$output" "$url" 2>/dev/null &&
            [ -s "$output" ]; then
            return 0
        fi

        rm -f "$output"

        if wget --no-check-certificate -qO "$output" "$url" 2>/dev/null &&
            [ -s "$output" ]; then
            return 0
        fi
    fi

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL -o "$output" "$url" 2>/dev/null &&
            [ -s "$output" ]; then
            return 0
        fi

        rm -f "$output"

        if curl -kfsSL -o "$output" "$url" 2>/dev/null &&
            [ -s "$output" ]; then
            return 0
        fi
    fi

    rm -f "$output"
    return 1
}


run_remote_installer() {
    url="$1"
    script="$TMP_DIR/installer.sh"

    rm -f "$script"

    if ! fetch_file "$url" "$script"; then
        return 1
    fi

    if [ ! -s "$script" ]; then
        return 1
    fi

    chmod 700 "$script" 2>/dev/null || return 1

    sh "$script"
}




if [ "$(id -u)" -ne 0 ]; then
    fail "Скрипт необходимо запускать от root."
    exit 1
fi

mkdir -p "$TMP_DIR" || {
    fail "Не удалось создать временный каталог $TMP_DIR."
    exit 1
}

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT


if [ -f /etc/openwrt_release ]; then
    . /etc/openwrt_release
else
    fail "Файл /etc/openwrt_release не найден."
    exit 1
fi




if command -v apk >/dev/null 2>&1 &&
    [ -z "${OPKG_INSTALLED_ROOT:-}" ]; then

    PKG_MANAGER="apk"

elif command -v opkg >/dev/null 2>&1; then

    PKG_MANAGER="opkg"

else

    fail "Не найден ни apk, ни opkg."
    exit 1

fi


case "$PKG_MANAGER" in
    apk)
        PKG_ARCH="$(apk --print-arch 2>/dev/null || true)"
        ;;
    opkg)
        PKG_ARCH="$(
            opkg print-architecture 2>/dev/null |
            awk '$1 == "arch" {print $2}' |
            tail -n 1
        )"
        ;;
esac

[ -n "$PKG_ARCH" ] || PKG_ARCH="${DISTRIB_ARCH:-unknown}"

printf '\n'
printf 'WRT-AIO-universal\n'
printf '=================\n'
printf 'Пакетный менеджер: %s\n' "$PKG_MANAGER"
printf 'Архитектура пакетов: %s\n' "$PKG_ARCH"
printf 'Архитектура OpenWrt: %s\n' "${DISTRIB_ARCH:-unknown}"




log "ПАКЕТЫ" "Обновление списков пакетов"

if pkg_refresh; then
    PACKAGES_UPDATE_STATUS="OK"
    ok "Списки пакетов обновлены."
else
    PACKAGES_UPDATE_STATUS="FAILED"
    fail "Не удалось обновить списки пакетов."
fi


log "ПАКЕТЫ" "Обновление установленных пакетов"

if pkg_upgrade_all; then
    PACKAGES_STATUS="OK"
    ok "Установленные пакеты обновлены."
else
    PACKAGES_STATUS="FAILED"
    fail "Не удалось обновить все установленные пакеты."
fi




log "BASE RU" "Проверка русского языка LuCI"

if pkg_installed "luci-i18n-base-ru"; then

    if package_needs_update "luci-i18n-base-ru"; then
        if pkg_install "luci-i18n-base-ru"; then
            BASE_RU_STATUS="OK"
            ok "Русский язык LuCI обновлён."
        else
            BASE_RU_STATUS="FAILED"
            fail "Не удалось обновить luci-i18n-base-ru."
        fi
    else
        BASE_RU_STATUS="OK"
        ok "Русский язык LuCI уже установлен и актуален."
    fi

else

    if pkg_install "luci-i18n-base-ru"; then
        BASE_RU_STATUS="OK"
        ok "Русский язык LuCI установлен."
    else
        BASE_RU_STATUS="FAILED"
        fail "Не удалось установить luci-i18n-base-ru."
    fi

fi




log "AURORA" "Проверка Aurora"

AURORA_NEEDS_UPDATE=0

if ! pkg_installed "luci-theme-aurora"; then
    AURORA_NEEDS_UPDATE=1
elif package_needs_update "luci-theme-aurora"; then
    AURORA_NEEDS_UPDATE=1
fi

if ! pkg_installed "luci-app-aurora-config"; then
    AURORA_NEEDS_UPDATE=1
elif package_needs_update "luci-app-aurora-config"; then
    AURORA_NEEDS_UPDATE=1
fi

if ! pkg_installed "luci-i18n-aurora-config-ru"; then
    AURORA_NEEDS_UPDATE=1
elif package_needs_update "luci-i18n-aurora-config-ru"; then
    AURORA_NEEDS_UPDATE=1
fi

if [ "$AURORA_NEEDS_UPDATE" -eq 0 ]; then

    AURORA_STATUS="OK"
    ok "Aurora уже установлена и актуальна."

else

    if run_remote_installer "$AURORA_INSTALL_URL"; then

        if pkg_installed "luci-theme-aurora" &&
            pkg_installed "luci-app-aurora-config" &&
            pkg_installed "luci-i18n-aurora-config-ru"; then

            AURORA_STATUS="OK"
            ok "Aurora установлена/обновлена."

        else

            AURORA_STATUS="FAILED"
            fail "Aurora installer завершился, но не все пакеты Aurora установлены."

        fi

    else

        AURORA_STATUS="FAILED"
        fail "Не удалось запустить установщик Aurora."

    fi

fi




log "FLASH" "Проверка общей ёмкости файловой системы"

FLASH_TOTAL_KB=""

if df -k /overlay >/dev/null 2>&1; then
    FLASH_TOTAL_KB="$(df -k /overlay | awk 'NR == 2 {print $2}')"
elif df -k / >/dev/null 2>&1; then
    FLASH_TOTAL_KB="$(df -k / | awk 'NR == 2 {print $2}')"
fi

FLASH_OK=0
FLASH_TOTAL_MB=0

case "$FLASH_TOTAL_KB" in
    ''|*[!0-9]*)
        warn "Не удалось определить общую ёмкость флеш-памяти."
        warn "Для безопасности sing-box-extended и NetShift пропускаются."
        ;;
    *)
        FLASH_TOTAL_MB=$((FLASH_TOTAL_KB / 1024))

        printf '  Общая ёмкость: %s MB\n' "$FLASH_TOTAL_MB"
        printf '  Минимум для sing-box-extended/NetShift: %s MB\n' "$MIN_FLASH_MB"

        if [ "$FLASH_TOTAL_MB" -ge "$MIN_FLASH_MB" ]; then
            FLASH_OK=1
            ok "Ёмкость флеш-памяти достаточна."
        else
            warn "Недостаточно общей ёмкости флеш-памяти."
            warn "Установка/обновление sing-box-extended и NetShift пропускается."
        fi
        ;;
esac




if [ "$FLASH_OK" -eq 1 ]; then

    log "SING-BOX" "Проверка sing-box-extended"

    SINGBOX_JSON="$TMP_DIR/sing-box.json"
    SINGBOX_FILE="$TMP_DIR/sing-box-package"
    CONTROL_ARCHIVE="$TMP_DIR/control.tar.gz"

    SINGBOX_STATUS="FAILED"
    SINGBOX_NEEDS_UPDATE=0

    if ! fetch_file "$SINGBOX_API_URL" "$SINGBOX_JSON"; then

        fail "Не удалось получить информацию о последнем релизе sing-box-extended."

    elif [ ! -s "$SINGBOX_JSON" ]; then

        fail "Ответ GitHub для sing-box-extended пуст."

    else

        case "$PKG_MANAGER" in
            apk)
                PACKAGE_EXT="apk"
                ;;
            opkg)
                PACKAGE_EXT="ipk"
                ;;
        esac

        RELEASE_ARCH="${DISTRIB_ARCH:-$PKG_ARCH}"

        SINGBOX_ASSET="$(
            grep -o '"browser_download_url":[[:space:]]*"[^"]*"' "$SINGBOX_JSON" |
            sed 's/.*"\(https:[^"]*\)"/\1/' |
            grep -E "_openwrt_${RELEASE_ARCH}\.${PACKAGE_EXT}$" |
            head -n 1
        )"

        if [ -z "$SINGBOX_ASSET" ]; then
            SINGBOX_ASSET="$(
                grep -o '"browser_download_url":[[:space:]]*"[^"]*"' "$SINGBOX_JSON" |
                sed 's/.*"\(https:[^"]*\)"/\1/' |
                grep -E "openwrt.*${RELEASE_ARCH}.*\.${PACKAGE_EXT}$" |
                head -n 1
            )"
        fi

        if [ -z "$SINGBOX_ASSET" ]; then

            fail "Не найден пакет sing-box-extended для архитектуры ${RELEASE_ARCH}."

        elif ! fetch_file "$SINGBOX_ASSET" "$SINGBOX_FILE"; then

            fail "Не удалось скачать пакет sing-box-extended."

        elif [ ! -s "$SINGBOX_FILE" ]; then

            fail "Скачанный пакет sing-box-extended пуст."

        else

            if pkg_installed "sing-box-extended"; then

                INSTALLED_SB_VERSION="$(pkg_version "sing-box-extended")"
                CANDIDATE_SB_VERSION=""

                case "$PKG_MANAGER" in
                    apk)
                        CANDIDATE_SB_VERSION="$(
                            tar -xzOf "$SINGBOX_FILE" .PKGINFO 2>/dev/null |
                            sed -n 's/^pkgver[[:space:]]*=[[:space:]]*//p' |
                            head -n 1
                        )"
                        ;;
                    opkg)
                        rm -f "$CONTROL_ARCHIVE"

                        if ar p "$SINGBOX_FILE" control.tar.gz > "$CONTROL_ARCHIVE" 2>/dev/null; then
                            CANDIDATE_SB_VERSION="$(
                                tar -xzOf "$CONTROL_ARCHIVE" ./control 2>/dev/null |
                                sed -n 's/^Version:[[:space:]]*//p' |
                                head -n 1
                            )"
                        fi
                        ;;
                esac

                if [ -n "$CANDIDATE_SB_VERSION" ]; then

                    if version_is_newer "$INSTALLED_SB_VERSION" "$CANDIDATE_SB_VERSION"; then
                        SINGBOX_NEEDS_UPDATE=1
                        ok "Доступно обновление sing-box-extended: $INSTALLED_SB_VERSION -> $CANDIDATE_SB_VERSION."
                    else
                        SINGBOX_STATUS="OK"
                        ok "sing-box-extended уже установлен и актуален."
                    fi

                else

                    fail "Не удалось определить версию пакета sing-box-extended."

                fi

            else

                SINGBOX_NEEDS_UPDATE=1

            fi


            if [ "$SINGBOX_NEEDS_UPDATE" -eq 1 ]; then

                case "$PKG_MANAGER" in
                    apk)
                        if apk add --allow-untrusted "$SINGBOX_FILE"; then
                            SINGBOX_STATUS="OK"
                            ok "sing-box-extended установлен/обновлён."
                        else
                            fail "Не удалось установить sing-box-extended."
                        fi
                        ;;
                    opkg)
                        if opkg install "$SINGBOX_FILE"; then
                            SINGBOX_STATUS="OK"
                            ok "sing-box-extended установлен/обновлён."
                        else
                            fail "Не удалось установить sing-box-extended."
                        fi
                        ;;
                esac

            fi

        fi
    fi

else

    SINGBOX_STATUS="SKIPPED"

fi




if [ "$FLASH_OK" -eq 1 ]; then

    log "NETSHIFT" "Проверка NetShift"

    NETSHIFT_NEEDS_UPDATE=0

    if ! pkg_installed "sing-box-extended"; then

        NETSHIFT_STATUS="FAILED"
        fail "NetShift не устанавливается: sing-box-extended не установлен."

    else

        if ! pkg_installed "netshift"; then
            NETSHIFT_NEEDS_UPDATE=1
        elif package_needs_update "netshift"; then
            NETSHIFT_NEEDS_UPDATE=1
        fi

        if ! pkg_installed "luci-app-netshift"; then
            NETSHIFT_NEEDS_UPDATE=1
        elif package_needs_update "luci-app-netshift"; then
            NETSHIFT_NEEDS_UPDATE=1
        fi

        if ! pkg_installed "luci-i18n-netshift-ru"; then
            NETSHIFT_NEEDS_UPDATE=1
        elif package_needs_update "luci-i18n-netshift-ru"; then
            NETSHIFT_NEEDS_UPDATE=1
        fi


        if [ "$NETSHIFT_NEEDS_UPDATE" -eq 0 ]; then

            NETSHIFT_STATUS="OK"
            ok "NetShift уже установлен и актуален."

        else

            if run_remote_installer "$NETSHIFT_INSTALL_URL"; then

                if pkg_installed "netshift" &&
                    pkg_installed "luci-app-netshift" &&
                    pkg_installed "luci-i18n-netshift-ru"; then

                    NETSHIFT_STATUS="OK"
                    ok "NetShift установлен/обновлён."

                else

                    NETSHIFT_STATUS="FAILED"
                    fail "NetShift installer завершился, но не все пакеты NetShift установлены."

                fi

            else

                NETSHIFT_STATUS="FAILED"
                fail "Не удалось запустить установщик NetShift."

            fi

        fi

    fi

else

    NETSHIFT_STATUS="SKIPPED"

fi




log "SING-BOX" "Проверка установленного sing-box"

if pkg_installed "sing-box"; then
    warn "Обычный пакет sing-box также установлен."
    warn "Это может конфликтовать с sing-box-extended."
fi




log "CRON" "Проверка ежедневной перезагрузки"

CRON_FILE="/etc/crontabs/root"
CRON_LINE="0 5 * * * /sbin/reboot"

if [ -f "$CRON_FILE" ] &&
    grep -Fqx "$CRON_LINE" "$CRON_FILE"; then

    CRON_STATUS="OK"
    ok "Ежедневная перезагрузка в 05:00 уже настроена."

else

    if printf '%s\n' "$CRON_LINE" >> "$CRON_FILE"; then
        CRON_STATUS="OK"
        ok "Ежедневная перезагрузка в 05:00 добавлена."
    else
        CRON_STATUS="FAILED"
        fail "Не удалось добавить задачу ежедневной перезагрузки."
    fi
fi

if [ "$CRON_STATUS" = "OK" ]; then
    if /etc/init.d/cron enable >/dev/null 2>&1 &&
        /etc/init.d/cron restart >/dev/null 2>&1; then
        ok "Служба cron включена и перезапущена."
    else
        CRON_STATUS="FAILED"
        fail "Не удалось перезапустить службу cron."
    fi
fi




log "ПРОВЕРКА" "Финальная проверка установки"

if pkg_installed "luci-i18n-base-ru"; then
    ok "luci-i18n-base-ru установлен."
else
    BASE_RU_STATUS="FAILED"
    fail "luci-i18n-base-ru не установлен."
fi


if pkg_installed "luci-theme-aurora" &&
    pkg_installed "luci-app-aurora-config" &&
    pkg_installed "luci-i18n-aurora-config-ru"; then

    ok "Все компоненты Aurora установлены."

else

    AURORA_STATUS="FAILED"
    fail "Не все компоненты Aurora установлены."

fi


if [ "$FLASH_OK" -eq 1 ]; then

    if pkg_installed "sing-box-extended"; then
        ok "sing-box-extended установлен."
    else
        SINGBOX_STATUS="FAILED"
        fail "sing-box-extended не установлен."
    fi


    if pkg_installed "netshift" &&
        pkg_installed "luci-app-netshift" &&
        pkg_installed "luci-i18n-netshift-ru"; then

        ok "Все компоненты NetShift установлены."

    else

        NETSHIFT_STATUS="FAILED"
        fail "Не все компоненты NetShift установлены."

    fi

else

    warn "Компоненты sing-box-extended и NetShift пропущены из-за недостаточной ёмкости флеш-памяти."

fi




printf '\n'
printf '=============================\n'
printf 'ИТОГ УСТАНОВКИ\n'
printf '=============================\n'

printf 'Обновление списков пакетов: %s\n' "$PACKAGES_UPDATE_STATUS"
printf 'Обновление пакетов:          %s\n' "$PACKAGES_STATUS"
printf 'Русский язык LuCI:           %s\n' "$BASE_RU_STATUS"
printf 'Aurora:                       %s\n' "$AURORA_STATUS"
printf 'sing-box-extended:            %s\n' "$SINGBOX_STATUS"
printf 'NetShift:                     %s\n' "$NETSHIFT_STATUS"
printf 'Cron:                         %s\n' "$CRON_STATUS"

if [ "$FLASH_OK" -eq 0 ]; then
    printf '\n'
    warn "Флеш-память меньше требуемых ${MIN_FLASH_MB} MB."
    warn "sing-box-extended и NetShift не устанавливались/не обновлялись."
fi

printf '\n'
printf 'Готово.\n'
