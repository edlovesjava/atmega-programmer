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
