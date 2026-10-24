// The lightest linear luminance in a box of a PNG (plan 14 D18): the island's glass is read over a known backdrop
// from a text-free box, and the result decides whether white text at 0.8 still reaches 4.5:1. The image is drawn
// into an sRGB context first, so a screenshot in the display's colour space is read as sRGB, as WCAG assumes.
// Usage: xcrun swift Scripts/png-luminance.swift FILE X Y WIDTH HEIGHT [POINT_WIDTH]
//   The box is in pixels from the top left, or in points when POINT_WIDTH (the image's width in points) is given.
//   Prints the luminance with three decimals; exits 2 on bad arguments (a POINT_WIDTH that is not a positive number,
//   a box not wholly inside the image) and 1 when the file cannot be read.
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func linear(_ value: Double) -> Double {
    value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

let arguments = CommandLine.arguments
let box = arguments.count >= 6 ? arguments[2...5].compactMap { Double($0) } : []
guard arguments.count == 6 || arguments.count == 7, box.count == 4 else {
    fail("usage: png-luminance.swift FILE X Y WIDTH HEIGHT [POINT_WIDTH]", 2)
}
let url = URL(filePath: arguments[1])
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fail("cannot read \(arguments[1])", 1) }

let width = image.width
let height = image.height
let pointWidth = arguments.count == 7 ? Double(arguments[6]) : Double(width)
guard let pointWidth, pointWidth.isFinite, pointWidth > 0 else { fail("POINT_WIDTH must be a positive number", 2) }
let scale = Double(width) / pointWidth
guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fail("cannot make an sRGB context", 1) }
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
guard let data = context.data else { fail("cannot read the pixels", 1) }
let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

let minX = Int((box[0] * scale).rounded(.down))
let minY = Int((box[1] * scale).rounded(.down))
let maxX = Int(((box[0] + box[2]) * scale).rounded(.up))
let maxY = Int(((box[1] + box[3]) * scale).rounded(.up))
// A box partly outside is refused, not clamped: a smaller region could miss the very pixels the gate is about.
guard minX >= 0, minY >= 0, maxX <= width, maxY <= height, minX < maxX, minY < maxY else {
    fail("the box is not wholly inside the \(width) x \(height) image", 2)
}

var lightest = 0.0
for y in minY..<maxY {
    for x in minX..<maxX {
        let offset = (y * width + x) * 4
        let (r, g, b) = (Double(pixels[offset]) / 255, Double(pixels[offset + 1]) / 255, Double(pixels[offset + 2]) / 255)
        lightest = max(lightest, 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b))
    }
}
print(String(format: "%.3f", lightest))
