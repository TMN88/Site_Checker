#!/bin/sh
# Site Checker bootstrap installer for OpenWrt 24.10 / 25.12.
set -eu

BASE="https://raw.githubusercontent.com/TMN88/Site_Checker/main"
CTRL="/usr/lib/lua/luci/controller/sitecheck.lua"
VIEW="/usr/lib/lua/luci/view/sitecheck/index.htm"
HELPER="/usr/libexec/sitecheck-check"
CONF="/etc/config/sitecheck"
TMP="/tmp/site-checker.$$"

log() { printf '[Site_Checker] %s\n' "$*"; }
die() { log "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Запусти этот скрипт от root."
[ -r /etc/openwrt_release ] || die "Эта панель предназначена для OpenWrt."
. /etc/openwrt_release
REL="${DISTRIB_RELEASE:-unknown}"
log "OpenWrt $REL; target: ${DISTRIB_TARGET:-unknown}; arch: ${DISTRIB_ARCH:-unknown}"
case "$REL" in 24.10*|25.12*) ;; *) log "Предупреждение: проверялась подготовка для 24.10/25.12; совместимость этой версии не подтверждена." ;; esac

fetch() {
  url="$1"; out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 60 -O "$out" "$url"
  elif command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -T 60 -O "$out" "$url"
  else
    die "Не найден curl, wget или uclient-fetch для скачивания файлов."
  fi
}

remove_app() {
  rm -f "$CTRL" "$VIEW" "$HELPER"
  rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
  [ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
  [ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  log "Панель удалена; конфигурация $CONF сохранена."
}
if [ "${1:-}" = "--uninstall" ]; then remove_app; exit 0; fi

PM=""
if command -v apk >/dev/null 2>&1; then PM=apk
elif command -v opkg >/dev/null 2>&1; then PM=opkg
else die "Не найден менеджер пакетов apk или opkg."; fi

mkdir -p "$TMP" /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/sitecheck /usr/libexec /etc/config
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

if [ "$PM" = apk ]; then
  if ! apk info -e luci-base >/dev/null 2>&1; then apk add luci-base || die "Не удалось установить luci-base."; fi
else
  if ! opkg status luci-base 2>/dev/null | grep -q '^Status:.* installed'; then
    opkg update
    opkg install luci-base || die "Не удалось установить luci-base."
  fi
fi

fetch "$BASE/files/controller/sitecheck.lua" "$TMP/sitecheck.lua" || die "Не удалось загрузить контроллер."
fetch "$BASE/files/view/index.htm" "$TMP/index.htm" || die "Не удалось загрузить интерфейс."
fetch "$BASE/files/sitecheck-check" "$TMP/sitecheck-check" || die "Не удалось загрузить проверяющий скрипт."
fetch "$BASE/files/sitecheck.conf" "$TMP/sitecheck.conf" || die "Не удалось загрузить конфигурацию по умолчанию."

install -m 0644 "$TMP/sitecheck.lua" "$CTRL"
install -m 0644 "$TMP/index.htm" "$VIEW"
install -m 0755 "$TMP/sitecheck-check" "$HELPER"
if [ ! -f "$CONF" ]; then
  install -m 0644 "$TMP/sitecheck.conf" "$CONF"
else
  log "Существующий $CONF не изменён."
fi

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
[ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
log "Установка завершена. Открой LuCI → Services → Site availability."
log "Для удаления снова запусти install.sh с аргументом --uninstall."
