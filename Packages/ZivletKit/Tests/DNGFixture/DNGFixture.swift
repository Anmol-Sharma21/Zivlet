import Foundation

/// A raw DNG made from our own bytes, for tests and the fixture set: a 12-bit Bayer mosaic, uncompressed, left half
/// red and right half blue. ImageIO refuses smaller mosaics (256 × 192 failed, 320 × 240 opens), so this is the
/// smallest size that keeps a photo's decode path.
public enum DNGFixture {
    public static let width = 320
    public static let height = 240
    private static let white = 4095
    private static let matrix: [Int32] = [15069, -8881, -1335, -5356, 15421, 1474, -192, 953, 7604]

    private struct Tag {
        let id: UInt16
        let type: UInt16
        let count: Int
        let value: Data
    }

    /// Big-endian TIFF with one directory: the tags, the values too long for an entry, then the pixels.
    public static func bytes() -> Data {
        let pixels = mosaic()
        let tags = tags(byteCount: pixels.count)
        let directorySize = 2 + tags.count * 12 + 4
        var values = Data()
        var offsets: [UInt16: Int] = [:]
        for tag in tags where tag.value.count > 4 {
            offsets[tag.id] = 8 + directorySize + values.count
            values.append(tag.value)
        }
        let pixelStart = 8 + directorySize + values.count
        var file = Data("MM".utf8) + big(UInt16(42)) + big(UInt32(8)) + big(UInt16(tags.count))
        for tag in tags {
            file += big(tag.id) + big(tag.type) + big(UInt32(tag.count))
            if tag.id == stripOffsets {
                file += big(UInt32(pixelStart))
            } else if let offset = offsets[tag.id] {
                file += big(UInt32(offset))
            } else {
                file += tag.value + Data(count: 4 - tag.value.count)
            }
        }
        return file + big(UInt32(0)) + values + pixels
    }

    /// RGGB: red and blue carry the picture and green stays dark, so the two halves stay far apart after decoding.
    private static func mosaic() -> Data {
        var pixels = Data(capacity: width * height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let isRed = x.isMultiple(of: 2) && y.isMultiple(of: 2)
                let isBlue = !x.isMultiple(of: 2) && !y.isMultiple(of: 2)
                let lit = x < width / 2 ? isRed : isBlue
                pixels += big(UInt16(lit ? white : 0))
            }
        }
        return pixels
    }

    private static let stripOffsets: UInt16 = 273

    private static func tags(byteCount: Int) -> [Tag] {
        let colourMatrix = matrix.reduce(into: Data()) { $0 += big(UInt32(bitPattern: $1)) + big(UInt32(10000)) }
        let neutral = [UInt32](repeating: 1, count: 6).reduce(into: Data()) { $0 += big($1) }
        return [
            Tag(id: 254, type: 4, count: 1, value: big(UInt32(0))),
            Tag(id: 256, type: 4, count: 1, value: big(UInt32(width))),
            Tag(id: 257, type: 4, count: 1, value: big(UInt32(height))),
            Tag(id: 258, type: 3, count: 1, value: big(UInt16(16))),
            Tag(id: 259, type: 3, count: 1, value: big(UInt16(1))),
            Tag(id: 262, type: 3, count: 1, value: big(UInt16(32803))),
            Tag(id: 271, type: 2, count: 7, value: Data("Zivlet\0".utf8)),
            Tag(id: 272, type: 2, count: 8, value: Data("Fixture\0".utf8)),
            Tag(id: stripOffsets, type: 4, count: 1, value: big(UInt32(0))),
            Tag(id: 274, type: 3, count: 1, value: big(UInt16(1))),
            Tag(id: 277, type: 3, count: 1, value: big(UInt16(1))),
            Tag(id: 278, type: 4, count: 1, value: big(UInt32(height))),
            Tag(id: 279, type: 4, count: 1, value: big(UInt32(byteCount))),
            Tag(id: 284, type: 3, count: 1, value: big(UInt16(1))),
            Tag(id: 33421, type: 3, count: 2, value: big(UInt16(2)) + big(UInt16(2))),
            Tag(id: 33422, type: 1, count: 4, value: Data([0, 1, 1, 2])),
            Tag(id: 50706, type: 1, count: 4, value: Data([1, 4, 0, 0])),
            Tag(id: 50707, type: 1, count: 4, value: Data([1, 3, 0, 0])),
            Tag(id: 50708, type: 2, count: 8, value: Data("Fixture\0".utf8)),
            Tag(id: 50714, type: 3, count: 1, value: big(UInt16(0))),
            Tag(id: 50717, type: 3, count: 1, value: big(UInt16(white))),
            Tag(id: 50721, type: 10, count: 9, value: colourMatrix),
            Tag(id: 50728, type: 5, count: 3, value: neutral),
            Tag(id: 50778, type: 3, count: 1, value: big(UInt16(21))),
        ]
    }

    private static func big(_ value: some FixedWidthInteger) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
