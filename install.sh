#!/bin/sh

apk update && apk upgrade && apk add luci-i18n-base-ru || {
    echo "Ошибка установки базовых пакетов. WAN подключен? Ебало провайдера представили?"
    exit 1
}

# Добавление GitHub в hosts (обход блокировок)
git="github.com"; grep -q "^140.82.114.3 $git" /etc/hosts || {
    printf "#$git\n140.82.114.3 $git\n185.199.110.154 github.githubassets.com\n185.199.110.133 camo.githubassets.com\n" >> /etc/hosts
    /etc/init.d/dnsmasq restart 2>/dev/null
}
printf "Гитхаб разлочен\n"

# Скачивание и установка темы Aurora
wget -O - https://openwrt.eamonxg.fun/install.sh | sh || {
    echo "Ошибка загрузки темы Aurora. Скачаешь вручную после настройки NetShift"
    exit 1
}

# Установка sing-box-extended (последний релиз под архитектуру)
ARCH="aarch64_cortex-a53"
APK_URL=$(uclient-fetch -qO- "https://api.github.com/repos/shtorm-7/sing-box-extended/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*'"$ARCH"'[^"]*\.apk"' \
  | head -n1 | sed 's/.*"\(https[^"]*\)".*/\1/')

[ -z "$APK_URL" ] && {
    echo "APK под $ARCH не найден в последнем релизе"
    exit 1
}

echo "Качаю: $APK_URL"
cd /tmp || exit 1
uclient-fetch -O 1.apk "$APK_URL" || {
    echo "Ошибка загрузки signbox-extended"
    exit 1
}
apk add --allow-untrusted 1.apk || {
    echo "Ошибка установки signbox-extended"
    exit 1
}

# Очистка
rm -f /tmp/*.apk

# Установка netshift (основной скрипт)
wget -O - https://raw.githubusercontent.com/yandexru45/netshift/refs/heads/main/install.sh | sh || {
    echo "Ошибка установки netshift"
    exit 1
}
