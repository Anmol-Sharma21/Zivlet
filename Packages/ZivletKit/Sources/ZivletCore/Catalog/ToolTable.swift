// Tool data (06b Task 4b, 03a §4.4). Symbol names are Zivlet's own choice.
extension ToolCatalog {
    struct ApplicabilityRow: Sendable {
        let formats: Set<FormatID>
        let single: [ToolID]
        let multi: [ToolID]
    }

    static let applicability: [ApplicabilityRow] = [
        .init(
            formats: [.jpg, .png, .webp, .heic, .tiff],
            single: [.shrink, .stripMetadata, .imageAdjust, .imageMarkup, .imageBackdrop, .imageCrop, .imageRedact],
            multi: [.shrink, .stripMetadata, .imageCrop, .pdfFromImages, .imageCollage]),
        .init(formats: [.svg], single: [.qrScan], multi: [.pdfFromImages, .imageCollage, .qrScan]),
        .init(formats: [.avif, .bmp], single: [.qrScan], multi: [.qrScan]),
        .init(
            formats: [.pdf], single: [.shrink, .stripMetadata, .pdfSplit, .pdfArrange, .qrScan],
            multi: [.shrink, .stripMetadata, .pdfSplit, .pdfCombine, .qrScan]),
        .init(
            formats: [.mp3, .m4a, .wav, .flac],
            single: [
                .shrink, .stripMetadata, .audioNormalize, .audioWaveform, .audioTrim, .audioChannelMix,
                .audioBleep,
            ],
            multi: [.shrink, .stripMetadata, .audioNormalize]),
        .init(
            formats: [.mp4, .mov, .mkv],
            single: [
                .shrink, .stripMetadata, .videoMute, .videoTrim, .videoCrop, .videoSpeed,
                .videoFrameGrab, .videoClips, .videoRedact,
            ],
            multi: [.shrink, .stripMetadata, .videoMute, .videoJoin]),
        .init(formats: [.gif], single: [.stripMetadata, .qrScan], multi: [.stripMetadata, .qrScan]),
        .init(formats: [.zip, .tar, .gz, .rar], single: [.archiveUnpack], multi: [.archiveUnpack]),
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
        spec(.qrScan, "READ QR", "qrcode.viewfinder", .instant, .multiAllowed, nil),
    ]

    private static func spec(
        _ id: ToolID, _ label: String, _ symbol: String, _ presentation: ToolPresentation,
        _ cardinality: ToolCardinality, _ suffix: String?
    ) -> ToolSpec {
        ToolSpec(
            id: id, wheelLabel: label, symbolName: symbol, presentation: presentation,
            cardinality: cardinality, outputSuffix: suffix)
    }
}
