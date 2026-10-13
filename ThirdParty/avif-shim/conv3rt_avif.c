// conv3rt AVIF encoder shim.
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include <avif/avif.h>

#include "conv3rt_avif.h"

int conv3rt_avif_encode_rgba(const uint8_t *rgba, int width, int height, int stride,
                             float quality,
                             const uint8_t *icc, size_t icc_size,
                             uint8_t **out, size_t *out_size) {
    if (rgba == NULL || out == NULL || out_size == NULL || width <= 0 || height <= 0) {
        return 1;
    }
    if (stride <= 0) stride = width * 4;

    avifResult result;

    // 8-bit 4:2:0 YUV; libavif converts RGBA -> YUV for us. AVIF here is a
    // lossy-only target (the RGB->YUV round trip is lossy), so there is no
    // lossless mode.
    avifImage *image = avifImageCreate((uint32_t)width, (uint32_t)height, 8, AVIF_PIXEL_FORMAT_YUV420);
    if (image == NULL) return 1;

    // The alpha plane (if any) is allocated by avifImageRGBToYUV when the RGB
    // source carries alpha.
    if (avifImageAllocatePlanes(image, AVIF_PLANES_YUV) != AVIF_RESULT_OK) {
        avifImageDestroy(image);
        return 2;
    }
    image->alphaPremultiplied = AVIF_FALSE;

    if (icc != NULL && icc_size > 0) {
        avifImageSetProfileICC(image, icc, icc_size);
    }

    avifRGBImage rgb;
    avifRGBImageSetDefaults(&rgb, image);
    rgb.format = AVIF_RGB_FORMAT_RGBA;
    rgb.depth = 8;
    rgb.pixels = (uint8_t *)rgba;      // borrowed, not owned
    rgb.rowBytes = (uint32_t)stride;
    // Non-premultiplied RGBA, matching image->alphaPremultiplied above.

    result = avifImageRGBToYUV(image, &rgb);
    if (result != AVIF_RESULT_OK) {
        avifImageDestroy(image);
        return 3;
    }

    avifEncoder *encoder = avifEncoderCreate();
    if (encoder == NULL) {
        avifImageDestroy(image);
        return 4;
    }
    int q = (int)lroundf(quality * 100.0f);
    if (q < 0) q = 0;
    if (q > 100) q = 100;
    encoder->quality = q;
    encoder->qualityAlpha = q;
    encoder->speed = AVIF_SPEED_DEFAULT;
    encoder->maxThreads = 1;

    avifRWData output = AVIF_DATA_EMPTY;
    result = avifEncoderAddImage(encoder, image, 1, AVIF_ADD_IMAGE_FLAG_SINGLE);
    if (result == AVIF_RESULT_OK) {
        result = avifEncoderFinish(encoder, &output);
    }

    avifEncoderDestroy(encoder);
    avifImageDestroy(image);

    if (result != AVIF_RESULT_OK) {
        avifRWDataFree(&output);
        return 5;
    }

    uint8_t *buf = (uint8_t *)malloc(output.size);
    if (buf == NULL) {
        avifRWDataFree(&output);
        return 6;
    }
    memcpy(buf, output.data, output.size);
    *out = buf;
    *out_size = output.size;
    avifRWDataFree(&output);
    return 0;
}
