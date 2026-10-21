//! What a document may cost to render (the review of M4): resvg's filters are single, uncancellable calls whose time
//! grows with the filtered area, so a few hundred bytes of SVG could keep a core busy for minutes. Embedded raster
//! images are decoded at render time by resvg's decoders, with no limits of Zivlet's.
//!
//! The work estimate is in nanoseconds on an M2 Pro (release build, measured at 8192 x 8192): per filtered pixel,
//! a plain primitive costs about 30 ns, a Gaussian blur about 110 ns whatever its deviation (box blur; 480 ns for a
//! deviation under 2 pixels, which resvg blurs with an IIR filter), turbulence
//! 60 ns plus 40 ns per octave, morphology about 2.5 ns per kernel cell, a convolution about 10 ns per matrix cell,
//! lighting about 40 ns. Each primitive's region is its subregion in pixels, capped at the canvas.
use resvg::usvg::{filter::Kind, Group, ImageKind, Node, Tree};

/// About three seconds of filter work; documents over it are rendered smaller, down to `MIN_EDGE`.
pub const WORK_BUDGET_NS: f64 = 3.0e9;
/// The smallest longest edge a costly document is lowered to before it is refused.
pub const MIN_EDGE: u32 = 256;
/// Embedded raster images: at most this many, each decoded to at most this many pixels, and this many in total.
pub const MAX_IMAGES: usize = 64;
pub const MAX_IMAGE_PIXELS: u64 = 50_000_000;
pub const MAX_IMAGE_TOTAL_PIXELS: u64 = 200_000_000;
/// Morphology kernels larger than this (in pixels per side) are counted at this size; resvg's own cap is lower.
const MAX_KERNEL_SIDE: f64 = 4096.0;

/// What the renderer found in a document before rendering it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Survey {
    /// The largest embedded raster image, in decoded pixels (0 without one).
    pub largest_image: u64,
}

/// Why a document is refused before rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refusal {
    /// Too many embedded images, one too large, or too many pixels in total.
    Images,
    /// Its filters cost more than the budget even at `MIN_EDGE`.
    Filters,
}

/// Checks the embedded raster images (header sizes, as the decoders will allocate them).
pub fn survey(tree: &Tree) -> Result<Survey, Refusal> {
    let mut sizes: Vec<u64> = Vec::new();
    visit(tree.root(), &mut |node| {
        if let Node::Image(image) = node {
            if let Some(pixels) = raster_pixels(image.kind()) {
                sizes.push(pixels);
            }
        }
    });
    let total: u64 = sizes.iter().sum();
    let largest = sizes.iter().copied().max().unwrap_or(0);
    if sizes.len() > MAX_IMAGES || largest > MAX_IMAGE_PIXELS || total > MAX_IMAGE_TOTAL_PIXELS {
        return Err(Refusal::Images);
    }
    Ok(Survey { largest_image: largest })
}

/// Decoded size of a raster image from its header; an unreadable header counts as too large.
fn raster_pixels(kind: &ImageKind) -> Option<u64> {
    match kind {
        ImageKind::JPEG(data) | ImageKind::PNG(data) | ImageKind::GIF(data) | ImageKind::WEBP(data) => {
            Some(match imagesize::blob_size(data) {
                Ok(size) => (size.width as u64).saturating_mul(size.height as u64),
                Err(_) => u64::MAX,
            })
        }
        ImageKind::SVG(_) => None, // its own nodes are visited
    }
}

/// Estimated filter work in nanoseconds for a render at `scale` onto a `canvas_pixels` canvas.
pub fn filter_work(tree: &Tree, scale: f32, canvas_pixels: f64) -> f64 {
    let mut work = 0.0;
    visit(tree.root(), &mut |node| {
        if let Node::Group(group) = node {
            work += group_work(group, f64::from(scale), canvas_pixels);
        }
    });
    work
}

fn group_work(group: &Group, scale: f64, canvas_pixels: f64) -> f64 {
    let (sx, sy) = group.abs_transform().get_scale();
    let (px, py) = (f64::from(sx) * scale, f64::from(sy) * scale);
    let mut work = 0.0;
    for filter in group.filters() {
        for primitive in filter.primitives() {
            let rect = primitive.rect();
            let area = f64::from(rect.width()) * px * f64::from(rect.height()) * py;
            work += area.min(canvas_pixels) * per_pixel_ns(primitive.kind(), px, py);
        }
    }
    work
}

fn per_pixel_ns(kind: &Kind, px: f64, py: f64) -> f64 {
    match kind {
        Kind::GaussianBlur(fe) => blur_ns(fe.std_dev_x().get(), fe.std_dev_y().get(), px, py),
        Kind::DropShadow(fe) => 60.0 + blur_ns(fe.std_dev_x().get(), fe.std_dev_y().get(), px, py),
        Kind::Turbulence(fe) => 60.0 + 40.0 * f64::from(fe.num_octaves()),
        Kind::Morphology(fe) => {
            let side = |r: f32, p: f64| (2.0 * f64::from(r) * p + 1.0).min(MAX_KERNEL_SIDE);
            (2.5 * side(fe.radius_x().get(), px) * side(fe.radius_y().get(), py)).max(30.0)
        }
        Kind::ConvolveMatrix(fe) => (10.0 * f64::from(fe.matrix().columns() * fe.matrix().rows())).max(30.0),
        Kind::DiffuseLighting(_) | Kind::SpecularLighting(_) | Kind::DisplacementMap(_) => 40.0,
        _ => 30.0,
    }
}

/// resvg blurs with a box blur once a deviation reaches 2 pixels and with an IIR filter below that, which costs
/// about four times as much per pixel.
fn blur_ns(std_x: f32, std_y: f32, px: f64, py: f64) -> f64 {
    const BOX_THRESHOLD: f64 = 2.0;
    if f64::from(std_x) * px >= BOX_THRESHOLD || f64::from(std_y) * py >= BOX_THRESHOLD {
        110.0
    } else {
        480.0
    }
}

/// Every node of `group`, its descendants, and the groups only reachable through a node (clip paths, masks,
/// patterns, feImage contents, nested SVG images).
fn visit(group: &Group, f: &mut dyn FnMut(&Node)) {
    for node in group.children() {
        f(node);
        if let Node::Group(child) = node {
            visit(child, f);
        }
        node.subroots(|root| visit(root, f));
    }
}

/// The longest edge, at most `cap`, whose filter work fits the budget; `None` when not even `MIN_EDGE` does.
/// `scale_for(edge)` is the render scale that gives that longest edge.
pub fn fitting_edge(tree: &Tree, cap: u32, scale_for: impl Fn(u32) -> f32) -> Option<u32> {
    let size = tree.size();
    let work_at = |edge: u32| {
        let s = scale_for(edge);
        let canvas = f64::from(size.width() * s).ceil() * f64::from(size.height() * s).ceil();
        filter_work(tree, s, canvas)
    };
    if work_at(cap) <= WORK_BUDGET_NS {
        return Some(cap);
    }
    let floor = MIN_EDGE.min(cap);
    if work_at(floor) > WORK_BUDGET_NS {
        return None;
    }
    let (mut fits, mut over) = (floor, cap);
    while over - fits > 1 {
        let mid = fits + (over - fits) / 2;
        if work_at(mid) <= WORK_BUDGET_NS {
            fits = mid;
        } else {
            over = mid;
        }
    }
    Some(fits)
}
