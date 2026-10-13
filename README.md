<div align="center">
  <img src="docs/icon.png" width="128" alt="conv3rt icon">
  <h1>conv3rt</h1>
  <p><b>A small, native macOS image converter.</b><br>
  Offline · on-device · honest about what it preserves · no account, no telemetry, no auto-update.</p>

  <p>
    <a href="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml"><img src="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
    <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
    <img src="https://img.shields.io/badge/price-free-brightgreen" alt="Free">
  </p>
</div>

---

Drop images in, pick a format, convert. conv3rt reads roughly **60 formats** on
modern macOS and writes **16** of them (17 with JPEG XL). It is explicit about
which conversion preserves your data and which does not — no "perfectly
lossless for everything" marketing.

## Why it's different

- **Lossless means something.** Lossless mode preserves decoded samples, bit
  depth, alpha, color profile and structure — and it is **blocked**, never
  silently downgraded, when the target can't. Highest Quality is always labeled
  as potentially lossy.
- **Read ≠ write.** macOS can decode WebP/AVIF/JPEG XL but not encode them.
  conv3rt writes WebP (and JPEG XL, if built) and does **not** pretend the
  others are targets.
- **Nothing happens behind your back.** Originals are never modified, outputs
  never overwrite (`name-1.png`), and a failed job leaves no partial file.
- **Fully offline.** No network code at all: no uploads, telemetry, analytics,
  crash reporting, update checks, or accounts.

## Formats

| | |
|---|---|
| **Read** | JPEG, PNG, TIFF, BMP, GIF, HEIC/HEIF, WebP, AVIF, JPEG XL, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, and nearly all camera RAW (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2, …) |
| **Write** | PNG, JPEG, TIFF, BMP, GIF, HEIC/HEIF, **WebP**, **JPEG XL**\*, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF |
| **Read-only** | AVIF, Radiance HDR, SGI, PICT, camera RAW |

<sub>\* JPEG XL writing is optional at build time (`scripts/build-jxl.sh`).</sub>

The full, generated matrix — read/write, alpha, animation, multipage, metadata
and lossless conditions per format — lives in
[`docs/FORMAT_MATRIX.md`](docs/FORMAT_MATRIX.md). It is generated from the
running code, so it can't drift.

## The Lossless promise

"Lossless" here means the decoded image survives intact: sample values, bit
depth, alpha, color profile, and animation/pages. It is **not** about file size,
and **not** about byte-identical files.

- `JPEG → PNG` can't recover what the JPEG already discarded — it only avoids
  adding *new* loss. conv3rt classifies the loss **it** adds, not the source's
  history.
- If the target can't preserve it (e.g. JPEG has no transparency), Lossless is
  **blocked** with a plain-English reason and an alternative.

Full contract: [`docs/LOSSLESS.md`](docs/LOSSLESS.md).

## Install

Download the build for your Mac from the
[**releases page**](https://github.com/onurergut/conv3rt/releases):

- **Apple Silicon** → `conv3rt-<version>-apple-silicon.zip`
- **Intel** → `conv3rt-<version>-intel.zip`

Unzip, drag **conv3rt** to Applications, and open. Builds are Developer
ID–signed and notarized. No Homebrew, no runtimes, no extra codecs to install.

## Use

1. Add files, a folder, or paste from the clipboard (drag-and-drop works too).
2. Pick an output format and **Lossless** or **Highest Quality**.
3. Choose an output folder.
4. Review the per-file notes (what's kept, what changes).
5. **Convert**. Cancel anytime; retry only the failures.

Advanced settings cover metadata policy (keep / remove location / remove),
animation & page handling, transparency background, PDF/SVG resolution, folder
mirroring, and lossy encoding quality.

**Finder:** Open With, plus a **"Convert with conv3rt"** Quick Action
(right-click → Quick Actions).

## Build from source

Requires the Xcode command line tools (Swift 5.9+), macOS 14+.

```sh
swift test                 # run the suite
swift run conv3rt          # run the app

# Optional: enable JPEG XL writing (builds libjxl; a few minutes per arch)
scripts/build-jxl.sh arm64

# Package a distributable app
scripts/package.sh arm64 0.4.0        # Apple Silicon
scripts/package.sh x86_64 0.4.0       # Intel
```

WebP writing works out of the box. JPEG XL writing is optional: build libjxl
and the package detects and links it; without it, JPEG XL is read-only and its
tests are compiled out.

## Project layout

```
Sources/Conv3rtCore/   UI-free, testable core (capabilities, inspection, planning, conversion, verification, file access, queue)
Sources/Conv3rtApp/    SwiftUI app (window, file list, settings, Finder services)
Tests/Conv3rtCoreTests/ 44 tests (42 without libjxl)
docs/                  architecture, format matrix, lossless contract, limits, codecs, testing, packaging, performance
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the design.

## Known limitations

- **AVIF** can't be written (would need a large AV1 encoder); it is read-only.
- **RAW / PSD / SVG / PDF** are exported as **flattened raster images** — their
  original structure is not preserved.
- WebP/JPEG XL output doesn't carry EXIF/XMP yet (ICC is written); animated
  WebP/JXL isn't implemented.

The complete list is in [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Privacy

conv3rt contains no network code. Images are processed entirely on-device, and
your files never leave your Mac.

## License

MIT for conv3rt's own code. Bundled libwebp is BSD-3; the optional libjxl is
BSD-3 with Apache-2.0 (Highway) and MIT (Brotli, lcms2) components. See
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).
