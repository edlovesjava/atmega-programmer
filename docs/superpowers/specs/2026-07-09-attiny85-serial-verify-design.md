# ATtiny85 Serial Verification — Design

**Date:** 2026-07-09
**Status:** Approved (brainstorm), pending implementation plan
**Parent project:** ATmega ISP Programmer (`docs/superpowers/specs/2026-07-06-atmega-isp-programmer-design.md`)

## 1. Goal

Extend the ATtiny85 verification firmware so it exercises the **serial path** in
addition to blink, and document how to use the **Arduino Nano itself** as a
USB-to-serial pass-through to watch that output — no separate USB-TTL adapter
required. This closes the last untested slice of the ATtiny85 bring-up (serial
I/O) using hardware the user already has on the bench.

## 2. Key constraint (the fact that shapes the design)

**The ATtiny85 has no hardware UART.** The installed core
(`framework-arduino-avr-attiny`, the Damellis "tiny" core) provides a `Serial`
object, but it is **bit-banged via the Analog Comparator** (`TinySoftwareSerial`),
and its pins are **fixed by the core**:

- **TX = AIN0 = PB0 = physical pin 5**
- **RX = AIN1 = PB1 = physical pin 6**

Consequences:

1. `Serial` TX (pin 5) is the pin the current blink LED uses (`LED_PIN=0`). They
   collide, so the LED must move. **New LED pin: PB4 = physical pin 3**
   (`LED_PIN=4`) — free in every mode (not an ISP line, not a serial line).
2. Pins 5/6 double as MOSI/MISO during ISP, so the target-side wiring on those
   pins is reused between modes; only the Nano-side wires move.
3. Software serial timing depends on the 8 MHz internal RC oscillator. Its
   factory accuracy is usually adequate at **9600 baud**; garbled characters
   would indicate oscillator tolerance (OSCCAL), not a wiring fault.

## 3. Firmware design — modify `firmware/blink_attiny85`

Update the existing verification firmware in place (rather than adding a separate
project) so `make blink CHIP=attiny85` continues to be the single ATtiny85
verifier, now covering LED **and** serial.

### `platformio.ini`

```
build_flags = -D LED_PIN=4        ; PB4 = physical pin 3 (was PB0/pin 5)
```

All other keys unchanged (`board = attiny85`, `board_build.f_cpu = 8000000L`).

### `src/main.cpp` behaviour

- `setup()`: `pinMode(LED_PIN, OUTPUT); Serial.begin(9600);`
- `loop()` is **non-blocking** (millis-based), so received bytes are serviced
  continuously — a `delay(500)` would swallow RX:
  - Every 500 ms: toggle the LED. On each ON edge, increment a counter and print
    `blink <n>` via `Serial.println`.
  - Every pass: `while (Serial.available()) Serial.write(Serial.read());` — echo
    each received byte straight back.

Observable result: LED blinks 500 ms on / 500 ms off on pin 3; the serial monitor
shows `blink 1`, `blink 2`, … once per second; characters typed in the monitor
echo back.

## 4. Wiring — Nano as serial pass-through

This is a **separate mode from ISP**. Workflow: flash the firmware over the ISP
rig first, then rewire to serial mode to watch output.

To turn the Nano into a plain USB-TTL bridge, hold its ATmega328 in reset so the
D0/D1 header pins pass straight through to the onboard CH340 USB chip.

| Connection | Purpose |
|---|---|
| Nano **RESET → GND** | holds the 328 in reset; D0/D1 become the CH340's lines |
| ATtiny **pin 5 (PB0, TX) → Nano D1** | target → PC |
| ATtiny **pin 6 (PB1, RX) → Nano D0** | PC → target |
| Nano **5V → pin 8**, **GND → pin 4** | power + common ground |
| Remove the D10–D13 ISP wires | not used in serial mode |

Then: `make console BAUD=9600`.

**Why same-label wiring (TX→D1/TX, RX→D0/RX)?** On the Nano the CH340's TXD drives
the 328's RXD (D0) and the CH340's RXD listens on the 328's TXD (D1). With the 328
tri-stated (held in reset), the D0/D1 headers *are* the CH340 lines, so connecting
the target the "straight" way reaches the USB chip correctly. This is the inverse
of normal crossover wiring precisely because you are tapping behind the header
labels.

**Caveat (document in README):** if the monitor shows garbage, it is the 8 MHz
internal oscillator's tolerance for bit-banged serial, not a wiring error — 9600
is the most forgiving rate; OSCCAL tuning is the deeper fix if needed.

## 5. Documentation changes (README)

1. New subsection **"Serial monitor via the Nano (pass-through)"** with the §4
   table, the `make console BAUD=9600` step, and the oscillator caveat.
2. Update the existing ATtiny85 wiring section: LED is now **pin 3 (PB4)**, not
   pin 5; drop the now-obsolete "MOSI shares the LED pin" note.

## 6. Out of scope

- Changing `profiles.mk` (no fuse/clock/signature change; still 8 MHz internal).
- A separate `serial_attiny85` firmware project (rejected — user wants blink
  itself to carry the serial test).
- OSCCAL auto-calibration (documented as a caveat only).
- Serial for the ATmega328 target (it has a real UART and its own path;
  unaffected here).

## 7. Verification

- Build: `pio run -d firmware/blink_attiny85 -e blink_attiny85` → `[SUCCESS]`,
  `TinySoftwareSerial` links, hex produced.
- Flash: `make blink CHIP=attiny85` → writes + verifies.
- Runtime (ISP rig): LED blinks 500/500 on pin 3.
- Serial (pass-through rig): `make console BAUD=9600` shows `blink <n>` ~1/s, and
  typed characters echo back. PASS = both the heartbeat prints and the echo work.
