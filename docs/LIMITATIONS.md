# Known limitations

Honest list of what conv3rt does **not** do today. None of these is silently
faked in the UI.

## Format coverage

- **WebP can be written** (bundled libwebp). Lossless uses `exact` mode; ICC,
  EXIF/GPS and XMP are written; animated sources become one animated WebP. IPTC
  is not written.
- **JPEG XL can be written only if you build libjxl** (`scripts/build-jxl.sh`).
  Without it, JPEG XL is read-only. ICC, EXIF/GPS and XMP are written; IPTC and
  animation are not.
- **AVIF can be written only if you build libavif + libaom**
  (`scripts/build-avif.sh`). It is **lossy only** (no lossless AVIF); the ICC
  profile is embedded, but EXIF/XMP and animation are not written. The build
  adds ~5 MB to the app.
- **Radiance HDR, SGI, PICT are read-only** on macOS; not output targets.
- **JPEG 2000 output is lossy.** Image I/O writes JP2 lossily by default
  (verified: sample 0 → 1), so it is not offered as a lossless target.
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
