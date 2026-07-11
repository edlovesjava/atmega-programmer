# jtag2updi Programmer (Phase 1) — Design

**Date:** 2026-07-09
**Status:** Approved (brainstorm), pending implementation plan
**Parent project:** ATmega ISP Programmer (`docs/superpowers/specs/2026-07-06-atmega-isp-programmer-design.md`)

## 1. Goal

Give this repo the ability to **build a second kind of programmer**: compile the
jtag2updi firmware and flash it onto a bare ATmega328, turning that 328 into a
**UPDI programmer** for the megaAVR-0 family (ATmega4809, etc.). The repo already
builds one programmer (`make isp` → ArduinoISP on the Nano); this adds the parallel
`jtag2updi`-on-a-328 path, bootstrapped by the ISP programmer it already has.

This is **Phase 1** only — *building* the programmer. Actually *using* it to program
and blink an ATmega4809 (megaAVR-0 profile, `-c jtag2updi` operations, MegaCoreX
verifier, 40-pin DIP wiring) is a separate follow-on spec (Phase 2).

## 2. The recursive/bootstrap shape

```
ISP programmer (Nano + ArduinoISP, existing)
      │  flashes jtag2updi firmware onto…
      ▼
bare ATmega328 + 16 MHz crystal + USB-TTL   ◄── becomes the UPDI programmer
      │  (Phase 2) drives UPDI via avrdude -c jtag2updi
      ▼
ATmega4809 target
```

A "Nano" is just a 328 + USB-serial chip + crystal + bootloader on a board; jtag2updi
is firmware that runs *on the 328*. Supplying those parts ourselves (a 328 the ISP
programmer can flash, a USB-TTL, a crystal) builds an equivalent programmer from parts.

## 3. Prerequisites already validated on hardware (2026-07-09)

The serial path this design leans on is proven (parent-repo V-6…V-8): `make bootloader`
burns Optiboot; a CP2102 USB-TTL flashes over the bootloader (`avrdude -c arduino -b
115200`); blink + serial heartbeat confirmed. So "flash jtag2updi over the USB-TTL" is
just "swap the hex."

Two bench facts that shape this design:
- **Optiboot reports a compile-time signature.** The vendored Optiboot is the 328P
  build, so over the bootloader a genuine non-P 328 answers `1E950F` → serial avrdude
  must use `-p m328p`. Handled via the `BLPART` profile field (§5).
- **A CP2102 without DTR/RTS needs a manual RESET tap** timed to Optiboot's ~1 s window.
  The Makefile can't tap RESET; the recipe runs avrdude and the operator taps.

## 4. Component: `firmware/jtag2updi/`

A standalone PlatformIO project (same pattern as `firmware/blink328`), holding the
**vendored jtag2updi source** built for a **16 MHz external-crystal ATmega328**.

- **Source:** vendor `ElTangas/jtag2updi` (the canonical fork). Copy its sketch +
  `source/` files into `firmware/jtag2updi/src/`. Record provenance (repo URL + commit)
  and the upstream `LICENSE` in the folder.
- **`platformio.ini`:** `board = ATmega328P`, `board_build.f_cpu = 16000000L`,
  `board_hardware.oscillator = external` — matching `blink328` (jtag2updi's serial
  timing assumes 16 MHz). Env named `jtag2updi`.
- **UPDI output pin:** jtag2updi's default (Arduino **D6 = PD6**), confirmed against the
  vendored `sys.h` during implementation; used in Phase 2 wiring (target UPDI via a
  ~4.7 kΩ series resistor).
- Builds to `firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex`.

## 5. Component: `profiles.mk` — `BLPART`

Add a **bootloader-part** field to the profiles, because the signature seen *over the
bootloader* is the Optiboot compile-time value, not the silicon:

- `328` block: `BLPART := m328p`
- `328p` block: `BLPART := m328p`
- `attiny85` block: `BLPART :=` (empty — no bootloader profile; serial ops are refused)

`BLPART` is always `m328p` today (the vendored Optiboot is the 328P build), but making
it a per-profile field means a chip whose bootloader reports a different signature just
sets its own value — no Makefile change.

## 6. Component: `Makefile` — serial-flash capability

New serial (bootloader) flash path, parallel to the existing ISP `AVRDUDE`:

```make
BLBAUD ?= 115200                                   # Optiboot serial baud
SERIALDUDE := avrdude -c arduino -p $(BLPART) -P $(PORT) -b $(BLBAUD)
```

New targets:

- **`serialflash`** — flash an arbitrary hex over the target's Optiboot bootloader via
  the USB-TTL. Guards: `HEX` set, and `BLPART` non-empty (else the chip has no
  bootloader path). Parallels `flash` (ISP) but uses `SERIALDUDE`.
  ```
  make serialflash CHIP=328 HEX=path/to.hex PORT=COM16
  ```
- **`jtag2updi`** — convenience: build `firmware/jtag2updi`, then serial-flash it onto
  the 328. Parallels `make isp` (which builds+flashes ArduinoISP onto the Nano); this
  builds+flashes jtag2updi onto the 328.
  ```
  make jtag2updi CHIP=328 PORT=COM16
  ```

`make help` gains both targets, each noting **PORT is the USB-TTL port (not the Nano's
COM4)** and that boards without DTR/RTS auto-reset need a **manual RESET tap** as avrdude
starts. The existing ISP path (`make flash CHIP=328 HEX=…`, via the Nano) remains a valid
alternative way to put jtag2updi on the 328 — more reliable (no manual tap) when the Nano
rig is already wired.

## 7. Error handling

- `serialflash`/`jtag2updi` with empty `BLPART` (e.g. `CHIP=attiny85`) → clear error
  ("CHIP='…' has no bootloader/serial path"), non-zero exit — same style as the existing
  `bootloader` guard.
- `serialflash` with no `HEX` → error, like `flash`.
- `DRYRUN=1` prints the composed `SERIALDUDE` command without running it (same as other
  targets), so the wiring/port can be checked hardware-free.

## 8. Verification

- **Build:** `pio run -d firmware/jtag2updi -e jtag2updi` → `[SUCCESS]`, hex produced.
- **Flash (bench):** `make jtag2updi CHIP=328 PORT=COM16` → avrdude writes+verifies over
  the bootloader (manual RESET tap). Optiboot is untouched (bootloader-section write is
  separate), so jtag2updi runs after power-up timeout.
- **Programmer-alive (bench):** `avrdude -c jtag2updi -P COM16 -p m4809` reaches the
  programmer — i.e. jtag2updi *answers* (vs "programmer not responding"). With **no 4809
  attached**, the subsequent target-read fails; that is expected. PASS for Phase 1 =
  jtag2updi builds, flashes, and answers avrdude. **End-to-end reading/flashing a real
  4809 is Phase 2** (needs the target chip + UPDI wiring).

## 9. Out of scope (→ Phase 2 spec)

- megaAVR-0 profile (ATmega4809 signature, `FUSE`/config bytes, MegaCoreX env).
- `id`/`fuses`/`flash`/`blink` operations over `-c jtag2updi` against the 4809.
- ATmega4809 40-pin DIP wiring (UPDI + power) and a MegaCoreX blink verifier.
- SerialUPDI (pymcuprog / `-c serialupdi`) as an alternative UPDI method.
- DTR/RTS auto-reset hardware (a cap-coupled adapter) — documented workaround only.
- **Rebuilding Optiboot as a true non-P `atmega328` build** (so it reports `1E9514`
  over the bootloader and serial ops could use `-p m328`) — deferred as optional
  cosmetic cleanup. It changes nothing functional (328P Optiboot runs fine on the non-P
  328; `BLPART=m328p` already handles the reported-signature mismatch). If ever wanted,
  MiniCore can burn a chip-matched bootloader, or build Optiboot with `MCU=atmega328`.
