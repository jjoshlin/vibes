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
│   ├── install.sh                installs/updates everything below (sudo)
│   ├── pigps-logger(.service)    logger wrapper (repairs GPX, waits for time)
│   ├── pigps-timesync(.service/.timer)  GPS time at boot + every 10 min, saves it
│   └── pigps-clocksave.service   saves the time at shutdown
├── windows/
│   ├── setup-ssh-key.ps1         one-time passwordless SSH
│   ├── getPhotoGPS.ps1           move tracks to I:\gps\ingest (+ KMZ)
│   ├── gpx2kmz.py                GPX → Google Earth KMZ
│   ├── ingest-shoot.ps1          card → I:\nikon\NNNN (NT2 counter + naming), GPS pull, geotag
│   ├── geocode_photos.py         Location / City (by ZIP) / State / Country into the photos
│   └── photos2kmz.ps1            geotagged shoot → Google Earth KMZ with photo pins
├── esp32/esp32_pi_console_bridge ESP32 USB↔UART console bridge (fallback access)
├── tools/ext4read.py             read tracks off the SD card from Windows
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
sudo bash setup_gps_time.sh     # once: packages, gpsd, chrony GPS/PPS
sudo bash install.sh            # logger, time sync, services (re-run to update)
```
Copy the whole `pi/` folder to the Pi first (e.g. `scp pi/* pigps@pigps.local:pigps-install/`).
Check: `cgps -s` (3D fix), `ppstest /dev/pps0` (one line per second),
`chronyc sources -v` (`#* PPS`), `ls -l ~/tracks`, `tail ~/timesync.log`.

### Time keeping
The Pi has no RTC; at boot systemd sets the clock from the mtime of
`/var/lib/systemd/timesync/clock`. Installing chrony stops anything updating that
file, so without help every boot starts at the time chrony was installed.
* **chrony** locks to GPS continuously once there's a fix (NMEA numbers the seconds,
  PPS gives the edge; `makestep 1 -1` allows stepping at any time).
* **`pigps-timesync`** (timer: 30 s after boot, then every 10 min) waits up to 3 min
  for a GPS fix, steps the clock to it, and saves the time for the next boot. Without
  a fix it only saves, so a boot never starts earlier than the last save.
* The GPS module's own coin-cell clock is **not** used: before a fix the MTK3339 can
  report the wrong date (a +1 day jump was seen), so gpsd runs without `-r`.
* Track files are renamed at ingest to the time of their first GPS point, so a stale
  clock at boot never gives a file a wrong name.
  **`pigps-clocksave`** saves it again at shutdown. Log: `~/timesync.log`.

### 5. Offload (on the PC)
Run `windows/setup-ssh-key.ps1` once in a normal PowerShell window, then
`windows/getPhotoGPS.ps1` whenever you want to ingest. Tracks land in
`I:\gps\ingest` as `track_YYYYMMDD_HHMMSSZ_ingested_YYYYMMDD.gpx` and are removed
from the Pi after a size-verified copy (the track still being written is kept).
Each new GPX also gets a `.kmz` next to it (via `gpx2kmz.py`, needs Python) that opens in
Google Earth with a time slider. Cut-off tracks are repaired up to the last complete point.

## Field routine
1. Power on; wait for the GPS FIX LED to blink once every 15 s.
2. Shoot. Tracks are UTC; set the camera offset in Lightroom/ExifTool.
3. **Hold the button ~1 s**, wait for the green LED to go out, then unplug.

## Ingesting a shoot
`.\windows\ingest-shoot.ps1 -Prefix "Event name "` (close Nikon Transfer 2 first). It copies the card into
the next Nikon Transfer folder number under `I:\nikon` with NT2's naming (first shot in a minute
bare, then `_01`, `_02`…), advances NT2's counter, pulls tracks from the Pi, geotags by each
photo's own capture time + UTC offset (only within 5 min of a fix, ≤60 s past a track end) and
writes `I:\gps\ingest\NNNN photos.kmz` for Google Earth. ExifTool keeps `*_original` backups.

### Location fields
`geocode_photos.py <folder>` (run by `ingest-shoot.ps1`) fills XMP + IPTC Location, City, State,
Country and country code, one lookup per ~50 m spot, cached in `I:\gps\geocode_cache.json`:
1. `I:\gps\places.csv` — your own names (`name,lat,lon,radius_m`), checked first.
2. Photon (komoot, OpenStreetMap data) — nearest named venue/park/landmark within 200 m.
3. Nominatim — street, ZIP, state, country; Zippopotam.us turns the ZIP into its postal city.
4. ExifTool's built-in GeoNames data if offline.
These online lookups send each spot's coordinates to those public services.

## Geotagging
* Lightroom Classic: Map → GPS Tracklog → Load Tracklog → Auto-Tag Selected Photos.
* ExifTool: `exiftool -geotag "I:\gps\ingest\*.gpx" -geosync=+00:00:00 <photos>`
