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
