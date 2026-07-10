#include <Arduino.h>

// LED_PIN is provided via build_flags (D13/PB5 on the 328).
#ifndef LED_PIN
#define LED_PIN 13
#endif

void setup() {
  pinMode(LED_PIN, OUTPUT);
  Serial.begin(9600);         // 328 hardware UART: TX=PD1 (pin 3), RX=PD0 (pin 2)
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("blink");    // heartbeat: one line per ~1 s cycle
  delay(500);                 // at 16 MHz this is a true 0.5 s; at wrong 8 MHz it drags to 1 s
  digitalWrite(LED_PIN, LOW);
  delay(500);
}
