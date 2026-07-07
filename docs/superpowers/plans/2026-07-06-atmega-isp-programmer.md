# ATmega ISP Programmer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable command-line toolkit that turns an Arduino Nano running ArduinoISP into an in-system programmer for AVR targets (read signature, set fuses, burn bootloader, flash firmware, open a console), validated first on a breadboard against a non-P ATmega328.

**Architecture:** A hybrid **PlatformIO + Makefile** repo. PlatformIO *builds* every firmware (the vendored ArduinoISP sketch for the Nano, plus per-target blink verifiers). A single Makefile *drives* all chip operations through one `avrdude -c stk500v1 ... -b 19200` code path, with per-chip data (avrdude part, signature, fuse bytes, clock, built-hex path) declared as plain make variables in `profiles.mk`. Chip is selected with `CHIP=`, port with `PORT=` (default `COM4`).

**Tech Stack:** PlatformIO Core (`pio`), GNU Make, avrdude, Arduino AVR framework (Nano `nanoatmega328`; targets via MiniCore/ATTinyCore board defs), Windows + PowerShell/Git-Bash host.

## Global Constraints

- **ISP family only.** SPI-programmed AVRs (ATmega328/328P, ATtiny85). UPDI/megaAVR-0 is a *separate* sibling project — no envs or profiles for it here. (spec §1, §2)
- **avrdude invocation shape is fixed:** `avrdude -c stk500v1 -p <PART> -P <PORT> -b 19200 <OP>`. Every operation is this line with a different `<OP>`. (spec §6)
- **Default `PORT=COM4`**, always overridable per-invocation (`make id CHIP=328 PORT=COM7`). (spec §12, decision 1)
- **Primary first target is the non-P ATmega328**: avrdude part `m328`, signature `0x1E9514`, 16 MHz external crystal, fuses `lfuse 0xFF / hfuse 0xD9 / efuse 0xFD` (no-bootloader ISP baseline). Must stay distinct from 328P (`m328p`, `0x1E950F`). (spec §7 FR-7, §8, §9, §12 decision 2)
- **Pro Mini programmed at 5 V** — no level shifting this stage; `promini8` is documented-but-not-exercised. (spec §12 decision 3)
- **ArduinoISP sketch is vendored** into the repo as a file (self-contained build), fetched from its canonical source — never hand-transcribed. (spec §12 decision 4)
- **Bootloader fuse/hex combos defer to MiniCore/Optiboot artifacts**; hand-maintained fuse bytes exist only for the no-bootloader ISP baseline. (spec §9, §12 decision 5)
- **Adding a new ISP AVR is a data change** (`profiles.mk` entry + optional blink env), never new build logic. (spec FR-9)
- **Target firmwares are built by PlatformIO but flashed by the Makefile's avrdude wrapper** — one flash code path for all chips. (refinement of spec §6; see Task 5.)
- **Host is Windows; `make` runs under Git Bash, not PowerShell/cmd.** The Makefile MUST set `SHELL := /bin/sh` as its first content line so GNU Make 3.81 runs recipes (which use `[ -z … ]`, `set -x`, `exit 1`) under sh, not cmd.exe. Verified working against Make 3.81 during pre-flight. All `make …` commands are run via the Bash (Git Bash) tool.

---

## File Structure

```
ATmega-Programmer/
  Makefile                # PORT?=COM4; CHIP-driven targets; DRYRUN=1 echoes commands instead of running
  profiles.mk             # per-CHIP data: PART/SIG/LFUSE/HFUSE/EFUSE/FCPU/HEX/BLOADER — pure make vars
  .gitignore              # .pio/ (any depth), *.hex build outputs (but NOT vendored hex/)
  README.md               # quickstart + command table + wiring pointer to spec
  firmware/               # one self-contained PlatformIO PROJECT per firmware (see note)
    arduinoisp/
      platformio.ini      # [env:programmer] board=nanoatmega328
      src/ArduinoISP.ino  # VENDORED from canonical source, verbatim
    blink328/
      platformio.ini      # [env:blink328] ATmega328P, 16 MHz external
      src/main.cpp        # 16 MHz blink, LED on D13/PB5 (serves 328 and 328p)
    blink_attiny85/
      platformio.ini      # [env:blink_attiny85] attiny85, 8 MHz internal
      src/main.cpp        # 8 MHz blink, LED on PB0
  bootloaders/
    optiboot_atmega328.hex  # VENDORED Optiboot image for 328/328p @16MHz (for `make bootloader`)
  hex/
    .gitkeep              # drop external .hex here to `make flash HEX=hex/foo.hex`
  docs/superpowers/
    specs/  plans/        # this plan + the design spec
```

**Responsibilities:**
- `profiles.mk` is the *only* place chip facts live. `Makefile` reads them; it contains no chip-specific literals.
- **Each `firmware/<x>/` is its own standalone PlatformIO project** (own `platformio.ini`, own `src/`), built with `pio run -d firmware/<x> -e <env>`. This is a deliberate structural decision: PlatformIO does **not** compile `.ino` sketches that sit in a subdirectory of a shared `src_dir` (verified — "Nothing to build"), and a single shared `src_dir` would cross-compile every firmware's `setup()/loop()` together. Per-project isolation keeps the vendored `.ino` verbatim and each build clean. `.cpp` firmwares follow the same layout for uniformity.
- PlatformIO only *builds* (produces `firmware.hex`); the Makefile's avrdude wrapper does every target flash. The one exception is `make isp`, which uses PlatformIO's own uploader to put ArduinoISP on the Nano over USB.
- Build output lives at `firmware/<x>/.pio/build/<env>/firmware.hex`.

---

## Task 1: Repo scaffolding + ArduinoISP builds on the Nano

Delivers FR-1 (buildable programmer firmware) and the project skeleton. A reviewer can reject this purely on "does `pio run -d firmware/arduinoisp -e programmer` compile."

**Files:**
- Create: `.gitignore`
- Create: `firmware/arduinoisp/platformio.ini`
- Create: `firmware/arduinoisp/src/ArduinoISP.ino` (vendored)
- Create: `hex/.gitkeep`
- Create: `README.md` (skeleton — expanded in Task 7)

**Interfaces:**
- Consumes: nothing (first task).
- Produces: standalone PlatformIO project at `firmware/arduinoisp/` with env **`programmer`** (`board = nanoatmega328`), built via `pio run -d firmware/arduinoisp -e programmer`. Establishes the **one-project-per-firmware** convention Task 5 reuses. Build output: `firmware/arduinoisp/.pio/build/programmer/firmware.hex`.

- [ ] **Step 1: Create `.gitignore`**

```gitignore
.pio/
.vscode/
*.bin
# NOTE: `.pio/` (no leading slash) matches the per-firmware build dirs at any depth.
# Do NOT ignore hex/ or bootloaders/ — those hold vendored/dropped images we keep.
```

- [ ] **Step 2: Vendor the ArduinoISP sketch (do not hand-type it)**

Create `firmware/arduinoisp/src/` and fetch the canonical ArduinoISP example verbatim into it. Use curl in Git Bash (verified reachable, HTTP 200, ~17.8 KB):

```bash
mkdir -p firmware/arduinoisp/src
curl -fsSL -o firmware/arduinoisp/src/ArduinoISP.ino \
  "https://raw.githubusercontent.com/arduino/arduino-examples/main/examples/11.ArduinoISP/ArduinoISP/ArduinoISP.ino"
```

This is a vendoring step — transcribing it by hand is a plan failure (the sketch is ~738 lines; errors would be silent). Sanity-check afterward: the file is ~738 lines and contains `void loop`. Its default pin map already matches spec §5 (SCK=D13, MISO=D12, MOSI=D11, RESET=D10, heartbeat=D9, error=D8, prog=D7).

- [ ] **Step 3: Write `firmware/arduinoisp/platformio.ini`**

```ini
; ArduinoISP -> the Nano, uploaded over USB by `make isp`.
; Standalone project so the vendored .ino compiles at its own src/ root
; (PlatformIO will not build a .ino under a shared/multi-firmware src_dir).
[env:programmer]
platform = atmelavr
framework = arduino
board = nanoatmega328
upload_protocol = arduino
; upload port is passed by the Makefile: pio run -d firmware/arduinoisp -e programmer -t upload --upload-port $(PORT)
```

- [ ] **Step 4: Write a skeleton `README.md`**

```markdown
# ATmega ISP Programmer

Arduino Nano as an Arduino-as-ISP programmer for AVR targets.
See `docs/superpowers/specs/2026-07-06-atmega-isp-programmer-design.md` for the full design, wiring, and fuse reference.

Quickstart and the full command table are filled in during Task 7.
```

- [ ] **Step 5: Create `hex/.gitkeep`** (empty file so the drop-folder is tracked)

- [ ] **Step 6: Build the programmer firmware (the test)**

Run (via Git Bash): `pio run -d firmware/arduinoisp -e programmer`
Expected: `[SUCCESS]` — ArduinoISP compiles for `nanoatmega328`, and `firmware/arduinoisp/.pio/build/programmer/firmware.hex` exists. This proves the vendored sketch + project are correct. (First run may auto-download the atmelavr toolchain; that's expected.)

- [ ] **Step 7: Commit**

```bash
git add .gitignore firmware/arduinoisp/platformio.ini firmware/arduinoisp/src/ArduinoISP.ino hex/.gitkeep README.md
git commit -m "feat: scaffold repo; ArduinoISP builds for the Nano (programmer project)"
```

---

## Task 2: `profiles.mk` chip data + a `show` target to prove resolution

Delivers FR-2/FR-3/FR-7/FR-9 *data*. Testable with zero hardware: `make show CHIP=328` must print exactly the right facts, and an unknown chip must fail loudly.

**Files:**
- Create: `profiles.mk`
- Create: `Makefile` (minimal: just include profiles, `show`, and error-on-unknown — grows in Task 3)

**Interfaces:**
- Consumes: nothing.
- Produces: make variables set per `CHIP`: `PART`, `SIG`, `LFUSE`, `HFUSE`, `EFUSE`, `FCPU`, `BLOADER` (bootloader hex path, may be empty), and `BUILT_HEX` (PlatformIO output path for the blink env). Later Makefile targets read only these names.

- [ ] **Step 1: Write `profiles.mk`**

```make
# profiles.mk — per-CHIP data. Adding an ISP AVR = a new block here, no Makefile changes.
# Selected via CHIP=<key>. Unknown keys fall through to the guard in the Makefile.

ifeq ($(CHIP),328)          # non-P ATmega328 — PRIMARY first target
  PART      := m328
  SIG       := 0x1E9514
  LFUSE     := 0xFF         # 16 MHz full-swing external crystal
  HFUSE     := 0xD9         # no bootloader (BOOTRST off)
  EFUSE     := 0xFD         # BOD 2.7 V
  FCPU      := 16000000L
  BLINK_ENV := blink328
  BLOADER   := bootloaders/optiboot_atmega328.hex
endif

ifeq ($(CHIP),328p)         # ATmega328P
  PART      := m328p
  SIG       := 0x1E950F
  LFUSE     := 0xFF
  HFUSE     := 0xD9
  EFUSE     := 0xFD
  FCPU      := 16000000L
  BLINK_ENV := blink328
  BLOADER   := bootloaders/optiboot_atmega328.hex
endif

ifeq ($(CHIP),attiny85)     # ATtiny85, 8 MHz internal
  PART      := attiny85
  SIG       := 0x1E930B
  LFUSE     := 0xE2
  HFUSE     := 0xDF
  EFUSE     := 0xFF
  FCPU      := 8000000L
  BLINK_ENV := blink_attiny85
  BLOADER   :=                # no bootloader profile for attiny this stage
endif

# promini16 / promini8 are documented in the spec (§8) but intentionally not
# defined as build targets this stage (program-at-5V only, no exercised rig).

# Each firmware is its own PlatformIO project; its hex lands under that project's .pio/.
BUILT_HEX := firmware/$(BLINK_ENV)/.pio/build/$(BLINK_ENV)/firmware.hex
```

- [ ] **Step 2: Write the minimal `Makefile` (profiles + guard + show)**

```make
# Makefile — see docs/superpowers/plans for the full task breakdown.
# SHELL must be sh (not cmd.exe): recipes use POSIX shell syntax. Windows host runs make via Git Bash.
SHELL  := /bin/sh
PORT   ?= COM4
DRYRUN ?=

include profiles.mk

# Guard: any chip-using target must have resolved a known CHIP.
_require_chip:
	@if [ -z "$(PART)" ]; then \
	  echo "ERROR: unknown or missing CHIP='$(CHIP)'. Known: 328, 328p, attiny85." >&2; \
	  exit 1; \
	fi

show: _require_chip
	@echo "CHIP=$(CHIP) PART=$(PART) SIG=$(SIG)"
	@echo "FUSES  lfuse=$(LFUSE) hfuse=$(HFUSE) efuse=$(EFUSE)  FCPU=$(FCPU)"
	@echo "BLINK_ENV=$(BLINK_ENV)  BUILT_HEX=$(BUILT_HEX)  BLOADER=$(BLOADER)"
	@echo "PORT=$(PORT)"

.PHONY: _require_chip show
```

- [ ] **Step 3: Test — known chip resolves correctly**

Run: `make show CHIP=328`
Expected (exact):
```
CHIP=328 PART=m328 SIG=0x1E9514
FUSES  lfuse=0xFF hfuse=0xD9 efuse=0xFD  FCPU=16000000L
BLINK_ENV=blink328  BUILT_HEX=firmware/blink328/.pio/build/blink328/firmware.hex  BLOADER=bootloaders/optiboot_atmega328.hex
PORT=COM4
```

- [ ] **Step 4: Test — 328p is distinct, attiny resolves, unknown fails**

Run: `make show CHIP=328p`
Expected: `PART=m328p SIG=0x1E950F` in the output (proves non-P vs P separation, FR-7).

Run: `make show CHIP=attiny85`
Expected: `PART=attiny85 SIG=0x1E930B` and `FCPU=8000000L`.

Run: `make show CHIP=bogus`
Expected: FAIL, stderr `ERROR: unknown or missing CHIP='bogus'. Known: 328, 328p, attiny85.`, non-zero exit.

- [ ] **Step 5: Commit**

```bash
git add profiles.mk Makefile
git commit -m "feat: profiles.mk chip data + make show with unknown-chip guard"
```

---

## Task 3: Makefile avrdude core — `id`, `fuses`, `flash`, `isp`, with `DRYRUN`

Delivers FR-1(upload)/FR-2/FR-3/FR-5/FR-6. Every avrdude target is testable without hardware via `DRYRUN=1`, which prints the exact command instead of running it. Asserting those strings is the automated gate; the real runs are manual (Task 8).

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `PART`, `SIG`, `LFUSE`, `HFUSE`, `EFUSE`, `PORT`, `BUILT_HEX` from Task 2; env `programmer` from Task 1.
- Produces: targets `id`, `fuses`, `flash`, `isp`. Introduces the `$(RUN)` macro (`echo` under DRYRUN, else the real shell) and `AVRDUDE` base string that Tasks 4–6 reuse.

- [ ] **Step 1: Add the run macro + avrdude base to the Makefile**

Insert after the `include profiles.mk` line:

```make
# DRYRUN=1 prints commands instead of executing them (hardware-free testing).
ifeq ($(DRYRUN),1)
  RUN := @echo
else
  RUN := @set -x;
endif

AVRDUDE := avrdude -c stk500v1 -p $(PART) -P $(PORT) -b 19200
```

- [ ] **Step 2: Write the failing test for `id` (dry-run)**

Run: `make id CHIP=328 DRYRUN=1`
Expected NOW: FAIL — `No rule to make target 'id'`. (Confirms the target is genuinely absent before we add it.)

- [ ] **Step 3: Add `id`, `fuses`, `flash`, `isp` targets**

Append to the Makefile:

```make
# Read + report device signature.
id: _require_chip
	$(RUN) $(AVRDUDE) -U signature:r:-:h

# Write the profile's fuse bytes.
fuses: _require_chip
	$(RUN) $(AVRDUDE) -U lfuse:w:$(LFUSE):m -U hfuse:w:$(HFUSE):m -U efuse:w:$(EFUSE):m

# Flash an arbitrary external hex: make flash CHIP=328 HEX=hex/foo.hex
flash: _require_chip
	@if [ -z "$(HEX)" ]; then echo "ERROR: set HEX=path/to/file.hex" >&2; exit 1; fi
	$(RUN) $(AVRDUDE) -U flash:w:$(HEX):i

# Flash ArduinoISP onto the Nano itself (over USB, via PlatformIO's uploader).
isp:
	$(RUN) pio run -d firmware/arduinoisp -e programmer -t upload --upload-port $(PORT)

.PHONY: id fuses flash isp
```

- [ ] **Step 4: Test — `id` dry-run emits the exact command**

Run: `make id CHIP=328 DRYRUN=1`
Expected (exact):
```
avrdude -c stk500v1 -p m328 -P COM4 -b 19200 -U signature:r:-:h
```

- [ ] **Step 5: Test — `fuses` dry-run + PORT override + flash guard**

Run: `make fuses CHIP=328 DRYRUN=1 PORT=COM7`
Expected (exact):
```
avrdude -c stk500v1 -p m328 -P COM7 -b 19200 -U lfuse:w:0xFF:m -U hfuse:w:0xD9:m -U efuse:w:0xFD:m
```

Run: `make flash CHIP=328 DRYRUN=1`
Expected: FAIL, stderr `ERROR: set HEX=path/to/file.hex`.

Run: `make flash CHIP=328 HEX=hex/foo.hex DRYRUN=1`
Expected (exact):
```
avrdude -c stk500v1 -p m328 -P COM4 -b 19200 -U flash:w:hex/foo.hex:i
```

- [ ] **Step 6: Test — `isp` dry-run**

Run: `make isp DRYRUN=1`
Expected (exact):
```
pio run -d firmware/arduinoisp -e programmer -t upload --upload-port COM4
```

- [ ] **Step 7: Commit**

```bash
git add Makefile
git commit -m "feat: avrdude core targets (id/fuses/flash/isp) with DRYRUN echo"
```

---

## Task 4: `bootloader` target (Optiboot via vendored hex + Arduino fuses)

Delivers FR-4 / V-7. Burning a bootloader = write the Arduino/Optiboot fuse variant *and* flash the vendored Optiboot image. Chips with no `BLOADER` in their profile must be refused.

**Files:**
- Modify: `Makefile`
- Create: `bootloaders/optiboot_atmega328.hex` (vendored)

**Interfaces:**
- Consumes: `PART`, `PORT`, `BLOADER` from profiles; `AVRDUDE`/`RUN` from Task 3.
- Produces: target `bootloader`. Introduces Optiboot hfuse value `0xDE` (spec §9) applied only in this target — the no-bootloader baseline `HFUSE=0xD9` in profiles is unchanged.

- [ ] **Step 1: Vendor the Optiboot image (do not hand-type)**

Obtain `optiboot_atmega328.hex` for a 16 MHz 328/328p and save to `bootloaders/optiboot_atmega328.hex`. Canonical source:
- MiniCore / Optiboot repo: `https://github.com/Optiboot/optiboot/blob/master/optiboot/bootloaders/optiboot/optiboot_atmega328.hex`
- (or the copy shipped inside the Arduino IDE hardware folder)

Save the `.hex` bytes verbatim. Vendoring, not transcription.

- [ ] **Step 2: Write the failing test for `bootloader` (dry-run)**

Run: `make bootloader CHIP=328 DRYRUN=1`
Expected NOW: FAIL — `No rule to make target 'bootloader'`.

- [ ] **Step 3: Add the `bootloader` target**

```make
# Burn Optiboot: set the boot-reset hfuse (0xDE), then flash the vendored image.
# lfuse/efuse stay as the profile's 16 MHz-xtal values.
bootloader: _require_chip
	@if [ -z "$(BLOADER)" ]; then echo "ERROR: CHIP='$(CHIP)' has no bootloader in its profile." >&2; exit 1; fi
	$(RUN) $(AVRDUDE) -e -U lfuse:w:$(LFUSE):m -U hfuse:w:0xDE:m -U efuse:w:$(EFUSE):m
	$(RUN) $(AVRDUDE) -U flash:w:$(BLOADER):i -U lock:w:0x0F:m

.PHONY: bootloader
```

- [ ] **Step 4: Test — bootloader dry-run for 328 emits both commands**

Run: `make bootloader CHIP=328 DRYRUN=1`
Expected (exact, two lines):
```
avrdude -c stk500v1 -p m328 -P COM4 -b 19200 -e -U lfuse:w:0xFF:m -U hfuse:w:0xDE:m -U efuse:w:0xFD:m
avrdude -c stk500v1 -p m328 -P COM4 -b 19200 -U flash:w:bootloaders/optiboot_atmega328.hex:i -U lock:w:0x0F:m
```

- [ ] **Step 5: Test — attiny85 (no bootloader profile) is refused**

Run: `make bootloader CHIP=attiny85 DRYRUN=1`
Expected: FAIL, stderr `ERROR: CHIP='attiny85' has no bootloader in its profile.`

- [ ] **Step 6: Commit**

```bash
git add Makefile bootloaders/optiboot_atmega328.hex
git commit -m "feat: bootloader target burns vendored Optiboot with boot-reset fuse"
```

---

## Task 5: Blink verification firmwares (build via PIO) + `blink` target

Delivers FR-5 (built-in verify firmware) and the V-5/V-9 firmware. Blink runs at a rate implied by the *actual* clock, so a correct-speed blink proves the fuses/crystal (spec §11 V-5). PIO builds the hex; the Makefile `blink` target flashes it via avrdude (the single flash code path).

**Files:**
- Create: `firmware/blink328/platformio.ini`
- Create: `firmware/blink328/src/main.cpp`
- Create: `firmware/blink_attiny85/platformio.ini`
- Create: `firmware/blink_attiny85/src/main.cpp`
- Modify: `Makefile` (add `blink` target)

**Interfaces:**
- Consumes: `BLINK_ENV`, `BUILT_HEX`, `PART`, `PORT` from profiles; `AVRDUDE`/`RUN` from Task 3. `BLINK_ENV` is `blink328` (for CHIP 328 and 328p) or `blink_attiny85`.
- Produces: standalone projects `firmware/blink328/` and `firmware/blink_attiny85/` (each with an env named identically to its folder); Makefile target `blink`. Each builds to `firmware/<env>/.pio/build/<env>/firmware.hex` — matching `BUILT_HEX` from Task 2.

- [ ] **Step 1: Write `firmware/blink328/src/main.cpp`**

```cpp
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
```

- [ ] **Step 2: Write `firmware/blink328/platformio.ini`**

Build-only project (no `upload_*`); the Makefile's avrdude wrapper flashes the output. `board = ATmega328P` is the MiniCore board id (verified building at 16 MHz external); the same hex runs on the non-P 328.

```ini
[env:blink328]
platform = atmelavr
framework = arduino
board = ATmega328P
board_build.f_cpu = 16000000L
board_hardware.oscillator = external
build_flags = -D LED_PIN=13
```

- [ ] **Step 3: Write `firmware/blink_attiny85/src/main.cpp`**

```cpp
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
```

- [ ] **Step 4: Write `firmware/blink_attiny85/platformio.ini`**

```ini
[env:blink_attiny85]
platform = atmelavr
framework = arduino
board = attiny85
board_build.f_cpu = 8000000L
build_flags = -D LED_PIN=0
```

- [ ] **Step 5: Confirm the board ids exist (guards against a wrong board name)**

Run: `pio boards ATmega328P` and `pio boards attiny85`
Expected: each prints a matching board row. If `ATmega328P` is not found, install MiniCore and use the exact id it reports; if `attiny85` is missing, use the ATTinyCore/atmelavr id it reports. (During pre-flight, `board = ATmega328P` at 16 MHz external built successfully.)

- [ ] **Step 6: Test — both blink firmwares compile**

Run: `pio run -d firmware/blink328 -e blink328`
Expected: `[SUCCESS]`, and `firmware/blink328/.pio/build/blink328/firmware.hex` exists. (First run may auto-download MiniCore + toolchain — expect ~1 min.)

Run: `pio run -d firmware/blink_attiny85 -e blink_attiny85`
Expected: `[SUCCESS]`, `firmware/blink_attiny85/.pio/build/blink_attiny85/firmware.hex` exists.

- [ ] **Step 7: Add the `blink` target to the Makefile**

```make
# Build the profile's blink firmware (its own PIO project), then flash the built hex via avrdude.
blink: _require_chip
	$(RUN) pio run -d firmware/$(BLINK_ENV) -e $(BLINK_ENV)
	$(RUN) $(AVRDUDE) -U flash:w:$(BUILT_HEX):i

.PHONY: blink
```

- [ ] **Step 8: Test — `blink` dry-run for 328 emits build + flash**

Run: `make blink CHIP=328 DRYRUN=1`
Expected (exact, two lines):
```
pio run -d firmware/blink328 -e blink328
avrdude -c stk500v1 -p m328 -P COM4 -b 19200 -U flash:w:firmware/blink328/.pio/build/blink328/firmware.hex:i
```

- [ ] **Step 9: Commit**

```bash
git add firmware/blink328 firmware/blink_attiny85 Makefile
git commit -m "feat: blink verification firmwares + make blink (build via PIO, flash via avrdude)"
```

---

## Task 6: `console` target (separate USB-TTL) + `help`

Delivers FR-8 and usability. Console uses `pio device monitor` on a *separate* adapter's port — no chip-programming coupling (spec §7).

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: `PORT`, `RUN`.
- Produces: targets `console`, `help`. Introduces `BAUD?=9600`.

- [ ] **Step 1: Add `BAUD` default near the top `PORT ?= COM4` line**

```make
BAUD   ?= 9600
```

- [ ] **Step 2: Write the failing test for `console` (dry-run)**

Run: `make console DRYRUN=1`
Expected NOW: FAIL — `No rule to make target 'console'`.

- [ ] **Step 3: Add `console` and `help` targets**

```make
# Serial monitor to a running target over a SEPARATE USB-TTL adapter (not the Nano).
console:
	$(RUN) pio device monitor -p $(PORT) -b $(BAUD)

help:
	@echo "ATmega ISP Programmer — targets (CHIP=328|328p|attiny85, PORT default COM4):"
	@echo "  make isp                         flash ArduinoISP onto the Nano"
	@echo "  make id        CHIP=328          read + report device signature"
	@echo "  make fuses     CHIP=328          write the profile's fuse bytes"
	@echo "  make bootloader CHIP=328         burn Optiboot"
	@echo "  make blink     CHIP=328          build + flash the verification blink"
	@echo "  make flash     CHIP=328 HEX=hex/foo.hex   flash an external hex"
	@echo "  make console   PORT=COM7 BAUD=9600        serial monitor (separate USB-TTL)"
	@echo "  make show      CHIP=328          print resolved profile"
	@echo "  Append DRYRUN=1 to print the command instead of running it."

.PHONY: console help
```

- [ ] **Step 4: Make `help` the default target** — add directly under the first line of the Makefile (before `include`):

```make
.DEFAULT_GOAL := help
```

- [ ] **Step 5: Test — console dry-run + defaults, and bare `make`**

Run: `make console DRYRUN=1`
Expected (exact): `pio device monitor -p COM4 -b 9600`

Run: `make console DRYRUN=1 PORT=COM7 BAUD=115200`
Expected (exact): `pio device monitor -p COM7 -b 115200`

Run: `make`
Expected: the help text (default goal), no error.

- [ ] **Step 6: Commit**

```bash
git add Makefile
git commit -m "feat: console target + help as default goal"
```

---

## Task 7: README quickstart + command table

Delivers the docs an operator needs. Folded documentation for the whole toolkit; a reviewer gates on "could a newcomer run the rig from this alone."

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: every target from Tasks 1–6 (names/flags must match exactly).
- Produces: nothing code depends on.

- [ ] **Step 1: Write the full `README.md`**

```markdown
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
```

- [ ] **Step 2: Verify the README table matches reality**

Run: `make help`
Expected: the target list in the help output matches the README table (same target names, same `CHIP`/`PORT`/`HEX`/`BAUD` variables). Fix either side on mismatch.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README quickstart + command table"
```

---

## Task 8: Manual hardware validation (spec §11 acceptance criteria)

**This task requires the physical rig and a real chip — it is operator-run, not agent-run.** No code changes; it's the sign-off checklist that proves the toolkit works end to end. Record pass/fail + observed values in the commit message or a `docs/validation-log.md`.

**Files:**
- Optional create: `docs/validation-log.md` (record observed signatures, fuse readbacks, blink timing)

- [ ] **V-1 Load ArduinoISP** — `make isp`; Nano's heartbeat LED (D9) breathes. PASS = upload OK + heartbeat.
- [ ] **V-2 Signature 328P** — on a 328P: `make id CHIP=328p` returns `0x1E950F`. PASS = match.
- [ ] **V-3 Signature non-P 328** — on the non-P 328: `make id CHIP=328` returns `0x1E9514`, and `make id CHIP=328p` does **not** silently succeed. PASS = correct sig, no false 328P match (FR-7). Note whether avrdude needed `-F` (spec §12 residual risk).
- [ ] **V-4 Fuses** — `make fuses CHIP=328`, then re-read fuses; lfuse/hfuse/efuse == `0xFF/0xD9/0xFD`. PASS = readback matches.
- [ ] **V-5 Blink verify** — `make blink CHIP=328`; LED blinks at ~0.5 s on / 0.5 s off (true 16 MHz). A ~1 s cadence means the chip is still on the 8 MHz internal osc → fuses/crystal wrong. PASS = correct cadence.
- [ ] **V-6 External hex** — `make flash CHIP=328 HEX=hex/<something>.hex` flashes and avrdude verifies. PASS = verify OK.
- [ ] **V-7 Bootloader** — `make bootloader CHIP=328`; then confirm the chip accepts a serial upload (Optiboot). PASS = serial upload works.
- [ ] **V-8 Console** — wire the separate USB-TTL (adapter TX→target RX/D0, adapter RX→target TX/D1, shared GND — spec §7); `make console PORT=<adapter>` shows target UART output. PASS = readable output.
- [ ] **V-9 ATtiny target** — `make id CHIP=attiny85` → `0x1E930B`; `make blink CHIP=attiny85` blinks. PASS = both work (proves the profile system generalizes, FR-9).

- [ ] **Final commit (validation log, if kept)**

```bash
git add docs/validation-log.md
git commit -m "test: Stage 1 hardware validation log (V-1..V-9)"
```

---

## Self-Review Notes

- **Spec coverage:** FR-1 (Task 1 build + Task 3 `isp`), FR-2 (Task 3 `id`), FR-3 (Task 3 `fuses`), FR-4 (Task 4 `bootloader`), FR-5 (Task 3 `flash` + Task 5 `blink`), FR-6 (`CHIP=` throughout), FR-7 (Task 2 328 vs 328p data + V-3), FR-8 (Task 6 `console`), FR-9 (Task 2 data-only profiles + Task 5 add-a-chip path). §7 console, §8 profiles, §9 fuses, §11 → Task 8. All mapped.
- **Type/name consistency:** `PART/SIG/LFUSE/HFUSE/EFUSE/FCPU/BLINK_ENV/BLOADER/BUILT_HEX` defined in Task 2 and consumed by identical names in Tasks 3–6. `AVRDUDE`/`RUN` defined Task 3, reused Tasks 4–6. Target names match between Makefile, `help`, and README.
- **Known residual risks (carried from spec §12, verified during Task 8, not blockers):** avrdude `m328` vs `m328p` force-flag behavior (V-3); exact Optiboot hfuse/hex per board variant (Task 4 uses the §9 `0xDE` + vendored image, revisit against MiniCore at V-7); PlatformIO MiniCore/ATTinyCore board ids (guarded by Task 5 Step 5).
