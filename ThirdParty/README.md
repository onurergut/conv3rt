# Third-party code

## libwebp-c/ — libwebp 1.4.0 (BSD-3)

A **curated source subset** of [libwebp](https://github.com/webmproject/libwebp)
tag `v1.4.0`, compiled directly by SwiftPM as the `CWebP` target. Included:
`src/enc`, `src/dec`, `src/dsp`, `src/utils`, `src/webp`, `src/mux`, and
`sharpyuv/`. Excluded: tools, examples, tests, benchmarks, `demux`, and all build
files. No libwebp source was modified.

conv3rt adds only:
- `conv3rt_webp.c` — a thin shim over `WebPConfig`/`WebPEncode` (with `exact = 1`
  for lossless) and the mux API (to write the ICCP color-profile chunk).
- `src/webp/conv3rt_webp.h` — its public declaration.

License: `libwebp-c/COPYING` (BSD 3-Clause) and `libwebp-c/PATENTS`. Both are
copied into the app bundle at `Contents/Resources/licenses/`.

### Re-vendoring a new version

```sh
curl -L https://github.com/webmproject/libwebp/archive/refs/tags/vX.Y.Z.tar.gz | tar xz
# copy src/{enc,dec,dsp,utils,webp,mux} and sharpyuv/ into libwebp-c/, then
# re-add conv3rt_webp.c / conv3rt_webp.h and rebuild.
```

The upstream full tree is **not** committed (git-ignored).
