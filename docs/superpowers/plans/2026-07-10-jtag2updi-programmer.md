# jtag2updi Programmer (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the repo a second programmer path — build the jtag2updi firmware and serial-flash it onto a bare ATmega328, turning that 328 into a UPDI programmer for the megaAVR-0 family.

**Architecture:** A new standalone PlatformIO project `firmware/jtag2updi/` holds the vendored `ElTangas/jtag2updi` source and builds it to a hex. `profiles.mk` gains a per-chip `BLPART` field (the signature Optiboot reports over the bootloader). The `Makefile` gains a `SERIALDUDE` invocation plus two targets: `serialflash` (flash any hex over Optiboot via a USB-TTL) and `jtag2updi` (build + serial-flash the firmware). No hardware is required to verify — every Makefile change is checked with `DRYRUN=1`, and the firmware is checked with a `pio run` build.

**Tech Stack:** PlatformIO (`atmelavr` platform), avr-gcc, GNU Make (POSIX `sh` recipes run under Git Bash on Windows), avrdude.

## Global Constraints

Copied verbatim from `docs/superpowers/specs/2026-07-09-jtag2updi-programmer-design.md`. Every task's requirements implicitly include these.

- **Host is a 16 MHz external-crystal ATmega328.** jtag2updi's serial timing assumes `F_CPU = 16000000`.
- **`BLPART` is `m328p` for both 328 and 328p, empty for attiny85.** The vendored Optiboot is the 328P build, so over the bootloader even a non-P 328 answers `1E950F` and serial avrdude must use `-p m328p`.
- **Serial `PORT` is the USB-TTL adapter's port, NOT the Nano's `COM4`.** The existing ISP path uses the Nano; the serial path uses a separate USB-TTL wired to the 328.
- **A CP2102 without DTR/RTS needs a manual RESET tap** timed to Optiboot's ~1 s window as avrdude starts. The Makefile cannot tap RESET; the operator does.
- **`DRYRUN=1` must print the composed command without running it** for every new target (same as existing targets).
- **jtag2updi's default UPDI pin is Arduino D6 = PD6** (the ATmega328 OC0A pin); used in Phase 2 wiring. No config change needed — it is the upstream default for the mega328P host.
- **PlatformIO env name is `jtag2updi`**; the built hex lands at `firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex`.

---

### Task 1: `firmware/jtag2updi/` — vendored firmware that builds to a hex

**Files:**
- Create: `firmware/jtag2updi/src/*.cpp`, `firmware/jtag2updi/src/*.h` (vendored from upstream `source/`)
- Create: `firmware/jtag2updi/platformio.ini`
- Create: `firmware/jtag2updi/PROVENANCE.md`
- Create: `firmware/jtag2updi/LICENSE` (copied from upstream)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: a build hex at `firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex`. Tasks 4 relies on this exact path.

**Why framework-less (read before writing `platformio.ini`):** Upstream `source/jtag2updi.cpp` defines its own `int main(void)`. PlatformIO's `framework = arduino` links the Arduino core, which *also* defines `main()` → a duplicate-`main` link error. So this project must be **framework-less** (`platform = atmelavr` with no `framework` line), mirroring upstream's bare `avr-g++` build in `make.sh`. This is the one place this project intentionally diverges from `firmware/blink328`.

- [ ] **Step 1: Vendor the upstream source (flat into `src/`)**

The upstream layout keeps every `.cpp`/`.h` in `source/` with flat local includes (`#include "sys.h"`), plus an empty `jtag2updi.ino` that only exists to make the Arduino IDE recognize the sketch. Since this is a framework-less build, copy the `.cpp`/`.h` files flat into `src/` and **omit the empty `.ino`**.

Run (from repo root):
```bash
git clone --depth 1 https://github.com/ElTangas/jtag2updi /tmp/j2u
git -C /tmp/j2u rev-parse HEAD          # expect: 07be876105e0b9cfedf2723b0ac88780bcae50d8
mkdir -p firmware/jtag2updi/src
cp /tmp/j2u/source/*.cpp /tmp/j2u/source/*.h firmware/jtag2updi/src/
cp /tmp/j2u/LICENSE firmware/jtag2updi/LICENSE
ls firmware/jtag2updi/src
```
Expected `src/` contents (11 `.cpp` + headers): `JICE_io.cpp JICE_io.h JTAG2.cpp JTAG2.h NVM.h NVM_v2.h UPDI_hi_lvl.cpp UPDI_hi_lvl.h UPDI_lo_lvl.cpp UPDI_lo_lvl.h crc16.cpp crc16.h dbg.cpp dbg.h jtag2updi.cpp parts.h sys.cpp sys.h updi_io.cpp updi_io.h updi_io_soft.cpp`

- [ ] **Step 2: Record provenance**

Create `firmware/jtag2updi/PROVENANCE.md`:
```markdown
# Vendored: ElTangas/jtag2updi

- Upstream: https://github.com/ElTangas/jtag2updi
- Commit: 07be876105e0b9cfedf2723b0ac88780bcae50d8
- Vendored: 2026-07-10
- Files: `source/*.cpp` and `source/*.h` copied flat into `src/`. The empty
  upstream `jtag2updi.ino` is intentionally omitted — this is a framework-less
  avr-gcc build, not an Arduino sketch.
- License: upstream `LICENSE` preserved alongside (see ./LICENSE).
- Local changes to the sources: none. All build configuration lives in
  `platformio.ini`; the vendored files are byte-for-byte upstream.
```

- [ ] **Step 3: Write `platformio.ini`**

Create `firmware/jtag2updi/platformio.ini`. The `-D` flags are upstream `make.sh`'s default `DEFINES` (host is the mega328P → UPDI on PD6 by default; no pin override needed):
```ini
; jtag2updi -> flashed onto a bare ATmega328 (16 MHz xtal) to make a UPDI programmer.
; FRAMEWORK-LESS on purpose: source/jtag2updi.cpp supplies its own int main(), which
; collides with the Arduino core's main() (duplicate `main`) under framework = arduino.
; This mirrors upstream make.sh (bare avr-g++ over source/), just driven by PlatformIO.
[env:jtag2updi]
platform = atmelavr
board = ATmega328P
board_build.f_cpu = 16000000L
build_flags =
  -Isrc
  -DF_CPU=16000000L
  -DNDEBUG
  -DUPDI_BAUD=225000U
  -DUPDI_IO_TYPE=2
  -DDISABLE_HOST_TIMEOUT
```

- [ ] **Step 4: Build to verify it compiles and links (this is the test)**

Run:
```bash
pio run -d firmware/jtag2updi -e jtag2updi
```
Expected: ends with `======= [SUCCESS] =======`, and the hex exists:
```bash
ls firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex
```
If you instead see a `multiple definition of 'main'` link error, `framework = arduino` slipped into `platformio.ini` — remove it (see the "Why framework-less" note above). If you see `fatal error: sys.h: No such file`, a header did not land flat in `src/` — recheck Step 1.

- [ ] **Step 5: Commit**

`.pio/` is already git-ignored (repo `.gitignore` line 1), so only the sources + config are tracked.
```bash
git add firmware/jtag2updi/src firmware/jtag2updi/platformio.ini firmware/jtag2updi/PROVENANCE.md firmware/jtag2updi/LICENSE
git commit -m "feat: vendor jtag2updi firmware as a framework-less PlatformIO project"
```

---

### Task 2: `profiles.mk` — `BLPART` field

**Files:**
- Modify: `profiles.mk` (three CHIP blocks)
- Modify: `Makefile:28-32` (the `show` target — add a `BLPART` line so this is independently testable)

**Interfaces:**
- Consumes: the existing `CHIP` selection mechanism in `profiles.mk`.
- Produces: `$(BLPART)` — resolves to `m328p` for `CHIP=328` and `CHIP=328p`, empty for `CHIP=attiny85`. Tasks 3 and 4 consume `$(BLPART)`.

- [ ] **Step 1: Write the failing test**

Run:
```bash
make show CHIP=328 | grep BLPART
```
Expected: FAIL — no output (exit 1); `show` does not yet print `BLPART`.

- [ ] **Step 2: Add `BLPART` to each profile block**

In `profiles.mk`, add a `BLPART` line to each block. For the `328` block (after `BLOADER`):
```make
  BLOADER   := bootloaders/optiboot_atmega328.hex
  BLPART    := m328p    # signature Optiboot reports over the bootloader (328P build)
```
For the `328p` block (after its `BLOADER`):
```make
  BLOADER   := bootloaders/optiboot_atmega328.hex
  BLPART    := m328p    # signature Optiboot reports over the bootloader (328P build)
```
For the `attiny85` block (after `BLOADER :=`):
```make
  BLOADER   :=
  BLPART    :=          # no bootloader/serial path this stage
```

- [ ] **Step 3: Expose `BLPART` in `show`**

In `Makefile`, add a `BLPART` line to the `show` target. Change:
```make
	@echo "BLINK_ENV=$(BLINK_ENV)  BUILT_HEX=$(BUILT_HEX)  BLOADER=$(BLOADER)"
```
to:
```make
	@echo "BLINK_ENV=$(BLINK_ENV)  BUILT_HEX=$(BUILT_HEX)  BLOADER=$(BLOADER)"
	@echo "BLPART=$(BLPART)"
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
make show CHIP=328     | grep BLPART   # -> BLPART=m328p
make show CHIP=328p    | grep BLPART   # -> BLPART=m328p
make show CHIP=attiny85 | grep BLPART  # -> BLPART=   (empty value, line present)
```
Expected: first two print `BLPART=m328p`; the attiny85 case prints `BLPART=` with an empty value.

- [ ] **Step 5: Commit**

```bash
git add profiles.mk Makefile
git commit -m "feat: add per-profile BLPART (bootloader-reported signature)"
```

---

### Task 3: `Makefile` — `serialflash` target

**Files:**
- Modify: `Makefile` (add `BLBAUD`/`SERIALDUDE` near `AVRDUDE:19`, add the `serialflash` target, extend `.PHONY:79`)

**Interfaces:**
- Consumes: `$(BLPART)` (Task 2), plus existing `$(PORT)`, `$(HEX)`, `$(RUN)`, `_require_chip`.
- Produces: target `serialflash`. Its guard style + `SERIALDUDE` are reused by Task 4.

- [ ] **Step 1: Write the failing test**

```bash
make serialflash CHIP=328 HEX=hex/foo.hex PORT=COM16 DRYRUN=1
```
Expected: FAIL — `make: *** No rule to make target 'serialflash'.  Stop.`

- [ ] **Step 2: Add `BLBAUD` + `SERIALDUDE`**

In `Makefile`, immediately after the `AVRDUDE :=` line (currently line 19), add:
```make
# Serial (bootloader) flash path: avrdude over Optiboot via a USB-TTL adapter.
# Uses BLPART (the signature Optiboot reports), not PART (the silicon signature).
BLBAUD ?= 115200
SERIALDUDE := avrdude -c arduino -p $(BLPART) -P $(PORT) -b $(BLBAUD)
```

- [ ] **Step 3: Add the `serialflash` target**

In `Makefile`, add after the `flash` target (after line 45). Guards mirror the existing `bootloader`/`flash` style; they use `@if` (not `$(RUN)`), so they fire even under `DRYRUN=1`:
```make
# Flash an arbitrary hex over the target's Optiboot bootloader via a USB-TTL.
# PORT here is the USB-TTL port (NOT the Nano's COM4). Boards without DTR/RTS
# auto-reset need a manual RESET tap as avrdude starts.
serialflash: _require_chip
	@if [ -z "$(BLPART)" ]; then echo "ERROR: CHIP='$(CHIP)' has no bootloader/serial path." >&2; exit 1; fi
	@if [ -z "$(HEX)" ]; then echo "ERROR: set HEX=path/to/file.hex" >&2; exit 1; fi
	$(RUN) $(SERIALDUDE) -U flash:w:$(HEX):i
```

- [ ] **Step 4: Add `serialflash` to `.PHONY`**

Change the `.PHONY` line (currently line 79) to include `serialflash`:
```make
.PHONY: _require_chip show id fuses flash isp bootloader blink console help serialflash
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
# Happy path (DRYRUN prints the composed command):
make serialflash CHIP=328 HEX=hex/foo.hex PORT=COM16 DRYRUN=1
# -> avrdude -c arduino -p m328p -P COM16 -b 115200 -U flash:w:hex/foo.hex:i

# No bootloader path (empty BLPART) errors, non-zero exit:
make serialflash CHIP=attiny85 HEX=hex/foo.hex DRYRUN=1; echo "exit=$?"
# -> ERROR: CHIP='attiny85' has no bootloader/serial path.   exit=1

# Missing HEX errors:
make serialflash CHIP=328 PORT=COM16 DRYRUN=1; echo "exit=$?"
# -> ERROR: set HEX=path/to/file.hex   exit=1
```
Expected: the happy path echoes the avrdude line above; both error cases print their message and `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "feat: add serialflash target (flash a hex over Optiboot via USB-TTL)"
```

---

### Task 4: `Makefile` — `jtag2updi` convenience target + help

**Files:**
- Modify: `Makefile` (add `J2U_HEX`, the `jtag2updi` target, two `help` lines, extend `.PHONY`)

**Interfaces:**
- Consumes: `$(SERIALDUDE)` + guard style (Task 3), `$(BLPART)` (Task 2), and the firmware hex path from Task 1: `firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex`.
- Produces: target `jtag2updi` (build + serial-flash the firmware onto the 328).

- [ ] **Step 1: Write the failing test**

```bash
make jtag2updi CHIP=328 PORT=COM16 DRYRUN=1
```
Expected: FAIL — `make: *** No rule to make target 'jtag2updi'.  Stop.`

- [ ] **Step 2: Add the `J2U_HEX` path**

In `Makefile`, just below the `SERIALDUDE :=` line from Task 3, add:
```make
J2U_HEX := firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex
```

- [ ] **Step 3: Add the `jtag2updi` target**

Add after the `serialflash` target. It parallels `make isp` (build + flash the programmer firmware), but builds jtag2updi and serial-flashes it onto the 328:
```make
# Build firmware/jtag2updi, then serial-flash it onto the 328 over Optiboot.
# Parallels `make isp` (ArduinoISP onto the Nano). PORT is the USB-TTL port.
jtag2updi: _require_chip
	@if [ -z "$(BLPART)" ]; then echo "ERROR: CHIP='$(CHIP)' has no bootloader/serial path." >&2; exit 1; fi
	$(RUN) pio run -d firmware/jtag2updi -e jtag2updi
	$(RUN) $(SERIALDUDE) -U flash:w:$(J2U_HEX):i
```

- [ ] **Step 4: Add the two `help` lines**

In the `help` target, after the `make isp` line (currently line 69), add:
```make
	@echo "  make serialflash CHIP=328 HEX=x.hex PORT=COM16   flash a hex over Optiboot (USB-TTL port; manual RESET tap)"
	@echo "  make jtag2updi CHIP=328 PORT=COM16               build + serial-flash jtag2updi onto the 328 (USB-TTL port; manual RESET tap)"
```

- [ ] **Step 5: Add `jtag2updi` to `.PHONY`**

Extend the `.PHONY` line to include `jtag2updi`:
```make
.PHONY: _require_chip show id fuses flash isp bootloader blink console help serialflash jtag2updi
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
# Happy path prints the build line then the serial-flash line:
make jtag2updi CHIP=328 PORT=COM16 DRYRUN=1
# -> pio run -d firmware/jtag2updi -e jtag2updi
# -> avrdude -c arduino -p m328p -P COM16 -b 115200 -U flash:w:firmware/jtag2updi/.pio/build/jtag2updi/firmware.hex:i

# Guard fires for a chip with no serial path:
make jtag2updi CHIP=attiny85 DRYRUN=1; echo "exit=$?"
# -> ERROR: CHIP='attiny85' has no bootloader/serial path.   exit=1

# Both targets appear in help:
make help | grep -E 'serialflash|jtag2updi'
```
Expected: the happy path echoes both command lines above; the guard prints its error with `exit=1`; `make help` lists both new targets.

- [ ] **Step 7: Commit**

```bash
git add Makefile
git commit -m "feat: add jtag2updi target (build + serial-flash the UPDI programmer)"
```

---

### Task 5: README — document the serial-flash targets

**Files:**
- Modify: `README.md` (the "Everyday commands" table at :129-138, plus a caution note)

**Interfaces:**
- Consumes: nothing (docs only).
- Produces: user-facing docs for `serialflash` and `jtag2updi`.

- [ ] **Step 1: Add the two commands to the "Everyday commands" table**

In `README.md`, in the table ending at line 138 (after the `make flash …` row at line 135), add:
```markdown
| `make serialflash CHIP=328 HEX=hex/foo.hex PORT=COM16` | Flash a hex over Optiboot via a USB-TTL |
| `make jtag2updi CHIP=328 PORT=COM16` | Build + serial-flash jtag2updi onto the 328 (makes a UPDI programmer) |
```

- [ ] **Step 2: Add a caution note after the table**

After the existing bootloader-baud note (the block ending at line 147), add:
```markdown
> **`serialflash` / `jtag2updi` use the USB-TTL port, not the Nano's `COM4`.** These
> flash over the target's Optiboot bootloader through a separate USB-TTL adapter wired
> to the 328. A CP2102 without DTR/RTS auto-reset needs a **manual RESET tap** on the
> 328 as avrdude starts (Optiboot's ~1 s window). Both refuse `CHIP=attiny85` (no
> bootloader path). `make jtag2updi` needs the 328 to already have Optiboot burned
> (`make bootloader CHIP=328` over the Nano first).
```

- [ ] **Step 3: Verify the docs render**

```bash
grep -nE 'serialflash|jtag2updi' README.md
```
Expected: matches in the table rows and the caution note.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document serialflash + jtag2updi targets in README"
```

---

## Notes for the executor

- **This is Phase 1 only** — *building* the programmer. Using it against a real ATmega4809 (megaAVR-0 profile, `-c jtag2updi` operations, MegaCoreX, 40-pin wiring) is Phase 2, a separate spec. Do not add megaAVR-0 profiles or 4809 operations here.
- **Hardware verification is deferred.** Tasks are fully verifiable without hardware (build + `DRYRUN=1`). The spec's §8 bench checks (`make jtag2updi CHIP=328 PORT=COM16` actually flashing, then `avrdude -c jtag2updi -P COM16 -p m4809` reaching the programmer) are an on-bench follow-up once a USB-TTL + 328 are wired — record the result in the memory status file, do not block plan completion on it.
- **Windows/Git Bash:** `make` recipes run under `sh`; `pio` and `avrdude` must be on `PATH` (same environment the existing ISP targets use).
