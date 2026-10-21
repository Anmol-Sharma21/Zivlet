// Format data (03a §3.1). UTIs verified with UTType(filenameExtension:) on macOS 27.0.
extension FormatRegistry {
    static let table: [Format] = image + audio + video + text + office + archives

    private static let image: [Format] = [
        Format(.jpg, .image, .raster, extensions: ["jpg", "jpeg", "jpe"], contentTypes: ["public.jpeg"]),
        Format(.png, .image, .raster, extensions: ["png"], contentTypes: ["public.png"]),
        Format(.webp, .image, .raster, extensions: ["webp"], contentTypes: ["org.webmproject.webp"]),
        Format(.heic, .image, .raster, extensions: ["heic", "heif"], contentTypes: ["public.heic", "public.heif"]),
        Format(.tiff, .image, .raster, extensions: ["tiff", "tif"], contentTypes: ["public.tiff"]),
        Format(.avif, .image, .raster, extensions: ["avif"], contentTypes: ["public.avif"]),
        Format(.bmp, .image, .raster, extensions: ["bmp"], contentTypes: ["com.microsoft.bmp"]),
        Format(.svg, .image, .svg, role: .inputOnly, extensions: ["svg", "svgz"], contentTypes: ["public.svg-image"]),
        Format(.pdf, .document, .pdf, extensions: ["pdf"], contentTypes: ["com.adobe.pdf"]),
    ]
    private static let audio: [Format] = [
        Format(.mp3, .audio, .audio, extensions: ["mp3"], contentTypes: ["public.mp3"]),
        Format(.m4a, .audio, .audio, extensions: ["m4a"], contentTypes: ["com.apple.m4a-audio"]),
        Format(.wav, .audio, .audio, extensions: ["wav"], contentTypes: ["com.microsoft.waveform-audio"]),
        Format(.flac, .audio, .audio, extensions: ["flac"], contentTypes: ["org.xiph.flac"]),
        Format(.ogg, .audio, .audio, extensions: ["ogg", "oga"], contentTypes: ["org.xiph.ogg-audio"]),
        Format(.opus, .audio, .audio, extensions: ["opus"], contentTypes: ["org.xiph.ogg-audio"]),
        Format(.aiff, .audio, .audio, extensions: ["aiff", "aif"], contentTypes: ["public.aiff-audio"]),
        Format(.wma, .audio, .audio, extensions: ["wma"], contentTypes: ["com.microsoft.windows-media-wma"]),
    ]
    private static let video: [Format] = [
        Format(.mp4, .video, .video, extensions: ["mp4", "m4v"], contentTypes: ["public.mpeg-4"]),
        Format(.mov, .video, .video, extensions: ["mov"], contentTypes: ["com.apple.quicktime-movie"]),
        Format(.mkv, .video, .video, extensions: ["mkv"], contentTypes: ["app.zivlet.matroska"]),
        Format(.webm, .video, .video, extensions: ["webm"], contentTypes: ["org.webmproject.webm"]),
        Format(.avi, .video, .video, extensions: ["avi"], contentTypes: ["public.avi"]),
        Format(.wmv, .video, .video, extensions: ["wmv"], contentTypes: ["com.microsoft.windows-media-wmv"]),
        Format(.gif, .video, .gif, extensions: ["gif"], contentTypes: ["com.compuserve.gif"]),
    ]
    private static let text: [Format] = [
        Format(.srt, .subtitle, .subtitle, extensions: ["srt"], contentTypes: ["app.zivlet.subrip"]),
        Format(.vtt, .subtitle, .subtitle, extensions: ["vtt"], contentTypes: ["org.w3.webvtt"]),
        Format(
            .docx, .document, .document, extensions: ["docx"],
            contentTypes: ["org.openxmlformats.wordprocessingml.document"]),
        Format(
            .pages, .document, .document, extensions: ["pages"],
            contentTypes: ["com.apple.iwork.pages.sffpages", "com.apple.iwork.pages.pages"], isPackage: true),
        Format(
            .md, .document, .document, extensions: ["md", "markdown"], contentTypes: ["net.daringfireball.markdown"]),
        Format(.rtf, .document, .document, role: .inputOnly, extensions: ["rtf"], contentTypes: ["public.rtf"]),
        Format(
            .rtfd, .document, .document, role: .inputOnly, extensions: ["rtfd"],
            contentTypes: ["com.apple.rtfd"], isPackage: true),
        Format(
            .textClipping, .document, .document, role: .inputOnly, extensions: ["textclipping"],
            contentTypes: ["com.apple.finder.textclipping"]),
        Format(.txt, .document, .document, extensions: ["txt", "text"], contentTypes: ["public.plain-text"]),
        Format(
            .html, .document, .document, role: .outputOnly, extensions: ["html", "htm"], contentTypes: ["public.html"]),
        Format(.epub, .document, .document, extensions: ["epub"], contentTypes: ["org.idpf.epub-container"]),
    ]
    private static let office: [Format] = [
        Format(
            .pptx, .document, .slides, extensions: ["pptx"],
            contentTypes: ["org.openxmlformats.presentationml.presentation"]),
        Format(
            .ppt, .document, .slides, role: .inputOnly, extensions: ["ppt"],
            contentTypes: ["com.microsoft.powerpoint.ppt"]),
        Format(
            .xlsx, .spreadsheet, .spreadsheet, extensions: ["xlsx"],
            contentTypes: ["org.openxmlformats.spreadsheetml.sheet"]),
        Format(
            .xls, .spreadsheet, .spreadsheet, role: .inputOnly, extensions: ["xls"],
            contentTypes: ["com.microsoft.excel.xls"]),
        Format(
            .ods, .spreadsheet, .spreadsheet, extensions: ["ods"],
            contentTypes: ["org.oasis-open.opendocument.spreadsheet"]),
        Format(
            .csv, .spreadsheet, .spreadsheet, extensions: ["csv"], contentTypes: ["public.comma-separated-values-text"]),
        Format(
            .tsv, .spreadsheet, .spreadsheet, extensions: ["tsv"], contentTypes: ["public.tab-separated-values-text"]),
    ]
    private static let archives: [Format] = [
        Format(.zip, .archive, .archive, extensions: ["zip"], contentTypes: ["public.zip-archive"]),
        Format(.tar, .archive, .archive, extensions: ["tar"], contentTypes: ["public.tar-archive"]),
        Format(
            .gz, .archive, .archive, extensions: ["tar.gz", "tgz", "gz"],
            contentTypes: ["org.gnu.gnu-zip-tar-archive", "org.gnu.gnu-zip-archive"]),
        Format(.rar, .archive, .archive, role: .inputOnly, extensions: ["rar"], contentTypes: ["app.zivlet.rar"]),
    ]
}
