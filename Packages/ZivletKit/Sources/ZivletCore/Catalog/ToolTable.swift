// Tool data (06b Task 4b, 03a §4.4). Symbol names are Zivlet's own choice.
extension ToolCatalog {
    /// The tools one format family shows for one item and for several, each marked visible or extra (P2-100).
    struct ApplicabilityRow: Sendable {
        struct Entry: Sendable, Hashable {
            let id: ToolID
            let visibility: ToolVisibility

            static func visible(_ id: ToolID) -> Entry { Entry(id: id, visibility: .defaultVisible) }
            static func extra(_ id: ToolID) -> Entry { Entry(id: id, visibility: .extra) }
        }

        let formats: Set<FormatID>
        let single: [Entry]
        let multi: [Entry]

        /// The entries for `count` items: `multi` from two items on.
        func entries(count: Int) -> [Entry] { count >= 2 ? multi : single }
    }

    /// D-M6-17: every current tool is visible by default; a tool moves to `.extra` only when its list would pass 12.
    static let applicability: [ApplicabilityRow] = [
        .init(
            formats: [.jpg, .png, .webp, .heic, .tiff],
            single: .visible(
                .shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .imageRedact),
            multi: .visible(.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage)),
        .init(formats: [.svg], single: .visible(.qrScan), multi: .visible(.pdfFromImages, .imageCollage, .qrScan)),
        .init(formats: [.avif, .bmp], single: .visible(.qrScan), multi: .visible(.qrScan)),
        .init(
            formats: [.pdf], single: .visible(.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .qrScan),
            multi: .visible(.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .qrScan)),
        .init(
            formats: [.mp3, .m4a, .wav, .flac],
            single: .visible(
                .shrink, .stripMetadata, .audioNormalize, .audioWaveform, .audioTrim, .audioChannelMix, .audioBleep),
            multi: .visible(.shrink, .stripMetadata, .audioNormalize)),
        .init(
            formats: [.mp4, .mov, .mkv],
            single: .visible(
                .shrink, .stripMetadata, .videoMute, .videoTrim, .videoCrop, .videoSpeed, .videoFrameGrab,
                .videoClips, .videoRedact),
            multi: .visible(.shrink, .stripMetadata, .videoMute, .videoJoin)),
        .init(formats: [.gif], single: .visible(.stripMetadata, .qrScan), multi: .visible(.stripMetadata, .qrScan)),
        .init(formats: [.zip, .tar, .gz, .rar], single: .visible(.archiveUnpack), multi: .visible(.archiveUnpack)),
    ]

    static let specTable: [ToolSpec] = [
        spec(.shrink, "COMPRESS", "arrow.down.forward.and.arrow.up.backward", .editor, .multiAllowed, "Compressed"),
        spec(.stripMetadata, "METADATA", "tag", .editor, .multiAllowed, "No Metadata"),
        spec(.imageAdjust, "EDIT", "slider.horizontal.3", .editor, .single, "Edited"),
        spec(.imageMarkup, "ANNOTATE", "pencil.tip.crop.circle", .editor, .single, "Annotated"),
        spec(.imageBackdrop, "ADD BG", "square.on.square.dashed", .editor, .single, "With Background"),
        spec(.imageCrop, "CROP", "crop", .editor, .multiAllowed, "Cropped"),
        spec(.audioNormalize, "NORMALIZE", "speaker.wave.2", .editor, .multiAllowed, "Normalized"),
        spec(.videoMute, "MUTE", "speaker.slash", .instant, .multiAllowed, "Muted"),
        spec(.videoTrim, "TRIM", "timeline.selection", .editor, .single, "Trimmed"),
        spec(.pdfSplit, "SPLIT", "doc.on.doc", .instant, .multiAllowed, "Pages"),
        spec(.pdfArrange, "ORGANIZE", "rectangle.grid.2x2", .editor, .single, "Organized"),
        spec(.archiveUnpack, "EXTRACT", "shippingbox", .instant, .multiAllowed, "Extracted"),
        spec(.pdfFromImages, "CREATE PDF", "doc.badge.plus", .instant, .multiOnly, "Images"),
        spec(.pdfCombine, "MERGE PDF", "doc.on.clipboard", .editor, .multiOnly, "Merged"),
        spec(.videoCrop, "CROP", "crop", .editor, .single, "Cropped"),
        spec(.videoSpeed, "SPEED", "gauge.with.dots.needle.67percent", .editor, .single, "Speed"),
        spec(.videoJoin, "JOIN", "film.stack", .editor, .multiOnly, "Joined"),
        spec(.videoFrameGrab, "SNAPSHOT", "camera.viewfinder", .editor, .single, "Snapshot"),
        spec(.videoClips, "SPLIT", "scissors", .editor, .single, "Clips"),
        spec(.audioWaveform, "VISUALIZE", "waveform.path", .editor, .single, "Visualizer"),
        spec(.audioTrim, "TRIM", "timeline.selection", .editor, .single, "Trimmed"),
        spec(.audioChannelMix, "CHANNELS", "speaker.wave.2.circle", .editor, .single, "Mono"),
        spec(.imageCollage, "COLLAGE", "square.grid.3x2", .editor, .multiOnly, "Collage"),
        spec(.imageRedact, "REDACT", "eye.slash", .editor, .single, "Redacted"),
        spec(.videoRedact, "REDACT", "eye.slash", .editor, .single, "Redacted"),
        spec(.audioBleep, "BLEEP", "waveform.badge.minus", .editor, .single, "Bleeped"),
        spec(.qrScan, "READ QR", "qrcode.viewfinder", .instant, .multiAllowed, nil, accepts: qrScanAccepts),
    ]

    private static func spec(
        _ id: ToolID, _ label: String, _ symbol: String, _ presentation: ToolPresentation,
        _ cardinality: ToolCardinality, _ suffix: String?, accepts: Set<FormatID>? = nil
    ) -> ToolSpec {
        ToolSpec(
            id: id, wheelLabel: label, symbolName: symbol, presentation: presentation,
            cardinality: cardinality, outputSuffix: suffix, accepts: accepts)
    }

    /// READ QR combines every image format, GIF and PDF.
    private static let qrScanAccepts: Set<FormatID> = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .svg, .gif, .pdf]
}

extension [ToolCatalog.ApplicabilityRow.Entry] {
    /// Keeps the table readable: every listed tool, in order, visible by default.
    static func visible(_ ids: ToolID...) -> Self { ids.map(Element.visible) }
}
