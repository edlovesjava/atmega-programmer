# ATtiny85 Serial Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the ATtiny85 verify firmware blink **and** exercise software serial (heartbeat print + RX echo), and document using the Nano as a USB-serial pass-through to watch it.

**Architecture:** Modify the existing `firmware/blink_attiny85` PlatformIO project in place — move the LED off the fixed serial TX pin (PB0→PB4) and add a non-blocking blink+echo `loop()` using the core's `Serial` (bit-banged `TinySoftwareSerial`). Add README wiring for a serial-monitor mode that holds the Nano's 328 in reset so its CH340 becomes a plain USB-TTL bridge.

**Tech Stack:** PlatformIO Core (`pio`), `framework-arduino-avr-attiny` (Damellis "tiny" core, provides `TinySoftwareSerial`), avrdude via the repo Makefile, ArduinoISP on the Nano.

## Global Constraints

- Target: `board = attiny85`, `board_build.f_cpu = 8000000L`, 8 MHz internal oscillator (no crystal). Unchanged.
- `Serial` on this core is bit-banged via the Analog Comparator with **fixed pins**: TX = AIN0 = PB0 = physical pin 5; RX = AIN1 = PB1 = physical pin 6. Not reconfigurable in firmware.
- LED must avoid PB0 (TX). New LED pin: **PB4 = physical pin 3** (`LED_PIN=4`).
- Serial baud: **9600** (matches `make console` default `BAUD`; most forgiving rate for the internal RC oscillator).
- Windows host: run `pio`/`make` from **Git Bash**.
- Nano is a CH340 clone on **COM4**; the same COM4 device is used in serial-monitor mode (the CH340 enumerates it, not the 328).
- `loop()` must be **non-blocking** (millis-based) — no `delay()` — so RX bytes are serviced every pass.

---

### Task 1: blink + serial-echo firmware

**Files:**
- Modify: `firmware/blink_attiny85/platformio.ini`
- Modify: `firmware/blink_attiny85/src/main.cpp`

**Interfaces:**
- Consumes: `LED_PIN` build flag; Arduino core `Serial` (`TinySoftwareSerial`) — `Serial.begin(long)`, `Serial.print`, `Serial.println`, `Serial.available()`, `Serial.read()`, `Serial.write(int)`; `millis()`, `pinMode`, `digitalWrite`.
- Produces: firmware hex at `firmware/blink_attiny85/.pio/build/blink_attiny85/firmware.hex` (unchanged path — `make blink CHIP=attiny85` consumes it). Runtime contract: LED on physical pin 3 blinks 500/500; `blink <n>` printed once per ~1 s at 9600 baud; any RX byte echoed back.

- [ ] **Step 1: Set the LED pin build flag**

Edit `firmware/blink_attiny85/platformio.ini` — change the `build_flags` line from `-D LED_PIN=0` to `-D LED_PIN=4`. Full file after edit:

```ini
[env:blink_attiny85]
platform = atmelavr
framework = arduino
board = attiny85
board_build.f_cpu = 8000000L
build_flags = -D LED_PIN=4
```

- [ ] **Step 2: Rewrite the firmware source**

Replace `firmware/blink_attiny85/src/main.cpp` in full:

```cpp
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
```

- [ ] **Step 3: Build and verify it compiles + links `TinySoftwareSerial`**

Run: `pio run -d firmware/blink_attiny85 -e blink_attiny85`
Expected: `[SUCCESS]`; `firmware/blink_attiny85/.pio/build/blink_attiny85/firmware.hex` exists; no unresolved-symbol errors for `Serial`. (Flash usage rises above the ~464 B of pure blink because the serial code links in — that is expected.)

- [ ] **Step 4: Commit the firmware**

```bash
git add firmware/blink_attiny85/platformio.ini firmware/blink_attiny85/src/main.cpp
git commit -m "feat: blink_attiny85 adds serial heartbeat + RX echo, LED to PB4/pin3"
```

- [ ] **Step 5: Hardware verify (operator, ISP rig)**

Run: `make blink CHIP=attiny85`
Expected: avrdude writes + verifies. Then, on the ISP rig, the **LED on physical pin 3** blinks 500 ms on / 500 ms off. (If it does not blink, confirm this core maps `LED_PIN=4` to PB4; if the wrong pin blinks, adjust `LED_PIN` to the value that lands on PB4 and rebuild.)

- [ ] **Step 6: Hardware verify serial (operator, pass-through rig)**

Rewire to serial mode per Task 2's table, then run: `make console` (defaults `PORT=COM4 BAUD=9600`).
Expected: monitor prints `blink 1`, `blink 2`, … ~once/second; typing characters echoes them back. PASS = both heartbeat and echo work. (Garbled text ⇒ 8 MHz oscillator tolerance, not wiring — noted in README.)

---

### Task 2: README — LED pin note + serial pass-through wiring

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: reader-facing wiring for serial-monitor mode; corrected LED pin reference.

- [ ] **Step 1: Note the verify LED pin in the ATtiny85 section**

In `README.md`, in the `### Target — ATtiny85 on a breadboard (DIP-8)` section, under the "Support parts on the breadboard" bullet list, add a bullet:

```markdown
- **Verify LED** (for `make blink`): physical **pin 3 (PB4)** → LED → ~330 Ω–1 kΩ → GND. (Pin 3 is used because the firmware's `Serial` TX is fixed to pin 5.)
```

- [ ] **Step 2: Add the serial pass-through subsection**

In `README.md`, immediately **after** the `### Target — ATtiny85 on a breadboard (DIP-8)` section and **before** `## Everyday commands`, insert:

```markdown
### Serial monitor via the Nano (pass-through)

The ATtiny85 has **no hardware UART** — the verify firmware bit-bangs serial
(`TinySoftwareSerial`) at **9600 baud** on fixed pins: **TX = pin 5 (PB0)**,
**RX = pin 6 (PB1)**. You can watch it without a separate USB-TTL adapter by
turning the **Nano itself** into a USB-serial bridge: tie the Nano's **RESET → GND**
to hold its ATmega328 in reset, which exposes the onboard CH340 straight through
D0/D1.

**This is a separate mode from ISP** — flash the firmware over the ISP rig first,
then rewire:

| Connection | Purpose |
|---|---|
| Nano **RESET → GND** | holds the 328 in reset; D0/D1 become the CH340's lines |
| ATtiny **pin 5 (PB0, TX) → Nano D1** | target → PC |
| ATtiny **pin 6 (PB1, RX) → Nano D0** | PC → target |
| Nano **5V → pin 8**, **GND → pin 4** | power + common ground |
| *(remove the D10–D13 ISP wires)* | not used in serial mode |

Then: `make console` (defaults `PORT=COM4 BAUD=9600`). You should see `blink 1`,
`blink 2`, … about once a second, and characters you type echo back.

> **Same-label wiring is correct here (TX→D1/TX, RX→D0/RX).** With the 328 held in
> reset, the D0/D1 headers *are* the CH340's lines, so connecting the target the
> "straight" way reaches the USB chip — the inverse of normal crossover wiring,
> because you're tapping behind the header labels.

> **Garbled characters?** That's the 8 MHz internal oscillator's tolerance for
> bit-banged serial, not a wiring fault. 9600 is the most forgiving rate; OSCCAL
> tuning is the deeper fix if it persists.
```

- [ ] **Step 3: Commit the docs**

```bash
git add README.md
git commit -m "docs: README — ATtiny85 serial pass-through wiring + verify LED on pin 3"
```

---

## Self-Review

**Spec coverage:**
- Firmware LED move PB0→PB4, `Serial.begin(9600)`, non-blocking blink + heartbeat + echo → Task 1 Steps 1–2. ✓
- Nano pass-through wiring table + `make console` + same-label rationale + oscillator caveat → Task 2 Step 2. ✓
- README LED-pin correction → Task 2 Step 1. ✓
- Out-of-scope items (no `profiles.mk` change, no separate firmware, no OSCCAL auto-cal, no 328 changes) → honored; no tasks touch them. ✓
- Verification (build, flash, LED, serial) → Task 1 Steps 3, 5, 6. ✓

**Placeholder scan:** No TBD/TODO; all code and markdown shown in full. ✓

**Type consistency:** `LED_PIN=4` (PB4/pin 3), TX=PB0/pin 5, RX=PB1/pin 6, 9600 baud, COM4 — consistent across both tasks and the Global Constraints. ✓

**Known residual risk:** the Damellis core's digital-pin numbering for `LED_PIN=4`→PB4 is validated at Task 1 Step 5 (which pin physically blinks); if it maps differently, adjust the flag value and rebuild before proceeding.
