# **PI\_GPS — Step-by-Step Assembly Guide**

*Raspberry Pi Zero v1.3 \+ Adafruit Ultimate GPS (\#746) \+ 4-channel level shifter (\#757) · standalone GPS track logger / time source*

## **What this build does**

The Pi Zero reads position and time from the Ultimate GPS over its serial port and records a GPX track log. You geotag photos from the Z6III (and the Z30) in post by matching photo timestamps to the track. Camera cable sync is intentionally left out for now because none of the three cables on hand have the needed pin connected. The PPS line is wired so the Pi can also act as a precise GPS-disciplined clock.

## **Parts and tools**

```bash
Item | Notes |
| :---- | :---- |
| Raspberry Pi Zero v1.3 | No Wi-Fi/Bluetooth on this model. Needs a 2×20 header soldered on. |
| Adafruit Ultimate GPS breakout #746 | Harness already soldered (colors below). |
| Adafruit 4-ch level shifter #757 (BSS138) | Use one; keep the second for future camera-cable work. |
| CR1220 coin cell | Goes in the holder on the back of the GPS. Keeps almanac/settings → fast fixes. |
| microSD card (8 GB+) + reader | For Raspberry Pi OS Lite (32-bit). |
| Micro-USB power (USB battery bank or 5V/1A+ supply) | Plugs into the Pi's PWR port. |
| Micro-USB OTG data cable | For setup/offload over USB (Zero v1.3 has no Wi-Fi). |
| Male headers for the shifter, female-female jumpers or 22–26 AWG hookup wire | Try to match the harness colors on the Pi side. |
| Soldering iron, solder, flush cutters, heat-shrink, multimeter | Heat-shrink for the two unused leads. |

## **Wiring reference**

**Full-color diagram: see PI_GPS_Wiring_Schematic.png in this folder.**

| Wire | GPS pin | Shifter HV side | Shifter LV side | Pi Zero pin | Purpose |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Red** | 3.3V (out) | HV | LV | 1 (3V3) | Logic reference for both sides |
| **Yellow** | TX | B2 | A2 | 10 (RXD, GPIO15) | NMEA data GPS → Pi |
| **Green** | RX | B3 | A3 | 8 (TXD, GPIO14) | Commands Pi → GPS |
| **Blue** | PPS | B4 | A4 | 12 (GPIO18) | 1 pulse-per-second timing |
| **White** | FIX | B1 | A1 | 11 (GPIO17) | Fix status (optional) |
| **Black** | GND | — | GND → pin 9 | 6 (GND) | Common ground |
| **Grey** | VIN | — | — | 2 (5V) | GPS power |
| **Orange** | EN | — | — | Not connected | GPS stays on (internal pull-up) |
| **Purple** | VBAT | — | — | Not connected | Coin cell in rear holder instead |

| Why run the shifter at 3.3V on both sides? The GPS and the Pi both use 3.3V logic, so no voltage translation is needed. With HV = GPS 3.3V and LV = Pi 3.3V, the #757 acts as a protective buffer between the boards and uses all four channels (TX, RX, PPS, FIX). Never put 5V on HV here: the shifter's pull-ups would push 5V into the GPS TX pin.
```

## **Step-by-step**

### **Phase 1 — Prep the boards**

> 1. **Install the coin cell.** Put a CR1220 in the holder on the back of the GPS, \+ side facing out.  
> 2. **Solder the Pi header.** Solder a 2×20 male header to the Pi Zero (it ships bare). Check for bridges between adjacent pins.  
> 3. **Solder the shifter headers.** Solder the two 6-pin male strips to the \#757. Look at the silkscreen and note where LV, HV, both GNDs and A1–A4 / B1–B4 are; the order on the board may differ from the logical order in the schematic.  
> 4. **Check the GPS harness.** With a multimeter in continuity mode, confirm each of the nine leads goes to the pin you expect (red 3.3V, orange EN, purple VBAT, white FIX, yellow TX, green RX, black GND, grey VIN, blue PPS). Confirm that grey (VIN) and black (GND) are NOT shorted.

### **Phase 2 — Wire it up (everything unpowered)**

> 1. **Insulate the unused leads.** Put heat-shrink over the orange (EN) and purple (VBAT) leads and fold them back. EN floats high, so the GPS stays on.  
> 2. **GPS → shifter HV side.** Red → HV · White → B1 · Yellow → B2 · Green → B3 · Blue → B4.  
> 3. **Shifter LV side → Pi.** LV → pin 1 (3V3) · A1 → pin 11 (GPIO17) · A2 → pin 10 (RXD) · A3 → pin 8 (TXD) · A4 → pin 12 (GPIO18) · GND → pin 9 (GND). Use the same color as the GPS wire on each channel so tracing stays easy.  
> 4. **GPS power straight to the Pi.** Grey (VIN) → pin 2 (5V) · Black (GND) → pin 6 (GND). Power bypasses the shifter.  
> 5. **Double-check the TX/RX crossover.** GPS TX (yellow) must end up at Pi RXD (pin 10), and GPS RX (green) at Pi TXD (pin 8). This is the most common mistake.  
> 6. **Continuity sweep.** Beep out every run end-to-end against the table, then confirm there is no continuity between Pi pin 2 (5V) and pin 6 (GND), or between pin 1 (3V3) and GND.

### **Phase 3 — Flash and configure the Pi**

> 1. **Flash the OS.** In Raspberry Pi Imager choose Raspberry Pi Zero → Raspberry Pi OS Lite (32-bit). In OS customisation set hostname pigps, a username/password and enable SSH. (The Zero v1.3 is ARMv6, so 64-bit images will not boot.)  
> 2. **Enable USB networking for headless access.** Before ejecting the card, edit the boot partition:

```bash
# config.txt — add at the bottom (under [all])
dtoverlay=dwc2

# cmdline.txt — single line; add right after "rootwait"
modules-load=dwc2,g_ether
```

> 3. **Enable the UART and PPS.** Also in config.txt:

```bash
enable_uart=1
dtoverlay=pps-gpio,gpiopin=18
```

> 4. **Remove the serial console.** In cmdline.txt delete "console=serial0,115200" (leave console=tty1). Otherwise Linux will talk over the GPS line. (Or use sudo raspi-config → Interface Options → Serial Port → login shell: No, hardware: Yes.)  
> 5. **First boot.** Plug the OTG cable into the Pi's USB (data) port, not PWR, and connect it to your computer. Wait about 90 seconds, then run ssh \<user\>@pigps.local. If the computer does not see the USB network, power the Pi from PWR and use a keyboard and mini-HDMI screen instead.

### **Phase 4 — Bring up the GPS**

> 1. **Take it outside.** Put it where it can see the sky. Red LED on the GPS: blinks about once a second while searching, and about once every 15 seconds once it has a fix. The first fix can take a few minutes; later ones take seconds thanks to the coin cell.  
> 2. **Raw serial test.** You should see \$GPRMC / \$GPGGA sentences scroll by:

```bash
stty -F /dev/serial0 9600 raw
cat /dev/serial0          # Ctrl-C to stop
```

> 3. **Install the GPS tools.**

```bash
sudo apt update
sudo apt install -y gpsd gpsd-clients pps-tools chrony
```

> 4. **Point gpsd at the GPS and PPS.** Edit /etc/default/gpsd:

```bash
START_DAEMON="true"
USBAUTO="false"
DEVICES="/dev/serial0 /dev/pps0"
GPSD_OPTIONS="-n"
```

```bash
sudo systemctl enable --now gpsd
cgps -s                   # live fix, satellites, time
sudo ppstest /dev/pps0    # one line per second = PPS working
```

### **Phase 5 — Automatic track logging**

> 1. **Create a log folder and service.** This starts a new GPX file on every boot:

```bash
mkdir -p ~/tracks
sudo tee /etc/systemd/system/gpxlog.service >/dev/null <<'UNIT'
[Unit]
Description=GPX track logger
After=gpsd.service
Requires=gpsd.service

[Service]
User=YOUR_USER
ExecStart=/bin/sh -c 'exec /usr/bin/gpxlogger -i 30 -f /home/YOUR_USER/tracks/track_$(date +%%Y%%m%%d_%%H%%M%%S).gpx'
Restart=always

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now gpxlog
```

Replace YOUR\_USER with your username. Because the Pi has no real-time clock, file names may show a stale time until the GPS fix sets the clock; the timestamps inside the GPX come straight from the GPS and are always correct.

### **Phase 6 — Field use and geotagging**

> 1. **Sync the camera clocks.** Before shooting, set the Z6III and Z30 clocks to match GPS time (your phone's clock is close enough), or take a photo of a clock that shows seconds so you can calculate the offset later.  
> 2. **Power up and shoot.** Plug the Pi into the battery bank, wait for the slow 15-second blink, then shoot as normal.  
> 3. **Shut down cleanly.** Before unplugging, SSH in and run sudo poweroff, or add the shutdown button from the Recommendations doc. Pulling power mid-write can corrupt the SD card.  
> 4. **Offload.** Over USB: scp \<user\>@pigps.local:tracks/\*.gpx . — or pull the SD card.  
> 5. **Geotag.** Lightroom Classic: Map module → GPS Tracklog button → Load Tracklog → select photos → Auto-Tag. Set the time-zone offset if the camera is on local time. Or use ExifTool:

```bash
exiftool -geotag "track_*.gpx" -geosync=+00:00:00 /path/to/photos
```

## **Troubleshooting**

| Symptom | Likely cause / fix |
| :---- | :---- |
| Nothing from cat /dev/serial0 | TX/RX swapped; serial console still enabled; enable\_uart missing; shifter LV/HV not powered. |
| Garbage characters | Wrong baud rate. Default is 9600 unless you changed it with PMTK251. |
| LED blinks 1/s forever | No sky view. Go outdoors, away from the house; give the first fix up to 15 minutes. |
| ppstest times out | Blue wire/channel, or the dtoverlay line is missing. PPS only pulses once the GPS has a fix. |
| cgps shows "NO FIX" but raw NMEA is fine | gpsd is not using /dev/serial0. Check /etc/default/gpsd and run sudo systemctl restart gpsd. |
| Pi reboots when the GPS is plugged in | Weak supply or a 5V/GND short. Recheck the grey and black wires. |

