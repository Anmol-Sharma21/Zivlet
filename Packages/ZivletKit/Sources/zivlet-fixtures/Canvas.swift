import CoreGraphics
import Foundation

/// Pixel sizes per fixture set: `small` keeps every image tiny for PR runs, `full` adds a 12 MP photo for the bench.
struct FixtureSet: Sendable {
    let name: String
    let still: (width: Int, height: Int)
    let photo: (width: Int, height: Int)
    let animation: (width: Int, height: Int)

    static let small = FixtureSet(name: "small", still: (64, 48), photo: (64, 48), animation: (32, 24))
    static let full = FixtureSet(name: "full", still: (1024, 768), photo: (4032, 3024), animation: (256, 192))

    static func named(_ name: String) -> FixtureSet? {
        [small, full].first { $0.name == name }
    }
}

/// What a fixture image is drawn with. Values only; drawing is in `Canvas.draw`.
struct Paint: Sendable {
    let width: Int
    let height: Int
    let space: CGColorSpace
    let bits: Int
    /// The left half is fully transparent.
    let halfTransparent: Bool
    /// Shifts the quadrant colours, so frames and pages differ.
    let phase: Int

    init(
        _ size: (width: Int, height: Int), space: CGColorSpace, bits: Int = 8, halfTransparent: Bool = false,
        phase: Int = 0
    ) {
        self.width = size.width
        self.height = size.height
        self.space = space
        self.bits = bits
        self.halfTransparent = halfTransparent
        self.phase = phase
    }
}

enum FixtureError: Error, CustomStringConvertible {
    case usage(String)
    case drawing(String)
    case writing(String)

    var description: String {
        switch self {
        case .usage(let text): "usage: \(text)"
        case .drawing(let name): "could not draw \(name)"
        case .writing(let name): "could not write \(name)"
        }
    }
}

/// Draws the fixture picture: four quadrants of distinct colours (so a wrong orientation shows) and a diagonal band.
enum Canvas {
    static let quadrants: [[CGFloat]] = [[0.9, 0.1, 0.1], [0.1, 0.7, 0.2], [0.1, 0.2, 0.9], [0.95, 0.85, 0.1]]
    static let cmykQuadrants: [[CGFloat]] = [
        [0, 0.9, 0.9, 0], [0.9, 0, 0.9, 0], [0.9, 0.8, 0, 0], [0, 0.1, 0.9, 0],
    ]

    static func draw(_ paint: Paint) throws(FixtureError) -> CGImage {
        let isCMYK = paint.space.model == .cmyk
        let alphaInfo: CGImageAlphaInfo = isCMYK ? .none : (paint.halfTransparent ? .premultipliedLast : .noneSkipLast)
        let order = paint.bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0
        guard
            let context = CGContext(
                data: nil, width: paint.width, height: paint.height, bitsPerComponent: paint.bits, bytesPerRow: 0,
                space: paint.space, bitmapInfo: alphaInfo.rawValue | order)
        else { throw .drawing("a \(paint.width) × \(paint.height) canvas") }
        try fillQuadrants(context, paint, cmyk: isCMYK)
        if paint.halfTransparent {
            context.clear(CGRect(x: 0, y: 0, width: paint.width / 2, height: paint.height))
        }
        guard let image = context.makeImage() else { throw .drawing("the canvas image") }
        return image
    }

    private static func fillQuadrants(_ context: CGContext, _ paint: Paint, cmyk: Bool) throws(FixtureError) {
        let halfW = CGFloat(paint.width) / 2
        let halfH = CGFloat(paint.height) / 2
        // Core Graphics has its origin bottom-left: index 0 is the top-left quadrant.
        let origins = [CGPoint(x: 0, y: halfH), CGPoint(x: halfW, y: halfH), .zero, CGPoint(x: halfW, y: 0)]
        let colours = cmyk ? cmykQuadrants : quadrants
        for (index, origin) in origins.enumerated() {
            let components = colours[(index + paint.phase) % colours.count] + [1]
            guard let colour = CGColor(colorSpace: paint.space, components: components) else {
                throw .drawing("a quadrant colour")
            }
            context.setFillColor(colour)
            context.fill(CGRect(origin: origin, size: CGSize(width: halfW, height: halfH)))
        }
        guard let white = CGColor(colorSpace: paint.space, components: cmyk ? [0, 0, 0, 0, 1] : [1, 1, 1, 1]) else {
            throw .drawing("the band colour")
        }
        context.setStrokeColor(white)
        context.setLineWidth(max(1, CGFloat(min(paint.width, paint.height)) / 16))
        context.strokeLineSegments(between: [.zero, CGPoint(x: paint.width, y: paint.height)])
    }
}
