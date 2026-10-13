# Changelog

## 0.5.0

- **Netpbm family**: full PFM (Portable Float Map, 32-bit float) read/write, plus
  PPM/PGM/PAM read and PPM/PGM/PFM write — the formats macOS Image I/O cannot
  read.
- **QOI** (lossless 8-bit RGBA) and **PCX** (24-bit truecolor / 8-bit indexed
  read, 24-bit write) codecs, pure Swift.
- All three are wired end-to-end: they are source formats and output targets,
  and the output verifier understands them.
- Fuzz/robustness tests (random and bit-flipped inputs never crash or leave
  output).
- 16-bit and color-profile correctness tests (depth preserved on PNG/TIFF;
  profile preserved or the loss flagged).
- UX: recent output folders, a completion cue, and a per-file output-format
  override.
- **DDS** (uncompressed) read/write codec; block-compressed DDS is readable
  but not writable.
- Saved **presets** (name + apply + delete) in the app.
- `scripts/make-dmg.sh` for DMG packaging; CI now reports code coverage.
- **AVIF writing** (lossy) via bundled libavif + libaom (optional build,
  `scripts/build-avif.sh`); adds ~5 MB. ICC embedded; no lossless AVIF.
- **Metadata writing**: WebP and JPEG XL now carry EXIF/GPS and XMP (plus ICC);
  IPTC is not written.
- **Animated WebP** output (libwebp mux), preserving all frames and timing.
  Animated JPEG XL is not offered (macOS Image I/O cannot read it back). The
  inspector now correctly detects animated WebP sources.

## 0.4.0

- **Resource guards**: oversize / decompression-bomb inputs and invalid
  dimensions are refused (never silently downscaled); corrupted and truncated
  files fail cleanly and leave no partial output.
- **CMYK safety**: converting a CMYK source to an RGB-only target is blocked in
  Lossless and warned in Highest Quality; TIFF/JPEG/JP2 keep CMYK.
- **App icon** and **accessibility labels** on the main controls.
- **Signing/notarization** tooling: `Resources/conv3rt.entitlements` and
  `scripts/notarize.sh`; `package.sh` signs with Hardened Runtime when a
  `CODESIGN_IDENTITY` is provided.
- Settings round-trip tests.

## 0.3.0

- **JPEG XL writing** via an optional bundled libjxl 0.11.2
  (`scripts/build-jxl.sh`). Lossless JXL is sample-exact; the ICC profile is
  embedded. A fresh clone without libjxl still builds (JPEG XL read-only).

## 0.2.0

- **WebP writing** via bundled libwebp 1.4.0. Lossless uses `exact` mode so RGB
  under fully transparent pixels is preserved; the ICC profile is written.
- **Performance report** (`docs/PERFORMANCE.md`) with measured numbers.

## 0.1.0

- Initial release: SwiftUI app + UI-free, testable conversion core.
- Runtime-discovered format capabilities; read and write tracked separately.
- Lossless / Highest Quality modes with an explicit contract; blocking instead
  of silent downgrade.
- Plan-before-convert analysis, atomic collision-safe writes, bounded
  concurrency, cancel/retry.
- Open With and a Finder Quick Action (macOS Services).
- No network, no telemetry, no accounts, no auto-update.
