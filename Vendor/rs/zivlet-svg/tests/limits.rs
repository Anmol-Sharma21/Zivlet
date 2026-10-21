//! Bounded work: costly filters lower the edge or are refused, embedded images are capped by their headers, and
//! `zivlet_svg_probe` says what `zivlet_svg_render` will do.
use resvg::usvg::{Options, Tree};
use zivlet_svg::limits::{filter_work, MIN_EDGE, WORK_BUDGET_NS};
use zivlet_svg::{
    zivlet_svg_free, zivlet_svg_probe, zivlet_svg_render, ZivletSvgImage, ZivletSvgInfo, ZIVLET_SVG_ARGUMENT,
    ZIVLET_SVG_LIMIT, ZIVLET_SVG_OK,
};

/// A PNG header claiming 10000 x 10000 (100 MP) and one claiming 2000 x 2000; imagesize reads only the header.
const PNG_100_MP: &str = "iVBORw0KGgoAAAANSUhEUgAAJxAAACcQCAYAAAC6TmIn";
const PNG_4_MP: &str = "iVBORw0KGgoAAAANSUhEUgAAB9AAAAfQCAYAAACaOMR5";

fn probe(svg: &str) -> (i32, ZivletSvgInfo) {
    let mut info = ZivletSvgInfo { width: 0.0, height: 0.0, edge: 0, image_pixels: 0 };
    let rc = unsafe { zivlet_svg_probe(svg.as_ptr(), svg.len(), 2.0, 8192, &mut info) };
    (rc, info)
}

/// A 4096 x 4096 document whose `body` fills it.
fn doc(defs: &str, body: &str) -> String {
    format!(r#"<svg xmlns="http://www.w3.org/2000/svg" width="4096" height="4096"><defs>{defs}</defs>{body}</svg>"#)
}

fn filtered(filter: &str) -> String {
    doc(&format!(r#"<filter id="f">{filter}</filter>"#), r#"<rect width="4096" height="4096" filter="url(#f)"/>"#)
}

/// Estimated work of `svg` rendered with its longest edge at `edge`.
fn work_at(svg: &str, edge: u32) -> f64 {
    let tree = Tree::from_data(svg.as_bytes(), &Options::default()).unwrap();
    let s = edge as f32 / tree.size().width().max(tree.size().height());
    let canvas = f64::from(tree.size().width() * s).ceil() * f64::from(tree.size().height() * s).ceil();
    filter_work(&tree, s, canvas)
}

#[test]
fn a_plain_document_keeps_its_full_size() {
    let (rc, info) = probe(r#"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"/>"#);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!((info.width, info.height, info.edge, info.image_pixels), (120.0, 80.0, 240, 0));
    let (rc, info) = probe(&doc("", r#"<rect width="4096" height="4096"/>"#));
    assert_eq!((rc, info.edge), (ZIVLET_SVG_OK, 8192));
}

/// One full-canvas blur at 8192 x 8192 took about 7 s; twenty take far longer. The edge comes down until the
/// estimate fits the budget, and render draws exactly that size.
#[test]
fn a_costly_filter_lowers_the_edge_and_render_agrees() {
    let svg = filtered(&r#"<feGaussianBlur stdDeviation="5"/>"#.repeat(20));
    let (rc, info) = probe(&svg);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert!(info.edge < 8192 && info.edge >= MIN_EDGE, "edge {}", info.edge);
    assert!(work_at(&svg, info.edge) <= WORK_BUDGET_NS);
    assert!(work_at(&svg, info.edge + 1) > WORK_BUDGET_NS);
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    assert_eq!(unsafe { zivlet_svg_render(svg.as_ptr(), svg.len(), 2.0, info.edge, &mut img) }, ZIVLET_SVG_OK);
    assert_eq!((img.width, img.height), (info.edge, info.edge));
    unsafe { zivlet_svg_free(&mut img) };
}

/// The review's hostile documents: each is refused or lowered to an edge whose estimate fits the budget.
#[test]
fn hostile_filters_are_bounded() {
    let many_blurs: String = (0..200).map(|_| r#"<rect width="4096" height="4096" filter="url(#f)"/>"#).collect();
    let cases = [
        filtered(r#"<feGaussianBlur stdDeviation="5000"/>"#),
        filtered(r#"<feTurbulence baseFrequency="0.01" numOctaves="10"/>"#),
        filtered(r#"<feMorphology radius="2000"/>"#),
        doc(r#"<filter id="f"><feGaussianBlur stdDeviation="5"/></filter>"#, &many_blurs),
    ];
    for svg in &cases {
        let (rc, info) = probe(svg);
        assert!(rc == ZIVLET_SVG_LIMIT || (rc == ZIVLET_SVG_OK && work_at(svg, info.edge) <= WORK_BUDGET_NS));
    }
    assert_eq!(probe(&cases[2]).0, ZIVLET_SVG_LIMIT, "a 2000-unit morphology is refused outright");
}

#[test]
fn render_refuses_what_probe_refuses() {
    let svg = filtered(r#"<feMorphology radius="2000"/>"#);
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    assert_eq!(unsafe { zivlet_svg_render(svg.as_ptr(), svg.len(), 2.0, 8192, &mut img) }, ZIVLET_SVG_LIMIT);
    assert!(img.rgba.is_null());
}

fn with_images(hrefs: &[&str]) -> String {
    let images: String = hrefs
        .iter()
        .map(|b64| format!(r#"<image href="data:image/png;base64,{b64}" width="10" height="10"/>"#))
        .collect();
    format!(r#"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">{images}</svg>"#)
}

/// resvg decodes embedded images with no limits of Zivlet's; their headers are checked first.
#[test]
fn embedded_images_are_capped_by_their_headers() {
    let (rc, info) = probe(&with_images(&[PNG_4_MP]));
    assert_eq!((rc, info.image_pixels), (ZIVLET_SVG_OK, 4_000_000));
    assert_eq!(probe(&with_images(&[PNG_100_MP])).0, ZIVLET_SVG_LIMIT, "one image over 50 MP");
    assert_eq!(probe(&with_images(&[PNG_4_MP; 65])).0, ZIVLET_SVG_LIMIT, "more than 64 images");
    assert_eq!(probe(&with_images(&[PNG_4_MP; 60])).0, ZIVLET_SVG_LIMIT, "240 MP in total");
    let svg = with_images(&[PNG_100_MP]);
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    assert_eq!(unsafe { zivlet_svg_render(svg.as_ptr(), svg.len(), 2.0, 8192, &mut img) }, ZIVLET_SVG_LIMIT);
}

#[test]
fn probe_refuses_bad_arguments() {
    let svg = "<svg/>";
    let mut info = ZivletSvgInfo { width: 0.0, height: 0.0, edge: 0, image_pixels: 0 };
    assert_eq!(unsafe { zivlet_svg_probe(svg.as_ptr(), svg.len(), 0.0, 8192, &mut info) }, ZIVLET_SVG_ARGUMENT);
    assert_eq!(unsafe { zivlet_svg_probe(svg.as_ptr(), svg.len(), 2.0, 0, &mut info) }, ZIVLET_SVG_ARGUMENT);
    assert_eq!(
        unsafe { zivlet_svg_probe(svg.as_ptr(), svg.len(), 2.0, 64, std::ptr::null_mut()) },
        ZIVLET_SVG_ARGUMENT
    );
}
