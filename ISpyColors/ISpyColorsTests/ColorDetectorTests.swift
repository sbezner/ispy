//
//  ColorDetectorTests.swift
//  ISpyColorsTests
//
//  Pure unit tests for the color logic — no camera, no device needed.
//

import XCTest
@testable import ISpyColors

final class ColorDetectorTests: XCTestCase {

    let detector = ColorDetector()

    // Helpers ---------------------------------------------------------------

    private func solid(_ p: RGBPixel, _ w: Int = 100, _ h: Int = 100) -> [RGBPixel] {
        Array(repeating: p, count: w * h)
    }

    private let blue = RGBPixel(r255: 0, g255: 0, b255: 255)
    private let red = RGBPixel(r255: 255, g255: 0, b255: 0)
    private let white = RGBPixel(r255: 255, g255: 255, b255: 255)
    private let black = RGBPixel(r255: 10, g255: 10, b255: 10)

    // HSV -------------------------------------------------------------------

    func testRGBtoHSVPrimaries() {
        XCTAssertEqual(detector.hsv(from: red).h, 0, accuracy: 0.5)
        XCTAssertEqual(detector.hsv(from: RGBPixel(r255: 0, g255: 255, b255: 0)).h, 120, accuracy: 0.5)
        XCTAssertEqual(detector.hsv(from: blue).h, 240, accuracy: 0.5)
        XCTAssertEqual(detector.hsv(from: white).s, 0, accuracy: 0.001)
        XCTAssertEqual(detector.hsv(from: white).v, 1, accuracy: 0.001)
    }

    // Acceptance: solid colors ---------------------------------------------

    func testSolidBluePassesBlue() {
        let result = detector.analyze(pixels: solid(blue), width: 100, height: 100, target: .blue)
        XCTAssertTrue(result.passed)
        XCTAssertGreaterThan(result.matchFraction, 0.9)
    }

    func testSolidRedFailsBlue() {
        let result = detector.analyze(pixels: solid(red), width: 100, height: 100, target: .blue)
        XCTAssertFalse(result.passed)
    }

    func testSolidRedPassesRed() {
        XCTAssertTrue(detector.analyze(pixels: solid(red), width: 100, height: 100, target: .red).passed)
    }

    // Acceptance: mixed image with a blue region ---------------------------

    func testMixedImageWithBlueRegionPassesBlue() {
        let w = 100, h = 100
        var pixels = solid(white, w, h)
        // A solid contiguous 40x50 blue rectangle = 2000 px = 20% of the image.
        for y in 0..<40 {
            for x in 0..<50 {
                pixels[y * w + x] = blue
            }
        }
        let result = detector.analyze(pixels: pixels, width: w, height: h, target: .blue)
        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.largestBlobFraction, 0.20, accuracy: 0.001)
    }

    func testScatteredBlueNoiseFailsContiguity() {
        // 12.5% of pixels are blue but each is isolated — no real blob.
        let w = 100, h = 100
        var pixels = solid(white, w, h)
        for i in stride(from: 0, to: w * h, by: 8) {
            pixels[i] = blue
        }
        let result = detector.analyze(pixels: pixels, width: w, height: h, target: .blue)
        XCTAssertGreaterThan(result.matchFraction, detector.minMatchFraction,
                             "Enough blue pixels overall...")
        XCTAssertFalse(result.passed, "...but scattered, so it must NOT pass.")
    }

    // White / black via sat+brightness, not hue ----------------------------

    func testWhiteAndBlack() {
        XCTAssertTrue(detector.analyze(pixels: solid(white), width: 100, height: 100, target: .white).passed)
        XCTAssertTrue(detector.analyze(pixels: solid(black), width: 100, height: 100, target: .black).passed)
        XCTAssertFalse(detector.analyze(pixels: solid(white), width: 100, height: 100, target: .blue).passed)
        // Mid gray is neither white nor black.
        let gray = RGBPixel(r255: 128, g255: 128, b255: 128)
        XCTAssertFalse(detector.analyze(pixels: solid(gray), width: 100, height: 100, target: .white).passed)
        XCTAssertFalse(detector.analyze(pixels: solid(gray), width: 100, height: 100, target: .black).passed)
    }

    // Every chromatic color matches its own solid swatch -------------------

    func testAllChromaticColors() {
        let samples: [(GameColor, RGBPixel)] = [
            (.red, RGBPixel(r255: 230, g255: 30, b255: 30)),
            (.orange, RGBPixel(r255: 255, g255: 140, b255: 0)),
            (.yellow, RGBPixel(r255: 255, g255: 235, b255: 0)),
            (.green, RGBPixel(r255: 0, g255: 200, b255: 0)),
            (.blue, RGBPixel(r255: 0, g255: 0, b255: 255)),
            (.purple, RGBPixel(r255: 140, g255: 0, b255: 200)),
            (.pink, RGBPixel(r255: 255, g255: 105, b255: 180)),
        ]
        for (color, pixel) in samples {
            let r = detector.analyze(pixels: solid(pixel), width: 100, height: 100, target: color)
            XCTAssertTrue(r.passed, "Solid \(color.rawValue) should pass '\(color.rawValue)'")
        }
    }

    // Threshold is tunable --------------------------------------------------

    func testColorThresholdIsTunable() {
        // Build a tiny 9% blue blob.
        let w = 100, h = 100
        var pixels = solid(white, w, h)
        for y in 0..<30 { for x in 0..<30 { pixels[y * w + x] = blue } } // 900 px = 9%

        var strict = ColorDetector(minMatchFraction: 0.20) // demand 20%
        XCTAssertFalse(strict.analyze(pixels: pixels, width: w, height: h, target: .blue).passed)

        strict.minMatchFraction = 0.05 // relax to 5%
        XCTAssertTrue(strict.analyze(pixels: pixels, width: w, height: h, target: .blue).passed)
    }
}
