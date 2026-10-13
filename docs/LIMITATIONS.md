# Known limitations

Honest list of what conv3rt does **not** do today. None of these is silently
faked in the UI.

## Format coverage

- **WebP, AVIF, JPEG XL cannot be written.** macOS Image I/O can decode them but
  not encode them, and no bundled encoder is shipped yet. They do not appear as
  output targets. See [`CODECS.md`](CODECS.md).
- **Radiance HDR, SGI, PICT are read-only** on macOS; not output targets.
- **PFM and PAM/PGM/PPM** beyond the native PBM UTI are not guaranteed.
- **EPS/PS/AI** and medical/scientific formats are not supported (they need
  Ghostscript-sized dependencies with accuracy and security costs).

## Structural sources

- **Camera RAW, PSD, SVG, PDF** are exported as **flattened raster images**. The
  original structure (sensor data, layers, vectors, PDF page objects) is not
  preserved, and these conversions are never labeled lossless.
- RAW output is not possible; conv3rt cannot create camera RAW from any image.
- PSD exports the merged/rendered image. Unsupported PSD variants error clearly.
- SVG is rasterized statically; scripts are not run and remote resources are not
  downloaded.

## Modes

- **Lossless is blocked** (not downgraded) whenever samples, depth, alpha, color
  profile or structure cannot be preserved.
- HEIC/HEIF is treated as **lossy** even at maximum quality: the RGB→YUV /
  subsampling pipeline is not proven lossless.
- APNG write is **not verified**, so animated sources into PNG require the
  export-all or first-frame decision.

## Integration

- **Finder Quick Action (Action Extension) is not implemented.** Only **Open
  With** is wired up (document types in `Info.plist` + `.onOpenURL`).
- No automatic updates, no `Check for Updates`, no Sparkle.

## Build / release

- Only the **Apple Silicon** build has been produced and launched on this
  machine. The **Intel** build path exists (`scripts/package.sh x86_64`) but has
  not been run or tested here — cross-compiling is not the same as testing on an
  Intel Mac.
- No Developer ID identity is configured here, so release artifacts are
  **ad-hoc signed**, not notarized. Real distribution requires signing +
  notarization (see [`PACKAGING.md`](PACKAGING.md)).

## Verification gaps

- The UI was launched and confirmed to create a window, but its rendering could
  not be screenshotted in this environment (no Screen Recording permission), so
  the visual layout has not been inspected end to end.
- Byte-level lossless verification is implemented for the native codecs covered
  by tests; formats not exercised by a test are marked `unverified` in the
  capability matrix rather than claimed supported.
