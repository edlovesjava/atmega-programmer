# profiles.mk — per-CHIP data. Adding an ISP AVR = a new block here, no Makefile changes.
# Selected via CHIP=<key>. Unknown keys fall through to the guard in the Makefile.

ifeq ($(CHIP),328)          # non-P ATmega328 — PRIMARY first target
  PART      := m328
  SIG       := 0x1E9514
  LFUSE     := 0xFF
  HFUSE     := 0xD9
  EFUSE     := 0xFD
  FCPU      := 16000000L
  BLINK_ENV := blink328
  BLOADER   := bootloaders/optiboot_atmega328.hex
  BLPART    := m328p    # signature Optiboot reports over the bootloader (328P build)
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
  BLPART    := m328p    # signature Optiboot reports over the bootloader (328P build)
endif

ifeq ($(CHIP),attiny85)     # ATtiny85, 8 MHz internal
  PART      := attiny85
  SIG       := 0x1E930B
  LFUSE     := 0xE2
  HFUSE     := 0xDF
  EFUSE     := 0xFF
  FCPU      := 8000000L
  BLINK_ENV := blink_attiny85
  BLOADER   :=
  BLPART    :=          # no bootloader/serial path this stage
endif

# promini16 / promini8 are documented in the spec (§8) but intentionally not
# defined as build targets this stage (program-at-5V only, no exercised rig).

# Each firmware is its own PlatformIO project; its hex lands under that project's .pio/.
BUILT_HEX := firmware/$(BLINK_ENV)/.pio/build/$(BLINK_ENV)/firmware.hex
