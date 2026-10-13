#!/bin/sh
# Site_Checker installer for OpenWrt 24.x and 25.x.
set -eu

# Pinned source revision, deliberately using jsDelivr rather than raw.githubusercontent.com
# because some routers/networks have returned stale cached raw files.
BASE="https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@3030d72203338d855956f1b692ea84b784b74baf"

CTRL="/usr/lib/lua/luci/controller/sitecheck.lua"
VIEW="/usr/lib/lua/luci/view/sitecheck/index.htm"
HELPER="/usr/libexec/sitecheck-check"
CONF="/etc/config/sitecheck"
LICENSE_DIR="/usr/share/licenses/Site_Checker"
TMP="/tmp/site-checker.$$"

log() { printf '[Site_Checker] %s\n' "$*"; }
die() { log "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Запусти этот скрипт от root."
[ -r /etc/openwrt_release ] || die "Этот скрипт предназначен для OpenWrt."
. /etc/openwrt_release
REL="${DISTRIB_RELEASE:-unknown}"
log "OpenWrt $REL; target: ${DISTRIB_TARGET:-unknown}; arch: ${DISTRIB_ARCH:-unknown}"
case "$REL" in
  24|24.*|25|25.*) ;;
  *) log "Предупреждение: скрипт предназначен для веток OpenWrt 24.x и 25.x; совместимость с $REL не подтверждена." ;;
esac

fetch() {
  url="$1"; out="$2"
  rm -f "$out"
  if command -v uclient-fetch >/dev/null 2>&1 && uclient-fetch -q -T 60 -O "$out" "$url"; then
    return 0
  fi
  rm -f "$out"
  if command -v wget >/dev/null 2>&1 && wget -q -T 60 -O "$out" "$url"; then
    return 0
  fi
  rm -f "$out"
  if command -v curl >/dev/null 2>&1 && curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$out"; then
    return 0
  fi
  rm -f "$out"
  return 1
}

remove_app() {
  rm -f "$CTRL" "$VIEW" "$HELPER"
  rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
  [ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
  [ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  log "Site_Checker удалён; конфигурация $CONF сохранена."
}
if [ "${1:-}" = "--uninstall" ]; then remove_app; exit 0; fi

PM=""
if command -v apk >/dev/null 2>&1; then PM=apk
elif command -v opkg >/dev/null 2>&1; then PM=opkg
else die "Не найден менеджер пакетов apk или opkg."; fi

# Install dependencies with the package manager native to this OpenWrt branch
# (apk for 25.12+, opkg for 24.10).
if [ "$PM" = apk ]; then
  MISSING=""
  for pkg in luci-base curl; do
    if ! apk info 2>/dev/null | grep -Fxq "$pkg"; then MISSING="$MISSING $pkg"; fi
  done
  if [ -n "$MISSING" ]; then
    log "Обновление списка пакетов apk."
    apk update || die "Не удалось обновить список пакетов apk."
    # Intentional word splitting: MISSING is a space-separated package list.
    apk add $MISSING || die "Не удалось установить зависимости:$MISSING"
  fi
else
  pkg_installed() { opkg status "$1" 2>/dev/null | grep -q '^Status:.* installed'; }
  MISSING=""
  for pkg in luci-base curl; do
    if ! pkg_installed "$pkg"; then MISSING="$MISSING $pkg"; fi
  done
  if [ -n "$MISSING" ]; then
    log "Обновление списка пакетов opkg."
    opkg update || die "Не удалось обновить список пакетов opkg."
    # Intentional word splitting: MISSING is a space-separated package list.
    opkg install $MISSING || die "Не удалось установить зависимости:$MISSING"
  fi
fi

mkdir -p "$TMP" /usr/lib/lua/luci/controller /usr/lib/lua/luci/view/sitecheck \
  /usr/libexec /etc/config
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

fetch "$BASE/files/controller/sitecheck.lua" "$TMP/sitecheck.lua" || die "Не удалось загрузить контроллер."
fetch "$BASE/files/view/index.htm" "$TMP/index.htm" || die "Не удалось загрузить интерфейс."
fetch "$BASE/files/sitecheck-check" "$TMP/sitecheck-check" || die "Не удалось загрузить проверяющий скрипт."
fetch "$BASE/files/sitecheck.conf" "$TMP/sitecheck.conf" || die "Не удалось загрузить конфигурацию по умолчанию."

for f in sitecheck.lua index.htm sitecheck-check sitecheck.conf; do
  [ -s "$TMP/$f" ] || die "Загружен пустой файл: $f"
done
/bin/sh -n "$TMP/sitecheck-check" || die "Синтаксическая ошибка в sitecheck-check."
grep -q '^module("luci.controller.sitecheck"' "$TMP/sitecheck.lua" || die "Загруженный контроллер не распознан."
grep -q '^config sitecheck' "$TMP/sitecheck.conf" || die "Конфигурация сайта не прошла проверку содержимого."

cp "$TMP/sitecheck.lua" "$CTRL"; chmod 0644 "$CTRL"
cp "$TMP/index.htm" "$VIEW"; chmod 0644 "$VIEW"
cp "$TMP/sitecheck-check" "$HELPER"; chmod 0755 "$HELPER"
if [ ! -f "$CONF" ]; then
  cp "$TMP/sitecheck.conf" "$CONF"; chmod 0644 "$CONF"
else
  log "Существующий $CONF сохранён без изменений."
fi


rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
[ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
log "Установка завершена. Открой LuCI → Services → Site_Checker."
log "Для удаления Site_Checker запусти install.sh с аргументом --uninstall; конфигурация сайтов сохраняется."
