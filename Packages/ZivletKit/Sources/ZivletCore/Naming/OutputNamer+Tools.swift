extension OutputNamer {
    /// Options that pick a tool's suffix variant (03a §4.4).
    public struct ToolNaming: Sendable, Equatable {
        public let metadata: MetadataNaming
        public let speed: Double
        public let channels: ChannelNaming
        public let snapshotCount: Int

        public init(
            metadata: MetadataNaming = .removeAll, speed: Double = 2.0, channels: ChannelNaming = .mono,
            snapshotCount: Int = 1
        ) {
            self.metadata = metadata
            self.speed = speed
            self.channels = channels
            self.snapshotCount = snapshotCount
        }
    }

    /// `<base> <suffix>` plus the tool's output extension; nil for tools without an output (Read QR).
    /// Multi-input tools pass the first file as `source`.
    public func tool(
        _ tool: ToolID, source fileName: String, format: FormatID, naming: ToolNaming = ToolNaming()
    ) -> OutputName? {
        guard let suffix = suffix(tool, format: format, naming: naming) else { return nil }
        let ext = outputExtension(tool, format: format, naming: naming)
        return OutputName(stem: "\(baseName(of: fileName)) \(suffix)", validExtension: ext)
    }

    func suffix(_ tool: ToolID, format: FormatID, naming: ToolNaming) -> String? {
        switch tool {
        case .stripMetadata where registry.format(format).family == .image:
            naming.metadata == .edit ? "Metadata Edited" : "Metadata Removed"
        case .videoSpeed:
            "Speed \(naming.speed.description)x"
        case .audioChannelMix:
            naming.channels.rawValue
        case .videoFrameGrab:
            naming.snapshotCount > 1 ? "Snapshots" : "Snapshot"
        default:
            tools.spec(tool).outputSuffix
        }
    }

    /// The output extension; nil means the tool writes a folder.
    func outputExtension(_ tool: ToolID, format: FormatID, naming: ToolNaming) -> String? {
        let sameExtension = registry.format(format).canonicalExtension
        switch tool {
        case .shrink:
            return format == .wav || format == .aiff ? "flac" : sameExtension
        case .videoFrameGrab:
            return naming.snapshotCount > 1 ? nil : "png"
        case .imageMarkup, .imageCollage:
            return "png"
        case .videoClips, .pdfSplit, .archiveUnpack:
            return nil
        case .pdfFromImages, .pdfCombine:
            return "pdf"
        case .videoJoin, .audioWaveform:
            return "mp4"
        case .copyText:
            return "txt"
        default:
            return sameExtension
        }
    }
}
