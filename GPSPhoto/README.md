# GPSPhoto (PI_GPS)

A standalone GPS track logger for geotagging photos from a Nikon Z6III and Z30.
A Raspberry Pi Zero v1.3 reads an Adafruit Ultimate GPS, keeps its own clock locked
to GPS time via PPS, and records a GPX track from power-on. Tracks are pulled onto a
Windows PC over a single USB cable and matched to photos in Lightroom or ExifTool.

Camera cable sync is deliberately left out for now (see `docs/drive/PI_GPS Recommendations.md` §7).

## Hardware

| Part | Notes |
|---|---|
| Raspberry Pi Zero v1.3 | ARMv6, no Wi-Fi. Needs a **32-bit** OS. |
| Adafruit Ultimate GPS #746 (MTK3339) | CR1220 coin cell in the rear holder |
| Adafruit #757 BSS138 4-ch level shifter | Run as a 3.3 V ↔ 3.3 V buffer |
| Momentary push button | Shutdown / wake |
| USB battery pack | Into the Pi's **PWR** port in the field |

### Pin map

| Pi pin | Signal | Connected to |
|---|---|---|
| 1 | 3V3 | Shifter LV (red) |
| 2 | 5V | GPS VIN (grey) |
| 5 | GPIO3 | **Button** (other leg to pin 14) |
| 6 | GND | GPS GND (black) |
| 8 | TXD / GPIO14 | A3 ↔ B3 → GPS RX (green) |
| 9 | GND | Shifter GND |
| 10 | RXD / GPIO15 | A2 ↔ B2 ← GPS TX (yellow) |
| 11 | GPIO17 | A1 ↔ B1 ← GPS FIX (white) |
| 12 | GPIO18 | A4 ↔ B4 ← GPS PPS (blue) |
| 14 | GND | **Button** |

Shifter HV = GPS 3.3 V out. GPS EN (orange) and VBAT (purple) are not connected.
Full diagram: [`docs/drive/PI_GPS_Wiring_Schematic.svg`](docs/drive/PI_GPS_Wiring_Schematic.svg)
(it predates the button).

## Repository layout

```
GPSPhoto/
├── README.md                     this file
├── CHANGELOG.md                  what changed, by date
├── NOTES.md                      build log, gotchas and lessons learned
├── pi/
│   ├── boot/config.txt.additions lines appended to /boot/firmware/config.txt
│   ├── boot/cmdline.txt.example  what a working cmdline.txt looks like
│   ├── setup_gps_time.sh         installs gpsd + chrony, GPS/PPS as the clock
│   ├── pigps-logger              logger wrapper (repairs GPX, waits for time)
│   └── pigps-logger.service      systemd unit
├── windows/
│   ├── setup-ssh-key.ps1         one-time passwordless SSH
│   └── getPhotoGPS.ps1           move tracks to I:\gps\ingest
├── esp32/esp32_pi_console_bridge ESP32 USB↔UART console bridge (fallback access)
└── docs/drive/                   original Google Drive docs (22 Sep 2026 snapshot)
```

## Setup from scratch

### 1. Flash the SD card
Raspberry Pi Imager → Device **Raspberry Pi Zero** → **Raspberry Pi OS Lite (32-bit)**.
Customisation: hostname `pigps`, user `pigps`, enable SSH (password), locale/time zone,
and **enable USB gadget mode** if offered.
(The current card actually runs the full Desktop image; it works, but Lite boots much
faster on a Zero.)

### 2. Edit the boot partition (the `bootfs` drive on the PC)
* Append [`pi/boot/config.txt.additions`](pi/boot/config.txt.additions) to `config.txt`.
* In `cmdline.txt` (one line) delete `console=serial0,115200 ` and **keep/add**
  `modules-load=dwc2,g_ether` right after `rootwait`. Without it USB networking fails
  after a reboot ("Device Descriptor Request Failed" on Windows), even though the
  device still shows up as rpi-usb-gadget (`2E8A:0013`) when it works.
  See [`pi/boot/cmdline.txt.example`](pi/boot/cmdline.txt.example).

### 3. Connect over USB from Windows
1. Plug the Pi's **USB** (inner) port into the PC. First boot takes a few minutes.
2. Install **rpi-usb-gadget-driver-setup.exe** from
   <https://github.com/raspberrypi/rpi-usb-gadget/releases>. The Pi then shows as
   *Raspberry Pi USB Remote NDIS Network Device* instead of a COM port.
3. `ncpa.cpl` → internet adapter → Properties → Sharing → share with that adapter.
   Replug the Pi; it gets `192.168.137.x` and `pigps.local` resolves.
4. `ssh pigps@pigps.local` (mRemoteNG/PuTTY works once the Pi has an IPv4 address).

### 4. GPS time + logging (on the Pi)
```bash
sudo bash setup_gps_time.sh
sudo install -m 755 pigps-logger /usr/local/bin/pigps-logger
sudo install -m 644 pigps-logger.service /etc/systemd/system/
mkdir -p ~/tracks
sudo systemctl daemon-reload && sudo systemctl enable --now pigps-logger
```
Check: `cgps -s` (3D fix), `ppstest /dev/pps0` (one line per second),
`chronyc sources -v` (`#* PPS`), `ls -l ~/tracks`.

### 5. Offload (on the PC)
Run `windows/setup-ssh-key.ps1` once in a normal PowerShell window, then
`windows/getPhotoGPS.ps1` whenever you want to ingest. Tracks land in
`I:\gps\ingest` as `track_YYYYMMDD_HHMMSSZ_ingested_YYYYMMDD.gpx` and are removed
from the Pi after a size-verified copy (the track still being written is kept).

## Field routine
1. Power on; wait for the GPS FIX LED to blink once every 15 s.
2. Shoot. Tracks are UTC; set the camera offset in Lightroom/ExifTool.
3. **Hold the button ~1 s**, wait for the green LED to go out, then unplug.

## Geotagging
* Lightroom Classic: Map → GPS Tracklog → Load Tracklog → Auto-Tag Selected Photos.
* ExifTool: `exiftool -geotag "I:\gps\ingest\*.gpx" -geosync=+00:00:00 <photos>`
