//
//  ImageAnalyzerTests.swift
//  ISpyColorsTests
//
//  Runs real photographs through the ACTUAL Swift pipeline:
//  CGImage -> ImageAnalyzer (CoreGraphics downsample) -> ColorDetector.analyze.
//
//  The Python test bank (tools/test_bank.py) only exercises a *port* of this
//  logic — it uses PIL/BILINEAR while the app uses CGContext with DeviceRGB and
//  medium interpolation. Those can disagree right at color boundaries, so this
//  test guards the real code path on a representative photo of each palette
//  color. Fixtures live in ISpyColorsTests/Fixtures/ (one <color>.jpg each),
//  downscaled from the Photos/ bank; they're high-margin so the result is
//  robust to the small CoreGraphics-vs-PIL downsample differences.
//

import XCTest
import UIKit
@testable import ISpyColors

final class ImageAnalyzerTests: XCTestCase {

    /// Load a bundled fixture as a CGImage. Synchronized test groups flatten
    /// resources to the bundle root, but we also try the Fixtures/ subdirectory.
    private func fixture(_ name: String,
                         file: StaticString = #filePath, line: UInt = #line) throws -> CGImage {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "jpg")
            ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Fixtures")
        let u = try XCTUnwrap(url, "fixture \(name).jpg not found in test bundle", file: file, line: line)
        let image = try XCTUnwrap(UIImage(contentsOfFile: u.path)?.cgImage,
                                  "could not decode \(name).jpg", file: file, line: line)
        return image
    }

    /// One representative real photo per color must PASS its color through the
    /// real ImageAnalyzer. This is the end-to-end guard the unit tests lacked.
    func testRealPhotosPassThroughActualImageAnalyzer() throws {
        let analyzer = ImageAnalyzer()
        let cases: [(String, GameColor)] = [
            ("red", .red), ("orange", .orange), ("yellow", .yellow), ("green", .green),
            ("blue", .blue), ("purple", .purple), ("pink", .pink), ("white", .white), ("black", .black),
        ]
        for (name, color) in cases {
            let image = try fixture(name)
            let result = try XCTUnwrap(analyzer.analyze(image, target: color),
                                       "analyze returned nil for \(name).jpg")
            XCTAssertTrue(result.passed,
                "\(name).jpg should PASS \(color.rawValue) through the real ImageAnalyzer " +
                "(match \(result.matchFraction), blob \(result.largestBlobFraction))")
        }
    }

    /// Sanity in the other direction: a photo must NOT pass an obviously wrong
    /// color. Catches a pipeline that just returns `passed` for everything.
    func testRealPhotosRejectObviouslyWrongColor() throws {
        let analyzer = ImageAnalyzer()
        let blueberries = try fixture("blue")
        XCTAssertFalse(try XCTUnwrap(analyzer.analyze(blueberries, target: .red)).passed,
                       "blueberries must not pass RED")
        let banana = try fixture("yellow")
        XCTAssertFalse(try XCTUnwrap(analyzer.analyze(banana, target: .blue)).passed,
                       "a banana must not pass BLUE")
    }
}
