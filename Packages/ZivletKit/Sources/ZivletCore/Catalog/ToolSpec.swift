/// The 28 tools, grouped by domain. Zivlet's own identifiers; the wheel order is data (`ToolCatalog.specTable`).
public enum ToolID: String, CaseIterable, Codable, Sendable {
    case shrink, stripMetadata
    case imageAdjust, imageMarkup, imageBackdrop, imageCrop, imageCollage, imageRedact
    case pdfSplit, pdfArrange, pdfFromImages, pdfCombine
    case archiveUnpack
    case audioNormalize, audioWaveform, audioTrim, audioChannelMix, audioBleep
    case videoMute, videoTrim, videoCrop, videoSpeed, videoJoin, videoFrameGrab, videoClips, videoRedact
    case qrScan, copyText
}

/// Whether a tool takes a wheel slot by default or waits in the extras for custom wheels, intents and the CLI
/// (P2-100, 17 §8.1).
public enum ToolVisibility: String, Codable, Sendable { case defaultVisible, extra }

public enum ToolPresentation: String, Codable, Sendable { case instant, editor }

/// `.multiAllowed` = 1…n files; `.multiOnly` = combining tools that need ≥ 2.
public enum ToolCardinality: String, Codable, Sendable { case single, multiAllowed, multiOnly }

public struct ToolSpec: Sendable, Hashable, Codable {
    public let id: ToolID
    public let wheelLabel: String
    public let symbolName: String  // chosen by Zivlet
    public let presentation: ToolPresentation
    public let cardinality: ToolCardinality
    public let outputSuffix: String?  // default suffix; OutputNamer applies variants (03a §4.4)
    /// The formats a combining tool takes when a selection mixes families; nil for every other tool (P2-100).
    public let accepts: Set<FormatID>?
}
