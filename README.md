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

## One-time: make the Nano a programmer
    make isp                 # uploads ArduinoISP to the Nano (heartbeat LED breathes)

Then wire the 6 ISP lines Nano→target (spec §5) with the 10 µF cap on the Nano's RESET.

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

## Adding a new ISP chip
Add a `CHIP` block to `profiles.mk` (part, signature, fuses, clock) and — if you want a
blink verifier — a `firmware/blink<x>/` project (its own `platformio.ini` + `src/main.cpp`,
env named like the folder). No Makefile changes.

## Ports
The Nano's COM port varies between machines/cables. Default is `COM4`; find yours with
`pio device list` and pass `PORT=COMx`.
