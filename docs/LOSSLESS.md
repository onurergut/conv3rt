# The Lossless contract

Lossless is **not** a quality slider set to 100%. It is a concrete promise about
the decoded image, judged against the source's decoded samples and image
properties.

## Four different things people call "lossless"

1. **Byte-identical copy** — the exact same file bytes. conv3rt does not do this
   for conversions (only same-format passthrough could, which is not the goal).
2. **Lossless re-encode** — decode the source, re-encode the *decoded* image
   with no further loss. This is what conv3rt's Lossless mode means.
3. **Visually lossless** — lossy, but looks fine. conv3rt never labels this
   "lossless" and does not use the phrase "visually lossless".
4. **Structural change** — RAW demosaic, PSD flatten, SVG/PDF rasterization.
   These are always reported as structural, never as lossless.

`JPEG → PNG` cannot recover what the JPEG already threw away. It can only avoid
adding *new* loss. conv3rt classifies the *added* loss, not the source's history.

## What Lossless mode guarantees (where the target allows it)

- Preserve decoded sample values.
- Do not silently reduce bit depth.
- Do not silently change the color profile.
- Do not convert color space unless unavoidable.
- Preserve alpha.
- Respect palette / color-count limits (GIF).
- Avoid chroma-subsampling loss.
- Preserve all animation frames and timing.
- Preserve multipage structure.
- Do not drop required image properties.

If any of these cannot hold, Lossless mode **blocks** the conversion, explains
why in English, suggests alternatives, and lets the user consciously switch mode.

## Per-format rules

| Target | Lossless path? | Conditions / traps |
|---|---|---|
| PNG | Yes | 8/16-bit, full alpha. Static only; APNG write is not verified. |
| TIFF | Yes | 8/16/32-bit, alpha, multipage. |
| BMP | Yes | Alpha preserved (32-bit). No color profile. |
| GIF | Conditional | ≤256 colors and 1-bit alpha; lossless only if the source fits. Otherwise blocked. |
| JPEG | **No** | Lossy only. Alpha and >8-bit are blocking in Lossless mode. |
| HEIC/HEIF | **No** | RGB→YUV, subsampling, bit depth — the full pipeline is not verified lossless. |
| JPEG 2000 | Yes | Keep exact samples and depth. |
| OpenEXR | Yes | Compression method and channel types must be lossless; do not route through 8-bit. |
| TGA, ICO, ICNS, Netpbm | Yes | Exact samples where representable. |
| WebP / AVIF / JPEG XL | n/a | Not writable on macOS; not offered as targets. |

## Traps this project explicitly guards against

- **WebP transparent-pixel RGB** — lossless WebP can change RGB under fully
  transparent pixels. (Not reachable via the native path, which cannot write
  WebP at all; relevant if a WebP encoder is added — it must use libwebp's exact
  mode.)
- **AVIF/HEIF** — an encoder "lossless" flag does not remove RGB→YUV, range,
  matrix, bit-depth or subsampling loss. conv3rt does not claim lossless here.
- **EXR** — a file being EXR says nothing about whether it is lossless; the
  compression method matters.
- **Shared 8-bit premultiplied RGBA canvas** — conv3rt never funnels everything
  through one 8-bit premultiplied sRGB canvas. The intermediate representation
  follows the source/target requirements.

## How it is verified

- Sources are synthetic images with known sample values
  (`Tests/Conv3rtCoreTests/Fixtures.swift`).
- After a Lossless conversion, decoded samples are compared exactly — not after
  collapsing to 8-bit sRGB, which would hide error.
- Alpha, fully transparent pixels, bit depth, ICC and frame counts are checked
  separately.
- Same-format passthrough is checked by hash where applicable.
- An encoder flag is never accepted as proof of losslessness.

`JPEG → PNG adds no loss beyond the JPEG` is a live, passing test.
