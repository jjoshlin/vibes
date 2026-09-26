#!/bin/bash
# PI_GPS offline installer: runs ONCE at boot, launched from cmdline.txt with
#   systemd.run=/boot/firmware/pigps-firstrun.sh systemd.run_success_action=reboot
#   systemd.unit=kernel-command-line.target
# Use it when the Pi is unreachable: copy this file and the pi/ files (into
# /boot/firmware/pigps-install/) onto the bootfs partition from a PC, add the
# arguments above to cmdline.txt, boot. It removes itself from cmdline.txt first,
# installs everything without needing network, logs to /boot/firmware/pigps-install.log
# and reboots into the normal system.
B=/boot/firmware
S=$B/pigps-install
exec >>"$B/pigps-install.log" 2>&1
echo "=== pigps-firstrun $(date -u +%FT%TZ)"

# 1. Never run twice: strip our arguments from cmdline.txt before anything else
sed -i -e 's| systemd.run=[^ ]*||g' -e 's| systemd.run_success_action=[^ ]*||g' \
       -e 's| systemd.run_failure_action=[^ ]*||g' -e 's| systemd.unit=kernel-command-line.target||g' \
       "$B/cmdline.txt"
echo "cmdline.txt: $(cat "$B/cmdline.txt")"

set -x
# 2. Scripts and units
install -m 755 "$S/pigps-logger"   /usr/local/bin/pigps-logger
install -m 755 "$S/pigps-timesync" /usr/local/bin/pigps-timesync
install -m 644 "$S/pigps-logger.service" "$S/pigps-timesync.service" \
               "$S/pigps-timesync.timer" "$S/pigps-clocksave.service" /etc/systemd/system/
install -d -o pigps -g pigps /home/pigps/tracks
systemctl daemon-reload
systemctl enable pigps-logger.service pigps-timesync.timer pigps-clocksave.service

# 3. gpsd -n only (no -r: GPS clock date is unreliable before a fix), chrony NMEA offset
sed -i 's/^GPSD_OPTIONS=.*/GPSD_OPTIONS="-n"/' /etc/default/gpsd
sed -i 's/refid NMEA offset [0-9.]*/refid NMEA offset 0.135/' /etc/chrony/conf.d/gps.conf

# 4. Persistent journal
install -d /var/log/journal /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\nSystemMaxUse=50M\n' > /etc/systemd/journald.conf.d/pigps.conf

# 5. USB network that never gives up (NetworkManager keyfile; NM isn't running yet)
cat > /etc/NetworkManager/system-connections/pigps-usb0.nmconnection <<'EOF'
[connection]
id=pigps-usb0
type=ethernet
interface-name=usb0
autoconnect=true
autoconnect-priority=100
autoconnect-retries=0

[ethernet]

[ipv4]
method=auto
may-fail=true
dhcp-timeout=2147483647
address1=192.168.137.2/24

[ipv6]
method=link-local
may-fail=true
EOF
chmod 600 /etc/NetworkManager/system-connections/pigps-usb0.nmconnection

# 6. Optional: headless. Boot to console and switch off desktop-only services.
#    Nothing is uninstalled; undo with: systemctl set-default graphical.target
#    and systemctl enable/unmask the units below.
if [ -f "$S/no-desktop" ]; then
  systemctl set-default multi-user.target
  for u in ModemManager.service bluetooth.service hciuart.service cups.service \
           cups-browsed.service colord.service udisks2.service \
           apt-daily.timer apt-daily-upgrade.timer; do
    systemctl disable "$u" || true
  done
  systemctl mask packagekit.service || true
  systemctl --global disable rpi-connect.service rpi-connect-wayvnc.service \
           pipewire.socket pipewire-pulse.socket wireplumber.service || true
fi

# 7. Save the current time for the next boot and record success
touch /var/lib/systemd/timesync/clock
set +x
echo "=== done $(date -u +%FT%TZ)"
touch "$B/pigps-install.done"
sync
exit 0
