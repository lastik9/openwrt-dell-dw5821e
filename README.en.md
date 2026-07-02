# openwrt-dell-dw5821e

Installer for the **Dell DW5821e** (Foxconn T77W968 / Qualcomm Snapdragon X20 LTE) modem on **OpenWrt 25 (apk)**: sets up the MBIM drivers, creates a network interface, and installs the [4IceG](https://github.com/4IceG) panels — `3ginfo-lite`, `sms-tool-js`, `modemband` — in a single run on a clean system.

![OpenWrt](https://img.shields.io/badge/OpenWrt-25.x%20(apk)-blue)
![Shell](https://img.shields.io/badge/shell-POSIX%20sh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

[Русский](README.md) · **English** · [中文](README.zh.md)

---

The installer sets up everything needed to run and monitor the Dell DW5821e on OpenWrt 25 and builds a ready-to-use interface. A second script — the uninstaller — cleanly reverts every change (handy for testing without reflashing).

### Why

The DW5821e is an M.2 modem based on the Qualcomm Snapdragon X20 LTE (Cat16). It runs over the **MBIM** protocol (`/dev/cdc-wdm0`), while its AT port is an `option`/`ttyUSB*` device. The modem exposes **two** AT ports (`ttyUSB0` and `ttyUSB1`, both answer `OK`), but full telemetry comes from `ttyUSB1`; `ttyUSB2` is GPS/NMEA and `ttyUSB3` is diagnostics. Bringing it up on OpenWrt and reading its data requires a specific package set and correct port/interface wiring. The script does all of that automatically, points the 4IceG panels at the right port, and fixes a modem-specific malformed-JSON bug (see "Known issues").

### What the script does

1. Prompts for the **APN** (default `internet`) and whether to install the **Russian** panel translations (`[Y/n]`).
2. Installs the MBIM stack: `kmod-usb-net-cdc-mbim`, `umbim`, `luci-proto-mbim`, plus the AT-port drivers (`kmod-usb-serial`, `kmod-usb-serial-option`) and `sms-tool`.
3. Adds the [4IceG/Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) apk repository and its signing key (idempotent).
4. Installs `luci-app-3ginfo-lite`, `luci-app-sms-tool-js`, `luci-app-modemband` (+ Russian locales if selected).
5. **Detects the MBIM device** (`/dev/cdc-wdm*`) for the interface; the AT port for the panels is fixed to `/dev/ttyUSB1` (this modem's working port).
6. Creates the **`LTE_DELL_5821`** interface (proto `mbim`, the detected cdc-wdm device, the entered APN, `pdptype`) and adds it to the `wan` firewall zone.
7. Wires the panels to the right ports: 3ginfo (`device` = ttyUSB1 + `network` = LTE_DELL_5821), modemband (`set_port` + `iface`), sms-tool (5 ports), and sets the SMS prefix to `7`.
8. Installs an **SMS reception** init script: on boot it waits for the AT port, then routes incoming SMS to SIM storage (`CPMS`) and enables new-message indications (`CNMI`) — otherwise SMS reception doesn't survive a reboot in MBIM mode.
9. Applies the **`\r` fix** in `3ginfo.sh` — without it LuCI shows a red `Bad control character in string literal in JSON` banner.
10. Reboots the router (10-second countdown, cancellable with `Ctrl+C`).

### Requirements

- OpenWrt **25.x** with the **apk** package manager (not for opkg builds).
- A **Dell DW5821e / Foxconn T77W968** modem, plugged in and enumerated (`/dev/cdc-wdm0` and `/dev/ttyUSB*` present).
- **Internet on the router** at install time (via another uplink or the already-working modem) — packages and keys are downloaded.
- **SSH** access with root.

### Install

Run **on the router** (over SSH):

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/install-dw5821e.sh
sh install-dw5821e.sh
```

After the reboot, open **LuCI → Network → Interfaces** (`LTE_DELL_5821` should show Carrier/RX/TX) and **LuCI → Modem(s)** (hard-refresh with Ctrl+F5 — signal, operator, band).

Settings are exposed as variables at the top of the script: interface name, firewall zone, default APN, PDP type, PIN, SMS prefix — all editable in one place.

### Uninstall

```sh
wget https://raw.githubusercontent.com/lastik9/openwrt-dell-dw5821e/main/uninstall-dw5821e.sh
sh uninstall-dw5821e.sh
```

The uninstaller removes the interface and its firewall entry, deletes the packages (panels and locales), cleans up the panel configs, the `\r`-fix artifacts and the added repo/key, then reboots. Modem drivers are **kept** by default (so your link doesn't drop); enable their removal with `REMOVE_DRIVERS=yes` at the top. Safe to re-run.

### Known issues

- **Red `Bad control character in string literal in JSON` banner** — the main quirk of this modem. Qualcomm AT responses use CRLF, and a stray `\r` leaks into the JSON and breaks parsing in LuCI. The script fixes this automatically (step 8) by appending `| tr -d '\r\n'` to `sanitize_number()` in `3ginfo.sh`. After a plugin upgrade the fix must be re-applied — the script saves a working copy at `/root/3ginfo.sh.fixed`. Details: [issue #121](https://github.com/4IceG/luci-app-3ginfo-lite/issues/121).
- **`Carrier: Absent` after install** — almost always the wrong **APN**. It depends on the carrier: the script defaults to `internet`, but some plans differ. Fix the APN on the interface and `Save & Apply`.
- **3ginfo shows no data** — check the AT port. On the DW5821e the working port is `/dev/ttyUSB1` (not ttyUSB2 — that's GPS). Check with: `sms_tool -d /dev/ttyUSB1 at ATI`.
- **Incoming SMS don't arrive** — in MBIM mode the Qualcomm modem doesn't persist SMS routing across reboots: `CPMS`/`CNMI` reset after a restart and incoming SMS never reach sms-tool (sending still works). The script installs `/etc/init.d/dw5821e-sms`, which waits for the port on boot and re-applies `AT+CPMS="SM","SM","SM"` + `AT+CNMI=2,1,0,0,0`. If reception still fails, check `AT+CNMI?` (should be `2,1,0,0,0`) and `AT+CEREG?` (second field `1` = registered).
- **Slow registration after a power-cycle** — after a full power-off the modem does a cold network scan, so LTE registration and internet can take up to a couple of minutes (longer than after a plain `reboot`). This is normal modem behaviour; SMS also start arriving once registration completes, not immediately.
- **Band locking** via modemband or `AT^SLBAND` — be careful: locking to a band that isn't present at your location will leave the modem unregistered. Check the current lock: `AT^SLBAND?`; reset: `AT^SLBAND`. On Foxconn firmware a band change takes effect **only after a modem reboot**. On some firmware the proprietary AT commands may return an error, in which case band control is unavailable.
- **Editing scripts on Windows?** Save with **LF (Unix)** line endings. A CRLF in `#!/bin/sh` breaks execution on the router. The repo guards this with `.gitattributes`.

### Diagnostics

```sh
ls -l /dev/cdc-wdm* /dev/ttyUSB*                     # modem devices
sms_tool -d /dev/ttyUSB1 at 'ATI'                    # modem response
sms_tool -d /dev/ttyUSB1 at 'AT+CESQ'                # signal (RSRP/RSRQ)
sms_tool -d /dev/ttyUSB1 at 'AT+COPS?'               # operator
sms_tool -d /dev/ttyUSB1 at 'AT^SLBAND?'             # current band lock
uci show network.LTE_DELL_5821                       # interface config
uci show 3ginfo; uci show modemband; uci show sms_tool_js
ifstatus LTE_DELL_5821 | grep -i up                  # is the interface up
logread | grep -i mbim                               # MBIM protocol log
```

### Tested on

OpenWrt 25.12.x (mediatek/filogic, `aarch64_cortex-a53`), Dell DW5821e (Snapdragon X20 LTE).

### Credits

This project is just an installer. The real work lives in the **[4IceG](https://github.com/4IceG)** projects:

- [luci-app-3ginfo-lite](https://github.com/4IceG/luci-app-3ginfo-lite) — modem monitoring panel
- [luci-app-sms-tool-js](https://github.com/4IceG/luci-app-sms-tool-js) — SMS / USSD / AT commands
- [luci-app-modemband](https://github.com/4IceG/luci-app-modemband) — LTE band control
- [Modem-extras-apk](https://github.com/4IceG/Modem-extras-apk) — apk package repository

The installed components are the property of their authors and distributed under their own licenses. The MIT license covers only this installer's code.

### License

[MIT](LICENSE) © 2026 lastik9
