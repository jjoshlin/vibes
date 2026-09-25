# Build notes

Things that were not obvious, in the order they bit.

## Getting in
- The Pi Zero v1.3 is ARMv6: only 32-bit Raspberry Pi OS boots, and the VS Code
  Remote-SSH extension does not work. Use a terminal for ssh and the SSH FS extension
  for editing.
- With an SD reader, reflashing beats recovering an unknown image. Imager
  customisation removes the "what's the login?" problem.
- `cmdline.txt` must stay a single line. Removing `console=serial0,115200` frees the
  UART for the GPS; keep everything Imager wrote (`ds=nocloud;...` applies the
  customisation on first boot, `resize` disappears after it).
- The stock `config.txt` has `dtoverlay=dwc2,dr_mode=host` under `[cm5]`; harmless on a Zero.

## USB networking on Windows
- Current Raspberry Pi OS enables **rpi-usb-gadget**, which enumerates as
  `2E8A:0013 "Raspberry Pi USB Gadget"`. Windows binds it to `usbser` and shows a
  **COM port**; the generic "Remote NDIS Compatible Device" isn't offered because the
  device is in the Ports class. Fix: Raspberry Pi's `rpi-usb-gadget-driver-setup.exe`.
- "Network cable unplugged" right after driver install just means the Pi hadn't
  brought `usb0` up yet.
- Without Internet Connection Sharing the link only has IPv6 link-local addresses.
  Windows OpenSSH can use those via `pigps.local`; PuTTY/mRemoteNG can't resolve it.
  With ICS on, the PC is `192.168.137.1` and the Pi gets `192.168.137.x`
  (`192.168.137.1` is the PC — "connection refused" there is expected).
- Don't mix `modules-load=dwc2,g_ether` with rpi-usb-gadget.
- "Unknown USB Device (Device Descriptor Request Failed)" means the Pi's USB gadget
  isn't answering: still booting, halted, or boot-looping.

## Windows tooling
- PowerShell ISE cannot show interactive prompts from native programs. `ssh`,
  `scp`, `ssh-keygen` and `sudo` hang there silently. Run them in a normal PowerShell
  window, or make them non-interactive (key auth, `-o BatchMode=yes`, `-N '""'`).
- Running as admin, the working directory is `C:\WINDOWS\system32`; never `scp ... .`
  from there.

## GPS / time
- The MTK3339 time sentences arrive ~0.13 s after the second at 9600 baud. chrony uses
  them only to number seconds; PPS supplies the edge.
- `noselect` NMEA + `lock NMEA` PPS works fully offline. `makestep 1 -1` because the
  Zero has no RTC and boots with fake-hwclock time.
- Indoors: 4 of 11 satellites, ±30 m. Outdoors it should be a few metres.
- GPX timestamps come from the GPS, so tracks are right even if the Pi clock isn't.
  The camera clocks are what need syncing.
- `cgps` borders showing as `qqqq`/`x`: PuTTY line-drawing; `export NCURSES_NO_UTF8_ACS=1`.

## Logger
- Without `-r`, gpxlogger exits when the fix drops (status 0), and systemd restarts it
  every 10 s, making a new file each time. `-r` keeps one file with new segments.
- A power cut leaves an unterminated GPX. The wrapper closes it on the next boot.

## Shutdown button
- GPIO3 (pin 5) is the only pin that also wakes a halted Pi. It has an on-board
  pull-up, so no resistor. Pin 14 is a free GND.
- If the button is stuck or wired to GND permanently, the Pi shuts down right after
  boot and GPIO3 wakes it again — a boot loop. Unplug the pin-5 wire to rule it out.
