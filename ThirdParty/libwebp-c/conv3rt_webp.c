// conv3rt WebP encoder shim. Uses libwebp's WebPConfig/WebPEncode advanced API
// so the `exact` flag can be honored on lossless encodes (preserving the RGB
// values beneath fully transparent pixels).
#include <stdlib.h>
#include <string.h>

#include "src/webp/encode.h"
#include "src/webp/mux.h"
#include "webp/conv3rt_webp.h"

// Sets one metadata chunk on the mux. A null/empty payload is a no-op that
// reports success so callers can pass optional metadata uniformly.
static int mux_set_chunk(WebPMux *mux, const char *fourcc,
                         const uint8_t *data, size_t size) {
    if (data == NULL || size == 0) return 1;
    WebPData chunk = { data, size };
    return WebPMuxSetChunk(mux, fourcc, &chunk, 1) == WEBP_MUX_OK;
}

// Wraps a raw WebP bitstream in a container and attaches the ICCP, EXIF and
// XMP chunks that were provided, so the output is a proper extended WebP.
// Returns 0 and a malloc'd buffer on success.
static int wrap_with_metadata(const uint8_t *bitstream, size_t bitstream_size,
                              const uint8_t *icc, size_t icc_size,
                              const uint8_t *exif, size_t exif_size,
                              const uint8_t *xmp, size_t xmp_size,
                              uint8_t **out, size_t *out_size) {
    WebPData data = { bitstream, bitstream_size };
    WebPMux *mux = WebPMuxCreate(&data, 1);
    if (mux == NULL) return 1;

    int ok = 0;
    if (mux_set_chunk(mux, "ICCP", icc, icc_size)
        && mux_set_chunk(mux, "EXIF", exif, exif_size)
        && mux_set_chunk(mux, "XMP ", xmp, xmp_size)) {
        WebPData assembled = { NULL, 0 };
        if (WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK && assembled.bytes != NULL) {
            uint8_t *buf = (uint8_t *)malloc(assembled.size);
            if (buf != NULL) {
                memcpy(buf, assembled.bytes, assembled.size);
                *out = buf;
                *out_size = assembled.size;
                ok = 1;
            }
            WebPDataClear(&assembled);
        }
    }
    WebPMuxDelete(mux);
    return ok ? 0 : 2;
}

int conv3rt_webp_encode_rgba(const uint8_t *rgba, int width, int height, int stride,
                             int lossless, float quality,
                             const uint8_t *icc, size_t icc_size,
                             const uint8_t *exif, size_t exif_size,
                             const uint8_t *xmp, size_t xmp_size,
                             uint8_t **out, size_t *out_size) {
    if (rgba == NULL || out == NULL || out_size == NULL || width <= 0 || height <= 0) {
        return 1;
    }

    WebPConfig config;
    if (!WebPConfigInit(&config)) return 1;

    config.lossless = lossless ? 1 : 0;
    config.exact = lossless ? 1 : 0;          // keep RGB under transparent pixels
    config.quality = lossless ? 100.f : quality;
    config.alpha_quality = 100;
    config.method = 6;                          // slowest / best quality

    if (!WebPValidateConfig(&config)) return 1;

    WebPPicture pic;
    if (!WebPPictureInit(&pic)) return 1;
    pic.use_argb = 1;
    pic.width = width;
    pic.height = height;
    if (!WebPPictureAlloc(&pic)) {
        WebPPictureFree(&pic);
        return 1;
    }
    if (!WebPPictureImportRGBA(&pic, rgba, stride)) {
        WebPPictureFree(&pic);
        return 1;
    }

    WebPMemoryWriter writer;
    WebPMemoryWriterInit(&writer);
    pic.writer = WebPMemoryWrite;
    pic.custom_ptr = &writer;

    const int ok = WebPEncode(&config, &pic);
    WebPPictureFree(&pic);

    if (!ok) {
        WebPMemoryWriterClear(&writer);
        return 2;
    }

    int has_icc = (icc != NULL && icc_size > 0);
    int has_exif = (exif != NULL && exif_size > 0);
    int has_xmp = (xmp != NULL && xmp_size > 0);
    if (has_icc || has_exif || has_xmp) {
        int rc = wrap_with_metadata(writer.mem, writer.size, icc, icc_size,
                                    exif, exif_size, xmp, xmp_size, out, out_size);
        WebPMemoryWriterClear(&writer);
        return rc;
    }

    *out = writer.mem;
    *out_size = writer.size;
    return 0;
}
