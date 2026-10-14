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
- Sparkle 2.10.0 supports manual **Check for Updates...** and automatic checks
  only after opt-in through its native permission prompt on the second launch.
  Every installation requires approval; silent installation and system-profile
  reporting are disabled. Installation waits while conversion is active.
- Version **0.5.0 has no updater**. The first update-capable version, **0.6.0**,
  must be installed manually once a real release is available.
- Architecture-specific stable feeds are prepared in `updates/`, currently as
  empty RSS feeds. They are not live until pushed to `main`; no GitHub Releases
  exist yet. No signed/notarized update artifact is claimed as published.

## Build / release

- Only the **Apple Silicon** build has been produced and launched on this
  machine. The **Intel** build path exists (`scripts/package.sh x86_64`) but has
  not been run or tested here — cross-compiling is not the same as testing on an
  Intel Mac.
- Developer ID signing is available for local packaging, but the current 0.6.0
  artifact has not been submitted for notarization or published as a release.
  Public distribution still requires Apple notarization and stapling, then
  release verification before Sparkle signs the final ZIP bytes. No Apple
  submission or GitHub publication has been performed as part of update
  preparation.
- The appcast generator is local-only. It accepts per-architecture stable ZIPs
  and canonical HTTPS assets under
  `github.com/onurergut/conv3rt/releases/download/`, rejects build/version
  downgrades, checks the signing account against the archived public key, and
  verifies exact archive bytes and length. It cannot confirm a remote asset
  exists or matches local bytes; publication must preserve the signed ZIP.
- Update checks and downloads are the only allowed network use. GitHub feed,
  release and release-asset CDN hosts receive ordinary IP/HTTP metadata. Images
  and conversion data stay on-device; no system profile or telemetry is sent.

## Verification gaps

- The UI was launched and confirmed to create a window, but its rendering could
  not be screenshotted in this environment (no Screen Recording permission), so
  the visual layout has not been inspected end to end.
- Byte-level lossless verification is implemented for the native codecs covered
  by tests; formats not exercised by a test are marked `unverified` in the
  capability matrix rather than claimed supported.
