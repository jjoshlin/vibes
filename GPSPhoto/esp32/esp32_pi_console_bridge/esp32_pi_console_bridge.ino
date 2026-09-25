// ESP32 <-> Raspberry Pi serial console bridge
// PC (USB, Serial) <-> ESP32 <-> Serial2 <-> Pi UART (pins 8/10)
//
// Wiring (Pi powered from its own supply; do NOT link 5V/3V3 between boards):
//   ESP32 GPIO16 (RX2)  <- Pi pin 8  (GPIO14 TXD)
//   ESP32 GPIO17 (TX2)  -> Pi pin 10 (GPIO15 RXD)
//   ESP32 GND           -- Pi pin 14 (GND)
// Unplug the level-shifter jumpers from Pi pins 8 and 10 first.
//
// On WROVER modules GPIO16/17 are used by PSRAM: change PI_RX/PI_TX
// to e.g. 26/27 and wire accordingly.

#define PI_RX 16   // ESP32 pin receiving from Pi TXD
#define PI_TX 17   // ESP32 pin sending to Pi RXD
#define BAUD  115200

void setup() {
  Serial.setRxBufferSize(1024);
  Serial.begin(BAUD);
  Serial2.setRxBufferSize(4096);   // boot log arrives in bursts
  Serial2.begin(BAUD, SERIAL_8N1, PI_RX, PI_TX);
  delay(200);
  Serial.println("\r\n[bridge] ESP32 <-> Pi console ready @115200. Power-cycle the Pi or press Enter.");
}

void loop() {
  uint8_t buf[256];
  size_t n;

  n = Serial2.available();
  if (n) {
    n = Serial2.readBytes(buf, min(n, sizeof(buf)));
    Serial.write(buf, n);
  }

  n = Serial.available();
  if (n) {
    n = Serial.readBytes(buf, min(n, sizeof(buf)));
    Serial2.write(buf, n);
  }
}
