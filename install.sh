#!/bin/sh
# Site_Checker installer for OpenWrt 24.x and 25.x.
set -eu

# Pinned source revision, deliberately using jsDelivr rather than raw.githubusercontent.com
# because some routers/networks have returned stale cached raw files.
BASE="https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@25e9088564e8643ef049624cfa06905b0e8635fe"

CTRL="/usr/lib/lua/luci/controller/sitecheck.lua"
VIEW="/usr/lib/lua/luci/view/sitecheck/index.htm"
HELPER="/usr/libexec/sitecheck-check"
CONF="/etc/config/sitecheck"
LICENSE_DIR="/usr/share/licenses/Site_Checker"
PVF_WORKER="/usr/bin/podkop-vpn-failover"
PVF_CONTROL="/usr/bin/podkop-vpn-failover-control"
PVF_INIT="/etc/init.d/podkop-vpn-failover"
PVF_LICENSE="/usr/share/licenses/Site_Checker/PODKOP-VPN-FAILOVER-LICENSE"
PVF_MARKER="/etc/site-checker-pvf-managed"
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
  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -T 60 -O "$out" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 60 -O "$out" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL --connect-timeout 10 --max-time 60 "$url" -o "$out"
  else
    die "Не найден curl, wget или uclient-fetch для скачивания файлов."
  fi
}

remove_app() {
  if [ -f "$PVF_MARKER" ]; then
    [ ! -x "$PVF_INIT" ] || { "$PVF_INIT" stop >/dev/null 2>&1 || true; "$PVF_INIT" disable >/dev/null 2>&1 || true; }
    rm -f "$PVF_WORKER" "$PVF_CONTROL" "$PVF_INIT" "$PVF_MARKER" "$PVF_LICENSE"
    log "Удалены компоненты failover, установленные этим установщиком."
  else
    log "Существующая установка podkop-vpn-failover сохранена."
  fi
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

# The bundled AWG health-check worker uses curl. Install dependencies with the
# package manager native to this OpenWrt branch (apk for 25.12+, opkg for 24.10).
if [ "$PM" = apk ]; then
  MISSING=""
  for pkg in luci-base curl; do
    if ! apk info -e "$pkg" >/dev/null 2>&1; then MISSING="$MISSING $pkg"; fi
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
  /usr/libexec /etc/config /usr/bin /etc/init.d "$LICENSE_DIR"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM

fetch "$BASE/files/controller/sitecheck.lua" "$TMP/sitecheck.lua" || die "Не удалось загрузить контроллер."
fetch "$BASE/files/view/index.htm" "$TMP/index.htm" || die "Не удалось загрузить интерфейс."
fetch "$BASE/files/sitecheck-check" "$TMP/sitecheck-check" || die "Не удалось загрузить проверяющий скрипт."
fetch "$BASE/files/sitecheck.conf" "$TMP/sitecheck.conf" || die "Не удалось загрузить конфигурацию по умолчанию."
fetch "$BASE/files/podkop-vpn-failover" "$TMP/podkop-vpn-failover" || die "Не удалось загрузить podkop-vpn-failover."
fetch "$BASE/files/podkop-vpn-failover-control" "$TMP/podkop-vpn-failover-control" || die "Не удалось загрузить управляющий скрипт failover."
fetch "$BASE/files/podkop-vpn-failover.init" "$TMP/podkop-vpn-failover.init" || die "Не удалось загрузить init-скрипт failover."
fetch "$BASE/files/PODKOP-VPN-FAILOVER-LICENSE" "$TMP/PODKOP-VPN-FAILOVER-LICENSE" || die "Не удалось загрузить лицензию стороннего компонента."

for f in sitecheck.lua index.htm sitecheck-check sitecheck.conf podkop-vpn-failover podkop-vpn-failover-control podkop-vpn-failover.init PODKOP-VPN-FAILOVER-LICENSE; do
  [ -s "$TMP/$f" ] || die "Загружен пустой файл: $f"
done
/bin/sh -n "$TMP/sitecheck-check" || die "Синтаксическая ошибка в sitecheck-check."
/bin/sh -n "$TMP/podkop-vpn-failover" || die "Синтаксическая ошибка в podkop-vpn-failover."
/bin/sh -n "$TMP/podkop-vpn-failover-control" || die "Синтаксическая ошибка в управляющем скрипте failover."
/bin/sh -n "$TMP/podkop-vpn-failover.init" || die "Синтаксическая ошибка в init-скрипте failover."
grep -q '^# podkop-vpn-failover$' "$TMP/podkop-vpn-failover" || die "Файл failover не прошёл проверку содержимого."
grep -q 'id="pvf-panel"' "$TMP/index.htm" || die "Интерфейс не содержит панели AWG failover."

# Preserve a separately installed failover setup's state. On a fresh router,
# register ownership so --uninstall can remove only files introduced here.
PVF_WAS_PRESENT=0
PVF_WAS_RUNNING=0
PVF_WAS_ENABLED=0
if [ -e "$PVF_INIT" ] || [ -e "$PVF_WORKER" ] || [ -e "$PVF_CONTROL" ]; then
  PVF_WAS_PRESENT=1
fi
if [ -x "$PVF_INIT" ]; then
  "$PVF_INIT" running >/dev/null 2>&1 && PVF_WAS_RUNNING=1
  "$PVF_INIT" enabled >/dev/null 2>&1 && PVF_WAS_ENABLED=1
  log "Останавливаю сервис failover перед обновлением файлов."
  "$PVF_INIT" stop >/dev/null 2>&1 || true
fi

cp "$TMP/sitecheck.lua" "$CTRL"; chmod 0644 "$CTRL"
cp "$TMP/index.htm" "$VIEW"; chmod 0644 "$VIEW"
cp "$TMP/sitecheck-check" "$HELPER"; chmod 0755 "$HELPER"
if [ ! -f "$CONF" ]; then
  cp "$TMP/sitecheck.conf" "$CONF"; chmod 0644 "$CONF"
else
  log "Существующий $CONF сохранён без изменений."
fi

cp "$TMP/podkop-vpn-failover" "$PVF_WORKER"; chmod 0755 "$PVF_WORKER"
cp "$TMP/podkop-vpn-failover-control" "$PVF_CONTROL"; chmod 0755 "$PVF_CONTROL"
cp "$TMP/podkop-vpn-failover.init" "$PVF_INIT"; chmod 0755 "$PVF_INIT"
cp "$TMP/PODKOP-VPN-FAILOVER-LICENSE" "$PVF_LICENSE"; chmod 0644 "$PVF_LICENSE"

if [ "$PVF_WAS_PRESENT" -eq 0 ]; then
  printf '%s\n' "Installed by Site_Checker" > "$PVF_MARKER"
  chmod 0600 "$PVF_MARKER"
  # As in the upstream project, automatic failover is intentionally left off
  # until a user verifies all AWG tunnels and explicitly enables it.
  "$PVF_INIT" disable >/dev/null 2>&1 || true
  "$PVF_INIT" stop >/dev/null 2>&1 || true
  log "Новый AWG failover установлен, но оставлен выключенным для безопасной первичной проверки."
else
  if [ "$PVF_WAS_ENABLED" -eq 1 ]; then
    "$PVF_INIT" enable >/dev/null 2>&1 || die "Не удалось восстановить автозапуск failover."
  else
    "$PVF_INIT" disable >/dev/null 2>&1 || true
  fi
  if [ "$PVF_WAS_RUNNING" -eq 1 ]; then
    log "Восстанавливаю ранее работавший сервис failover."
    "$PVF_CONTROL" restart || die "Файлы обновлены, но failover не удалось перезапустить."
  else
    "$PVF_INIT" stop >/dev/null 2>&1 || true
  fi
fi

rm -f /tmp/luci-indexcache /tmp/luci-modulecache/* 2>/dev/null || true
[ ! -x /etc/init.d/rpcd ] || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
[ ! -x /etc/init.d/uhttpd ] || /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
log "Установка завершена. Открой LuCI → Services → Site_Checker."
log "В секции AWG / Podkop VPN Failover сначала нажми «Проверить все AWG», затем вручную включи failover."
log "Для удаления панели запусти install.sh с аргументом --uninstall; конфигурация сайтов и сторонняя установка failover сохраняются."
