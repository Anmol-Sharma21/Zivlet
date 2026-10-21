//! C ABI for SVG -> premultiplied RGBA8 rendering over resvg (D-M4-6, D-M4-7).
//!
//! Only `data:` image hrefs resolve: there is no resources directory and string hrefs (files, URLs) are dropped,
//! so a hostile SVG cannot read other files or reach a network. System fonts are loaded once per process.
//! Rendering is bounded (`limits`): costly filters lower the output's longest edge, documents still too costly are
//! refused, and embedded raster images are capped by their header sizes. A panic inside resvg or a decoder is
//! caught at this boundary and fails the one call (the crate unwinds on panic).
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, OnceLock};

use resvg::tiny_skia::{Pixmap, Transform};
use resvg::usvg::{fontdb, ImageHrefResolver, Options, Tree};

pub mod limits;

/// A rendered image. `rgba` holds `width * height * 4` premultiplied bytes owned by this library;
/// release it with `zivlet_svg_free`.
#[repr(C)]
pub struct ZivletSvgImage {
    pub width: u32,
    pub height: u32,
    pub rgba: *mut u8,
}

/// What `zivlet_svg_probe` learns without rendering.
#[repr(C)]
pub struct ZivletSvgInfo {
    /// Intrinsic size in CSS pixels.
    pub width: f32,
    pub height: f32,
    /// The longest edge `zivlet_svg_render` will draw for the `max_edge` asked (lower for costly filters).
    pub edge: u32,
    /// The largest embedded raster image in decoded pixels (0 without one), for the caller's memory budget.
    pub image_pixels: u64,
}

pub const ZIVLET_SVG_OK: i32 = 0;
/// The bytes are not an SVG document resvg can read.
pub const ZIVLET_SVG_PARSE: i32 = 1;
/// The input is larger than `MAX_INPUT_BYTES`, or the document has no area.
pub const ZIVLET_SVG_SIZE: i32 = 2;
/// The pixel buffer could not be allocated.
pub const ZIVLET_SVG_ALLOC: i32 = 3;
/// A null pointer, a scale that is not a positive finite number, or a zero edge cap.
pub const ZIVLET_SVG_ARGUMENT: i32 = 4;
/// Too costly to render: filters over the work budget even at the smallest edge, or embedded images over the caps.
pub const ZIVLET_SVG_LIMIT: i32 = 5;
/// resvg or a decoder panicked; the call failed and nothing was returned.
pub const ZIVLET_SVG_PANIC: i32 = 6;

/// Inputs over 64 MiB are refused before parsing (03b §6.4).
pub const MAX_INPUT_BYTES: usize = 64 * 1024 * 1024;

fn fonts() -> &'static Arc<fontdb::Database> {
    static DB: OnceLock<Arc<fontdb::Database>> = OnceLock::new();
    DB.get_or_init(|| {
        let mut db = fontdb::Database::new();
        db.load_system_fonts();
        Arc::new(db)
    })
}

fn options() -> Options<'static> {
    Options {
        resources_dir: None,
        fontdb: fonts().clone(),
        image_href_resolver: ImageHrefResolver {
            resolve_data: ImageHrefResolver::default_data_resolver(),
            resolve_string: Box::new(|_, _| None),
        },
        ..Options::default()
    }
}

/// Parses `len` bytes at `data`, refusing null, oversized and unparsable input.
unsafe fn parse(data: *const u8, len: usize) -> Result<Tree, i32> {
    if data.is_null() {
        return Err(ZIVLET_SVG_ARGUMENT);
    }
    if len > MAX_INPUT_BYTES {
        return Err(ZIVLET_SVG_SIZE);
    }
    let bytes = std::slice::from_raw_parts(data, len);
    Tree::from_data(bytes, &options()).map_err(|_| ZIVLET_SVG_PARSE)
}

/// Pixel size for `edge * scale`, rounded up, but never past `max_edge` (float error must not add a pixel).
fn pixels(edge: f32, scale: f32, max_edge: u32) -> u32 {
    let exact = f64::from(edge) * f64::from(scale);
    let rounded = (exact - 1e-3).ceil().max(0.0);
    (rounded as u32).min(max_edge)
}

/// The scale that fits the longest edge into `max_edge` (never above `scale`).
fn fitted_scale(tree: &Tree, scale: f32, max_edge: u32) -> f32 {
    let longest = tree.size().width().max(tree.size().height());
    if longest * scale > max_edge as f32 {
        max_edge as f32 / longest
    } else {
        scale
    }
}

/// The longest edge drawn for `max_edge`: the uncapped size, lowered until the filter work fits the budget.
fn planned_edge(tree: &Tree, scale: f32, max_edge: u32) -> Result<u32, i32> {
    let size = tree.size();
    let s = fitted_scale(tree, scale, max_edge);
    let natural = pixels(size.width(), s, max_edge).max(pixels(size.height(), s, max_edge));
    if natural == 0 {
        return Err(ZIVLET_SVG_SIZE);
    }
    limits::fitting_edge(tree, natural, |edge| fitted_scale(tree, scale, edge)).ok_or(ZIVLET_SVG_LIMIT)
}

fn checked(tree: &Tree) -> Result<limits::Survey, i32> {
    limits::survey(tree).map_err(|_| ZIVLET_SVG_LIMIT)
}

/// Runs `body`, turning a panic into `ZIVLET_SVG_PANIC`.
fn guarded(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(ZIVLET_SVG_PANIC)
}

/// Renders `len` bytes of SVG at `scale`, with the longest edge capped at `max_edge` pixels, or lower when the
/// document's filters would cost more than the budget (pass the `edge` from `zivlet_svg_probe` to know the size).
///
/// # Safety
/// `data` must point to `len` readable bytes and `out` to a writable `ZivletSvgImage`.
#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_render(
    data: *const u8,
    len: usize,
    scale: f32,
    max_edge: u32,
    out: *mut ZivletSvgImage,
) -> i32 {
    if out.is_null() || !scale.is_finite() || scale <= 0.0 || max_edge == 0 {
        return ZIVLET_SVG_ARGUMENT;
    }
    guarded(|| {
        let tree = match parse(data, len) {
            Ok(tree) => tree,
            Err(code) => return code,
        };
        if let Err(code) = checked(&tree) {
            return code;
        }
        let edge = match planned_edge(&tree, scale, max_edge) {
            Ok(edge) => edge,
            Err(code) => return code,
        };
        let s = fitted_scale(&tree, scale, edge);
        let size = tree.size();
        let (w, h) = (pixels(size.width(), s, edge), pixels(size.height(), s, edge));
        if w == 0 || h == 0 {
            return ZIVLET_SVG_SIZE;
        }
        let Some(mut pixmap) = Pixmap::new(w, h) else { return ZIVLET_SVG_ALLOC };
        resvg::render(&tree, Transform::from_scale(s, s), &mut pixmap.as_mut());
        let mut buffer = pixmap.take().into_boxed_slice();
        let rgba = buffer.as_mut_ptr();
        std::mem::forget(buffer);
        *out = ZivletSvgImage { width: w, height: h, rgba };
        ZIVLET_SVG_OK
    })
}

/// Writes the document's intrinsic size in CSS pixels without rendering it.
///
/// # Safety
/// `data` must point to `len` readable bytes; `width` and `height` must be writable.
#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_size(data: *const u8, len: usize, width: *mut f32, height: *mut f32) -> i32 {
    if width.is_null() || height.is_null() {
        return ZIVLET_SVG_ARGUMENT;
    }
    guarded(|| match parse(data, len) {
        Ok(tree) => {
            *width = tree.size().width();
            *height = tree.size().height();
            ZIVLET_SVG_OK
        }
        Err(code) => code,
    })
}

/// Writes the intrinsic size, the longest edge `zivlet_svg_render` will draw for `scale` and `max_edge`, and the
/// largest embedded image, without rendering. Refuses (`ZIVLET_SVG_LIMIT`) what `zivlet_svg_render` would refuse.
///
/// # Safety
/// `data` must point to `len` readable bytes; `out` must be writable.
#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_probe(
    data: *const u8,
    len: usize,
    scale: f32,
    max_edge: u32,
    out: *mut ZivletSvgInfo,
) -> i32 {
    if out.is_null() || !scale.is_finite() || scale <= 0.0 || max_edge == 0 {
        return ZIVLET_SVG_ARGUMENT;
    }
    guarded(|| {
        let tree = match parse(data, len) {
            Ok(tree) => tree,
            Err(code) => return code,
        };
        let survey = match checked(&tree) {
            Ok(survey) => survey,
            Err(code) => return code,
        };
        match planned_edge(&tree, scale, max_edge) {
            Ok(edge) => {
                *out = ZivletSvgInfo {
                    width: tree.size().width(),
                    height: tree.size().height(),
                    edge,
                    image_pixels: survey.largest_image,
                };
                ZIVLET_SVG_OK
            }
            Err(code) => code,
        }
    })
}

/// Releases the pixels of an image returned by `zivlet_svg_render` and sets `rgba` to null. Null is ignored.
///
/// # Safety
/// `image` must be null or come from `zivlet_svg_render` and not have been freed.
#[no_mangle]
pub unsafe extern "C" fn zivlet_svg_free(image: *mut ZivletSvgImage) {
    if image.is_null() || (*image).rgba.is_null() {
        return;
    }
    let count = ((*image).width as usize) * ((*image).height as usize) * 4;
    drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut((*image).rgba, count)));
    (*image).rgba = std::ptr::null_mut();
}

#[cfg(test)]
mod tests {
    #[test]
    fn a_panic_fails_only_the_call() {
        assert_eq!(super::guarded(|| panic!("a decoder bug")), super::ZIVLET_SVG_PANIC);
        assert_eq!(super::guarded(|| super::ZIVLET_SVG_OK), super::ZIVLET_SVG_OK);
    }
}
