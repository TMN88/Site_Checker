#!/bin/sh
# Site_Checker installer for OpenWrt 24.x and 25.x.
set -eu

# Pinned source revision, deliberately using jsDelivr rather than raw.githubusercontent.com
# because some routers/networks have returned stale cached raw files.
BASE="https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@76465ef0c7928a403cb6847de0dd62722899e8d7"

CTRL="/usr/lib/lua/luci/controller/sitecheck.lua"
VIEW="/usr/lib/lua/luci/view/sitecheck/index.htm"
HELPER="/usr/libexec/sitecheck-check"
ZAPRET_HELPER="/usr/libexec/sitecheck-check-zapret"
ZAPRET_SITES="/usr/libexec/sitecheck-system-sites"
CONF="/etc/config/sitecheck"
TMP="/tmp/site-checker.$$"

log() { printf '[Site_Checker] %s\n' "$*"; }
die() { log "ОШИБКА: $*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "Запусти этот скрипт от root."
[ -r /etc/openwrt_release ] || die "Этот скрипт предназначен для OpenWrt."
. /etc/openwrt_release
REL="${DISTRIB_RELEASE:-unknown}"
log "OpenWrt $REL; target: ${DISTRIB_TARGET:-unknown}; arch: ${DISTRIB_ARCH:-unknown}"
case "$REL" in
  24|24.*) PM="opkg" ;;
  25|25.*) PM="apk" ;;
  *) PM="" ; log "Предупреждение: скрипт предназначен для OpenWrt 24.10.x (opkg) и 25.12.x (apk); совместимость с $REL не подтверждена." ;;
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

cleanup_managed_failover() {
  # Remove only the legacy component explicitly marked as installed by
  # an older Site_Checker installer; leave unmarked services untouched.
  if [ -f /etc/site-checker-pvf-managed ]; then
    [ ! -x /etc/init.d/podkop-vpn-failover ] || {
      /etc/init.d/podkop-vpn-failover stop >/dev/null 2>&1 || true
      /etc/init.d/podkop-vpn-failover disable >/dev/null 2>&1 || true
    }
    rm -f /usr/bin/podkop-vpn-failover /usr/bin/podkop-vpn-failover-control
    rm -f /etc/init.d/podkop-vpn-failover /etc/site-checker-pvf-managed
    rm -f /usr/share/licenses/Site_Checker/PODKOP-VPN-FAILOVER-LICENSE
    log "Удалены компоненты устаревшей интеграции из предыдущей версии Site_Checker."
  fi
}

remove_app() {
  cleanup_managed_failover
  rm -f "$CTRL" "$VIEW" "$HELPER" "$ZAPRET_HELPER" "$ZAPRET_SITES"
  rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
  [ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
  [ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
  log "Site_Checker удалён; конфигурация $CONF сохранена."
}
if [ "${1:-}" = "--uninstall" ]; then remove_app; exit 0; fi


cleanup_managed_failover

if [ "$PM" = "apk" ] && ! command -v apk >/dev/null 2>&1; then die "Для OpenWrt 25.x не найден apk."; fi
if [ "$PM" = "opkg" ] && ! command -v opkg >/dev/null 2>&1; then die "Для OpenWrt 24.x не найден opkg."; fi
if [ -z "$PM" ]; then
  if command -v apk >/dev/null 2>&1; then PM=apk
  elif command -v opkg >/dev/null 2>&1; then PM=opkg
  else die "Не найден менеджер пакетов apk или opkg."; fi
fi

# Install dependencies with the package manager native to this OpenWrt branch
# (apk for OpenWrt 25.12+, opkg for OpenWrt 24.10).
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
fetch "$BASE/files/sitecheck-check-zapret" "$TMP/sitecheck-check-zapret" || die "Не удалось загрузить дополнительный проверяющий скрипт."
fetch "$BASE/files/sitecheck-system-sites" "$TMP/sitecheck-system-sites" || die "Не удалось загрузить список и запускатель проверки Zapret Manager."
fetch "$BASE/files/sitecheck.conf" "$TMP/sitecheck.conf" || die "Не удалось загрузить конфигурацию по умолчанию."

for f in sitecheck.lua index.htm sitecheck-check sitecheck-check-zapret sitecheck-system-sites sitecheck.conf; do
  [ -s "$TMP/$f" ] || die "Загружен пустой файл: $f"
done
/bin/sh -n "$TMP/sitecheck-check" || die "Синтаксическая ошибка в sitecheck-check."
/bin/sh -n "$TMP/sitecheck-check-zapret" || die "Синтаксическая ошибка в sitecheck-check-zapret."
/bin/sh -n "$TMP/sitecheck-system-sites" || die "Синтаксическая ошибка в sitecheck-system-sites."
grep -q '^module("luci.controller.sitecheck"' "$TMP/sitecheck.lua" || die "Загруженный контроллер не распознан."
grep -q '^config sitecheck' "$TMP/sitecheck.conf" || die "Конфигурация сайта не прошла проверку содержимого."

cp "$TMP/sitecheck.lua" "$CTRL"; chmod 0644 "$CTRL"
cp "$TMP/index.htm" "$VIEW"; chmod 0644 "$VIEW"
cp "$TMP/sitecheck-check" "$HELPER"; chmod 0755 "$HELPER"
cp "$TMP/sitecheck-check-zapret" "$ZAPRET_HELPER"; chmod 0755 "$ZAPRET_HELPER"
cp "$TMP/sitecheck-system-sites" "$ZAPRET_SITES"; chmod 0755 "$ZAPRET_SITES"
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
