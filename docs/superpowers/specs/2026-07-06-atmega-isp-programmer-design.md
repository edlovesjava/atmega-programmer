---
title: "ATmega ISP Programmer — Design Spec (Stage 1: Breadboard)"
description: A PlatformIO + Makefile toolkit that turns an Arduino Nano (Lafvin clone) into an Arduino-as-ISP programmer for AVR targets — read signature, set fuses, burn bootloader, flash firmware, and open a serial console — starting with ATmega328P/328 on a breadboard.
type: spec
status: draft
stage: breadboard-prototype
created: 2026-07-06
tags:
  - electronics
  - avr
  - isp
  - programmer
  - platformio
  - avrdude
  - spec
  - breadboard
---
# ATmega ISP Programmer — Design Spec

**Stage 1: Breadboard Prototype** · Status: `draft` · Created: 2026-07-06

> A reusable "programmer workstation" repo. An Arduino Nano runs the **ArduinoISP** firmware and acts as an in-system programmer for AVR targets over the 6-wire SPI/ISP interface. The repo bundles the programmer firmware, per-target verification firmware, and a Makefile that wraps `avrdude` for the common operations.
>
> **Scope note:** This project covers the **ISP family only** (SPI-programmed AVRs: ATmega328P/328, ATtiny, etc.). The **ATmega4809 / megaAVR-0** uses the UPDI interface and needs a different firmware (jtag2updi), wiring, and core (MegaCoreX) — it gets its **own sibling project**, not an env here.

---

## 1. Overview

An Arduino Nano (Lafvin clone) flashed with the stock **ArduinoISP** sketch becomes an ISP programmer. From the host, `avrdude` talks to it using the **`stk500v1` protocol at 19200 baud** and drives the target AVR over six wires (MOSI, MISO, SCK, RESET, VCC, GND). With this rig you can:

- **Identify** a target (read its device signature).
- **Set fuses** (e.g. select a 16 MHz external crystal on a fresh chip).
- **Burn a bootloader** (e.g. Optiboot) so the target can later self-program over serial.
- **Flash firmware** — either verification firmware built in this repo, or an arbitrary external `.hex`.
- **Open a serial console** to a running target over a **separate USB-TTL adapter** (see §7).

Stage 1 validates the whole flow on a **solderless breadboard** with the Nano plugged in via header pins, status LEDs, and jumpers. The circuit and toolchain are intended to stay constant as the physical build progresses to perf board and PCB (see §10 Roadmap).

## 2. Goals & Non-Goals

### Goals
- Flash the **ArduinoISP** firmware onto the Nano with one command.
- Program AVR targets over ISP: **read signature, set fuses, burn bootloader, flash `.hex`**.
- Support a set of **target profiles** (§8) as *data*, so adding a chip is a config entry, not new code.
- Ship minimal **per-target "blink" verification firmware** to prove a freshly-programmed chip actually runs.
- Provide a **serial console** mode for a running target via a separate USB-TTL.
- Reuse the house pattern: **PlatformIO for builds + a Makefile wrapping avrdude**, matching `capacitance_meter_button` and `attiny-bare`.

### Non-Goals (this project)
- **UPDI / megaAVR-0 (ATmega4809)** — separate sibling project (different interface, firmware, core).
- High-voltage programming (HVPP/HVSP) to recover fuse-locked chips.
- A GUI. Command-line (`make` + `pio`) only.
- Simultaneous ISP-and-console on the one Nano (physically precluded — see §7).

## 3. Functional Requirements

| # | Requirement |
|---|---|
| FR-1 | One command flashes ArduinoISP onto the Nano (`board = nanoatmega328`). |
| FR-2 | Read a target's device signature and report the matching profile. |
| FR-3 | Write fuse bytes to a target from its profile (lfuse/hfuse/efuse). |
| FR-4 | Burn a bootloader to a target (where the profile defines one). |
| FR-5 | Flash a `.hex` to a target — either built-in verification firmware or an external file in `hex/`. |
| FR-6 | Select the operating target by a single variable (e.g. `make flash CHIP=328p`). |
| FR-7 | Support the non-P **ATmega328** (`-p m328`, signature `0x1E9514`) distinctly from the **328P** (`-p m328p`, `0x1E950F`). |
| FR-8 | Provide a serial console mode against a chosen port/baud via a separate USB-TTL adapter. |
| FR-9 | Target profiles are declared as data; adding a new ISP AVR requires no new build code. |

## 4. Hardware Architecture (Stage 1 — Breadboard)

```
        Host PC ──USB──► Arduino Nano (Lafvin) ──6-wire ISP──► Target AVR on breadboard
                         running ArduinoISP                     (e.g. ATmega328P + 16MHz xtal)
                         LEDs: heartbeat / err / prog

        (console mode, separate)  Host PC ──USB──► USB-TTL ──TX/RX──► Target UART (D0/D1)
```

### Blocks
1. **Programmer host — Arduino Nano.** Plugged into the breadboard via its header pins, powered/enumerated over USB. Runs ArduinoISP. A **10 µF cap between Nano RESET and GND** prevents the Nano from auto-resetting when the host opens the port.
2. **Status LEDs** (ArduinoISP convention): **D9 = heartbeat** (alive), **D8 = error**, **D7 = programming/PMODE**. Each via a current-limiting resistor (~330 Ω–1 kΩ) to GND.
3. **Target circuit.** For the raw ATmega328/328P (pin-identical): DIP-28 on the breadboard with **0.1 µF** decoupling on VCC (pin 7) and AVCC (pin 20), and a **10 kΩ pull-up on RESET** (pin 1) to VCC. Powered by the breadboard 5 V supply. The **16 MHz crystal** across XTAL1/XTAL2 (pins 9/10) with **2× 22 pF** load caps is **optional and required only to *run* at 16 MHz** — ISP itself (read signature, fuses, flash) works on the chip's factory internal oscillator (8 MHz ÷ 8 = 1 MHz) with **no crystal**. Add the crystal, *then* `make fuses` to switch the clock to it (setting the crystal fuse with no crystal present makes the chip unresponsive to ISP). Board targets (Pro Mini) bring their own support circuitry and just expose the ISP header.
4. **ISP jumpers.** Six jumpers carry the ISP signals from the Nano to the target (table below).
5. **Console link (separate).** A USB-TTL adapter to the target's UART (D0/D1) for §7.

## 5. Wiring

### ISP — Nano (programmer) → Target

| Nano pin | Signal | ATmega328/328P DIP pin | ATtiny85 pin |
|---|---|---|---|
| D13 | SCK  | 19 (PB5) | 7 (PB2) |
| D12 | MISO | 18 (PB4) | 6 (PB1) |
| D11 | MOSI | 17 (PB3) | 5 (PB0) |
| D10 | RESET (target /RESET) | 1 | 1 |
| 5V  | VCC | 7 (+ AVCC pin 20) | 8 |
| GND | GND | 8 (+ 22) | 4 |

(328 and 328P are pin-identical — same wiring; only the signature / `CHIP=` differs.)

### Target support components (328/328P breadboard)

| Part | Placement | Purpose |
|---|---|---|
| 0.1 µF ×2 | pin 7 ↔ 8, and pin 20 ↔ 22 | decoupling |
| 10 kΩ | pin 1 (RESET) → **VCC** | RESET pull-up |
| 16 MHz crystal + 2×22 pF | pins 9 ↔ 10, caps to GND | **optional** — only to *run* at 16 MHz (see §4) |

**The 10 µF cap between the *Nano's* RESET and GND** is required *while using the Nano as a programmer* (it blocks the port-open auto-reset that desyncs avrdude → `cannot obtain SW version`). **Remove it when running `make isp`** (flashing ArduinoISP onto the Nano needs the auto-reset). For board targets (Pro Mini) the same six signals go to the onboard 2×3 ISP header instead of chip pins.

### Target — ATtiny85 (DIP-8)

The ATtiny85 uses the six ISP signals from the table above (pin 1 RESET, 5 MOSI,
6 MISO, 7 SCK, 8 VCC, 4 GND). It runs on its **8 MHz internal oscillator** — no
crystal, ever (the verify firmware is built for 8 MHz, so blink timing is real).

```
        ATtiny85 (DIP-8), notch/dot = pin-1 end

  D10 RESET ── PB5 │1 •   8│ VCC ── 5V
      (unused) PB3 │2     7│ PB2 ── SCK  (D13)
   verify LED  PB4 │3     6│ PB1 ── MISO (D12) / Serial RX
          GND  GND │4     5│ PB0 ── MOSI (D11) / Serial TX
                   └───────┘

  Pins 5/6/7 do double duty: MOSI/MISO/SCK during ISP,
  Serial TX/RX during the serial mode below.
```

| Part | Placement | Purpose |
|---|---|---|
| 0.1 µF | pin 8 ↔ 4 | decoupling |
| 10 kΩ | pin 1 (RESET) → **VCC** | RESET pull-up |
| Verify LED + ~330 Ω–1 kΩ | **pin 3 (PB4)** → LED → resistor → GND | `make blink` indicator |

The verify LED is on **PB4 (pin 3)**, not the MOSI pin, because the firmware's
software-serial **TX is fixed to PB0 (pin 5)** — see below.

### Serial monitor — Nano as pass-through (ATtiny85)

The ATtiny85 has **no hardware UART**. The Arduino core provides `Serial` via a
bit-banged `TinySoftwareSerial` on **fixed** pins — **TX = PB0 (pin 5)**,
**RX = PB1 (pin 6)** — at **9600 baud** (the most forgiving rate for the internal
RC oscillator). This is a **separate mode from ISP**: flash over the ISP rig first,
then rewire. Rather than a separate USB-TTL adapter, the Nano itself becomes the
bridge — hold its ATmega328 in reset so the D0/D1 headers pass straight to the
onboard CH340:

| Connection | Purpose |
|---|---|
| Nano **RESET → GND** | holds the 328 in reset; D0/D1 become the CH340's lines |
| ATtiny **pin 5 (PB0, TX) → Nano D1** | target → PC |
| ATtiny **pin 6 (PB1, RX) → Nano D0** | PC → target |
| Nano **5V → pin 8**, **GND → pin 4** | power + common ground |
| *(remove the D10–D13 ISP wires)* | not used in serial mode |

Then `make console` (defaults `PORT=COM4 BAUD=9600`). **Same-label wiring (TX→D1,
RX→D0) is correct here** because, with the 328 held in reset, the D0/D1 headers
*are* the CH340's lines — the inverse of normal crossover, since you tap behind the
header labels. Garbled characters indicate 8 MHz-oscillator tolerance, not a wiring
fault (OSCCAL tuning is the deeper fix).

### Status LEDs (on the Nano's programmer pins)

| Nano pin | LED | Meaning |
|---|---|---|
| D9 | Heartbeat | Sketch alive (breathing) |
| D8 | Error | Last operation failed |
| D7 | Programming | ISP session active |

## 6. Software Architecture

**Hybrid: PlatformIO builds + a Makefile wrapping avrdude.**

```
ATmega-Programmer/
  Makefile
  profiles.mk              # target profile data (avrdude part, clock, fuses, notes)
  firmware/                # one standalone PlatformIO PROJECT per firmware (see note)
    arduinoisp/            # ArduinoISP -> the Nano            (env: programmer)
      platformio.ini
      src/ArduinoISP.ino
    blink328/              # 16 MHz blink -> 328/328P verify   (env: blink328)
      platformio.ini
      src/main.cpp
    blink_attiny85/        # 8 MHz blink  -> ATtiny85 verify   (env: blink_attiny85)
      platformio.ini
      src/main.cpp
  bootloaders/             # vendored Optiboot image(s) for `make bootloader`
  hex/                     # drop external .hex files here to flash
  docs/                    # this spec, wiring photos, fuse notes
```

> **As-built note:** Each firmware is its **own** PlatformIO project (own `platformio.ini`, source under `src/`), built with `pio run -d firmware/<x>`. PlatformIO does not compile a `.ino` that lives in a subdirectory of a shared `src_dir`, and a shared `src_dir` would cross-compile every firmware's `setup()/loop()` together — per-project isolation avoids both and keeps the vendored ArduinoISP sketch verbatim.

### PlatformIO envs
- **`programmer`** — `platform=atmelavr`, `board=nanoatmega328`, `framework=arduino`; source is the vendored ArduinoISP sketch. `make isp` → `pio run -d firmware/arduinoisp -e programmer -t upload`.
- **Verification envs** (`blink328`, `blink_attiny85`, …) — each **builds** for its target MCU/clock; the Makefile then **flashes the built `.hex` through the Nano with avrdude** (one avrdude flash path for all chips), rather than uploading from PlatformIO.

### Makefile operations (chip selected by `CHIP=`)
| Command | Action |
|---|---|
| `make isp` | Flash ArduinoISP onto the Nano |
| `make id CHIP=328p` | Read + report device signature |
| `make fuses CHIP=328p` | Write the profile's fuse bytes |
| `make bootloader CHIP=328p` | Burn the profile's bootloader |
| `make blink CHIP=328p` | Build + upload the verification blink (via PIO) |
| `make flash CHIP=328p HEX=hex/foo.hex` | Flash an external hex via avrdude |
| `make console PORT=COM7 BAUD=9600` | Serial monitor to a target (separate USB-TTL) |

Under the hood every avrdude call is the same shape as `attiny-bare`:
`avrdude -c stk500v1 -p <part> -P <PORT> -b 19200 -U ...`, with `<part>` and fuse bytes pulled from `profiles.mk`.

**Port default:** the Nano's serial port is exposed as a `PORT=` variable defaulting to **`COM4`** (the current rig). Override per-invocation, e.g. `make id CHIP=328 PORT=COM7`.

## 7. Console Mode (TX/RX)

The ArduinoISP sketch **occupies the Nano's USB serial** for the stk500v1 protocol, so the Nano cannot simultaneously be an ISP programmer and a serial console. Console mode therefore uses a **separate USB-TTL adapter** wired to the target's UART:

| USB-TTL | Target (ATmega328P) |
|---|---|
| TX | D0 / RXD (PD0, pin 2) |
| RX | D1 / TXD (PD1, pin 3) |
| GND | GND |

(Cross-over: adapter TX → target RX, adapter RX → target TX; share GND; do **not** cross VCC.) `make console` just opens a serial monitor on that adapter's port. This also ties into the "usb to ttl communication connector" tool already on the knowledge-base tool list.

## 8. Target Profiles (v1)

Profiles are data in `profiles.mk`. Fuse bytes below are the **no-bootloader, program-via-ISP** baseline; the Arduino/Optiboot variants differ (see §9). MiniCore is the recommended source of truth for exact bytes.

| `CHIP` | avrdude `-p` | Signature | Clock | Notes |
|---|---|---|---|---|
| `328`  | `m328`  | `0x1E9514` | 16 MHz xtal | **primary raw-DIP rig (first target chip)**; non-P, distinct signature |
| `328p` | `m328p` | `0x1E950F` | 16 MHz xtal | pin-compatible P variant |
| `promini16` | `m328p` | `0x1E950F` | 16 MHz | 5V board via onboard ISP header |
| `promini8`  | `m328p` | `0x1E950F` | 8 MHz | 3.3V board; **level caveat** (see below) |
| `attiny85` | `attiny85` | `0x1E930B` | 8 MHz int | already documented in `attiny85_programmer` |

**Pro Mini 3.3V caveat:** driving 5 V ISP signals into a 3.3 V-powered part is out of spec. Either power it at 5 V during programming or use a 3.3 V-level ISP.

## 9. Fuse Reference (ATmega328P / 328)

| Use case | lfuse | hfuse | efuse | Meaning |
|---|---|---|---|---|
| 16 MHz xtal, **no bootloader** (ISP upload) | `0xFF` | `0xD9` | `0xFD` | full-swing crystal; BOOTRST off; BOD 2.7 V |
| 16 MHz xtal, **Optiboot** (Uno-style) | `0xFF` | `0xDE` | `0xFD` | as above + boot reset vector |

A **fresh 328P ships on the internal 8 MHz osc** (`lfuse 0x62`) — ISP still works in that state, but the chip won't run at 16 MHz until these fuses are written. ATtiny85 profile uses the documented `lfuse 0xE2 / hfuse 0xDF / efuse 0xFF` (8 MHz internal).

## 10. Roadmap — Future Stages

*(Brief note only; each stage gets its own spec when reached.)*

- **Stage 1 — Breadboard (this spec).** Nano plugged in via headers, LEDs + jumpers, 6-wire ISP; later add the separate USB-TTL console. Validate the full toolchain.
- **Stage 2 — Perf board.** Solder the validated rig: fixed Nano socket, LEDs, a proper 2×3 ISP header, and a target socket. Durable and repeatable.
- **Stage 3 — PCB, possibly with ZIF.** KiCad layout; a **ZIF socket** for the 28-pin DIP so chips can be dropped in/out without pin wear; silkscreen labeling; consider selectable 3.3 V/5 V programming rails.
- **Sibling project — megaAVR-0 (UPDI).** ATmega4809 via jtag2updi + MegaCoreX; separate repo sharing these Makefile/PlatformIO conventions.

## 11. Validation — Stage 1 Acceptance Criteria

| # | Test | Pass criteria |
|---|---|---|
| V-1 | Load ArduinoISP | `make isp` uploads to the Nano; heartbeat LED breathes. |
| V-2 | Signature read (328P) | `make id CHIP=328p` returns `0x1E950F`; profile matches. |
| V-3 | Signature read (non-P 328) | `make id CHIP=328` returns `0x1E9514`; no false 328P match. |
| V-4 | Fuses | `make fuses CHIP=328p` sets 16 MHz-xtal fuses; readback confirms. |
| V-5 | Blink verify | `make blink CHIP=328p` runs; LED blinks at the rate implied by 16 MHz (proves clock/fuses). |
| V-6 | External hex | `make flash CHIP=328p HEX=…` flashes and verifies an arbitrary hex. |
| V-7 | Bootloader | `make bootloader CHIP=328p` burns Optiboot; chip then accepts a serial upload. |
| V-8 | Console | `make console` shows target UART output over the separate USB-TTL. |
| V-9 | ATtiny target | `make id/blink CHIP=attiny85` works, proving the profile system generalizes. |

## 12. Decisions & Remaining Risks

Resolved 2026-07-06:

- **COM port — RESOLVED.** `PORT=` variable defaulting to **`COM4`** (current rig); override per-invocation. Auto-detect deferred to a later stage.
- **Non-P as first target — RESOLVED.** The **non-P ATmega328** (sig `0x1E9514`, part `m328`) is the primary first chip and gets the 16 MHz-xtal no-bootloader fuses (`lfuse 0xFF / hfuse 0xD9 / efuse 0xFD`). *Risk to watch:* confirm avrdude distinguishes `m328` vs `m328p` without `-F`; document if a force flag ever proves necessary.
- **Pro Mini 3.3V — RESOLVED.** Program at **5 V** for now; no level shifting. `promini8` stays a documented profile but is not exercised until a level-shift approach is chosen.
- **ArduinoISP source — RESOLVED.** **Vendor** the sketch into the repo (`firmware/arduinoisp/`) so the build is self-contained.
- **Bootloader fuse bytes — RESOLVED (approach).** Defer to **MiniCore** (`-t fuses` / burn-bootloader) as the source of truth for bootloader+fuse combos; keep hand-maintained bytes only for the no-bootloader ISP baseline in §9. Exact per-variant bytes still to be captured from MiniCore when Stage 1 reaches V-7.
