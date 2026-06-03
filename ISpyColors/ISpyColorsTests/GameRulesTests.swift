//
//  GameRulesTests.swift
//  ISpyColorsTests
//
//  Tests the pure turn-outcome rule, plus an end-to-end check (real Vision) that
//  the same object photographed twice awards exactly ONE star while a different
//  object of the same color is accepted — acceptance criterion #4, exercised
//  without a camera by driving the same DuplicateDetector + GameRules path the
//  GameViewModel uses.
//

import XCTest
import Vision
import CoreGraphics
@testable import ISpyColors

final class GameRulesTests: XCTestCase {

    // MARK: Pure rule

    func testOutcomeTruthTable() {
        XCTAssertEqual(GameRules.outcome(colorPassed: false, isDuplicate: false), .colorFail)
        XCTAssertEqual(GameRules.outcome(colorPassed: false, isDuplicate: true), .colorFail) // color fails first
        XCTAssertEqual(GameRules.outcome(colorPassed: true, isDuplicate: true), .duplicateFail)
        XCTAssertEqual(GameRules.outcome(colorPassed: true, isDuplicate: false), .win)

        XCTAssertTrue(GameRules.awardsStar(.win))
        XCTAssertFalse(GameRules.awardsStar(.colorFail))
        XCTAssertFalse(GameRules.awardsStar(.duplicateFail))
    }

    // MARK: End-to-end "exactly one star"

    private func makeImage(bg: (UInt8, UInt8, UInt8),
                           square: (UInt8, UInt8, UInt8)? = nil,
                           size: Int = 120) -> CGImage {
        let bpp = 4, bpr = size * bpp
        var data = [UInt8](repeating: 0, count: size * size * bpp)
        for y in 0..<size {
            for x in 0..<size {
                let inSq = square != nil && x > size / 4 && x < 3 * size / 4
                                        && y > size / 4 && y < 3 * size / 4
                let c = inSq ? square! : bg
                let i = (y * size + x) * bpp
                data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2; data[i + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        return CGContext(data: &data, width: size, height: size, bitsPerComponent: 8,
                         bytesPerRow: bpr, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// Minimal session simulator mirroring GameViewModel.takePhoto's verdict path.
    private final class Session {
        let dup = DuplicateDetector(duplicateThreshold: 0.30)
        var prints: [VNFeaturePrintObservation] = []
        var stars = 0

        func play(_ image: CGImage, colorPassed: Bool) throws -> TurnOutcome {
            let candidate = colorPassed ? try dup.generateFeaturePrint(for: image) : nil
            let isDup = candidate.map { dup.evaluate(candidate: $0, against: prints).isDuplicate } ?? false
            let outcome = GameRules.outcome(colorPassed: colorPassed, isDuplicate: isDup)
            if outcome == .win {
                if let candidate { prints.append(candidate) }
                stars += 1
            }
            return outcome
        }
    }

    func testSameObjectTwiceAwardsExactlyOneStar() throws {
        try VisionTestSupport.skipUnlessFeaturePrintsAvailable()
        let session = Session()
        let objectA = makeImage(bg: (30, 60, 210), square: (240, 240, 40))

        XCTAssertEqual(try session.play(objectA, colorPassed: true), .win)
        XCTAssertEqual(session.stars, 1)

        // Same object again -> duplicate -> NO additional star.
        XCTAssertEqual(try session.play(objectA, colorPassed: true), .duplicateFail)
        XCTAssertEqual(session.stars, 1, "Same object must award exactly one star")
    }

    func testDifferentObjectSameColorIsAccepted() throws {
        try VisionTestSupport.skipUnlessFeaturePrintsAvailable()
        let session = Session()
        let objectA = makeImage(bg: (30, 60, 210), square: (240, 240, 40))
        let objectB = makeImage(bg: (20, 40, 200), square: (10, 10, 10))

        XCTAssertEqual(try session.play(objectA, colorPassed: true), .win)
        XCTAssertEqual(try session.play(objectB, colorPassed: true), .win,
                       "A clearly different object of the same color must be accepted")
        XCTAssertEqual(session.stars, 2)
    }

    func testColorFailAwardsNoStarAndSkipsDuplicateCheck() throws {
        let session = Session()
        let object = makeImage(bg: (20, 40, 200), square: (10, 10, 10))
        XCTAssertEqual(try session.play(object, colorPassed: false), .colorFail)
        XCTAssertEqual(session.stars, 0)
    }
}
