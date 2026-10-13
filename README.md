# Site Checker для OpenWrt

LuCI-панель для проверки доступности сайтов **с самого роутера OpenWrt**, а не из браузера. Проект вдохновлён практическим подходом к проверке URL из [StressOzz/Zapret-Manager](https://github.com/StressOzz/Zapret-Manager), но реализован как отдельная LuCI-панель.

## Возможности

- Раздел LuCI: **Services → Site availability** (Доступность сайтов).
- Проверка HTTP/HTTPS с роутера с учётом его DNS, маршрутизации и сетевых правил.
- Отображение статуса, задержки и HTTP-кода (реальные миллисекунды и HTTP-код при наличии `curl`; иначе доступен упрощённый fallback).
- Автообновление каждые 60 секунд.
- Редактируемый список до 30 адресов.
- Установка одной командой на OpenWrt 24.10 и 25.12. Совместимость зависит также от сборки и состава LuCI на конкретном устройстве.

## Установка

Подключись по SSH к роутеру и выполни от root. Установщик скачивается через jsDelivr по фиксированному коммиту, чтобы обойти устаревший кэш `raw.githubusercontent.com`:

```sh
wget -O /tmp/site-checker-install.sh https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@793ed67833519ddcb64931ec9f40a4f83223b017/install.sh && sh /tmp/site-checker-install.sh
```

Если команда `wget` недоступна, но установлен `curl`:

```sh
curl -fsSL https://cdn.jsdelivr.net/gh/TMN88/Site_Checker@793ed67833519ddcb64931ec9f40a4f83223b017/install.sh -o /tmp/site-checker-install.sh && sh /tmp/site-checker-install.sh
```

После установки открой LuCI → **Services → Site availability**.

## Удаление

Если файл установщика уже скачан:

```sh
sh /tmp/site-checker-install.sh --uninstall
```

Удаление сохраняет `/etc/config/sitecheck`. Для удаления конфига вручную удали его после деинсталляции.

## Сборка пакета

Папка `package/luci-app-sitecheck` содержит Makefile и исходники LuCI-приложения. Копируй её в `package/` подходящего SDK для своего target/subtarget, затем выполни:

```sh
make package/luci-app-sitecheck/compile V=s
```

Это исходный пакет, а не заранее собранный IPK/APK. Для сборки необходим SDK, соответствующий архитектуре роутера.

## Важные замечания

- Недоступность URL не обязательно означает блокировку: возможны ошибки DNS, TLS, маршрутизации, firewall или самого сервера.
- Результат теста с роутера не гарантирует, что клиентский трафик проходит те же правила, например политики Podkop.
- Перед запуском установщика ознакомься с его содержимым и запускай скрипты только из доверенного репозитория.
