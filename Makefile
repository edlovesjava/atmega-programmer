# Makefile — see docs/superpowers/plans for the full task breakdown.
# SHELL must be sh (not cmd.exe): recipes use POSIX shell syntax. Windows host runs make via Git Bash.
SHELL  := /bin/sh
PORT   ?= COM4
DRYRUN ?=

include profiles.mk

# DRYRUN=1 prints commands instead of executing them (hardware-free testing).
ifeq ($(DRYRUN),1)
  RUN := @echo
else
  RUN := @set -x;
endif

AVRDUDE := avrdude -c stk500v1 -p $(PART) -P $(PORT) -b 19200

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

# Burn Optiboot: set the boot-reset hfuse (0xDE), then flash the vendored image.
# lfuse/efuse stay as the profile's 16 MHz-xtal values.
bootloader: _require_chip
	@if [ -z "$(BLOADER)" ]; then echo "ERROR: CHIP='$(CHIP)' has no bootloader in its profile." >&2; exit 1; fi
	$(RUN) $(AVRDUDE) -e -U lfuse:w:$(LFUSE):m -U hfuse:w:0xDE:m -U efuse:w:$(EFUSE):m
	$(RUN) $(AVRDUDE) -U flash:w:$(BLOADER):i -U lock:w:0x0F:m

.PHONY: _require_chip show id fuses flash isp bootloader
