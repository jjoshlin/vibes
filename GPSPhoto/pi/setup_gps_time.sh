#!/bin/bash
# PI_GPS: make the GPS (NMEA + PPS on GPIO18) the Pi's time source.
# Run once, with internet available:  sudo bash /boot/firmware/setup_gps_time.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }

apt-get update
apt-get install -y gpsd gpsd-clients pps-tools chrony   # chrony replaces systemd-timesyncd

# gpsd: read the GPS UART + PPS, start at boot, poll even with no clients (-n)
cat > /etc/default/gpsd <<'EOF'
START_DAEMON="true"
USBAUTO="false"
DEVICES="/dev/serial0 /dev/pps0"
GPSD_OPTIONS="-n"
EOF

# chrony: NMEA gives the whole seconds, PPS gives the precise edge
mkdir -p /etc/chrony/conf.d
cat > /etc/chrony/conf.d/gps.conf <<'EOF'
refclock SHM 0 refid NMEA offset 0.135 delay 0.2 noselect
refclock PPS /dev/pps0 refid PPS lock NMEA prefer
EOF

# Allow stepping the clock at any time (no RTC; boot time comes from fake-hwclock)
if grep -q '^makestep' /etc/chrony/chrony.conf; then
  sed -i 's/^makestep.*/makestep 1 -1/' /etc/chrony/chrony.conf
else
  echo 'makestep 1 -1' >> /etc/chrony/chrony.conf
fi

systemctl enable gpsd
systemctl restart gpsd chrony

echo
echo "Done. Once the GPS has a fix (FIX LED blinks every 15 s), check with:"
echo "  ppstest /dev/pps0      # one line per second"
echo "  cgps -s                # position + time"
echo "  chronyc sources -v     # want '#* PPS'"
echo "  chronyc tracking"
