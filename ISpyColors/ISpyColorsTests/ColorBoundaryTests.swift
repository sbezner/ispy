//
//  ColorBoundaryTests.swift
//  ISpyColorsTests
//
//  Parametric sweep of the per-pixel classifier at and around every hue-band
//  edge. Unlike the photo bank (which can only contain images that already
//  pass), these tests pin down the EXACT boundaries, so a future tweak that
//  shifts a band — or re-opens the eggplant purple/pink bug — fails loudly.
//
//  Bands under test (see ColorDetector.hueBand):
//    red 345–14 · orange 14–45 · yellow 45–66 · green 66–168
//    blue 168–252 · purple 252–330 · pink 330–345  (pink also via isPink)
//

import XCTest
@testable import ISpyColors

final class ColorBoundaryTests: XCTestCase {

    private let d = ColorDetector()

    /// HSV (h in 0..<360, s,v in 0...1) -> RGBPixel. Inverse of ColorDetector.hsv,
    /// so we can probe a precise hue. Standard HSV->RGB.
    private func px(_ h: Double, _ s: Double, _ v: Double) -> RGBPixel {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double)
        switch h {
        case ..<60:   (r, g, b) = (c, x, 0)
        case ..<120:  (r, g, b) = (x, c, 0)
        case ..<180:  (r, g, b) = (0, c, x)
        case ..<240:  (r, g, b) = (0, x, c)
        case ..<300:  (r, g, b) = (x, 0, c)
        default:      (r, g, b) = (c, 0, x)
        }
        return RGBPixel(r: r + m, g: g + m, b: b + m)
    }

    private func matches(_ p: RGBPixel) -> [GameColor] {
        GameColor.allCases.filter { d.pixel(p, matches: $0) }
    }

    private func assertColor(_ h: Double, _ s: Double, _ v: Double, is color: GameColor,
                             not other: GameColor? = nil,
                             file: StaticString = #filePath, line: UInt = #line) {
        let got = matches(px(h, s, v))
        XCTAssertTrue(got.contains(color),
            "hue \(h)°,s\(s),v\(v) should be \(color.rawValue); got \(got.map(\.rawValue))",
            file: file, line: line)
        if let other {
            XCTAssertFalse(got.contains(other),
                "hue \(h)°,s\(s),v\(v) should NOT be \(other.rawValue); got \(got.map(\.rawValue))",
                file: file, line: line)
        }
    }

    // MARK: Band midpoints — each colorful midpoint maps to its own color.

    func testBandMidpoints() {
        let s = 0.85, v = 0.85
        assertColor(0,   s, v, is: .red)
        assertColor(30,  s, v, is: .orange)
        assertColor(55,  s, v, is: .yellow)
        assertColor(120, s, v, is: .green)
        assertColor(210, s, v, is: .blue)
        assertColor(290, s, v, is: .purple)
        assertColor(337, s, v, is: .pink)
    }

    // MARK: Every adjacent boundary — just-below vs just-at flip cleanly.
    // Band is [lower, upper): hue == upper belongs to the NEXT band.

    func testHueBoundaries() {
        let s = 0.85, v = 0.85
        // red | orange  @14
        assertColor(12, s, v, is: .red,    not: .orange)
        assertColor(16, s, v, is: .orange, not: .red)
        // orange | yellow @45
        assertColor(43, s, v, is: .orange, not: .yellow)
        assertColor(47, s, v, is: .yellow, not: .orange)
        // yellow | green @66
        assertColor(64, s, v, is: .yellow, not: .green)
        assertColor(68, s, v, is: .green,  not: .yellow)
        // green | blue @168
        assertColor(166, s, v, is: .green, not: .blue)
        assertColor(170, s, v, is: .blue,  not: .green)
        // blue | purple @252
        assertColor(250, s, v, is: .blue,   not: .purple)
        assertColor(254, s, v, is: .purple, not: .blue)
        // purple | pink @330
        assertColor(328, s, v, is: .purple, not: .pink)
        assertColor(332, s, v, is: .pink,   not: .purple)
        // pink | red (wrap) @345
        assertColor(343, s, v, is: .pink, not: .red)
        assertColor(347, s, v, is: .red,  not: .pink)
    }

    // MARK: The eggplant lesson — deep vs light magenta split at 330°.

    func testDeepMagentaIsPurpleLightMagentaIsPink() {
        // Deep, darker magenta (eggplant/plum ~315-325°) -> purple, never pink.
        assertColor(319, 0.55, 0.45, is: .purple, not: .pink)
        assertColor(310, 0.70, 0.40, is: .purple, not: .pink)
        // Bright rosy magenta above the line -> pink, never purple.
        assertColor(335, 0.50, 1.0, is: .pink, not: .purple)
    }

    // MARK: Pink as a tint — light/pale reds are pink, saturated red is not.

    func testPinkTintVsSaturatedRed() {
        // Pale, bright red reads as pink (baby pink / salmon). It ALSO satisfies
        // the lenient red band — that overlap is intended (per-color checks are
        // independent; a forgiving game would award either), so we only assert
        // the tint rule fires, not that red is excluded.
        assertColor(350, 0.25, 1.0, is: .pink)
        // The guarantee that matters: deep saturated red stays red and must NOT
        // leak into pink.
        assertColor(0, 0.90, 0.85, is: .red, not: .pink)
    }

    // MARK: White / black are brightness/saturation, independent of hue.

    func testWhiteAndBlackIgnoreHue() {
        // Near-white at any hue -> white, not the hue's chromatic color.
        for h in stride(from: 0.0, to: 360.0, by: 60.0) {
            assertColor(h, 0.05, 0.95, is: .white)
        }
        // Very dark at any hue -> black.
        for h in stride(from: 0.0, to: 360.0, by: 60.0) {
            assertColor(h, 0.80, 0.10, is: .black)
        }
        // Mid-gray is neither.
        let gray = matches(px(0, 0.0, 0.5))
        XCTAssertFalse(gray.contains(.white), "mid gray is not white")
        XCTAssertFalse(gray.contains(.black), "mid gray is not black")
    }
}
