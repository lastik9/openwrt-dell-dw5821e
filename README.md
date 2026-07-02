# openwrt-dell-dw5821e

Установщик модема **Dell DW5821e** (Foxconn T77W968 / Qualcomm Snapdragon X20 LTE) на **OpenWrt 25 (apk)**: разворачивает MBIM-драйверы, создаёт сетевой интерфейс и ставит панели [4IceG](https://github.com/4IceG) — `3ginfo-lite`, `sms-tool-js`, `modemband` — за один прогон на чистой системе.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

**Русский** · [English](README.en.md) · [中文](README.zh.md)

---

Скрипт устанавливает всё, что нужно для работы и мониторинга модема Dell DW5821e на OpenWrt 25, и сам создаёт готовый к работе интерфейс. Второй скрипт — деинсталлятор — начисто откатывает изменения (удобно для тестов без перепрошивки).

### Зачем

DW5821e — это M.2-модем на чипе Qualcomm Snapdragon X20 LTE (Cat16). Он работает через протокол **MBIM** (`/dev/cdc-wdm0`), а его AT-порт — это `option`/`ttyUSB*`. У модема **два** AT-порта (`ttyUSB0` и `ttyUSB1`, оба отвечают `OK`), при этом полную телеметрию отдаёт `ttyUSB1`; `ttyUSB2` — это GPS/NMEA, `ttyUSB3` — диагностика. Чтобы поднять модем на OpenWrt и снимать данные, нужен строго определённый набор пакетов и правильная привязка портов/интерфейса. Скрипт всё это разворачивает автоматически, настраивает панели 4IceG под нужный порт и лечит специфичную для этого модема болячку с невалидным JSON (см. «Известные болячки»).

### Что делает скрипт

1. Спрашивает **APN** (по умолчанию `internet`) и хотите ли ставить **русский язык** для панелей (`[Y/n]`).
2. Ставит MBIM-стек: `kmod-usb-net-cdc-mbim`, `umbim`, `luci-proto-mbim`, а также драйверы AT-портов (`kmod-usb-serial`, `kmod-usb-serial-option`) и `sms-tool`.
3. Подключает apk-репозиторий [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) и его ключ подписи (идемпотентно).
4. Ставит панели `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ русские локали, если выбрано).
5. **Определяет MBIM-устройство** (`/dev/cdc-wdm*`) для интерфейса; AT-порт для панелей фиксирован — `/dev/ttyUSB1` (рабочий порт этого модема).
6. Создаёт интерфейс **`LTE_DELL_5821`** (proto `mbim`, найденное cdc-wdm-устройство, введённый APN, `pdptype`) и добавляет его в firewall-зону `wan`.
7. Настраивает панели под нужные порты: 3ginfo (`device` = ttyUSB1 + `network` = LTE_DELL_5821), modemband (`set_port` + `iface`), sms-tool (5 портов), и меняет SMS-префикс на `7`.
8. Ставит init-скрипт **приёма SMS**: при загрузке ждёт готовности AT-порта и направляет входящие в память SIM (`CPMS`) с включением уведомлений (`CNMI`) — иначе в MBIM-режиме приём SMS не переживает перезагрузку.
9. Применяет **фикс `\r`** в `3ginfo.sh` — без него LuCI показывает красный баннер `Bad control character in string literal in JSON`.
10. Перезагружает роутер (с 10-секундным отсчётом и возможностью отмены `Ctrl+C`).

### Требования

- OpenWrt **25.x** с пакетным менеджером **apk** (для opkg-сборок скрипт не предназначен).
- Модем **Dell DW5821e / Foxconn T77W968**, воткнут и определился (порт `/dev/cdc-wdm0` и `/dev/ttyUSB*` присутствуют).
- **Интернет на роутере** на момент установки (через другой аплинк или уже поднятый модем) — качаются пакеты и ключи.
- Доступ по **SSH** и права root.

### Установка

Команды выполняются **на роутере** (по SSH):

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/install-dw5821e.sh
sh install-dw5821e.sh
```

После перезагрузки открой **LuCI → Network → Interfaces** (у `LTE_DELL_5821` должны появиться Carrier/RX/TX) и **LuCI → Modem(s)** (обнови Ctrl+F5 — сигнал, оператор, бэнд).

Настройки вынесены в переменные в шапке скрипта: имя интерфейса, firewall-зона, APN по умолчанию, тип PDP, PIN, SMS-префикс — при желании правятся в одном месте.

### Удаление

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/uninstall-dw5821e.sh
sh uninstall-dw5821e.sh
```

Деинсталлятор снимает интерфейс и его запись из firewall, удаляет пакеты (панели и их локали), чистит конфиги панелей, артефакты фикса `\r` и добавленный репозиторий/ключ, затем перезагружается. Драйверы модема по умолчанию **оставляются** (чтобы не оборвать связь); удаление включается флагом `REMOVE_DRIVERS=yes` в шапке. Безопасен к повторному запуску.

### Известные болячки

- **Красный баннер `Bad control character in string literal in JSON`** — главная болячка этого модема. AT-ответы Qualcomm приходят с `\r` (CRLF), символ просачивается в JSON и ломает разбор в LuCI. Скрипт лечит это автоматически (шаг 8), добавляя `| tr -d '\r\n'` в функцию `sanitize_number()` в `3ginfo.sh`. При обновлении плагина фикс нужно накатить заново — скрипт сохраняет рабочую копию в `/root/3ginfo.sh.fixed`. Подробности: [issue #121](https://github.com/4IceG/luci-app-3ginfo-lite/issues/121).
- **`Carrier: Absent` после установки** — почти всегда неверный **APN**. Он зависит от оператора: скрипт по умолчанию ставит `internet`, но у части тарифов он другой. Исправь APN в интерфейсе и `Save & Apply`.
- **3ginfo не показывает данные** — проверь AT-порт. У DW5821e рабочий порт `/dev/ttyUSB1` (не ttyUSB2 — там GPS). Команда проверки: `sms_tool -d /dev/ttyUSB1 at ATI`.
- **Не приходят входящие SMS** — в MBIM-режиме Qualcomm-модем не сохраняет настройки маршрутизации SMS между перезагрузками: после ребута сбрасываются `CPMS`/`CNMI`, и входящие не доходят до sms-tool (отправка при этом работает). Скрипт ставит init-скрипт `/etc/init.d/dw5821e-sms`, который при загрузке дожидается порта и заново задаёт `AT+CPMS="SM","SM","SM"` + `AT+CNMI=2,1,0,0,0`. Если приём всё же не работает — проверь `AT+CNMI?` (должно быть `2,1,0,0,0`) и `AT+CEREG?` (второй параметр `1` = зарегистрирован).
- **Долгая регистрация после отключения питания** — после полного обесточивания (power-cycle) модем делает холодный поиск сети, и регистрация в LTE + подъём интернета занимают до пары минут (дольше, чем после обычного `reboot`). Это нормальное поведение модема; SMS тоже начинают приходить после завершения регистрации, не сразу.
- **Лок бэндов** через modemband или `AT^SLBAND` — осторожно: если залочить бэнд, которого нет в твоей точке, модем не зарегистрируется. Проверка текущей лочки: `AT^SLBAND?`; сброс: `AT^SLBAND`. На прошивках Foxconn смена бэндов вступает в силу **только после перезагрузки** модема. На части прошивок проприетарные AT-команды могут возвращать ошибку — тогда управление бэндами недоступно.
- **Правишь скрипты на Windows?** Сохраняй в переводах строк **LF (Unix)**. CRLF в `#!/bin/sh` ломает запуск на роутере. В репозитории это подстраховано файлом `.gitattributes`.

### Диагностика

```sh
ls -l /dev/cdc-wdm* /dev/ttyUSB*                     # устройства модема
sms_tool -d /dev/ttyUSB1 at 'ATI'                    # ответ модема
sms_tool -d /dev/ttyUSB1 at 'AT+CESQ'                # сигнал (RSRP/RSRQ)
sms_tool -d /dev/ttyUSB1 at 'AT+COPS?'               # оператор
sms_tool -d /dev/ttyUSB1 at 'AT^SLBAND?'             # текущая лочка бэндов
uci show network.LTE_DELL_5821                       # конфиг интерфейса
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_DELL_5821 | grep -i up                  # поднят ли интерфейс
logread | grep -i mbim                               # лог протокола MBIM
```

### Проверено на

OpenWrt 25.12.x (mediatek/filogic, `aarch64_cortex-a53`), модем Dell DW5821e (Snapdragon X20 LTE).

### Благодарности

Проект — лишь установщик. Основная работа сделана в проектах **[4IceG](https://github.com/4IceG)**:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — панель мониторинга модема
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT-команды
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — управление LTE-диапазонами
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk-репозиторий пакетов

Устанавливаемые компоненты — собственность их авторов и распространяются под их лицензиями. Лицензия MIT покрывает только код этого установщика.

### Лицензия

[MIT](LICENSE) © 2026 lastik9
