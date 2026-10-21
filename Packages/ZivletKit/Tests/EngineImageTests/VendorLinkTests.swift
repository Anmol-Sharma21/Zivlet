import CWebP
import CZivletSVG
import Testing

@Suite("Vendored libraries link and answer (A9)")
struct VendorLinkTests {
    @Test func libwebpIs160() {
        #expect(WebPGetEncoderVersion() == 0x01_06_00)
        #expect(WebPGetMuxVersion() == 0x01_06_00)
    }

    @Test func zivletSVGRefusesGarbage() {
        var image = ZivletSvgImage(width: 0, height: 0, rgba: nil)
        let bytes = Array("not svg".utf8)
        #expect(zivlet_svg_render(bytes, bytes.count, 2, 8192, &image) == Int32(ZIVLET_SVG_PARSE))
    }

    @Test func zivletSVGRendersAndFrees() {
        var image = ZivletSvgImage(width: 0, height: 0, rgba: nil)
        let bytes = Array(#"<svg xmlns="http://www.w3.org/2000/svg" width="12" height="8"/>"#.utf8)
        #expect(zivlet_svg_render(bytes, bytes.count, 2, 8192, &image) == Int32(ZIVLET_SVG_OK))
        #expect(image.width == 24 && image.height == 16)
        zivlet_svg_free(&image)
        #expect(image.rgba == nil)
    }
}
