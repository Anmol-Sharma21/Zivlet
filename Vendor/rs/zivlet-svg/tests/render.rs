//! Behaviour of the C ABI: size, edge cap, refusals, and the data:-only image resolver.
use zivlet_svg::{
    zivlet_svg_free, zivlet_svg_render, zivlet_svg_size, ZivletSvgImage, ZIVLET_SVG_ARGUMENT, ZIVLET_SVG_OK,
    ZIVLET_SVG_PARSE, ZIVLET_SVG_SIZE,
};

fn render(svg: &[u8], scale: f32, max_edge: u32) -> (i32, ZivletSvgImage) {
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    let rc = unsafe { zivlet_svg_render(svg.as_ptr(), svg.len(), scale, max_edge, &mut img) };
    (rc, img)
}

fn pixel(img: &ZivletSvgImage, x: u32, y: u32) -> [u8; 4] {
    let i = ((y * img.width + x) * 4) as usize;
    unsafe { [*img.rgba.add(i), *img.rgba.add(i + 1), *img.rgba.add(i + 2), *img.rgba.add(i + 3)] }
}

#[test]
fn renders_at_twice_the_intrinsic_size() {
    let svg = br##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80"><rect width="120" height="80" fill="#00f"/></svg>"##;
    let (rc, mut img) = render(svg, 2.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!((img.width, img.height), (240, 160));
    assert_eq!(pixel(&img, 120, 80), [0, 0, 255, 255]);
    unsafe { zivlet_svg_free(&mut img) };
    assert!(img.rgba.is_null());
}

#[test]
fn caps_the_longest_edge() {
    let (rc, mut img) =
        render(br#"<svg xmlns="http://www.w3.org/2000/svg" width="100000" height="50000"/>"#, 2.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!((img.width, img.height), (8192, 4096));
    unsafe { zivlet_svg_free(&mut img) };
}

#[test]
fn refuses_non_svg_and_bad_arguments() {
    assert_eq!(render(b"not svg", 2.0, 8192).0, ZIVLET_SVG_PARSE);
    assert_eq!(render(b"<svg/>", 0.0, 8192).0, ZIVLET_SVG_ARGUMENT);
    assert_eq!(render(b"<svg/>", f32::NAN, 8192).0, ZIVLET_SVG_ARGUMENT);
    assert_eq!(render(b"<svg/>", 2.0, 0).0, ZIVLET_SVG_ARGUMENT);
    let mut img = ZivletSvgImage { width: 0, height: 0, rgba: std::ptr::null_mut() };
    assert_eq!(unsafe { zivlet_svg_render(std::ptr::null(), 4, 1.0, 64, &mut img) }, ZIVLET_SVG_ARGUMENT);
    unsafe { zivlet_svg_free(std::ptr::null_mut()) }; // a null image is ignored
}

#[test]
fn refuses_inputs_over_64_mib_before_parsing() {
    let big = vec![b' '; 64 * 1024 * 1024 + 1];
    assert_eq!(render(&big, 1.0, 64).0, ZIVLET_SVG_SIZE);
}

#[test]
fn reports_the_intrinsic_size_without_rendering() {
    let svg = br#"<svg xmlns="http://www.w3.org/2000/svg" width="120.5" height="80"/>"#;
    let (mut w, mut h) = (0f32, 0f32);
    assert_eq!(unsafe { zivlet_svg_size(svg.as_ptr(), svg.len(), &mut w, &mut h) }, ZIVLET_SVG_OK);
    assert_eq!((w, h), (120.5, 80.0));
    assert_eq!(unsafe { zivlet_svg_size(b"nope".as_ptr(), 4, &mut w, &mut h) }, ZIVLET_SVG_PARSE);
    assert_eq!(unsafe { zivlet_svg_size(svg.as_ptr(), svg.len(), std::ptr::null_mut(), &mut h) }, ZIVLET_SVG_ARGUMENT);
}

#[test]
fn loads_only_data_hrefs() {
    let dir = std::env::temp_dir().join(format!("zsvg-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let red_svg = dir.join("red.svg");
    std::fs::write(&red_svg, r##"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="#f00"/></svg>"##).unwrap();
    let b64 = include_str!("red-20.png.b64");
    let svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20"><rect width="40" height="20" fill="#fff"/><image href="{}" width="20" height="20"/><image href="data:image/png;base64,{}" x="20" width="20" height="20"/></svg>"##,
        red_svg.display(),
        b64.trim()
    );
    let (rc, mut img) = render(svg.as_bytes(), 1.0, 8192);
    assert_eq!(rc, ZIVLET_SVG_OK);
    assert_eq!(pixel(&img, 10, 10)[..3], [255, 255, 255]); // file href ignored
    assert!(pixel(&img, 30, 10)[0] > 240 && pixel(&img, 30, 10)[1] < 16); // data href drawn
    unsafe { zivlet_svg_free(&mut img) };
    let _ = std::fs::remove_dir_all(&dir);
}
