import CoreGraphics
import Foundation
import PDFKit
import Vision
import ZivletCore
import ZivletEngineKit

/// Vision's barcode request behind a port, so Read QR's rules are tested without Vision.
public protocol BarcodeDetecting: Sendable {
    func detect(_ image: CGImage) async throws -> [DetectedCode]
}

/// The real request (macOS 26 Swift API) with every symbology it reports as supported on this Mac, not a fixed list.
/// A code whose payload is not text is skipped. Run only in the worker (D-M6-8).
public struct VisionBarcodeDetector: BarcodeDetecting {
    public init() {}

    public func detect(_ image: CGImage) async throws -> [DetectedCode] {
        var request = DetectBarcodesRequest()
        request.symbologies = request.supportedSymbologies
        return try await request.perform(on: image).compactMap { observation in
            guard let payload = observation.payloadString else { return nil }
            let top = Double(max(observation.topLeft.y, observation.topRight.y))
            return DetectedCode(payload: payload, symbology: String(describing: observation.symbology), top: top)
        }
    }
}

/// Read QR (P2-51, plan 20b A7): the codes of one image or PDF. Images use Copy Text's decode limits
/// (`ImageTextSource`); PDF pages are drawn at 200 DPI under the page renderer's caps. A locked PDF is refused
/// before any page is drawn; more pages than the limit too. Cancellation is checked before each page.
public struct CodeReader: Sendable {
    public static let dpi: CGFloat = 200

    let detector: any BarcodeDetecting
    let maximumPixels: Int

    public init(
        detector: any BarcodeDetecting = VisionBarcodeDetector(),
        maximumPixels: Int = ImageTextSource.maximumHeaderPixels
    ) {
        self.detector = detector
        self.maximumPixels = maximumPixels
    }

    /// `password` opens a locked PDF (P2-107); rendering pages needs no permission bit.
    public func read(_ url: URL, pageLimit: Int = PDFTextSource.pageLimit, password: JobSecret? = nil)
        async throws(CodeError) -> [FoundCode]
    {
        if Task.isCancelled { throw .cancelled }
        guard ImageTextSource.isPDF(url) else {
            let image: CGImage
            do {
                image = try ImageTextSource.decode(url, maximumPixels: maximumPixels)
            } catch {
                throw CodeError(error)
            }
            return FoundCode.arranged(try await detect(image), page: nil)
        }
        return try await readPDF(url, pageLimit: pageLimit, password: password)
    }

    private func readPDF(_ url: URL, pageLimit: Int, password: JobSecret?) async throws(CodeError) -> [FoundCode] {
        guard PDFLimits.allows(fileAt: url) else { throw .tooLarge }
        guard let document = LockedPDF.open(url, password: password) else { throw .unreadable }
        guard !document.isLocked else { throw .pdfLocked }
        guard document.pageCount <= pageLimit else { throw .tooManyPages(document.pageCount) }
        var found: [FoundCode] = []
        for index in 0..<document.pageCount {
            if Task.isCancelled { throw .cancelled }
            guard let page = document.page(at: index) else { throw .unreadable }
            let image: CGImage
            do {
                image = try PageRenderer.render(page, dpi: Self.dpi)
            } catch {
                throw CodeError(error)
            }
            found += FoundCode.arranged(try await detect(image), page: index + 1)
        }
        return found
    }

    private func detect(_ image: CGImage) async throws(CodeError) -> [DetectedCode] {
        do {
            let detected = try await detector.detect(image)
            if Task.isCancelled { throw CodeError.cancelled }
            return detected
        } catch {
            if Task.isCancelled { throw .cancelled }
            throw .detectionFailed
        }
    }
}
