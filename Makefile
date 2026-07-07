# Makefile — see docs/superpowers/plans for the full task breakdown.
# SHELL must be sh (not cmd.exe): recipes use POSIX shell syntax. Windows host runs make via Git Bash.
SHELL  := /bin/sh
PORT   ?= COM4
BAUD   ?= 9600
DRYRUN ?=

.DEFAULT_GOAL := help

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

# Build the profile's blink firmware (its own PIO project), then flash the built hex via avrdude.
blink: _require_chip
	$(RUN) pio run -d firmware/$(BLINK_ENV) -e $(BLINK_ENV)
	$(RUN) $(AVRDUDE) -U flash:w:$(BUILT_HEX):i

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

.PHONY: _require_chip show id fuses flash isp bootloader blink console help
