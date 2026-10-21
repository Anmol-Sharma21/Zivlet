/// Every format Zivlet knows: 45 inputs + `html` (output only). Order = 02 §7.1.
public enum FormatID: String, CaseIterable, Codable, Sendable {
    case jpg, png, webp, heic, tiff, avif, bmp, svg, pdf
    case mp3, m4a, wav, flac, ogg, opus, aiff, wma
    case mp4, mov, mkv, webm, avi, wmv, gif
    case srt, vtt
    case docx, pages, md, rtf, rtfd, textClipping, txt, html, epub
    case pptx, ppt, xlsx, xls, ods, csv, tsv
    case zip, tar, gz, rar
}

/// Mixing family for multi-file rules (03a §2.6): GIF mixes as video, PDF and slides as document.
public enum FormatFamily: String, CaseIterable, Codable, Sendable {
    case image, audio, video, document, spreadsheet, subtitle, archive
}

/// Pair-count category (03a §3.3). The category of a pair is its source's category.
public enum FormatCategory: String, CaseIterable, Codable, Sendable {
    case raster, svg, audio, video, gif, pdf, document, slides, spreadsheet, subtitle, archive
}

public enum FormatRole: String, Codable, Sendable {
    case inputOnly, outputOnly, inputAndOutput
}
