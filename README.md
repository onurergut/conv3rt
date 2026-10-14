<div align="center">
  <img src="docs/icon.png" width="128" alt="conv3rt icon">
  <h1>conv3rt</h1>
  <p><b>A small, native macOS image converter.</b><br>
  On-device conversion · honest about what it preserves · no account, no telemetry, no silent installs.</p>

  <p>
    <a href="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml"><img src="https://github.com/onurergut/conv3rt/actions/workflows/ci.yml/badge.svg?branch=main" alt="CI"></a>
    <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform: macOS 14+">
    <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
    <img src="https://img.shields.io/badge/license-MIT-green" alt="License: MIT">
    <img src="https://img.shields.io/badge/price-free-brightgreen" alt="Free">
  </p>
</div>

---

Drop images in, pick a format, convert. conv3rt reads **60+ formats** on modern
macOS and writes **19** of them (**21** with the optional JPEG XL and AVIF
codecs). It is explicit about which conversion preserves your data and which
does not — no "perfectly lossless for everything" marketing.

## Why it's different

- **Lossless means something.** Lossless mode preserves decoded samples, bit
  depth, alpha, color profile and structure — and it is **blocked**, never
  silently downgraded, when the target can't. Highest Quality is always labeled
  as potentially lossy.
- **Read ≠ write.** macOS can decode WebP/AVIF/JPEG XL but not encode them.
  conv3rt writes WebP itself, and JPEG XL / AVIF when built, and is honest
  about which formats it can only read.
- **Nothing happens behind your back.** Originals are never modified, outputs
  never overwrite (`name-1.png`), and a failed job leaves no partial file.
- **On-device conversion.** Images never leave your Mac. Network access is
  limited to update checks and downloads; no uploads, telemetry, analytics,
  crash reporting, or accounts. Automatic checks require opt-in, and every
  update installation requires approval.

## Formats

| | |
|---|---|
| **Read** | JPEG, PNG, TIFF, BMP, GIF, HEIC/HEIF, WebP, AVIF, JPEG XL, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, SVG, DDS, QOI, PCX, PFM, and nearly all camera RAW (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2, …) |
| **Write** | PNG, JPEG, TIFF, BMP, GIF, HEIC/HEIF, **WebP**, **JPEG XL**\*, **AVIF**\*, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, DDS, QOI, PCX, PFM |
| **Read-only** | Radiance HDR, SGI, PICT, camera RAW |

<sub>\* JPEG XL and AVIF writing are optional at build time (`scripts/build-jxl.sh`, `scripts/build-avif.sh`).</sub>

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

Unzip, drag **conv3rt** to Applications, and open. Every public release is
Developer ID-signed and notarized by Apple; local ad-hoc builds are not
distribution artifacts. No Homebrew, no runtimes, no extra codecs to install.
The latest release is **0.6.0**.

Any version before **0.6.0** has no updater, so moving to 0.6.0 is a one-time
manual install. From 0.6.0 on, the app keeps itself up to date.

## Updates

**Check for Updates...** in the app menu checks manually. Sparkle's native
permission prompt on the second launch offers automatic checks; they remain
off unless you opt in. Every installation needs your approval. Silent installs,
automatic downloads, and system-profile reporting are disabled. Updates do not
quit the app while conversion is active.

Stable feeds are separate for Apple Silicon and Intel:

- `https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-arm64.xml`
- `https://raw.githubusercontent.com/onurergut/conv3rt/main/updates/appcast-x86_64.xml`

Both feeds are live and point at the notarized archives on the
[**releases page**](https://github.com/onurergut/conv3rt/releases). The app only
sees an update once a newer signed and notarized build is published there.

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

# Optional: enable lossy AVIF writing (builds libavif + libaom; slower)
scripts/build-avif.sh arm64

# Package locally; distribution still needs Developer ID signing + notarization
scripts/package.sh arm64 0.6.0 2     # Apple Silicon; version and monotonic build
scripts/package.sh x86_64 0.6.0 2    # Intel; same release build number

# Deterministic appcast fixtures; no production key or network
bash scripts/test-appcast.sh
```

WebP writing works out of the box. JPEG XL writing is optional: build libjxl
and the package detects and links it; without it, JPEG XL is read-only and its
tests are skipped.

### Prepare an update feed locally

After Developer ID signing, approved notarization, stapling, and regeneration
of the final ZIP, prepare one architecture's feed with:

```sh
# SPARKLE_ACCOUNT must name the app-specific Keychain account used for this app.
swift scripts/generate-appcast.swift \
  --archive dist/conv3rt-0.6.0-apple-silicon/conv3rt-0.6.0-apple-silicon.zip \
  --asset-url https://github.com/onurergut/conv3rt/releases/download/v0.6.0/conv3rt-0.6.0-apple-silicon.zip \
  --arch arm64 --account "$SPARKLE_ACCOUNT"
```

`v0.6.0` was built exactly this way. The generator derives version, monotonic
build number, and minimum macOS version from the archived plist. It
runs `scripts/verify-release.sh <app> <version> <arch> release <build-number>`
against a staged copy, then uses Sparkle 2.10.0's official `sign_update` to sign
and verify the final ZIP bytes. The Keychain account's public key must match
`SUPublicEDKey` in the archive. Official tools use the fixed Keychain service
`https://sparkle-project.org` with an app-specific `--account`; no private key
file, export, environment variable, or custom signer is used.

The generator updates only the matching local XML feed. It performs no network
requests, Apple uploads, release creation, or push. Separately approved
publication must upload the exact signed ZIP without further changes, then
publish the matching feed to `main`. The generator cannot confirm the remote
asset exists or matches those bytes. Intel uses `--arch x86_64` and the
`conv3rt-<version>-intel.zip` archive. Build numbers must increase; duplicate or
older builds and lower versions are rejected without changing the feed.

## Project layout

```
Sources/Conv3rtCore/   UI-free, testable core (capabilities, inspection, planning, conversion, verification, file access, queue)
Sources/Conv3rtApp/    SwiftUI app (window, file list, settings, Finder services)
Tests/Conv3rtCoreTests/ the test suite
docs/                  format matrix and user-facing notes
```

## Known limitations

- **AVIF** is written **lossily** only (optional build with libavif + libaom);
  there is no lossless AVIF, and its output carries no EXIF/XMP.
- **RAW / PSD / SVG / PDF** are exported as **flattened raster images** — their
  original structure is not preserved.
- **WebP** output carries ICC, EXIF/GPS and XMP (not IPTC) and supports animated
  output. **JPEG XL** output carries ICC, EXIF/GPS and XMP but is not animated.

The complete list is in [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Privacy

Images are processed entirely on-device; your files never leave your Mac.
Network use is limited to update checks and update downloads, through GitHub
(`raw.githubusercontent.com`, `github.com`, and GitHub's release-asset CDN
hosts). Those hosts see ordinary connection and HTTP metadata, such as your IP
address and update request headers. No images, conversion data, account data,
telemetry, analytics, crash reports, or system profile are uploaded. Automatic
checks require opt-in; manual **Check for Updates...** is always user-initiated.

## License

MIT for conv3rt's own code. Bundled libwebp is BSD-3; the optional libjxl is
BSD-3 with Apache-2.0 (Highway) and MIT (Brotli, lcms2) components. See
[`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).
