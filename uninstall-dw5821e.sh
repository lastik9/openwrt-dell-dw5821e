#!/bin/sh
#
# uninstall-dw5821e.sh
# Reverses install-dw5821e.sh on OpenWrt 25.x (apk-based).
#
# Removes: the three 4IceG LuCI panels (+ their RU translations),
#          the LTE_DELL_5821 network interface and its firewall membership,
#          the 4IceG apk repository + signing key,
#          the CRLF-fix backups, and restores 3ginfo.sh from backup if present.
#
# By default it KEEPS the modem drivers (MBIM stack, serial modules, sms-tool),
# because removing them can drop your internet connection. Set REMOVE_DRIVERS=yes
# below if you really want a bare system.
#
# Usage:
#   scp -O uninstall-dw5821e.sh root@192.168.1.1:/tmp/
#   sh /tmp/uninstall-dw5821e.sh
#
# Re-running is safe: every step is idempotent.

# NOTE: no `set -e` here on purpose - uninstall should push through even if a
# given item is already gone.

IFACE_NAME="LTE_DELL_5821"
FW_ZONE="wan"
TGINFO="/usr/share/3ginfo-lite/3ginfo.sh"
FEEDS="/etc/apk/repositories.d/customfeeds.list"
KEY="/etc/apk/keys/IceG-apkpub.pem"
REPO_ADB="https://raw.githubusercontent.com/4IceG/Modem-extras-apk/main/myapk/packages.adb"

# --- What to remove --------------------------------------------------------
REMOVE_DRIVERS="no"     # yes -> also remove MBIM/serial drivers + sms-tool
REMOVE_REPO="yes"       # yes -> remove the 4IceG apk repo + signing key

say() { echo ""; echo ">>> $1"; }

# --- Confirm ---------------------------------------------------------------
echo "This will remove the 4IceG panels, the '$IFACE_NAME' interface,"
echo "the panel configs, and (optionally) the 4IceG repo."
[ "$REMOVE_DRIVERS" = "yes" ] && echo "It will ALSO remove modem drivers (may drop your connection!)."
printf 'Proceed? [y/N]: '
read -r ans || ans=""
case "$ans" in
    [Yy]*) : ;;
    *) echo "Aborted."; exit 0 ;;
esac

# --- 1. Remove the LuCI panels (+ RU translations) -------------------------
say "Step 1: removing 4IceG LuCI panels"
for pkg in \
    luci-i18n-3ginfo-lite-ru  luci-app-3ginfo-lite \
    luci-i18n-sms-tool-js-ru  luci-app-sms-tool-js \
    luci-i18n-modemband-ru    luci-app-modemband
do
    if apk info -e "$pkg" >/dev/null 2>&1; then
        apk del "$pkg" 2>/dev/null && echo "   removed $pkg"
    fi
done

# --- 2. Remove the network interface + firewall membership -----------------
say "Step 2: removing interface '$IFACE_NAME'"
if uci -q get network."$IFACE_NAME" >/dev/null 2>&1; then
    uci -q delete network."$IFACE_NAME"
    uci commit network
    echo "   deleted network.$IFACE_NAME"
else
    echo "   network.$IFACE_NAME not present, skipping"
fi

# Drop it from the firewall zone's network list.
ZONE_SECT="$(uci show firewall 2>/dev/null | grep "\.name='${FW_ZONE}'" | head -n1 | sed "s/\.name='${FW_ZONE}'.*//")"
if [ -n "$ZONE_SECT" ]; then
    uci -q del_list "${ZONE_SECT}".network="$IFACE_NAME"
    uci commit firewall
    echo "   removed '$IFACE_NAME' from firewall zone '$FW_ZONE'"
fi

# --- 3. Remove leftover panel configs --------------------------------------
# apk del usually removes these; delete any that linger so a later reinstall
# starts clean.
say "Step 3: removing leftover panel configs"
for cfg in /etc/config/3ginfo /etc/config/modemband /etc/config/sms_tool_js; do
    [ -f "$cfg" ] && rm -f "$cfg" && echo "   removed $cfg"
done

# --- 4. Restore / clean up 3ginfo.sh and its backups -----------------------
say "Step 4: removing SMS reception init script + CRLF-fix artifacts"
if [ -f /etc/init.d/dw5821e-sms ]; then
    /etc/init.d/dw5821e-sms disable 2>/dev/null
    rm -f /etc/init.d/dw5821e-sms && echo "   removed /etc/init.d/dw5821e-sms"
fi
if [ -f "${TGINFO}.bak" ]; then
    # If the package is gone the file may already be removed; only restore if
    # the live file still exists (i.e. package was kept for some reason).
    [ -f "$TGINFO" ] && cp -a "${TGINFO}.bak" "$TGINFO" && echo "   restored $TGINFO from .bak"
    rm -f "${TGINFO}.bak" && echo "   removed ${TGINFO}.bak"
fi
[ -f /root/3ginfo.sh.fixed ] && rm -f /root/3ginfo.sh.fixed && echo "   removed /root/3ginfo.sh.fixed"

# --- 5. Remove the 4IceG apk repository + key ------------------------------
if [ "$REMOVE_REPO" = "yes" ]; then
    say "Step 5: removing 4IceG apk repository"
    # Match by substring, NOT by exact line: the feed URL has changed over
    # versions (github.com/.../raw redirect -> direct raw.githubusercontent.com).
    # An exact grep -vF against one URL would leave the other form stranded in
    # customfeeds.list, breaking every later apk update. The substring covers both.
    if [ -f "$FEEDS" ] && grep -q '4IceG/Modem-extras-apk' "$FEEDS" 2>/dev/null; then
        sed -i '\#4IceG/Modem-extras-apk#d' "$FEEDS"
        echo "   removed repo line from $FEEDS"
    else
        echo "   repo line not present, skipping"
    fi
    [ -f "$KEY" ] && rm -f "$KEY" && echo "   removed signing key $KEY"
    apk update 2>/dev/null || true
fi

# --- 6. Optionally remove modem drivers ------------------------------------
if [ "$REMOVE_DRIVERS" = "yes" ]; then
    say "Step 6: removing modem drivers (connection may drop)"
    for pkg in \
        sms-tool \
        luci-proto-mbim umbim kmod-usb-net-cdc-mbim \
        kmod-usb-serial-option kmod-usb-serial
    do
        if apk info -e "$pkg" >/dev/null 2>&1; then
            apk del "$pkg" 2>/dev/null && echo "   removed $pkg"
        fi
    done
else
    say "Step 6: keeping modem drivers (REMOVE_DRIVERS=no)"
    echo "   MBIM stack, serial modules and sms-tool left in place."
fi

# --- 7. Restart web UI -----------------------------------------------------
say "Step 7: restarting web interface"
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

# --- 8. Reboot -------------------------------------------------------------
say "Step 8: удаление завершено"
echo "    Удалены:"
echo "      - панели 4IceG (3ginfo-lite, sms-tool-js, modemband) и переводы"
echo "      - интерфейс '$IFACE_NAME' и его правило в firewall-зоне '$FW_ZONE'"
echo "      - конфиги панелей и артефакты фикса \\r"
[ "$REMOVE_REPO" = "yes" ]    && echo "      - репозиторий 4IceG и ключ подписи"
[ "$REMOVE_DRIVERS" = "yes" ] && echo "      - драйверы модема (MBIM + serial + sms-tool)"
[ "$REMOVE_DRIVERS" = "yes" ] || echo "    Драйверы модема оставлены (REMOVE_DRIVERS=no)."
echo "    Перезагрузка очистит остаточное состояние ядра и портов."

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
