// conv3rt JPEG XL encode shim (thin wrapper over libjxl's C encoder API).
#ifndef CONV3RT_JXL_H
#define CONV3RT_JXL_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Encodes tightly packed 8-bit non-premultiplied RGBA to JPEG XL.
//   lossless != 0 -> lossless encode (uses_original_profile, frame lossless).
//   lossless == 0 -> lossy at `quality` (0..1).
// If icc/icc_size are non-null the ICC profile is embedded.
// On success returns 0; *out is a malloc'd buffer (free with free()).
int conv3rt_jxl_encode_rgba(const uint8_t *rgba, int width, int height,
                            int lossless, float quality,
                            const uint8_t *icc, size_t icc_size,
                            uint8_t **out, size_t *out_size);

#ifdef __cplusplus
}
#endif

#endif  // CONV3RT_JXL_H
