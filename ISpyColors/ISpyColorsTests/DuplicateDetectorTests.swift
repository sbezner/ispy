//
//  DuplicateDetectorTests.swift
//  ISpyColorsTests
//
//  Tests for Vision-backed duplicate detection. These run on a host that has
//  Vision available (any iOS simulator / device). They synthesize simple
//  CGImages so no photo assets are needed.
//

import XCTest
import Vision
import CoreGraphics
@testable import ISpyColors

final class DuplicateDetectorTests: XCTestCase {

    let detector = DuplicateDetector(duplicateThreshold: 0.30)

    /// Every test here needs real Vision feature prints; skip (don't fail) when
    /// the simulator lacks the ML backend. Runs for real on a device.
    override func setUpWithError() throws {
        try VisionTestSupport.skipUnlessFeaturePrintsAvailable()
    }

    // Build a solid-color CGImage with an optional contrasting square so two
    // images can be made "clearly different".
    private func makeImage(background: (UInt8, UInt8, UInt8),
                           square: (UInt8, UInt8, UInt8)? = nil,
                           size: Int = 120) -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = size * bytesPerPixel
        var data = [UInt8](repeating: 0, count: size * size * bytesPerPixel)
        for y in 0..<size {
            for x in 0..<size {
                let inSquare = square != nil && x > size / 4 && x < 3 * size / 4
                                            && y > size / 4 && y < 3 * size / 4
                let c = inSquare ? square! : background
                let i = (y * size + x) * bytesPerPixel
                data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2; data[i + 3] = 255
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &data, width: size, height: size,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testSameImageIsDuplicate() throws {
        let img = makeImage(background: (40, 90, 200), square: (240, 240, 40))
        let printA = try XCTUnwrap(detector.generateFeaturePrint(for: img))
        let printB = try XCTUnwrap(detector.generateFeaturePrint(for: img))

        let result = detector.evaluate(candidate: printB, against: [printA])
        XCTAssertTrue(result.isDuplicate, "Identical images must read as duplicate")
        XCTAssertEqual(result.nearestDistance ?? 1, 0, accuracy: 0.05)
    }

    func testDifferentImagesAreNotDuplicate() throws {
        let a = makeImage(background: (20, 30, 200), square: (250, 250, 250))   // blue + white box
        let b = makeImage(background: (210, 40, 40), square: (10, 10, 10))      // red + black box
        let printA = try XCTUnwrap(detector.generateFeaturePrint(for: a))
        let printB = try XCTUnwrap(detector.generateFeaturePrint(for: b))

        let result = detector.evaluate(candidate: printB, against: [printA])
        XCTAssertFalse(result.isDuplicate, "Clearly different images must NOT read as duplicate")
        XCTAssertGreaterThan(result.nearestDistance ?? 0, detector.duplicateThreshold)
    }

    func testNoStoredPrintsIsNeverDuplicate() throws {
        let img = makeImage(background: (10, 200, 10))
        let print = try XCTUnwrap(detector.generateFeaturePrint(for: img))
        let result = detector.evaluate(candidate: print, against: [])
        XCTAssertFalse(result.isDuplicate)
        XCTAssertNil(result.nearestDistance)
    }

    func testThresholdIsTunable() throws {
        let a = makeImage(background: (20, 30, 200), square: (250, 250, 250))
        let b = makeImage(background: (210, 40, 40), square: (10, 10, 10))
        let printA = try XCTUnwrap(detector.generateFeaturePrint(for: a))
        let printB = try XCTUnwrap(detector.generateFeaturePrint(for: b))
        let d = try detector.distance(printA, printB)

        // A huge threshold makes even different images "duplicates".
        let loose = DuplicateDetector(duplicateThreshold: d + 1.0)
        XCTAssertTrue(loose.evaluate(candidate: printB, against: [printA]).isDuplicate)

        // A tiny threshold makes even identical images "not duplicates".
        let strict = DuplicateDetector(duplicateThreshold: 0.0)
        let printA2 = try XCTUnwrap(detector.generateFeaturePrint(for: a))
        XCTAssertFalse(strict.evaluate(candidate: printA2, against: [printA]).isDuplicate)
    }
}
