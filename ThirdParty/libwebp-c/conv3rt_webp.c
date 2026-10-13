// conv3rt WebP encoder shim. Uses libwebp's WebPConfig/WebPEncode advanced API
// so the `exact` flag can be honored on lossless encodes (preserving the RGB
// values beneath fully transparent pixels).
#include <stdlib.h>
#include <string.h>

#include "src/webp/encode.h"
#include "src/webp/mux.h"
#include "webp/conv3rt_webp.h"

typedef struct {
    conv3rt_webp_progress_hook hook;
    void *user_data;
    int frame;
    int frames;
} ProgressContext;

static int report_progress(int percent, const WebPPicture *picture) {
    const ProgressContext *context = (const ProgressContext *)picture->user_data;
    if (context == NULL || context->hook == NULL) return 1;
    const int total_percent = (int)(((int64_t)context->frame * 100 + percent) / context->frames);
    return context->hook(total_percent, context->user_data);
}

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
                             conv3rt_webp_progress_hook progress, void *user_data,
                             uint8_t **out, size_t *out_size) {
    if (rgba == NULL || out == NULL || out_size == NULL || width <= 0 || height <= 0) {
        return 1;
    }

    WebPConfig config;
    if (!WebPConfigInit(&config)) return 1;

    config.lossless = lossless ? 1 : 0;
    config.exact = lossless ? 1 : 0;          // keep RGB under transparent pixels
    config.quality = lossless ? 75.f : quality;
    config.alpha_quality = 100;
    config.method = lossless ? 4 : 6;

    if (!WebPValidateConfig(&config)) return 1;

    WebPPicture pic;
    if (!WebPPictureInit(&pic)) return 1;
    pic.use_argb = 1;
    pic.width = width;
    pic.height = height;
    ProgressContext context = { progress, user_data, 0, 1 };
    pic.progress_hook = report_progress;
    pic.user_data = &context;
    if (progress != NULL && !progress(0, user_data)) {
        WebPPictureFree(&pic);
        return 2;
    }
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

int conv3rt_webp_encode_anim_rgba(const uint8_t *rgba_frames, int width, int height,
                                  int stride, const int *durations_ms, int frame_count,
                                  int lossless, float quality, int loop_count,
                                  const uint8_t *icc, size_t icc_size,
                                  const uint8_t *exif, size_t exif_size,
                                  const uint8_t *xmp, size_t xmp_size,
                                  conv3rt_webp_progress_hook progress, void *user_data,
                                  uint8_t **out, size_t *out_size) {
    if (rgba_frames == NULL || durations_ms == NULL || frame_count <= 0
        || out == NULL || out_size == NULL || width <= 0 || height <= 0
        || stride != width * 4) {
        return 1;
    }

    WebPAnimEncoderOptions opts;
    if (!WebPAnimEncoderOptionsInit(&opts)) return 1;
    opts.anim_params.loop_count = loop_count;
    opts.minimize_size = 0;
    opts.allow_mixed = 0;

    WebPAnimEncoder *enc = WebPAnimEncoderNew(width, height, &opts);
    if (enc == NULL) return 1;

    const size_t frame_bytes = (size_t)height * (size_t)stride;
    int rc = 0;
    int timestamp_ms = 0;
    ProgressContext context = { progress, user_data, 0, frame_count };
    for (int i = 0; i < frame_count; i++) {
        context.frame = i;
        if (progress != NULL && !progress((int)((int64_t)i * 100 / frame_count), user_data)) {
            rc = 2;
            break;
        }
        WebPConfig config;
        if (!WebPConfigInit(&config)) { rc = 2; break; }
        config.lossless = lossless ? 1 : 0;
        config.exact = lossless ? 1 : 0;      // keep RGB under transparent pixels
        config.quality = lossless ? 75.f : quality;
        config.alpha_quality = 100;
        config.method = lossless ? 4 : 6;
        if (!WebPValidateConfig(&config)) { rc = 2; break; }

        WebPPicture pic;
        if (!WebPPictureInit(&pic)) { rc = 2; break; }
        pic.use_argb = 1;
        pic.width = width;
        pic.height = height;
        pic.progress_hook = report_progress;
        pic.user_data = &context;
        if (!WebPPictureAlloc(&pic)) { WebPPictureFree(&pic); rc = 2; break; }
        if (!WebPPictureImportRGBA(&pic, rgba_frames + (size_t)i * frame_bytes, stride)) {
            WebPPictureFree(&pic);
            rc = 2;
            break;
        }
        if (!WebPAnimEncoderAdd(enc, &pic, timestamp_ms, &config)) {
            WebPPictureFree(&pic);
            rc = 3;
            break;
        }
        WebPPictureFree(&pic);
        if (durations_ms[i] > 0) {
            if (durations_ms[i] > INT32_MAX - timestamp_ms) { rc = 3; break; }
            timestamp_ms += durations_ms[i];
        }
    }

    // Flush with a null frame so the last frame's duration is honored.
    if (rc == 0 && !WebPAnimEncoderAdd(enc, NULL, timestamp_ms, NULL)) rc = 3;

    // Attach metadata chunks before assembling (no-op for empty payloads).
    if (rc == 0 && icc != NULL && icc_size > 0) {
        WebPData d = { icc, icc_size };
        if (WebPAnimEncoderSetChunk(enc, "ICCP", &d, 1) != WEBP_MUX_OK) rc = 4;
    }
    if (rc == 0 && exif != NULL && exif_size > 0) {
        WebPData d = { exif, exif_size };
        if (WebPAnimEncoderSetChunk(enc, "EXIF", &d, 1) != WEBP_MUX_OK) rc = 4;
    }
    if (rc == 0 && xmp != NULL && xmp_size > 0) {
        WebPData d = { xmp, xmp_size };
        if (WebPAnimEncoderSetChunk(enc, "XMP ", &d, 1) != WEBP_MUX_OK) rc = 4;
    }

    WebPData assembled = { NULL, 0 };
    if (rc == 0) {
        if (!WebPAnimEncoderAssemble(enc, &assembled) || assembled.bytes == NULL) {
            rc = 3;
        }
    }
    if (rc == 0) {
        uint8_t *buf = (uint8_t *)malloc(assembled.size);
        if (buf == NULL) {
            rc = 5;
        } else {
            memcpy(buf, assembled.bytes, assembled.size);
            *out = buf;
            *out_size = assembled.size;
        }
    }
    WebPDataClear(&assembled);
    WebPAnimEncoderDelete(enc);
    return rc;
}
