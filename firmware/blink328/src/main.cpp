#include <Arduino.h>

// LED_PIN is provided via build_flags (D13/PB5 on the 328).
#ifndef LED_PIN
#define LED_PIN 13
#endif

void setup() {
  pinMode(LED_PIN, OUTPUT);
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  delay(500);                 // at 16 MHz this is a true 0.5 s; at wrong 8 MHz it drags to 1 s
  digitalWrite(LED_PIN, LOW);
  delay(500);
}
