#!/bin/sh
#
# install-dw5821e.sh  (v2 - full setup)
# One-shot installer for Dell DW5821e (Foxconn T77W968 / Qualcomm Snapdragon X20)
# on a clean OpenWrt 25.x (apk-based) router.
#
# Installs: MBIM drivers, AT-port drivers, sms-tool,
#           luci-app-3ginfo-lite + luci-app-sms-tool-js + luci-app-modemband
#           (from 4IceG apk repo) + optional Russian translations,
#           detects the MBIM control device, creates a ready-to-use MBIM
#           network interface (APN prompted at install time) in the firewall
#           WAN zone, wires all 4IceG panels to the AT port, and applies the
#           CRLF (\r) JSON fix that this Qualcomm modem needs.
#
# Port map on the DW5821e:
#   - MBIM control device (for the interface) : /dev/cdc-wdm0  (auto-detected)
#   - AT port (3ginfo / modemband / sms-tool) : /dev/ttyUSB1
#       (ttyUSB0 is a 2nd AT port, ttyUSB2 = GPS, ttyUSB3 = diag -> not used)
#
# Usage:
#   scp -O install-dw5821e.sh root@192.168.1.1:/tmp/
#   sh /tmp/install-dw5821e.sh
#
# Re-running is safe: every step is idempotent.

set -e

AT_PORT="/dev/ttyUSB1"          # DW5821e working AT port (ttyUSB2 is GPS, do NOT use)
MBIM_DEV_DEFAULT="/dev/cdc-wdm0" # MBIM control device for the interface
TGINFO="/usr/share/3ginfo-lite/3ginfo.sh"
FEEDS="/etc/apk/repositories.d/customfeeds.list"
KEYDIR="/etc/apk/keys"
REPO_ADB="https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/packages.adb"
REPO_KEY="https://github.com/4IceG/Modem-extras-apk/raw/refs/heads/main/myapk/IceG-apkpub.pem"

# --- Network interface settings --------------------------------------------
CREATE_INTERFACE="yes"          # yes | no  -- create the MBIM interface
IFACE_NAME="LTE_DELL_5821"      # interface (and UCI section) name
FW_ZONE="wan"                   # firewall zone to place the interface into
APN_DEFAULT="internet"          # used if you just press Enter at the prompt
PDP_TYPE="ipv4v6"               # ipv4 | ipv6 | ipv4v6 (dual-stack)
PIN_CODE=""                     # SIM PIN, leave empty if the SIM has none

# --- 4IceG panel settings --------------------------------------------------
SMS_PREFIX="7"                  # country dialing prefix for sms-tool (48=PL, 7=RU)

say() { echo ""; echo ">>> $1"; }

# --- Ask for the APN up front so the rest can run unattended ---------------
APN="$APN_DEFAULT"
if [ "$CREATE_INTERFACE" = "yes" ]; then
    printf 'APN for the LTE interface [%s]: ' "$APN_DEFAULT"
    read -r apn_input || apn_input=""
    [ -n "$apn_input" ] && APN="$apn_input"
    echo "   using APN: $APN"
fi

# --- Ask whether to install Russian translations ---------------------------
# Covers all three 4IceG panels: 3ginfo-lite, sms-tool-js and modemband.
INSTALL_RU="yes"
printf 'Install Russian translations for the 4IceG panels? [Y/n]: '
read -r ru_input || ru_input=""
case "$ru_input" in
    [Nn]*) INSTALL_RU="no" ;;
    *)     INSTALL_RU="yes" ;;
esac
echo "   Russian translations: $INSTALL_RU"

# --- 1. Drivers: MBIM stack + AT serial ports ------------------------------
say "Step 1: installing modem drivers (MBIM + serial AT ports)"
apk update
apk add kmod-usb-net-cdc-mbim umbim luci-proto-mbim
apk add sms-tool kmod-usb-serial kmod-usb-serial-option

# --- 2. Add 4IceG apk repository (idempotent) ------------------------------
say "Step 2: adding 4IceG apk repository"
if ! grep -qF "$REPO_ADB" "$FEEDS" 2>/dev/null; then
    echo "$REPO_ADB" >> "$FEEDS"
    echo "   repo line added"
else
    echo "   repo line already present, skipping"
fi

mkdir -p "$KEYDIR"
if [ ! -s "$KEYDIR/IceG-apkpub.pem" ]; then
    wget "$REPO_KEY" -O "$KEYDIR/IceG-apkpub.pem"
    echo "   signing key installed"
else
    echo "   signing key already present, skipping"
fi
apk update

# --- 3. Install the plugins ------------------------------------------------
say "Step 3: installing 3ginfo-lite, sms-tool-js and modemband"
apk add luci-app-3ginfo-lite
apk add luci-app-sms-tool-js
# modemband: GUI band-locking (drives AT^SLBAND under the hood on this modem).
apk add luci-app-modemband

if [ "$INSTALL_RU" = "yes" ]; then
    say "Step 3: installing Russian translations"
    # Installed best-effort: a missing -ru package can't abort the run.
    apk add luci-i18n-3ginfo-lite-ru  || echo "   (3ginfo RU not in feed, skipping)"
    apk add luci-i18n-sms-tool-js-ru  || echo "   (sms-tool-js RU not in feed, skipping)"
    apk add luci-i18n-modemband-ru    || echo "   (modemband RU not in feed, skipping)"
fi

# --- 4. Detect MBIM device + set the AT port -------------------------------
# The interface needs the MBIM control device (/dev/cdc-wdm*). The AT panels
# need the serial AT port, which on the DW5821e is a fixed /dev/ttyUSB1.
say "Step 4: detecting MBIM control device"
MBIM_DEV=""
for d in /dev/cdc-wdm0 /dev/cdc-wdm1 /dev/cdc-wdm2; do
    [ -c "$d" ] && { MBIM_DEV="$d"; break; }
done
[ -n "$MBIM_DEV" ] || MBIM_DEV="$MBIM_DEV_DEFAULT"
echo "   MBIM device: $MBIM_DEV"
echo "   AT port    : $AT_PORT"
if ! [ -c "$MBIM_DEV" ]; then
    echo "   NOTE: $MBIM_DEV not present yet (modem may enumerate after reboot)."
    echo "   Verify after reboot with:  ls -l /dev/cdc-wdm*"
fi

# 3ginfo-lite: AT port + bind to the LTE interface (instead of wan).
uci set 3ginfo.@3ginfo[0].device="$AT_PORT"
[ "$CREATE_INTERFACE" = "yes" ] && uci set 3ginfo.@3ginfo[0].network="$IFACE_NAME"
uci commit 3ginfo

# --- 5. Create the MBIM network interface ----------------------------------
# Builds a ready-to-use interface: proto=mbim, the MBIM control device,
# the APN entered above, and membership in the WAN firewall zone.
if [ "$CREATE_INTERFACE" = "yes" ]; then
    say "Step 5: creating interface '$IFACE_NAME' (proto mbim, device $MBIM_DEV, APN $APN)"

    uci set network."$IFACE_NAME"=interface
    uci set network."$IFACE_NAME".proto='mbim'
    uci set network."$IFACE_NAME".device="$MBIM_DEV"
    uci set network."$IFACE_NAME".apn="$APN"
    uci set network."$IFACE_NAME".pdptype="$PDP_TYPE"
    uci set network."$IFACE_NAME".auth='none'
    if [ -n "$PIN_CODE" ]; then
        uci set network."$IFACE_NAME".pincode="$PIN_CODE"
    fi
    uci commit network

    # Put the interface into the firewall zone (default: wan).
    ZONE_SECT="$(uci show firewall 2>/dev/null | grep "\.name='${FW_ZONE}'" | head -n1 | sed "s/\.name='${FW_ZONE}'.*//")"
    if [ -n "$ZONE_SECT" ]; then
        uci -q del_list "${ZONE_SECT}".network="$IFACE_NAME"   # avoid duplicates
        uci add_list "${ZONE_SECT}".network="$IFACE_NAME"
        uci commit firewall
        echo "   added '$IFACE_NAME' to firewall zone '$FW_ZONE'"
    else
        echo "   WARNING: firewall zone '$FW_ZONE' not found."
        echo "   Add '$IFACE_NAME' to a WAN zone manually in LuCI -> Firewall."
    fi
fi

# --- 6. Configure the 4IceG panels (modemband + sms-tool) ------------------
# Point modemband and sms-tool at the AT port, bind modemband to the LTE
# interface, and set the SMS dialing prefix. Each block is guarded on its
# config file so a skipped/absent panel can't abort the run.
say "Step 6: configuring 4IceG panels (AT port $AT_PORT)"

if [ -f /etc/config/modemband ]; then
    uci set modemband.@modemband[0].set_port="$AT_PORT"
    if [ "$CREATE_INTERFACE" = "yes" ]; then
        uci set modemband.@modemband[0].iface="$IFACE_NAME"
        uci commit modemband
        echo "   modemband: port=$AT_PORT, iface=$IFACE_NAME"
    else
        uci commit modemband
        echo "   modemband: port=$AT_PORT"
    fi
fi

if [ -f /etc/config/sms_tool_js ]; then
    S="sms_tool_js.@sms_tool_js[0]"
    uci set "$S".pnumber="$SMS_PREFIX"
    # All five SMS/USSD/AT/call/read ports -> the AT port.
    uci set "$S".readport="$AT_PORT"    # чтение SMS
    uci set "$S".callport="$AT_PORT"    # журнал вызовов
    uci set "$S".sendport="$AT_PORT"    # отправка SMS
    uci set "$S".ussdport="$AT_PORT"    # USSD
    uci set "$S".atport="$AT_PORT"      # AT-команды
    uci commit sms_tool_js
    echo "   sms-tool: prefix=$SMS_PREFIX, all ports=$AT_PORT"
fi

# --- 7. SMS reception fix (boot-time init script) --------------------------
# In MBIM mode this Qualcomm modem does NOT persist the SMS routing settings
# across reboots: after a restart CPMS/CNMI reset and incoming SMS never reach
# sms-tool (sending still works). We install a boot script that waits for the
# AT port to answer, then routes incoming SMS to SIM storage (CPMS) and enables
# new-message indications (CNMI) - applied twice, since CPMS often doesn't
# "stick" on the first try right after boot.
say "Step 7: installing SMS reception init script"

cat > /etc/init.d/dw5821e-sms <<EOF
#!/bin/sh /etc/rc.common
START=99
boot() {
    (
        # wait until the AT port answers OK (up to ~60s)
        n=0
        while [ \$n -lt 30 ]; do
            sms_tool -d $AT_PORT at 'AT' 2>/dev/null | grep -q OK && break
            sleep 2; n=\$((n+1))
        done
        sleep 3
        sms_tool -d $AT_PORT at 'AT+CPMS="SM","SM","SM"' >/dev/null 2>&1
        sms_tool -d $AT_PORT at 'AT+CNMI=2,1,0,0,0'     >/dev/null 2>&1
        sleep 5
        sms_tool -d $AT_PORT at 'AT+CPMS="SM","SM","SM"' >/dev/null 2>&1
        sms_tool -d $AT_PORT at 'AT+CNMI=2,1,0,0,0'     >/dev/null 2>&1
    ) &
}
EOF
chmod +x /etc/init.d/dw5821e-sms
/etc/init.d/dw5821e-sms enable
echo "   installed /etc/init.d/dw5821e-sms (routes incoming SMS to SIM on boot)"

# Apply once now so reception works without waiting for the first reboot.
sms_tool -d "$AT_PORT" at 'AT+CPMS="SM","SM","SM"' >/dev/null 2>&1 || true
sms_tool -d "$AT_PORT" at 'AT+CNMI=2,1,0,0,0'     >/dev/null 2>&1 || true

# --- 8. Apply the CRLF (\r) JSON fix in sanitize_number() ------------------
# The modem returns CRLF line endings; a stray \r survives into the JSON and
# breaks JSON.parse() in the frontend. We patch every line ending in echo "$1"
# (the file has more than one) by appending | tr -d '\r\n'.
say "Step 8: applying CRLF (\\r) JSON fix"

if [ ! -f "$TGINFO" ]; then
    echo "   WARNING: $TGINFO not found, skipping fix"
elif ! grep -q 'echo "\$1"$' "$TGINFO"; then
    echo "   nothing to patch (all relevant lines already sanitize), skipping"
else
    cp -a "$TGINFO" "${TGINFO}.bak"
    sed -i "s#echo \"\$1\"\$#echo \"\$1\" | tr -d '\\\\r\\\\n'#" "$TGINFO"
    cp -a "$TGINFO" /root/3ginfo.sh.fixed
    if grep -q 'echo "\$1"$' "$TGINFO"; then
        echo "   WARNING: a bare 'echo \"\$1\"' line still remains - check manually:"
        grep -n 'echo "\$1"$' "$TGINFO" | sed 's/^/      /'
    else
        echo "   patched all matching lines; copy saved to /root/3ginfo.sh.fixed"
        echo "   result:"
        grep -n "| tr -d '" "$TGINFO" | sed 's/^/      /'
    fi
fi

# --- 9. Restart web UI -----------------------------------------------------
say "Step 9: restarting web interface"
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart

# --- 10. Reboot -------------------------------------------------------------
# A full reboot ensures modem drivers, ttyUSB/cdc-wdm ports and the web UI all
# come up cleanly. The reminder is printed BEFORE the countdown so there is
# time to read it (and cancel with Ctrl+C).
say "Step 10: installation complete"
echo "    После перезагрузки:"
echo "      - LuCI -> Network -> Interfaces: у '$IFACE_NAME' должны появиться Carrier/RX/TX."
echo "        Если Carrier остаётся 'Absent' — обычно дело в APN (исправь и Save & Apply)."
echo "      - LuCI -> Modem(s): обнови Ctrl+F5 для сигнала / оператора / бэнда."
echo "    Если 3ginfo не показывает данные модема — проверь AT-порт:"
echo "        sms_tool -d $AT_PORT at ATI"
echo "        uci set 3ginfo.@3ginfo[0].device=$AT_PORT; uci commit 3ginfo; /etc/init.d/uhttpd restart"

echo ""
echo ">>> Перезагрузка через 10 секунд (Ctrl+C — отмена)"
i=10
while [ "$i" -gt 0 ]; do
    printf '\r   перезагрузка через %2d с ... ' "$i"
    sleep 1
    i=$((i - 1))
done
echo ""
sync
reboot
