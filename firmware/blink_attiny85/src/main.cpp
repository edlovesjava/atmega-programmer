#include <Arduino.h>

// LED_PIN provided via build_flags (PB4 = physical pin 3 on the ATtiny85).
// Serial here is TinySoftwareSerial (the ATtiny85 has no hardware UART):
// TX = PB0 (physical pin 5), RX = PB1 (physical pin 6), 9600 baud — fixed by the core.
#ifndef LED_PIN
#define LED_PIN 4
#endif

static unsigned long last = 0;
static bool on = false;
static unsigned long count = 0;

void setup() {
  pinMode(LED_PIN, OUTPUT);
  Serial.begin(9600);
}

void loop() {
  // Non-blocking heartbeat: toggle every 500 ms; print a counter on each ON edge.
  if (millis() - last >= 500) {
    last = millis();
    on = !on;
    digitalWrite(LED_PIN, on ? HIGH : LOW);
    if (on) {
      count++;
      Serial.print("blink ");
      Serial.println(count);
    }
  }
  // Echo any received bytes straight back.
  while (Serial.available() > 0) {
    Serial.write(Serial.read());
  }
}
