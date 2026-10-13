// conv3rt WebP encode shim (thin wrapper over libwebp's advanced API).
#ifndef CONV3RT_WEBP_H
#define CONV3RT_WEBP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Encodes 8-bit non-premultiplied RGBA (row stride in bytes) to WebP.
//   lossless != 0  -> lossless encode with WebPConfig.exact = 1, so the RGB
//                     values of fully transparent pixels are preserved exactly.
//   lossless == 0  -> lossy encode at `quality` (0..100).
// If `icc`/`icc_size` are non-null, the ICC profile is written into the container
// (ICCP chunk). If `exif`/`exif_size` are non-null the raw EXIF payload (TIFF
// structure, no "Exif\0\0" header) is written into the "EXIF" chunk. If
// `xmp`/`xmp_size` are non-null the XMP packet is written into the "XMP " chunk.
// On success returns 0 and sets *out to a malloc'd buffer (free with free()) and
// *out_size to its length. Returns nonzero on failure.
int conv3rt_webp_encode_rgba(const uint8_t *rgba, int width, int height, int stride,
                             int lossless, float quality,
                             const uint8_t *icc, size_t icc_size,
                             const uint8_t *exif, size_t exif_size,
                             const uint8_t *xmp, size_t xmp_size,
                             uint8_t **out, size_t *out_size);

#ifdef __cplusplus
}
#endif

#endif  // CONV3RT_WEBP_H
