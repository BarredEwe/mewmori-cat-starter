import AppKit
import XCTest
#if SWIFT_PACKAGE
@testable import CatStarter
import CatOCR
#else
@testable import CatStarterCore
#endif

final class CatStarterTests: XCTestCase {
    func testTrackClampsToTheLastKey() {
        let track = Track(
            part: "body",
            property: .scaleY,
            keys: [
                Keyframe(time: 0, value: 0, easing: nil),
                Keyframe(time: 1, value: 0.02, easing: nil),
                Keyframe(time: 2, value: 0, easing: nil)
            ],
            easing: .easeInOut
        )

        XCTAssertEqual(track.value(at: -1), 0)
        XCTAssertEqual(track.value(at: 3), 0)
    }

    func testPoseAddsOverlayDeltas() {
        let base = AnimationClip(
            id: "run",
            duration: 1,
            loop: true,
            tracks: [Track(part: "body", property: .scaleY, keys: [Keyframe(time: 0, value: 0.035, easing: nil)], easing: .linear)]
        )
        let overlay = AnimationClip(
            id: "breathe",
            duration: 1,
            loop: true,
            tracks: [Track(part: "body", property: .scaleY, keys: [Keyframe(time: 0, value: 0.02, easing: nil)], easing: .linear)]
        )

        let result = composePose(from: [(base, 1), (overlay, 1)], at: 0)

        XCTAssertEqual(result.value(for: "body", property: .scaleY), 0.055, accuracy: 0.0001)
    }

    func testValidatorReportsUnknownParentAndCycle() {
        let rig = Rig(
            referenceHeight: 100,
            pixelsPerUnit: 5.25,
            parts: [
                Part(id: "body", texture: "body.png", parent: "missing", position: Point(0, 0), z: 0, anchor: nil),
                Part(id: "head", texture: "head.png", parent: "body", position: Point(0, 0), z: 1, anchor: nil),
                Part(id: "tail", texture: "tail.png", parent: "head", position: Point(0, 0), z: 2, anchor: nil),
                Part(id: "body", texture: "body.png", parent: "tail", position: Point(0, 0), z: 3, anchor: nil)
            ],
            gaze: Gaze(pupils: [], maxOffset: 3)
        )

        let issues = RigValidator.validate(rig, availableTextures: ["body.png", "head.png", "tail.png"])

        XCTAssertTrue(issues.contains { $0.message.contains("unknown parent") })
        XCTAssertTrue(issues.contains { $0.message.contains("cycle") })
    }

    func testScreenObservationUsesFirstRecognizedLine() {
        XCTAssertEqual(
            ScreenObservation.message(from: "\n  Первое предложение\nВторое предложение"),
            "Вижу: Первое предложение"
        )
        XCTAssertEqual(ScreenObservation.message(from: "   \n"), "На экране текста не вижу.")
    }

    func testVisionOCRReadsGeneratedText() throws {
        let image = NSImage(size: NSSize(width: 640, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 180).fill()
        ("HELLO CAT" as NSString).draw(
            at: NSPoint(x: 40, y: 55),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()

        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let result = try ScreenOCR.recognizeText(in: cgImage)

        XCTAssertTrue(result.uppercased().contains("HELLO CAT"), "OCR result: \(result)")
    }

    func testThumbnailIgnoresTinyChangeButNotWidespreadChange() {
        let original = [UInt8](repeating: 120, count: ScreenThumbnail.side * ScreenThumbnail.side)
        var blinked = original
        for index in 0..<8 { blinked[index] = 255 }
        var scrolled = original
        for index in scrolled.indices where index.isMultiple(of: 2) { scrolled[index] = 160 }

        XCTAssertTrue(ScreenThumbnail.isSimilar(original, blinked))
        XCTAssertFalse(ScreenThumbnail.isSimilar(original, scrolled))
    }

    func testDigestUsesGeometryFiltersChromeAndEscapesScreenText() {
        let digest = ScreenDigest.make(from: [
            RecognizedLine(text: "Описание <ошибки>", boundingBox: CGRect(x: 0.1, y: 0.3, width: 0.5, height: 0.04)),
            RecognizedLine(text: "Поиск", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.03)),
            RecognizedLine(text: "Mewmori", boundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.08))
        ])

        XCTAssertFalse(digest.contains("Поиск"))
        XCTAssertTrue(digest.contains("role=\"heading\">Mewmori"))
        XCTAssertTrue(digest.contains("Описание &lt;ошибки&gt;"))
        XCTAssertLessThan(
            try XCTUnwrap(digest.range(of: "Mewmori")?.lowerBound),
            try XCTUnwrap(digest.range(of: "Описание")?.lowerBound)
        )
        XCTAssertLessThanOrEqual(digest.count, ScreenDigest.maxCharacters + 120)
    }

    func testDigestStopsBeforeContentBudgetIsExceeded() {
        let observations = (0..<8).map { index in
            RecognizedLine(
                text: "строка \(index) " + String(repeating: "а", count: 110),
                boundingBox: CGRect(x: 0.1, y: Double(index) / 10, width: 0.8, height: 0.04)
            )
        }

        let digest = ScreenDigest.make(from: observations)

        XCTAssertTrue(digest.contains("строка 4"))
        XCTAssertFalse(digest.contains("строка 5"))
    }
}
