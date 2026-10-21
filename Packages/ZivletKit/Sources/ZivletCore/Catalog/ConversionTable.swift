// The 275 conversion pairs (03a §3.3, 06b Task 4a). Row order = petal order.
extension ConversionCatalog {
    static let table: [ConversionRow] = raster + audioVideo + documents + dataFormats

    private static let raster: [ConversionRow] = [
        .init(.jpg, [.png, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
        .init(.png, [.jpg, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
        .init(.webp, [.jpg, .png, .heic, .tiff, .avif, .bmp, .pdf]),
        .init(.heic, [.jpg, .png, .webp, .tiff, .avif, .bmp, .pdf]),
        .init(.tiff, [.jpg, .png, .webp, .heic, .avif, .bmp, .pdf]),
        .init(.avif, [.jpg, .png, .webp, .heic, .tiff, .bmp, .pdf]),
        .init(.bmp, [.jpg, .png, .webp, .heic, .tiff, .avif, .pdf]),
        .init(.svg, [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .pdf]),
    ]
    private static let audioVideo: [ConversionRow] = [
        .init(.mp3, [.m4a, .wav, .flac, .ogg, .opus, .aiff, .wma]),
        .init(.m4a, [.mp3, .wav, .flac, .ogg, .opus, .aiff, .wma]),
        .init(.wav, [.mp3, .m4a, .flac, .ogg, .opus, .aiff, .wma]),
        .init(.flac, [.mp3, .m4a, .wav, .ogg, .opus, .aiff, .wma]),
        .init(.ogg, [.mp3, .m4a, .wav, .flac, .opus, .aiff, .wma]),
        .init(.opus, [.mp3, .m4a, .wav, .flac, .ogg, .aiff, .wma]),
        .init(.aiff, [.mp3, .m4a, .wav, .flac, .ogg, .opus, .wma]),
        .init(.wma, [.mp3, .m4a, .wav, .flac, .ogg, .opus, .aiff]),
        .init(.mp4, [.mov, .mkv, .webm, .avi, .wmv, .gif, .mp3]),
        .init(.mov, [.mp4, .mkv, .webm, .avi, .wmv, .gif, .mp3]),
        .init(.mkv, [.mp4, .mov, .webm, .avi, .wmv, .gif, .mp3]),
        .init(.webm, [.mp4, .mov, .mkv, .avi, .wmv, .gif, .mp3]),
        .init(.avi, [.mp4, .mov, .mkv, .webm, .wmv, .gif, .mp3]),
        .init(.wmv, [.mp4, .mov, .mkv, .webm, .avi, .gif, .mp3]),
        .init(.gif, [.mp4, .mov, .mkv, .webm, .avi, .wmv]),
    ]
    private static let documents: [ConversionRow] = [
        .init(.pdf, [.docx, .pages, .pptx, .xlsx, .jpg, .png, .epub, .txt, .md]),
        .init(.docx, [.pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        .init(.pages, [.docx, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        .init(.md, [.docx, .pages, .pdf, .txt, .html, .epub, .png, .jpg]),
        .init(.rtf, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        .init(.rtfd, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        .init(.textClipping, [.docx, .pages, .pdf, .txt, .md, .html, .epub, .png, .jpg]),
        .init(.txt, [.docx, .pages, .pdf, .md, .html, .epub, .jpg, .png]),
        .init(.epub, [.pdf, .docx, .pages, .txt, .md, .html]),
        .init(.ppt, [.pdf, .jpg, .png]),
        .init(.pptx, [.pdf, .jpg, .png]),
    ]
    private static let dataFormats: [ConversionRow] = [
        .init(.xlsx, [.ods, .csv, .tsv, .pdf]),
        .init(.xls, [.xlsx, .ods, .csv, .tsv, .pdf]),
        .init(.ods, [.xlsx, .csv, .tsv, .pdf]),
        .init(.csv, [.xlsx, .ods, .tsv, .pdf]),
        .init(.tsv, [.xlsx, .ods, .csv, .pdf]),
        .init(.srt, [.vtt, .txt]),
        .init(.vtt, [.srt, .txt]),
        .init(.zip, [.tar, .gz]),
        .init(.tar, [.zip, .gz]),
        .init(.gz, [.zip, .tar]),
        .init(.rar, [.zip, .tar, .gz]),
    ]
}
