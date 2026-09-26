#!/bin/bash
# PI_GPS: install/update the Pi-side scripts and services from this folder.
# Run on the Pi from the folder holding these files:  sudo bash install.sh
# Safe to re-run. Assumes setup_gps_time.sh has been run once (packages installed).
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
cd "$(dirname "$0")"

install -m 755 pigps-logger   /usr/local/bin/pigps-logger
install -m 755 pigps-timesync /usr/local/bin/pigps-timesync
install -m 644 pigps-logger.service pigps-timesync.service pigps-timesync.timer \
               pigps-clocksave.service /etc/systemd/system/
install -d -o pigps -g pigps /home/pigps/tracks

# gpsd: poll without clients (-n). Not -r: the GPS clock is unreliable before a fix
sed -i 's/^GPSD_OPTIONS=.*/GPSD_OPTIONS="-n"/' /etc/default/gpsd

# chrony: measured NMEA latency
sed -i 's/refid NMEA offset [0-9.]*/refid NMEA offset 0.135/' /etc/chrony/conf.d/gps.conf

# Keep the system journal across reboots (to diagnose unexpected restarts)
install -d /var/log/journal
systemd-tmpfiles --create --prefix /var/log/journal
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nStorage=persistent\nSystemMaxUse=50M\n' > /etc/systemd/journald.conf.d/pigps.conf
systemctl restart systemd-journald

# USB network: never drop the link when Windows' Internet Connection Sharing doesn't
# answer DHCP. Keep retrying DHCP forever, always hold 192.168.137.2 (same subnet as
# ICS, so the PC can reach it even without a lease), keep IPv6 link-local up.
nmcli con delete pigps-usb0 >/dev/null 2>&1 || true
nmcli con add type ethernet ifname usb0 con-name pigps-usb0 autoconnect yes \
  connection.autoconnect-priority 100 connection.autoconnect-retries 0 \
  ipv4.method auto ipv4.may-fail yes ipv4.dhcp-timeout infinity \
  ipv4.addresses 192.168.137.2/24 \
  ipv6.method link-local ipv6.may-fail yes >/dev/null
echo "USB network: connection pigps-usb0 (static 192.168.137.2 + DHCP)"

# Optional: boot to console instead of the desktop (saves ~half the RAM/CPU on a Zero)
if [ "${1:-}" = "--no-desktop" ]; then
  systemctl set-default multi-user.target
  for u in ModemManager.service bluetooth.service hciuart.service cups.service \
           cups-browsed.service colord.service udisks2.service \
           apt-daily.timer apt-daily-upgrade.timer; do
    systemctl disable "$u" >/dev/null 2>&1 || true
  done
  systemctl mask packagekit.service >/dev/null 2>&1 || true
  systemctl --global disable rpi-connect.service rpi-connect-wayvnc.service \
           pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 || true
  echo "Headless: desktop and desktop-only services disabled (undo: sudo systemctl set-default graphical.target)"
fi

systemctl daemon-reload
systemctl enable pigps-logger.service pigps-timesync.timer pigps-clocksave.service
systemctl restart gpsd chrony
systemctl start pigps-clocksave.service pigps-timesync.timer
systemctl restart pigps-logger.service
sleep 5
/usr/local/bin/pigps-timesync

echo
echo "Installed. Checks:"
systemctl is-active gpsd chrony pigps-logger pigps-timesync.timer pigps-clocksave
tail -n 3 /home/pigps/timesync.log

# Switch usb0 to the new connection last: an SSH session over USB may drop for a
# few seconds. Reconnect with ssh pigps@pigps.local (or 192.168.137.2).
echo "Activating pigps-usb0 now (SSH may pause briefly)..."
nmcli con up pigps-usb0 >/dev/null 2>&1 &
