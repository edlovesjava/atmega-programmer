# ATmega ISP Programmer

An Arduino Nano running **ArduinoISP** as an in-system programmer for ISP-family AVRs
(ATmega328/328P, ATtiny85). PlatformIO builds the firmware; a Makefile drives every
chip operation through `avrdude` (`stk500v1` @ 19200 baud).

Full design, wiring diagrams, and the fuse reference:
**`docs/superpowers/specs/2026-07-06-atmega-isp-programmer-design.md`**

## Prerequisites
- PlatformIO Core (`pio`) and `avrdude` on PATH
- An Arduino Nano + the breadboard rig from spec §4–§5
- A separate USB-TTL adapter for `console` (spec §7)
- On Windows, run `make`/`pio` from **Git Bash** (the Makefile uses POSIX `sh`).

> **First build downloads toolchains.** The target blink projects use MiniCore
> (`ATmega328P`) and ATtiny cores. The first `pio run` (via `make blink`) auto-downloads
> these platform packages — a one-time several-minute step, not a hang.

## One-time: make the Nano a programmer
    make isp                 # uploads ArduinoISP to the Nano (heartbeat LED breathes)

Then wire the ISP lines Nano→target (below). Full diagrams and the fuse reference are in the spec.

## Wiring

### Programmer — Arduino Nano (runs ArduinoISP)

| Nano pin | Signal | → goes to target |
|---|---|---|
| D13 | SCK  | SCK |
| D12 | MISO | MISO |
| D11 | MOSI | MOSI |
| D10 | RESET | target /RESET |
| 5V  | VCC  | target VCC (powers the target) |
| GND | GND  | target GND |

- **Status LEDs** (optional, but handy): D9 = heartbeat (breathing = alive), D8 = error, D7 = programming. Each via ~330 Ω–1 kΩ to GND.
- **10 µF cap, Nano RESET ↔ GND:** keep it **installed while using the Nano as a programmer** (it blocks the auto-reset that would desync avrdude → `cannot obtain SW version`). **Remove it only when running `make isp`** (flashing ArduinoISP onto the Nano needs the auto-reset).

### Target — ATmega328 / 328P on a breadboard (DIP-28)

The 328 and 328P are **pin-identical** — same wiring; only the signature/`CHIP=` differs.

| Nano pin | 328/328P DIP pin |
|---|---|
| D10 (RESET) | 1 |
| D11 (MOSI) | 17 (PB3) |
| D12 (MISO) | 18 (PB4) |
| D13 (SCK) | 19 (PB5) |
| 5V | 7 (VCC) **and** 20 (AVCC) |
| GND | 8 (GND) **and** 22 (GND) |

Support parts on the breadboard:
- **0.1 µF** decoupling: pin 7 ↔ 8, and pin 20 ↔ 22.
- **10 kΩ** pull-up: pin 1 (RESET) → **VCC** (not GND).
- Chip orientation: the **notch/dot marks the pin-1 end** — pin 1 top-left.

### Optional — external 16 MHz oscillator (crystal)

**You do not need the crystal to read or program a chip over ISP.** A fresh 328/328P runs
on its internal oscillator (8 MHz ÷ 8 = 1 MHz) and answers ISP fine without one. Add the
crystal only when you want the chip to *run at 16 MHz*:

- **16 MHz crystal** across pins **9 (XTAL1)** and **10 (XTAL2)**, each with a **22 pF cap to GND**.
- Then `make fuses CHIP=328` to switch the clock source to the crystal (`lfuse=0xFF`).
- Order matters: **wire the crystal first, then set the fuses.** Setting the crystal fuse
  with no crystal present makes the chip unresponsive to ISP until you add one.

### Target — ATtiny85 on a breadboard (DIP-8)

Same six ISP signals, different pinout. The ATtiny85 runs on its **8 MHz internal
oscillator** — no crystal, ever (its blink is built for 8 MHz, so timing is correct as-is).

| Nano pin | ATtiny85 DIP pin |
|---|---|
| D10 (RESET) | 1 (/RESET) |
| D11 (MOSI) | 5 (PB0) |
| D12 (MISO) | 6 (PB1) |
| D13 (SCK) | 7 (PB2) |
| 5V | 8 (VCC) |
| GND | 4 (GND) |

Support parts on the breadboard:
- **0.1 µF** decoupling: pin 8 ↔ 4.
- **10 kΩ** pull-up: pin 1 (RESET) → **VCC**.
- Chip orientation: the **notch/dot marks the pin-1 end**.
- **Verify LED** (for `make blink`): physical **pin 3 (PB4)** → LED → ~330 Ω–1 kΩ → GND. (Pin 3 is used because the firmware's `Serial` TX is fixed to pin 5.)

The `make bootloader` target is intentionally refused for `attiny85` (no bootloader this stage);
`make id` / `make blink` / `make fuses` / `make flash` all work with `CHIP=attiny85`.

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

## Everyday commands
`CHIP` selects the target (`328` = non-P primary, `328p`, `attiny85`).
`PORT` defaults to `COM4`; override anytime. Append `DRYRUN=1` to preview a command.

| Command | Does |
|---|---|
| `make id CHIP=328` | Read + report device signature |
| `make fuses CHIP=328` | Write the profile's fuse bytes (16 MHz xtal) |
| `make bootloader CHIP=328` | Burn Optiboot |
| `make blink CHIP=328` | Build + flash the verification blink |
| `make flash CHIP=328 HEX=hex/foo.hex` | Flash an external hex |
| `make console PORT=COM7 BAUD=9600` | Serial monitor via a separate USB-TTL |
| `make show CHIP=328` | Print the resolved profile |
| `make help` | List all targets |

> ⚠️ **`make fuses CHIP=328` needs the crystal wired first.** It sets `lfuse=0xFF`
> (external 16 MHz crystal). After that write the chip **will not respond to ISP or run**
> unless a working 16 MHz crystal + 2×22 pF caps are present on XTAL1/XTAL2. A fresh chip
> (8 MHz internal) is fine to program; just wire the crystal before writing fuses.

> **`make bootloader` → serial uploads at 115200.** The vendored Optiboot runs its serial
> bootloader at **115200 baud** (not the `9600` console default). Use `BAUD=115200` when
> uploading a sketch to the target over serial after burning the bootloader.

## Adding a new ISP chip
Add a `CHIP` block to `profiles.mk` (part, signature, fuses, clock) and — if you want a
blink verifier — a `firmware/blink<x>/` project (its own `platformio.ini` + `src/main.cpp`,
env named like the folder). No Makefile changes.

## Ports
The Nano's COM port varies between machines/cables. Default is `COM4`; find yours with
`pio device list` and pass `PORT=COMx`.

## Troubleshooting

**`make id` returns `00 00 00` or `FF FF FF` (no valid signature).** The programmer is fine
(the handshake worked); the *target* isn't answering. In order of likelihood:
1. **Chip seating / breadboard contact — the #1 cause, by far.** Reseat the chip firmly (a
   cheap breadboard may not grip the legs — press it fully home), move to fresh rows, or use a
   machined-pin / ZIF socket. A reading that *changes* between tries, or appears only when you
   *press* on the chip, is the obvious tell — but a **steady** `00`/`FF` across several chips can
   *also* be pure seating, so don't assume it's a wiring short. (In this project's bring-up, a
   rock-steady `00 00 00` on every chip turned out to be a poorly-seated chip in a low-quality
   breadboard — reseating fixed it, no wiring change.) Electrically, `FF FF FF` = MISO floating
   high (open), `00 00 00` = MISO held low — but both usually trace back to contact, not a short.
2. **Orientation / swapped pins** — notch to the pin-1 end; MOSI (pin 17) and MISO (pin 18) not crossed.
3. **Power** — confirm ~5 V across pin 7 ↔ 8 (and 20 ↔ 22).
4. It is **not** a missing bootloader or missing crystal — ISP needs neither to read a fresh chip.

**`make isp` fails: `stk500_getsync(): not in sync: resp=0x1c`.** Nano bootloader baud mismatch.
This repo pins `upload_speed = 115200` in `firmware/arduinoisp/platformio.ini` (new-bootloader
clone Nanos). For an old-bootloader Nano, change it to `57600`.

**Running avrdude by hand?**
- Always include **`-b 19200`** — `-c stk500v1` defaults to 115200 and fails "not in sync" without it.
- `-c stk500v1` talks *through* ArduinoISP to your **target**. `-c arduino` talks to the **Nano's own
  bootloader** — that reads the *Nano itself* (a 328P), not your breadboard chip. Don't confuse them.

**Blink runs way too slow (~8 s instead of ~0.5 s).** The chip is on its 1 MHz internal clock while
the firmware was built for 16 MHz (16× slow). Wire the crystal and run `make fuses CHIP=…` to switch
the clock to 16 MHz — the blink jumps to the correct rate.
