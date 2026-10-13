// conv3rt AVIF encode shim (thin wrapper over libavif's C encoder API).
#ifndef CONV3RT_AVIF_H
#define CONV3RT_AVIF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Encodes tightly packed 8-bit non-premultiplied RGBA to a lossy AVIF still
// image. RGB->YUV, matrix and subsampling are handled by libavif/aom; AVIF has
// no lossless path here (the RGB->YUV round trip is lossy), so quality is the
// only control.
//   quality: 0..1 (mapped to libavif's 0..100 quality scale).
//   icc/icc_size: if non-null, the ICC profile is embedded in the AVIF.
// On success returns 0; *out is a malloc'd buffer (free with free()).
// On failure returns non-zero and leaves *out untouched.
int conv3rt_avif_encode_rgba(const uint8_t *rgba, int width, int height, int stride,
                             float quality,
                             const uint8_t *icc, size_t icc_size,
                             uint8_t **out, size_t *out_size);

#ifdef __cplusplus
}
#endif

#endif  // CONV3RT_AVIF_H
