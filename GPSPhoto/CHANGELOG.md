# Changelog

## 2026-09-26 (evening) — First shoot: Sulphur Homecoming
- `windows/ingest-shoot.ps1`: card → `I:\nikon\NNNN` using Nikon Transfer 2's folder counter and
  file naming (read/written in `HKCU\Software\Nikon\NkFramework\Nikon Transfer 2`), size-verified
  copy (8.6 GB in 25 s vs NT2 stalling at ~1–18 MB/s), GPS pull, geotag, photo KMZ.
- `windows/photos2kmz.ps1`: Google Earth KMZ with each photo as a thumbnail pin (embedded NEF
  preview), balloon preview, time stamps and the shoot's track.
- `gpx2kmz.py` hides segment labels.
- `windows/geocode_photos.py`: fills Location / City (postal city of the ZIP) / State / Country /
  country code (XMP + IPTC). Sources: `I:\gps\places.csv` → Photon → Nominatim + Zippopotam.us →
  ExifTool GeoNames. Public Overpass servers were unreachable/timing out, so not used. Shoot 1134:
  Highway 90 / The Grove at Heritage Square / Golden Nugget Lake Charles (Saltgrass isn't mapped).
- Photo KMZ balloons show place, city, state.
- `geocode_photos.py --overwrite` for Lightroom export folders (no `*_original` files). Lightroom
  exports only carry the location fields it had at import, so photos imported before geocoding
  need this (or the fields typed into Lightroom). Checked: the exports had no embedded C2PA
  Content Credentials, so editing them afterwards breaks nothing.
- Result: 309/309 NEFs in `I:\nikon\1134` geotagged. 204 matched directly; 105 (16:13–16:41,
  under trees at The Grove) interpolated across a no-fix gap after confirming <5 m movement.
- Lesson: don't run Nikon Transfer 2 at the same time — it advanced the counter mid-ingest
  (script now refuses unless `-Folder` is given).

## 2026-09-26 — USB networking recovery

### Fixed
- USB networking died after the first reboot following the 2026-09-25 changes
  (Windows: "Unknown USB Device (Device Descriptor Request Failed)"). The Pi itself
  kept booting and logging. Restoring `modules-load=dwc2,g_ether` in `cmdline.txt`
  brought it back; the 2026-09-25 advice to remove it was wrong.

### Changed
- `gpio-shutdown` button line is commented out in the Pi's `config.txt` while the
  USB problem was isolated. Not the cause as far as we know; re-enable and retest.
- README / NOTES / `cmdline.txt.example` now say to keep `modules-load=dwc2,g_ether`.

### Added
- GPS time at boot + every 10 min: `pi/pigps-timesync`, `pigps-timesync.timer`
  (30 s after boot, then 10 min), `pigps-clocksave.service` (save at shutdown).
  Root cause of the stale boot clock: systemd restores time from the mtime of
  `/var/lib/systemd/timesync/clock`, which stopped updating when chrony replaced
  systemd-timesyncd (frozen at 2026-09-25 09:27).
- Tried gpsd `-r` (use the GPS module's clock before a fix) and removed it the same
  day: the MTK3339 reported a date one day ahead before it had satellites, and the
  sync script briefly set the Pi to 2026-09-27. Only a real fix is trusted now.
- `pigps-timesync` waits up to 3 min for a fix at each run instead of giving up.
- `getPhotoGPS.ps1` names ingested tracks by their first GPS timestamp.
- Headless option (`install.sh --no-desktop` / `no-desktop` flag): boots to console,
  disables desktop-only services and the automatic apt timers. Free RAM 229 → 318 MB.
- `pi/pigps-firstrun.sh`: offline one-time installer run from `cmdline.txt`
  (`systemd.run=`), for when the Pi is unreachable. Removes itself before running.
- USB network: NetworkManager connection `pigps-usb0` keeps retrying DHCP forever and
  always holds `192.168.137.2` (Windows ICS DHCP sometimes doesn't answer; NM used to
  give up and drop all addresses for 5 min).
- `pi/install.sh`: one command to install/update all Pi-side scripts and services;
  also applies the 0.135 s NMEA offset and makes the journal persistent.
- `windows/gpx2kmz.py`: GPX → KMZ for Google Earth (gx:Track with time slider,
  start/end pins). Repairs truncated files (NUL padding / missing tags) by keeping
  complete points. `getPhotoGPS.ps1` runs it after every ingest.
- `pigps-logger` strips NUL padding left by a power cut before closing the GPX.
- Test run: ingest moved 9 tracks (kept the active one on the Pi), 13 KMZ built.
- `tools/ext4read.py`: read-only ext4 reader for a Pi SD card in a Windows reader
  (no WSL or extra software). Used to recover 8 tracks while USB was down.

### Found
- The card runs the full Desktop image (not Lite), and `apt upgrade -y` was run on
  2026-09-25 09:44 local, updating raspi-firmware (20260907 → 20260915) and
  regenerating the initramfs. Kernel stayed 6.18.50.

## 2026-09-25 — Working logger

### Added
- `pi/setup_gps_time.sh`: installs gpsd, gpsd-clients, pps-tools, chrony; gpsd on
  `/dev/serial0` + `/dev/pps0`; chrony uses NMEA (seconds) + PPS (edge) with
  `makestep 1 -1`.
- `pi/pigps-logger` + `pi/pigps-logger.service`: GPX logging from boot. Repairs
  files left open by a power cut, deletes files that never got a fix, waits up to
  3 min for GPS time so file names are correct.
- `windows/getPhotoGPS.ps1`: moves tracks to `I:\gps\ingest`, appends
  `_ingested_YYYYMMDD`, verifies size before deleting from the Pi, never deletes the
  active track, uses `BatchMode` so it fails instead of hanging.
- `windows/setup-ssh-key.ps1`: ed25519 key + authorized_keys on the Pi.
- Shutdown/wake button on pin 5 (GPIO3) + pin 14 (GND) via `gpio-shutdown`
  overlay, 1 s debounce.
- `esp32/esp32_pi_console_bridge`: USB↔UART bridge sketch (fallback console).
- Google Drive docs copied to `docs/drive/`.

### Changed
- Reflashed with Raspberry Pi OS (32-bit, Trixie) instead of the unknown base image
  (turned out to be the Desktop variant, see 2026-09-26).
- USB networking now uses Raspberry Pi's `rpi-usb-gadget` (VID 2E8A:0013) and its
  Windows driver instead of the generic RNDIS driver.
- Removed `modules-load=dwc2,g_ether` from `cmdline.txt` — **reverted 2026-09-26**.
- NMEA refclock offset 0.3 → 0.135 s (measured by chrony and cgps).
- gpxlogger now runs with `-r` so a lost fix starts a new segment instead of exiting.
- Shutdown button moved from the Recommendations doc's GPIO21 (pin 40) to GPIO3
  (pin 5) so the same button also wakes the Pi.

### Verified
- 3D fix, chrony `#* PPS`, stratum 1, ~1 µs offset, agrees with internet NTP to a few ms.
- GPX points at 1 Hz with `<fix>3d</fix>`.

## 2026-09-22 — Hardware build
- Hardware wired per `docs/drive/PI_GPS_Wiring_Schematic.svg`.
- Assembly Guide, Recommendations and Progress Notes written (see `docs/drive/`).
- Blocked: unknown SD image, no USB gadget networking, no SD reader.
