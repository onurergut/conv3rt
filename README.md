<div align="center">
  <img src="docs/icon.png" width="112" alt="conv3rt app icon">
  <h1>conv3rt</h1>
  <p><b>A native macOS image converter for 60+ formats, with a lossless mode that blocks instead of lying.</b></p>

  <p>
    <a href="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml"><img src="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
    <a href="https://github.com/onurergut/conv3rt/releases/latest"><img src="https://img.shields.io/github/v/release/onurergut/conv3rt?label=release" alt="Latest release"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
  </p>
</div>

---

**Status:** actively developed. Latest release: **0.6.1** (30 October 2026).

conv3rt is a free, native Mac app for converting images without uploading them
or opening a terminal. Drag in files, folders, or an image from the clipboard,
choose an output format, and convert. It reads **60+ formats** and writes **19**
of them. The 0.6.1 downloads include the optional JPEG XL and AVIF encoders, for
**21** curated output formats.

## Why conv3rt

- **Already on your Mac: Preview and Finder Quick Actions** are the fastest path
  for a one-off JPEG or PNG. conv3rt adds the formats Preview cannot open,
  explicit lossless decisions, and outputs such as WebP, JPEG XL and AVIF.
- **Command-line converters such as `sips` and ImageMagick** are better for
  scripts and CI. conv3rt is for interactive work: drag, review what changed,
  convert.
- **Hosted web converters** upload your files. conv3rt processes everything
  on-device.
- **Other GUI converters** cover similar ground. conv3rt is free and
  MIT-licensed, native SwiftUI, and its Lossless mode refuses a conversion
  instead of quietly downgrading it.

**When not to use conv3rt:** automating conversions in a script or CI (use
`sips` or ImageMagick), converting on Windows, Linux or a phone, working with
video or audio, or producing lossless AVIF or camera RAW output.

## Install

1. Open the [releases page](https://github.com/onurergut/conv3rt/releases) and
   download the build for your Mac:
   - **Apple Silicon** → `conv3rt-0.6.1-apple-silicon.zip`
   - **Intel** → `conv3rt-0.6.1-intel.zip`
2. Unzip it in Finder (double-click) and drag **conv3rt** to Applications.
3. Open it. Public releases are Developer ID-signed and notarized by Apple.

**Requirements:** macOS 14 or later, Apple Silicon or Intel. No Homebrew,
runtime, or additional codec downloads.

Use Finder's Archive Utility or `ditto -x -k` to unzip. Command-line `unzip`
can add AppleDouble metadata files; the 0.6.1 archives are built without them,
so both extraction paths preserve the code signature.

Any version before **0.6.0** has no updater, so moving to 0.6.0 or later is a
one-time manual install. From 0.6.0 on, the app can update itself.

## Use

1. Add files, a folder, or paste from the clipboard. Drag-and-drop works too.
2. Pick an output format and **Lossless** or **Highest Quality**.
3. Choose an output folder.
4. Review the per-file notes: what is kept, what changes.
5. **Convert**. Cancel anytime; retry only the failures.

Advanced settings cover metadata policy (keep / remove location / remove),
animation and page handling, transparency background, PDF/SVG resolution, folder
mirroring, and lossy encoding quality.

**Finder:** Open With, plus a **"Convert with conv3rt"** Quick Action
(right-click → Quick Actions).

## Formats

| | |
|---|---|
| **Read** | JPEG, PNG, TIFF, BMP, GIF, HEIC/HEIF, WebP, AVIF, JPEG XL, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, SVG, DDS, QOI, PCX, PFM, and nearly all camera RAW (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2, …) |
| **Write** | PNG, JPEG, TIFF, BMP, GIF, HEIC/HEIF, **WebP**, **JPEG XL**\*, **AVIF**\*, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, DDS, QOI, PCX, PFM |
| **Read-only** | Radiance HDR, SGI, PICT, camera RAW |

<sub>\* JPEG XL and AVIF writing are optional at build time (`scripts/build-jxl.sh`, `scripts/build-avif.sh`).</sub>

The full matrix — read/write, alpha, animation, multipage, metadata and
lossless conditions per format — is in
[`docs/FORMAT_MATRIX.md`](docs/FORMAT_MATRIX.md). It is a generated snapshot
from the running code on macOS 15.7.3; regenerate it with
`swift run conv3rt --dump-matrix`. CI does not compare the checked-in file, so
treat it as documentation rather than a live guarantee.

## The Lossless promise

"Lossless" here means the decoded image survives intact: sample values, bit
depth, alpha, color profile, and animation/pages. It is **not** about file size,
and **not** about byte-identical files.

- `JPEG → PNG` cannot recover what the JPEG already discarded — it only avoids
  adding *new* loss. conv3rt classifies the loss **it** adds, not the source's
  history.
- If the target cannot preserve it (for example, JPEG has no transparency),
  Lossless is **blocked** with a plain-English reason and an alternative.

Full contract: [`docs/LOSSLESS.md`](docs/LOSSLESS.md).

## Privacy

Images are processed entirely on-device; your files never leave your Mac.
Network use is limited to update checks and update downloads, through GitHub
(`raw.githubusercontent.com`, `github.com`, and GitHub's release-asset CDN
hosts). Those hosts see ordinary connection and HTTP metadata, such as your IP
address and update request headers. No images, conversion data, account data,
telemetry, analytics, crash reports, or system profile are uploaded. Automatic
checks require opt-in; manual **Check for Updates...** is always user-initiated.

## Updates

**Check for Updates...** in the app menu checks manually. Sparkle's native
permission prompt on the second launch offers automatic checks; they remain off
unless you opt in. Every installation needs your approval. Silent installs,
automatic downloads, and system-profile reporting are disabled. Updates wait
until active imports and conversions finish.

Stable feeds are separate for Apple Silicon and Intel, live in `updates/`, and
point at the notarized archives on the
[releases page](https://github.com/onurergut/conv3rt/releases).

## Known limitations

- **AVIF** is written **lossily** only (optional build with libavif + libaom);
  there is no lossless AVIF, and its output carries no EXIF/XMP.
- **RAW / PSD / SVG / PDF** are exported as **flattened raster images** — their
  original structure is not preserved.
- **WebP** output carries ICC, EXIF/GPS and XMP (not IPTC) and supports animated
  output. **JPEG XL** output carries ICC, EXIF/GPS and XMP but is not animated.

The complete list is in [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Documentation

- [Lossless contract](docs/LOSSLESS.md)
- [Format matrix](docs/FORMAT_MATRIX.md)
- [Known limitations](docs/LIMITATIONS.md)
- [Changelog](CHANGELOG.md)

## Build from source

Requires the Xcode command line tools (Swift 5.9+) and macOS 14+.

```sh
swift test                 # run the suite
swift run conv3rt          # run the app
```

Optional JPEG XL/AVIF encoders, packaging, notarization, and update-feed
generation are in [CONTRIBUTING.md](CONTRIBUTING.md#release-builds).

## Contributing

Bug reports and pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

MIT for conv3rt's own code. Bundled libwebp is BSD-3; the optional libjxl is
BSD-3 with Apache-2.0 (Highway) and MIT (Brotli, lcms2) components. See
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).
