# **PI\_GPS Progress Notes**

*Session: Sept 22, 2026*

## **Status**

> * **Hardware:** fully wired per PI\_GPS\_Wiring\_Schematic (GPS → \#757 shifter → Pi Zero v1.3).  
> * **Power plan:** USB battery pack into the Pi's PWR port. Test the pack for low-current auto-shutoff (run 30–60 min, then check uptime).  
> * **SD card:** has an existing "base" Pi image. No microSD reader on hand, so the card can't be reflashed or edited from the PC right now.  
> * **USB test:** Pi plugged into the **USB** port (not PWR) with a known-good data cable (works with ESP32). Pi green LED is solid (on a Zero that normally means booted/idle). **Windows Device Manager shows no RNDIS device**, so USB gadget (network over USB) is NOT enabled on the current image.  
> * **PC:** Windows. Plan to use VS Code. Note: the VS Code Remote-SSH extension does NOT work on a Pi Zero v1.3 (ARMv6). Use the VS Code terminal for ssh and the "SSH FS" extension for file editing.

## **Open questions**

> * Where did the base image come from? If it was a 64-bit image or one set up for the Pi 5, it won't fully boot on the Zero v1.3 and must be reflashed as Raspberry Pi OS Lite (32-bit).  
> * Username and password on the base image? (Older images default to pi / raspberry.)

## **Next step: get into the Pi (pick one)**

> 1. **Screen and keyboard:** mini-HDMI→HDMI adapter \+ micro-USB OTG adapter \+ USB keyboard. Power the Pi from PWR, log in, run the commands below.  
> 2. **SD adapter:** put the microSD in a full-size SD adapter, use a laptop SD slot, and edit config.txt / cmdline.txt on the boot drive.  
> 3. **ESP32 as a USB-serial bridge** (uses gear on hand):  
   * Unplug the jumpers on Pi pins 8 and 10 from the shifter.  
   * Connect ESP32 GPIO16 (RX2) → Pi pin 8 (TXD), ESP32 GPIO17 (TX2) → Pi pin 10 (RXD), and ESP32 GND → Pi pin 6 or 9\.  
   * Flash the passthrough sketch below and open the Arduino Serial Monitor at 115200 with line ending "Newline". Press Enter to get a login prompt.  
   * When done, restore the shifter jumpers: A3 → pin 8, A2 → pin 10\.

void setup(){ Serial.begin(115200); Serial2.begin(115200, SERIAL\_8N1, 16, 17); }  
void loop(){ while(Serial.available()) Serial2.write(Serial.read());  
             while(Serial2.available()) Serial.write(Serial2.read()); }

## **Commands to run once logged in (enable USB networking, UART, PPS, SSH)**

B=/boot/firmware; \[ \-d \$B \] || B=/boot  
printf "dtoverlay=dwc2\\nenable\_uart=1\\ndtoverlay=pps-gpio,gpiopin=18\\n" | sudo tee \-a \$B/config.txt  
sudo sed \-i 's/console=serial0,115200 //; s/rootwait/rootwait modules-load=dwc2,g\_ether/' \$B/cmdline.txt  
sudo raspi-config nonint do\_hostname pigps  
sudo systemctl enable ssh  
sudo poweroff  
Note: when using the ESP32 serial method, removing console=serial0 takes effect after the reboot, which is expected: the serial console is only needed this one time.

## **After that (over USB from Windows)**

> 1. Plug the Pi's **USB** port into the PC. In Device Manager, find the RNDIS device. If it shows as a COM port or unknown device: Update driver → Browse → Let me pick → Network adapters → Microsoft → **Remote NDIS Compatible Device**.  
> 2. Share internet: Win+R → ncpa.cpl → Wi-Fi adapter → Properties → Sharing → allow, and select the RNDIS adapter. Replug the Pi.  
> 3. In the VS Code terminal: ssh username@pigps.local  
> 4. Install the GPS software:

sudo apt update && sudo apt install \-y gpsd gpsd-clients pps-tools chrony  
sudo tee /etc/default/gpsd \>/dev/null \<\<'EOF'  
START\_DAEMON="true"  
USBAUTO="false"  
DEVICES="/dev/serial0 /dev/pps0"  
GPSD\_OPTIONS="-n"  
EOF  
sudo systemctl enable \--now gpsd  
ls \-l /dev/serial0 /dev/pps0

> 5. Test outdoors: cgps \-s (fix and satellites), then sudo ppstest /dev/pps0 (one line per second).  
> 6. Then set up GPX auto-logging: Phase 5 in the PI\_GPS Assembly Guide.