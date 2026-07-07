#include <Arduino.h>

// LED_PIN provided via build_flags (PB0 = physical pin 5 on the ATtiny85).
#ifndef LED_PIN
#define LED_PIN 0
#endif

void setup() {
  pinMode(LED_PIN, OUTPUT);
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  delay(500);
  digitalWrite(LED_PIN, LOW);
  delay(500);
}
