# Changelog

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
- Reflashed with Raspberry Pi OS Lite (32-bit, Trixie) instead of the unknown base image.
- USB networking now uses Raspberry Pi's `rpi-usb-gadget` (VID 2E8A:0013) and its
  Windows driver instead of `g_ether` + the generic RNDIS driver.
- Removed `modules-load=dwc2,g_ether` from `cmdline.txt` (conflicts with rpi-usb-gadget).
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
