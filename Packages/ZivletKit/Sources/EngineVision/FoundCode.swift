/// One code Read QR found (P2-51): its payload as text, its symbology by Vision's name ("qr", "code128", …) and the
/// PDF page it was on (from 1; nil for an image).
public struct FoundCode: Codable, Sendable, Equatable, Hashable {
    public let payload: String
    public let symbology: String
    public let page: Int?

    public init(payload: String, symbology: String, page: Int?) {
        self.payload = payload
        self.symbology = symbology
        self.page = page
    }

    /// One page's or image's codes top to bottom; the same payload and symbology twice on it is kept once.
    static func arranged(_ detected: [DetectedCode], page: Int?) -> [FoundCode] {
        var seen = Set<FoundCode>()
        return detected.enumerated()
            .sorted { $0.element.top == $1.element.top ? $0.offset < $1.offset : $0.element.top > $1.element.top }
            .map { FoundCode(payload: $0.element.payload, symbology: $0.element.symbology, page: page) }
            .filter { seen.insert($0).inserted }
    }
}

/// A code as the detector reports it: payload, symbology and how high its top edge sits (0 bottom … 1 top).
public struct DetectedCode: Sendable, Equatable {
    public let payload: String
    public let symbology: String
    public let top: Double

    public init(payload: String, symbology: String, top: Double) {
        self.payload = payload
        self.symbology = symbology
        self.top = top
    }
}
