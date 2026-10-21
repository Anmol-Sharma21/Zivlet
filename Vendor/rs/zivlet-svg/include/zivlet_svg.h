// C interface of zivlet-svg (Vendor/rs/zivlet-svg/src/lib.rs): SVG bytes -> premultiplied RGBA8 via resvg.
// Only data: image hrefs resolve; there is no file or network access. Inputs over 64 MiB are refused.
#ifndef ZIVLET_SVG_H
#define ZIVLET_SVG_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ZivletSvgImage {
    uint32_t width;
    uint32_t height;
    uint8_t *_Nullable rgba;  // width * height * 4 premultiplied bytes; release with zivlet_svg_free
} ZivletSvgImage;

enum {
    ZIVLET_SVG_OK = 0,
    ZIVLET_SVG_PARSE = 1,     // not an SVG document
    ZIVLET_SVG_SIZE = 2,      // input over 64 MiB, or a document without area
    ZIVLET_SVG_ALLOC = 3,     // the pixel buffer could not be allocated
    ZIVLET_SVG_ARGUMENT = 4,  // null pointer, scale not positive and finite, or max_edge == 0
};

// Renders `len` bytes at `scale`, with the longest edge capped at `max_edge` pixels.
int32_t zivlet_svg_render(const uint8_t *_Nullable data, size_t len, float scale, uint32_t max_edge,
                          ZivletSvgImage *_Nullable out);

// Writes the intrinsic size in CSS pixels without rendering.
int32_t zivlet_svg_size(const uint8_t *_Nullable data, size_t len, float *_Nullable width, float *_Nullable height);

// Releases an image's pixels and sets rgba to NULL; NULL is ignored.
void zivlet_svg_free(ZivletSvgImage *_Nullable image);

#ifdef __cplusplus
}
#endif

#endif
