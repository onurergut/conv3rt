// conv3rt JPEG XL encoder shim.
#include <stdlib.h>
#include <string.h>

#include <jxl/encode.h>

#include "conv3rt_jxl.h"

int conv3rt_jxl_encode_rgba(const uint8_t *rgba, int width, int height,
                            int lossless, float quality,
                            const uint8_t *icc, size_t icc_size,
                            const uint8_t *exif, size_t exif_size,
                            const uint8_t *xmp, size_t xmp_size,
                            uint8_t **out, size_t *out_size) {
    if (rgba == NULL || out == NULL || out_size == NULL || width <= 0 || height <= 0) {
        return 1;
    }

    JxlEncoder *enc = JxlEncoderCreate(NULL);
    if (enc == NULL) return 1;

    // Metadata boxes are opt-in; enable them up front so JxlEncoderAddBox is
    // allowed once the frame has been added.
    const int want_exif = (exif != NULL && exif_size > 0);
    const int want_xmp = (xmp != NULL && xmp_size > 0);
    const int boxes_ok = (JxlEncoderUseBoxes(enc) == JXL_ENC_SUCCESS);

    JxlBasicInfo info;
    JxlEncoderInitBasicInfo(&info);
    info.xsize = (uint32_t)width;
    info.ysize = (uint32_t)height;
    info.bits_per_sample = 8;
    info.exponent_bits_per_sample = 0;
    info.num_color_channels = 3;
    info.num_extra_channels = 1;      // alpha
    info.alpha_bits = 8;
    info.alpha_exponent_bits = 0;
    info.alpha_premultiplied = JXL_FALSE;
    info.uses_original_profile = lossless ? JXL_TRUE : JXL_FALSE;
    if (JxlEncoderSetBasicInfo(enc, &info) != JXL_ENC_SUCCESS) {
        JxlEncoderDestroy(enc);
        return 2;
    }

    if (icc != NULL && icc_size > 0) {
        if (JxlEncoderSetICCProfile(enc, icc, icc_size) != JXL_ENC_SUCCESS) {
            JxlColorEncoding color;
            JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
            if (JxlEncoderSetColorEncoding(enc, &color) != JXL_ENC_SUCCESS) {
                JxlEncoderDestroy(enc);
                return 2;
            }
        }
    } else {
        JxlColorEncoding color;
        JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
        if (JxlEncoderSetColorEncoding(enc, &color) != JXL_ENC_SUCCESS) {
            JxlEncoderDestroy(enc);
            return 2;
        }
    }

    JxlEncoderFrameSettings *frame = JxlEncoderFrameSettingsCreate(enc, NULL);
    if (frame == NULL) {
        JxlEncoderDestroy(enc);
        return 2;
    }
    if (lossless) {
        JxlEncoderSetFrameLossless(frame, JXL_TRUE);
    } else {
        float d = (1.0f - quality) * 4.0f;
        if (d < 0.f) d = 0.f;
        JxlEncoderSetFrameDistance(frame, d);
    }

    JxlPixelFormat pf;
    pf.num_channels = 4;
    pf.data_type = JXL_TYPE_UINT8;
    pf.endianness = JXL_NATIVE_ENDIAN;
    pf.align = 0;
    const size_t frame_size = (size_t)width * (size_t)height * 4;
    if (JxlEncoderAddImageFrame(frame, &pf, rgba, frame_size) != JXL_ENC_SUCCESS) {
        JxlEncoderDestroy(enc);
        return 3;
    }
    JxlEncoderCloseFrames(enc);

    // Attach metadata boxes after the frame, before closing boxes. Boxes are
    // best-effort: an encoder that refuses them still yields a valid codestream.
    if (boxes_ok && want_exif) {
        // The "Exif" box contents are prefixed by a 4-byte tiff-header offset,
        // which is zero when the TIFF header follows immediately.
        uint8_t *boxed = (uint8_t *)malloc(exif_size + 4);
        if (boxed != NULL) {
            boxed[0] = boxed[1] = boxed[2] = boxed[3] = 0;
            memcpy(boxed + 4, exif, exif_size);
            JxlBoxType type; memcpy(type, "Exif", 4);
            JxlEncoderAddBox(enc, type, boxed, exif_size + 4, JXL_FALSE);
            free(boxed);
        }
    }
    if (boxes_ok && want_xmp) {
        JxlBoxType type; memcpy(type, "xml ", 4);
        JxlEncoderAddBox(enc, type, xmp, xmp_size, JXL_FALSE);
    }

    JxlEncoderCloseBoxes(enc);
    JxlEncoderCloseInput(enc);

    size_t cap = 1u << 16, size = 0;
    uint8_t *buf = (uint8_t *)malloc(cap);
    if (buf == NULL) {
        JxlEncoderDestroy(enc);
        return 4;
    }

    for (;;) {
        uint8_t *next = buf + size;
        size_t avail = cap - size;
        JxlEncoderStatus st = JxlEncoderProcessOutput(enc, &next, &avail);
        size = cap - avail;
        if (st == JXL_ENC_SUCCESS) break;
        if (st == JXL_ENC_NEED_MORE_OUTPUT) {
            size_t newcap = cap * 2;
            uint8_t *grown = (uint8_t *)realloc(buf, newcap);
            if (grown == NULL) { free(buf); JxlEncoderDestroy(enc); return 4; }
            buf = grown;
            cap = newcap;
            continue;
        }
        free(buf);
        JxlEncoderDestroy(enc);
        return 5;
    }

    JxlEncoderDestroy(enc);
    *out = buf;
    *out_size = size;
    return 0;
}
