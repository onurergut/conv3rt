// conv3rt WebP encode shim (thin wrapper over libwebp's advanced API).
#ifndef CONV3RT_WEBP_H
#define CONV3RT_WEBP_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int (*conv3rt_webp_progress_hook)(int percent, void *user_data);

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
                             conv3rt_webp_progress_hook progress, void *user_data,
                             uint8_t **out, size_t *out_size);

// Encodes an animated WebP from several 8-bit non-premultiplied RGBA frames.
// `rgba_frames` points to `frame_count` tightly packed frames laid back to back,
// each `height * stride` bytes (stride must be width * 4). `durations_ms[i]` is
// the display time of frame i in milliseconds. All frames must share one size.
// `loop_count` is the number of animation loops (0 = infinite).
// Encoding is lossless+exact when `lossless != 0`, else lossy at `quality`
// (0..100). The ICCP/EXIF/XMP chunks are attached when their payloads are given.
// On success returns 0 and sets *out to a malloc'd buffer (free with free()).
int conv3rt_webp_encode_anim_rgba(const uint8_t *rgba_frames, int width, int height,
                                  int stride, const int *durations_ms, int frame_count,
                                  int lossless, float quality, int loop_count,
                                  const uint8_t *icc, size_t icc_size,
                                  const uint8_t *exif, size_t exif_size,
                                  const uint8_t *xmp, size_t xmp_size,
                                  conv3rt_webp_progress_hook progress, void *user_data,
                                  uint8_t **out, size_t *out_size);

#ifdef __cplusplus
}
#endif

#endif  // CONV3RT_WEBP_H
