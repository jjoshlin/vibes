# **PI\_GPS — Configuration & Upgrade Recommendations**

*Options for getting more out of the Pi Zero \+ Ultimate GPS build. Camera cable sync is deferred until a cable with the needed pin connected is on hand.*

## **How to send GPS (PMTK) commands**

The MTK3339 chip accepts \$PMTK… commands on its RX pin (the green wire, from Pi TXD). Checksums below are pre-computed. Stop gpsd first, or use gpsctl, so two programs are not writing to the port at once. Settings are held in the GPS's backup RAM, so they survive power-off only while the CR1220 coin cell is installed. Without it, run them from a boot script.

```bash
sudo systemctl stop gpsd.socket gpsd
printf '$PMTK313,1*2E\r\n' > /dev/serial0      # example
sudo systemctl start gpsd
```

## **1\. GPS module settings**

```bash
Goal | Command | Notes |
| :---- | :---- | :---- |
| Turn on SBAS/WAAS correction | $PMTK313,1*2E then $PMTK301,2*2E | Better accuracy in North America (typically ~3 m → ~2 m). Recommended. |
| Output only RMC + GGA | $PMTK314,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0*28 | Less serial traffic; needed if you raise the update rate at 9600 baud. Reset to default: $PMTK314,-1*04 |
| Faster baud (115200) | $PMTK251,115200*1F | Then set gpsd to the new speed (gpsd auto-detects, or stty). Back to default: $PMTK251,9600*17 |
| 5 Hz updates | $PMTK220,200*2C | Smoother tracks when moving fast (boat, vehicle). Use with RMC+GGA only or 115200 baud. |
| 10 Hz updates | $PMTK220,100*2F | Requires 115200 baud. Overkill for walking; uses more power and bigger logs. |
| Back to 1 Hz | $PMTK220,1000*1F | Best for walking and hiking. |
| Static navigation (stop drift at rest) | $PMTK386,0.4*39 | Position freezes below 0.4 m/s, which removes "spider web" jitter while you stand still. Off: $PMTK386,0*23 |
| Antenna status report | $PGCMD,33,1*6C | Adds $PGTOP sentences: 2 = internal patch, 3 = external active antenna. |
| Firmware version | $PMTK605*31 | Useful for confirming commands are being accepted. |
| Hot / cold restart | $PMTK101*32 / $PMTK103*30 | Cold restart clears the almanac; use it if the module gets confused after a long trip. |

## **2\. Built-in LOCUS logger (backup track with no Pi needed)**

The GPS chip has its own flash logger (LOCUS). It records a fix every 15 s by default, about 16 hours' worth, even if the Pi's SD card or software fails. It still needs power, but it gives you a second, independent track log.

| Action | Command |
| :---- | :---- |
| Start logging | $PMTK185,0*22 |
| Stop logging | $PMTK185,1*23 |
| Log every 5 s instead of 15 | $PMTK187,1,5*38 |
| Query status | $PMTK183*38 |
| Dump log (convert with Adafruit's LOCUS parser) | $PMTK622,1*29 |
| Erase log | $PMTK184,1*22 |

## **3\. Precision time (PPS + chrony)**

Because the blue PPS wire is on GPIO18, the Pi can keep time accurate to microseconds with no internet connection. This matters because the Pi Zero has no battery-backed clock. It also means file names and system logs are correct in the field, and the Pi can later serve NTP to the Pi 5 or home-lab gear. Add to /etc/chrony/chrony.conf:

| refclock SHM 0 refid NMEA offset 0.2 delay 0.2 noselect
refclock PPS /dev/pps0 lock NMEA refid PPS prefer
makestep 1 -1
```

Check it with chronyc sources \-v; after a few minutes PPS should show "\*". Fine-tune the NMEA offset value if chrony reports a consistent bias.

## **4\. Pi software upgrades**

> * **Safe-shutdown button:** Wire a momentary button from pin 40 (GPIO21) to pin 39 (GND), then add dtoverlay=gpio-shutdown,gpio\_pin=21 to config.txt. One press gives a clean poweroff, so no more SD corruption from pulling the plug. (GPIO3/pin 5 would also let the button wake the Pi, but keep it free if you add the OLED below.)  
> * **Waypoint / "mark" button:** A second button on a spare GPIO, with a small Python script, drops a named waypoint into the GPX. Handy for marking a nest, a trailhead or a shot location.  
> * **FIX-pin status:** GPIO17 already carries the FIX signal. A short script can drive an external LED, or log fix gained/lost events.  
> * **Protect the SD card:** Use a high-endurance card, and consider logging to a small USB stick. Raspberry Pi OS's Overlay File System option makes the OS read-only, but then tracks must go to a separate writable location or they vanish on reboot.  
> * **Daily files and auto-cleanup:** Rotate GPX files per day and prune anything older than 90 days with a cron job.  
> * **Tiny web page over USB:** With USB gadget networking already on, a lightweight web page (fix, satellites, battery time, download links) removes the need for SSH in the field.

## **5\. Hardware upgrades**

> * **External active antenna:** The \#746 has a u.FL port. A u.FL→SMA pigtail plus a small magnetic active antenna lets the electronics live in the bag while the antenna sits on top. The module switches to the external antenna automatically.  
> * **0.96" SSD1306 OLED (I²C, pins 3 & 5):** Shows fix, satellite count and UTC time with seconds. Photograph it once at the start of a shoot to get the exact camera clock offset for geotagging.  
> * **Pi Zero 2 W (drop-in):** Adds Wi-Fi and Bluetooth for phone access or a hotspot, and is much faster. Note: its Bluetooth takes the main UART, so add dtoverlay=disable-bt to keep the GPS on /dev/serial0.  
> * **3D-printed case:** Put the ceramic patch antenna facing up under a thin, non-metal lid. Add a cold-shoe or 1/4"-20 mount for the SmallRig Nighthawk cage, and a vent slot for the Pi.  
> * **Power budget:** Roughly 100–150 mA at 5V for the Pi Zero plus about 25 mA for the GPS. A 10,000 mAh bank gives a day or more. Some banks shut off at low draw; if yours does, use a bank with an "always-on" / low-current mode.  
> * **EN pin power control (optional):** Wiring the orange EN lead to a spare GPIO (e.g. pin 13, GPIO27) lets software fully power the GPS down between sessions. For most shoots, leaving it on is simpler; the coin cell keeps warm starts fast either way.

## **6\. Photo workflow tips**

> * One track covers both the Z6III and the Z30 as long as you stay within about 20 yards of each other. Just sync both camera clocks.  
> * Keep the cameras on local time and the GPX in UTC (the default). Lightroom and ExifTool handle the offset; with ExifTool, use \-geosync to correct any leftover clock drift.  
> * Log at 1 Hz on foot and 5 Hz from a boat or vehicle. Static navigation mode keeps tracks clean while you wait at one spot.

## **7\. Deferred: camera cable sync**

Left out for now because none of the three cables on hand have the required pin connected. When a fully pinned cable is available, revisit using the second \#757 level shifter. Check the camera-side voltage and pinout before connecting anything, and confirm the NMEA sentences and baud rate the camera expects.