# conv3rt

A small, native macOS image converter. Drop images in, pick a format, convert —
offline, on-device, no account, no telemetry, no auto-updates.

- **Platform:** macOS 14 Sonoma or later
- **Architectures:** Apple Silicon and Intel (separate builds)
- **Price:** free, MIT-licensed, open source
- **UI language:** English only

## What it does

conv3rt converts images between the formats macOS and its bundled codecs can
actually read and write. It is honest about what each conversion preserves and
what it loses.

- **Lossless** mode preserves decoded image data exactly where the target format
  allows it. If the target cannot preserve it (for example, JPEG has no
  transparency and no true lossless path), the conversion is **blocked** with a
  clear reason — never silently downgraded.
- **Highest Quality** mode gets the best result the target format allows, and
  tells you up front what will change.

This is *not* "every format to every format, perfectly". Reading a format does
not imply we can write it. See [Format support](#format-support).

## Format support

Support is read from the operating system at runtime, never hard-coded. The full
generated matrix is in [`docs/FORMAT_MATRIX.md`](docs/FORMAT_MATRIX.md).

Highlights on macOS 15:

| Capability | Examples |
|---|---|
| **Read** | JPEG, PNG, TIFF, BMP, GIF, HEIC/HEIF, WebP, AVIF, JPEG XL, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF, nearly all camera RAW families (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2, …) |
| **Write** | PNG, JPEG, TIFF, BMP, GIF, HEIC/HEIF, **WebP**, JPEG 2000, OpenEXR, TGA, ICO, ICNS, Netpbm, PSD, PDF |
| **Read-only** | AVIF, JPEG XL, Radiance HDR, SGI, PICT, all camera RAW |

WebP is **read** by macOS Image I/O and **written** by the bundled libwebp
(BSD-3). It is the only bundled third-party codec; others (AVIF, JPEG XL) are
**not** output targets because macOS cannot encode them and no encoder is
bundled. conv3rt does not pretend otherwise. See
[`docs/CODECS.md`](docs/CODECS.md).

## The Lossless contract

"Lossless" means the decoded sample values, bit depth, alpha, color profile and
structure (animation/pages) are preserved. It is **not** about file size and
**not** about byte-identical files. Full definition and the per-format rules are
in [`docs/LOSSLESS.md`](docs/LOSSLESS.md).

## Build from source

Requires Xcode command line tools (Swift 5.9+), macOS 14+.

```sh
# Run the test suite
swift test

# Build and run (development)
swift run conv3rt

# Print the live format capability matrix
swift run conv3rt --dump-capabilities

# Build a distributable .app for one architecture
scripts/package.sh arm64          # Apple Silicon
scripts/package.sh x86_64         # Intel
```

See [`docs/PACKAGING.md`](docs/PACKAGING.md) for signing, notarization and
release steps.

## Privacy

conv3rt never connects to the network: no uploads, no telemetry, no analytics,
no crash upload, no update checks, no license server. Images are processed
entirely on-device. See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Known limitations

See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md). The short version:

- AVIF / JPEG XL **cannot be written** (no bundled encoder yet); WebP can.
- WebP output does not yet carry EXIF/XMP (ICC is written).
- Finder Quick Action extension is not implemented; **Open With** works.
- RAW, PSD, SVG and PDF are **exported as flattened raster images**; their
  original structure is not preserved.
- 16-bit or HDR data is only preserved when the target can store it; otherwise
  the conversion is blocked (Lossless) or warned (Highest Quality).

## License

MIT for conv3rt's own code (`LICENSE`). Bundled third-party codecs, if any,
keep their own licenses — see [`THIRD_PARTY_NOTICES.txt`](THIRD_PARTY_NOTICES.txt).
