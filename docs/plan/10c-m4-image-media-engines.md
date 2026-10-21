# 10c — M4 stream B: WebP output, SVG input, image plan completion, media fixes

Part of [10-implementation-plan-m4](10-implementation-plan-m4.md). Conventions: index §6. Swift commands from
`Packages/ZivletKit`. Depends on A5, A6, A9 (binary targets); B6 also on A3/A4 (bundled ffmpeg with zscale).

Route count after this stream: raster 49 (43 today + 6 → webp), SVG 8 (pulled forward, D-M4-6), audio 56, video 42,
GIF 6 = **161** catalog pairs available, of which 153 are the Phase 1 set.

---

## Task B1 — `WebPPlan`: pure options for the six → webp pairs (P1-09)

| Field | Value |
|---|---|
| Goal | `WebPPlanner.options(tier:probe:)` → `WebPOptions {quality, method, sharpYUV, exactAlpha, lossless, animated, keepICC, keepEXIF, keepXMP}`; quality 65 / 85 / 96 by tier; `method 4`; `use_sharp_yuv 1`; `exact 1` when the source has alpha; animated when the source has more than one frame and is APNG or HEICS; lossless only when the tier is `.best` **and** the source is PNG with ≤ 256 colours is out of scope — Phase 1 never picks lossless automatically, so "no silent lossless fallback larger than the source" holds by construction. `ImagePipelineSpec` gains an optional `webp: WebPOptions` (Codable, validated: quality 0…100, method 0…6) |
| 05 rows | P1-09 |
| Sources | 03b §6.2 table row `webp`, 13 §2.3 |

**Files:** create `Sources/EngineImage/WebPPlanner.swift`, `Tests/EngineImageTests/WebPPlannerTests.swift`; modify
`Sources/ZivletEngineKit/ImagePipelineSpec.swift` (+ `WebPOptions`, decoding runs the same checks),
`Sources/EngineImage/ImagePlanner.swift` (attach options when the target is `.webp`).

### B1.1 Failing tests first

```swift
import Foundation
import Testing
import ZivletCore
import ZivletEngineKit

@testable import EngineImage

@Suite("WebP plan (P1-09, 03b §6.2)")
struct WebPPlannerTests {
    static func probe(alpha: Bool = false, frames: Int = 1, type: String = "public.png") -> ImageProbe {
        ImageProbe(typeIdentifier: type, frameCount: frames, pixelSize: PixelSize(width: 64, height: 48),
            orientation: 1, hasAlpha: alpha)
    }

    @Test(arguments: [(QualityTier.small, 65.0), (.standard, 85.0), (.best, 96.0)])
    func qualityFollowsTheLadder(tier: QualityTier, quality: Double) {
        let options = WebPPlanner.options(tier: tier, probe: Self.probe())
        #expect(options.quality == quality)
        #expect(options.method == 4 && options.sharpYUV && !options.lossless)
    }

    @Test func alphaKeepsExactRGBUnderTransparentPixels() {
        #expect(WebPPlanner.options(tier: .standard, probe: Self.probe(alpha: true)).exactAlpha)
        #expect(!WebPPlanner.options(tier: .standard, probe: Self.probe(alpha: false)).exactAlpha)
    }

    @Test(arguments: [("public.png", 5, true), ("public.heics", 3, true), ("public.tiff", 4, false),
        ("public.png", 1, false)])
    func animationIsCarriedOnlyFromAnimatedTypes(type: String, frames: Int, animated: Bool) {
        #expect(WebPPlanner.options(tier: .standard, probe: Self.probe(frames: frames, type: type)).animated
            == animated)
    }

    @Test func metadataIsKeptByDefault() {
        let options = WebPPlanner.options(tier: .standard, probe: Self.probe())
        #expect(options.keepICC && options.keepEXIF && options.keepXMP)
    }

    @Test func planForPngToWebpCarriesTheOptionsAndAllFramesWhenAnimated() throws {
        let input = try InputItem(url: URL(fileURLWithPath: "/in/a.png"), format: .png, byteCount: 10)
        let request = try JobRequest(input: input, operation: .convert(.webp), destination: URL(fileURLWithPath: "/in"))
        let plan = try ImagePlanner.plan(request, probe: Self.probe(frames: 5), staged: URL(fileURLWithPath: "/in/.s"),
            writableTypes: [], options: ImageOptions())
        guard case .image(let spec) = plan.stages[0] else { Issue.record("not an image stage"); return }
        #expect(spec.destinationType == "org.webmproject.webp")
        #expect(spec.webp?.animated == true && spec.frames == [0, 1, 2, 3, 4])
        #expect(plan.notes.isEmpty)
    }

    @Test(arguments: [-1.0, 101.0])
    func invalidQualityIsRefusedOnDecode(quality: Double) throws {
        let json = #"{"quality":\#(quality),"method":4,"sharpYUV":true,"exactAlpha":false,"lossless":false,"#
            + #""animated":false,"keepICC":true,"keepEXIF":true,"keepXMP":true}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(WebPOptions.self, from: Data(json.utf8)) }
    }
}
```

### B1.2 Run, expect failure

`swift test --filter WebPPlannerTests` → `error: cannot find 'WebPPlanner' in scope` (also `WebPOptions`).

### B1.3 Implement

`ImageRoutes.missing` changes: `target == .webp` → available (libwebp is linked, A9), so the gate no longer asks
ImageIO for `org.webmproject.webp`. `ImagePlanner.frames` returns all frames (capped at 1,000 and at
`maxPixelsPerJob`) when the WebP options say animated; otherwise frame 0 plus `PlanNote.firstFrameOnly` as today.

### B1.4 Verify green / B1.5 Commit

`swift test --filter EngineImageTests` green. Commit `feat(image): WebP plan options for the six raster → webp pairs`.

---

## Task B2 — `WebPWriter`: libwebp encode, animation and metadata (P1-25 encoder half)

| Field | Value |
|---|---|
| Goal | In `ImagePipeline.run`, a `webp` spec decodes each frame upright (D-M3-29: orientation baked, written as 1), flattens nothing, imports RGBA into `WebPPicture` (`WebPPictureImportRGBA`), encodes with `WebPEncode` (still) or `WebPAnimEncoder` (animated, source delays from the APNG/HEICS dictionaries, loop count kept), then `WebPMux` adds ICCP / EXIF / XMP chunks from the source; writes to the staged file through the `StagedFile` checks (D-M3-26); cancellation polled between frames (`BlockingWork` flag); memory freed on every path (`WebPPictureFree`, `WebPMemoryWriterClear`, `WebPAnimEncoderDelete`, `WebPMuxDelete`). Verifier: ImageIO reads `org.webmproject.webp`, frame count = planned frames, displayed size = expected, alpha present iff the source had alpha |
| 05 rows | P1-25 |
| Verified | The prototype executable in A5 exercised exactly these libwebp calls from Swift (still with alpha, mux ICCP, 5-frame animation) and read the results back with ImageIO |

**Files:** create `Sources/EngineImage/WebPWriter.swift` (≤ 200 lines; split `WebPMuxer.swift` if longer),
`Tests/EngineImageTests/WebPWriterTests.swift`; modify `Sources/EngineImage/ImagePipeline.swift` (dispatch),
`Sources/EngineImage/ImageEngine.swift` (`ImageVerifier.checkRaster` reads WebP via ImageIO; no change in logic),
`Tests/EngineImageTests/ImageFixtures.swift` (APNG and HEICS fixtures made with ImageIO).

### B2.1 Failing tests first

Real files, written by ImageIO fixtures (no committed binaries):

```swift
@Suite("WebP writer on real files (P1-25)")
struct WebPWriterTests {
    @Test(arguments: [FormatID.jpg, .png, .heic, .tiff, .avif, .bmp])
    func everyRasterSourceBecomesAReadableWebP(source: FormatID) async throws {
        let rig = try ImageRig()                       // existing helper: temp dir + ImageEngine with real ImageIO
        let input = try rig.fixture(source, size: PixelSize(width: 64, height: 48), alpha: source == .png)
        let output = try await rig.convert(input, to: .webp)
        let image = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
        #expect(CGImageSourceGetType(image) as String? == "org.webmproject.webp")
        #expect(CGImageSourceGetCount(image) == 1)
        #expect(try rig.pixelSize(output) == PixelSize(width: 64, height: 48))
    }

    @Test func pngAlphaSurvives() async throws {
        let rig = try ImageRig()
        let output = try await rig.convert(try rig.fixture(.png, alpha: true), to: .webp)
        #expect(try rig.hasAlpha(output))
    }

    @Test func animatedPNGKeepsItsFramesAndDelays() async throws {
        let rig = try ImageRig()
        let apng = try rig.animatedPNG(frames: 4, delay: 0.1)
        let output = try await rig.convert(apng, to: .webp)
        #expect(try rig.frameCount(output) == 4)
        #expect(try rig.delays(output) == [0.1, 0.1, 0.1, 0.1])
    }

    @Test func iccProfileIsCarried() async throws {
        let rig = try ImageRig()
        let output = try await rig.convert(try rig.fixture(.jpg, colorSpace: .displayP3), to: .webp)
        #expect(try rig.profileName(output) == "Display P3")
    }

    @Test(arguments: [2, 6])
    func orientationIsBakedAndWrittenAsOne(orientation: Int) async throws {
        let rig = try ImageRig()
        let output = try await rig.convert(try rig.fixture(.jpg, orientation: orientation), to: .webp)
        #expect(try rig.orientation(output) == 1)
        #expect(try rig.isUpright(output, comparedWith: .jpg, orientation: orientation))
    }

    @Test func cancellingBetweenFramesLeavesNoOutput() async throws {
        let rig = try ImageRig()
        let apng = try rig.animatedPNG(frames: 200, delay: 0.04, size: PixelSize(width: 1024, height: 768))
        await #expect(throws: JobError.cancelled) { try await rig.convert(apng, to: .webp, cancelAfter: .milliseconds(30)) }
        #expect(try rig.stagedFiles().isEmpty)
    }
}
```

`ImageRig` methods that do not exist yet (`animatedPNG`, `delays`, `profileName`, `isUpright`) are added to
`ImageFixtures.swift` in this task; `isUpright` reuses the M3 orientation comparison from `ImageOrientationTests`.

### B2.2 Run, expect failure

`swift test --filter WebPWriterTests` → the route is available after B1 but execute fails:
`ImageWriteFailure.unsupportedType("org.webmproject.webp")` from `CGImageDestinationCreateWithURL` (ImageIO cannot write
WebP) — the expected RED.

### B2.3 Implement

Encode order per frame: `oriented(source, index)` (existing) → draw into an sRGB-or-source-colour-space
`CGContext` with `premultipliedLast` 8-bit RGBA → `WebPPictureImportRGBA` (unpremultiply first: libwebp expects
straight alpha; use `vImageUnpremultiplyData_RGBA8888`). Failure codes map: `VP8_ENC_ERROR_OUT_OF_MEMORY` →
`writeFailed("out of memory")`, `…BAD_DIMENSION` → `unsupportedInput(.tooLarge)` (WebP max 16383 × 16383; the plan
refuses larger sources up front with `tooLarge` and a test), anything else → `writeFailed("WebP encoder error N")`.

### B2.4 Verify green / B2.5 Commit

`swift test --filter EngineImageTests` green; `make coverage` EngineImage ≥ 80 %. Commit `feat(image): WebP output
with libwebp: still, animated, ICC/EXIF/XMP`.

---

## Task B3 — SVG input: `SVGRenderer` and the eight svg pairs (D-M4-6, P2-11 subset)

| Field | Value |
|---|---|
| Goal | `ImageReader.probe` recognises SVG (and `.svgz`, gunzipped in Swift with a 64 MiB cap and a 100:1 ratio cap) and returns intrinsic size from `zivlet_svg_render` at scale 1 (cheap: render cost is paid once again at execute; acceptable, or add `zivlet_svg_size` to the crate — preferred, add it in A6 if not yet). Plan: scale 2 (03b §6.4), longest edge ≤ 8192, `expectedSize` = the clamped size. Execute: render to RGBA → `CGImage` (premultiplied last, sRGB) → the existing raster writer (JPEG/PNG/HEIC/TIFF/AVIF/BMP) or `WebPWriter`. **svg → pdf**: one PDF page the size of the SVG at 72 pt per CSS px, holding the 2× raster as an image (D-M4-6); plan note `.svgRasterizedInPDF`, card copy "The drawing was saved as a picture inside the PDF." Vector PDF arrives with krilla-svg in P2-10 |
| 05 rows | P2-10/P2-11 subset (pull-forward), G-2 |
| Verified | Renderer behaviour (2× scale, 8192 cap, data:-only hrefs, parse error) in the A6 prototype |

**Files:** create `Sources/EngineImage/SVGRenderer.swift`, `Tests/EngineImageTests/SVGEngineTests.swift`; modify
`ImagePlanner.swift` (svg source), `ImagePipeline.swift` (svg frame source), `ImagePDFWriter.swift` (image page from a
`CGImage`), `ImageRoutes.missing` (svg available), `Sources/ZivletCore/Jobs/JobRequest.swift` (`PlanNote` case),
`Sources/ZivletRuntime/JobErrorCopy.swift` / `BatchPresentation.swift` (note sentence).

### B3.1 Failing tests first

```swift
@Suite("SVG input (D-M4-6): seven raster targets and raster-in-PDF")
struct SVGEngineTests {
    static let drawing = #"""
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
        <rect width="120" height="80" fill="#0a0"/><circle cx="60" cy="40" r="30" fill="#00f"/></svg>
        """#

    @Test(arguments: [FormatID.jpg, .png, .webp, .heic, .tiff, .avif, .bmp])
    func rendersAtTwiceTheIntrinsicSize(target: FormatID) async throws {
        let rig = try ImageRig()
        let output = try await rig.convert(try rig.write(Self.drawing, named: "d.svg"), to: target)
        #expect(try rig.pixelSize(output) == PixelSize(width: 240, height: 160))
        #expect(try rig.colour(output, x: 120, y: 80).isMostlyBlue)
    }

    @Test func pdfIsOnePageAtTheDrawingSizeWithAnImage() async throws {
        let rig = try ImageRig()
        let (output, notes) = try await rig.convertWithNotes(try rig.write(Self.drawing, named: "d.svg"), to: .pdf)
        let document = try #require(CGPDFDocument(output as CFURL))
        #expect(document.numberOfPages == 1)
        #expect(document.page(at: 1)?.getBoxRect(.mediaBox).size == CGSize(width: 120, height: 80))
        #expect(notes == [.svgRasterizedInPDF])
    }

    @Test func svgzIsGunzippedWithinLimits() async throws {
        let rig = try ImageRig()
        let output = try await rig.convert(try rig.writeGzipped(Self.drawing, named: "d.svgz"), to: .png)
        #expect(try rig.pixelSize(output) == PixelSize(width: 240, height: 160))
    }

    @Test func aGzipBombIsRefused() async throws {
        let rig = try ImageRig()
        let bomb = try rig.writeGzipped(String(repeating: " ", count: 80 << 20), named: "b.svgz")
        await #expect(throws: JobError.unsupportedInput(.tooLarge)) { try await rig.convert(bomb, to: .png) }
    }

    @Test func externalFilesAreNeverRead() async throws {
        let rig = try ImageRig()
        let red = try rig.fixture(.png, size: PixelSize(width: 20, height: 20), colour: .red)
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="#fff"/><image href="\#(red.path)" width="20" height="20"/></svg>"#
        let output = try await rig.convert(try rig.write(svg, named: "x.svg"), to: .png)
        #expect(try rig.colour(output, x: 20, y: 20).isWhite)
    }

    @Test func notSVGIsUnreadable() async throws {
        let rig = try ImageRig()
        await #expect(throws: JobError.unsupportedInput(.unreadable)) {
            try await rig.convert(try rig.write("hello", named: "n.svg"), to: .png)
        }
    }
}
```

### B3.2 Run, expect failure

`swift test --filter SVGEngineTests` → `routeUnavailable(svg, png, ["svg renderer"])` for every case (D-M3-7).

### B3.3 Implement

`SVGRenderer` wraps the C calls in a `~Copyable` owner that frees the buffer in `deinit`; runs inside
`BlockingWork` (never on the cooperative pool, D-M3-10). The 8192 cap equals 67 MP, below the 200 MP decode cap.
The first render in a process loads system fonts (prototype: 0.65 s cold, under 0.05 s warm) — `ConversionService`
warms the renderer on a background queue after launch the first time an SVG is dragged (hover probe), not at launch.

### B3.4 Verify green / B3.5 Commit

`swift test --filter EngineImageTests` green. Commit `feat(image): SVG input through resvg; svg → pdf as an image
page until vector PDF lands`.

---

## Task B4 — Image plan completion: animation, multi-page TIFF, Web (sRGB), AVIF fallback (P1-08, G-5, G-6)

| Field | Value |
|---|---|
| Goal | (a) Animated sources (APNG, HEICS) to animated-capable targets (PNG → APNG via `kCGImagePropertyAPNGDictionary`, HEIC → HEICS via `public.heics`, WebP via B2) carry every frame with delays and loop count; other targets get frame 0 + `firstFrameOnly` note (today's behaviour). (b) Multi-page TIFF → single-image targets: one output per page in a folder `<base> Images/<base> 001.<ext>` (03b §6.2, `OutputNamer+Tools` already has the folder rule — reuse it), published as one batch entry with one undo record. (c) Colour: keep the source ICC by default; `ImageOptions.colour = .webSRGB` converts to sRGB and drops the profile (the Settings value lands in D3; default `.keep`). (d) HDR gain-map HEIC/AVIF sources: decode with `kCGImageSourceDecodeToSDR` for SDR targets and add note `.hdrToneMapped`. (e) AVIF route: ImageIO when `public.avif` is writable, else the media engine's `libsvtav1` still path `-frames:v 1 -c:v libsvtav1 -svtav1-params avif=1 -crf N -pix_fmt yuv420p -f avif` (11 §12); the route gate picks one from the capability snapshot |
| 05 rows | P1-08 (remaining acceptance), G-5, G-6 |
| Sources | 03b §6.2–6.3, 11 §12, 13 §2.1 |

**Files:** modify `ImagePlanner.swift` (split `ImagePlanner+Frames.swift`, `ImagePlanner+Colour.swift` to stay under
400 lines), `ImagePipeline.swift` (animation dictionaries, multi-output), `ImageEngine.swift` (multi-output
`StagedOutput`s — see note), `Sources/EngineMedia/AVIFStill.swift` (new, ffmpeg AVIF still plan),
`Tests/EngineImageTests/ImagePlanGoldenTests.swift` (new: goldens per pair × {8-bit sRGB, 16-bit P3, animated, alpha,
HDR gain map} = 36 × 5 plan snapshots as JSON under `Tests/EngineImageTests/Goldens/`).

Note on (b): the `Engine` contract returns one `StagedOutput`. Multi-page TIFF to N files needs `[StagedOutput]` and
N staging claims; this is a contract change across Runtime (`JobPipeline`, `Publisher`, `UndoHistory`). Do it as its
own commit inside this task with the failing test "a 3-page TIFF → PNG publishes `scan Images/scan 001.png` …
`scan 003.png`, one undo entry, Undo trashes the folder". If the change exceeds the size rules, split (b) into task
B4b and keep the M3 behaviour (first page + note) until it lands.

### B4.1 Failing tests first (excerpt; goldens are generated once with `ZIVLET_RECORD_GOLDENS=1` and reviewed)

```swift
@Test func apngToPngStaysAnimated() async throws {
    let rig = try ImageRig()
    let output = try await rig.convert(try rig.animatedPNG(frames: 3, delay: 0.2), to: .png)
    #expect(try rig.frameCount(output) == 3 && rig.delays(output) == [0.2, 0.2, 0.2])
}

@Test func heicsToHeicStaysASequence() async throws {
    let rig = try ImageRig()
    let output = try await rig.convert(try rig.heicSequence(frames: 3), to: .heic)
    #expect(try rig.typeIdentifier(output) == "public.heics" && rig.frameCount(output) == 3)
}

@Test func webSRGBDropsTheProfileAndConverts() throws {
    let plan = try ImagePlanner.plan(Fx.request(.jpg, to: .png), probe: Fx.probe(profile: "Display P3"),
        staged: Fx.staged, writableTypes: Fx.allWritable, options: ImageOptions(colour: .webSRGB))
    #expect(plan.imageSpec?.colour == .convertToSRGB)
}

@Test func avifFallsBackToTheMediaEngineWhenImageIOCannotWriteIt() {
    #expect(ImageRoutes.avifRoute(writableTypes: ["public.png"], mediaEncoders: ["libsvtav1"]) == .ffmpegStill)
    #expect(ImageRoutes.avifRoute(writableTypes: ["public.avif"], mediaEncoders: []) == .imageIO)
    #expect(ImageRoutes.avifRoute(writableTypes: [], mediaEncoders: []) == nil)
}
```

### B4.2–B4.5

RED: missing members (`colour`, `avifRoute`, `heicSequence`) fail to compile. GREEN: `swift test --filter
EngineImageTests`. Commits (one per sub-goal): `feat(image): carry APNG and HEICS animation`, `feat(runtime): multi-
page TIFF to a folder of images with one undo entry`, `feat(image): Web (sRGB) colour option`, `feat(image): HDR gain
maps tone-mapped for SDR targets`, `feat(image): AVIF through SVT-AV1 when ImageIO cannot write it`.

---

## Task B5 — Media fixes found by the prototype: HDR input tags, Vorbis fixtures (D-M4-12)

| Field | Value |
|---|---|
| Goal | (a) The HDR → SDR chain names its input explicitly: `zscale=tin=<trc>:min=<matrix>:pin=<primaries>:t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p`, with `<trc>`/`<matrix>`/`<primaries>` mapped from `MediaInfo` (`smpte2084`, `arib-std-b67`, `bt2020nc`, `bt2020`), so a stream whose container tags are missing but whose probe said HDR does not fail with zscale's "no path between colorspaces". (b) Test fixtures that need Ogg Vorbis synthesize with `libvorbis` (the bundled build disables the native `vorbis` encoder); HDR fixtures are tagged in the bitstream with `-bsf:v hevc_metadata=transfer_characteristics=16:colour_primaries=9:matrix_coefficients=9` and encoded with `hevc_videotoolbox -profile:v main10 -pix_fmt p010le` (no `libx265` in our build) |
| Evidence | Prototype matrix run with the bundled build: all 104 pairs passed only after (b); the HDR smoke case failed with `code 3074: no path between colorspaces` when the fixture was untagged, and passed once tagged |
| 05 rows | P1-05 (HDR chain robustness), P1-23, P1-61 input |

**Files:** modify `Sources/EngineMedia/FFmpegArgs.swift` (tone-map chain builder takes `HDRSignal`),
`Sources/EngineMedia/MediaInfo.swift` (expose transfer/matrix/primaries names), `Tests/EngineMediaTests/Goldens/*`
(regenerated HDR goldens, reviewed), `Tests/EngineMediaTests/MediaIntegrationTests.swift` (ogg recipe →
`["-c:a", "libvorbis", "-ac", "2"]`, needs `["libvorbis"]`), `Tests/EngineMediaTests/FFmpegSmokeTests.swift` (HDR
recipe as above; `requires: ["hevc_videotoolbox", "zscale", "tonemap", "libvpx-vp9"]`).

### B5.1 Failing test first

```swift
@Test func toneMapChainNamesTheInputTransferMatrixAndPrimaries() throws {
    let info = Fx.info(Fx.video(0, "hevc", 3840, 2160, pixFmt: "yuv420p10le", hdr: true, transfer: "arib-std-b67",
        primaries: "bt2020", matrix: "bt2020nc"))
    let argv = try MediaPlanner.plan(Fx.request(.mov, to: .mp4, info: info)).passes[0].argv
    let vf = try #require(argv.firstIndex(of: "-vf").map { argv[$0 + 1] })
    #expect(vf.hasPrefix("zscale=tin=arib-std-b67:min=bt2020nc:pin=bt2020:t=linear:npl=100,"))
}
```

Plus: `make smoke` with the bundled helpers (`ZIVLET_FFMPEG_DIR=Vendor/out/media-stage/Helpers`) — the HDR case,
synthesized **untagged** (a new smoke case `mov-hdr-untagged__webm` whose `info` says HDR), fails before (a).

### B5.2–B5.5

RED: the chain lacks `tin=`. GREEN: `swift test --filter EngineMediaTests` and the bundled smoke run (16 cases, 0
known issues). Commits `fix(media): name the HDR input signal in the tone-map chain` and `test(media): Vorbis and
tagged-HDR fixtures that the bundled ffmpeg can make`.

---

## Task B6 — Media verifier completion and GIF clip guard (G-4, G-17)

| Field | Value |
|---|---|
| Goal | `MediaVerifier` also checks the stream count against the plan (video+audio+subtitle streams the plan maps) and, for MP4/MOV outputs, `AVURLAsset.load(.isPlayable)` inside the engine (03b §5.9; today only the integration test asserts it). Video → GIF with a source longer than 60 s gets plan note `.longGIF` and the card sentence "Long clips make very large GIFs; this one is N minutes." (03b §5.6) — no refusal |
| 05 rows | P1-23 (remaining), G-4, G-17 |

**Files:** modify `Sources/EngineMedia/MediaVerifier.swift`, `Sources/EngineMedia/GIFPlanner.swift`,
`Sources/ZivletCore/Jobs/JobRequest.swift` (`PlanNote.longGIF(seconds:)`), `Sources/ZivletRuntime/BatchPresentation.swift`;
tests in `MediaEngineTests` (fake probe with one stream fewer → `verificationFailed("… expected 2 streams, found 1")`;
a fake `PlayabilityCheck` returning false → `verificationFailed("… not playable …")`) and `MediaPlannerRuleTests`
(61 s source → note, 60 s → none).

Commits `feat(media): verify stream count and AVFoundation playability` and `feat(media): note long clips turned
into GIFs`.
