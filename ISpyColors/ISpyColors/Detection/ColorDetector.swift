//
//  ColorDetector.swift
//  ISpyColors
//
//  PURE, TESTABLE COLOR LOGIC.
//
//  This file intentionally imports nothing but Foundation and uses NO Apple
//  UI/imaging frameworks (no UIKit, no Vision, no CoreGraphics). Everything here
//  operates on plain arrays of normalized RGB pixels. That keeps the color logic
//  portable: the same algorithm could be re-implemented on Android with minimal
//  rework, and it can be unit-tested without a camera or a device.
//
//  The bridge from a captured photo -> [RGBPixel] lives in the camera/analysis
//  layer (see ImageAnalyzer.swift), NOT here.
//

import Foundation

// MARK: - Palette

/// The fixed, kid-friendly palette the game spies for.
public enum GameColor: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, white, black

    public var id: String { rawValue }

    /// Word shown to the player ("BLUE").
    public var displayName: String { rawValue.uppercased() }
}

// MARK: - Pixel & HSV value types

/// A single pixel with each channel normalized to 0...1.
public struct RGBPixel: Equatable, Sendable {
    public let r: Double
    public let g: Double
    public let b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Convenience initializer from 0...255 integer channels.
    public init(r255: Int, g255: Int, b255: Int) {
        self.init(r: Double(r255) / 255.0,
                  g: Double(g255) / 255.0,
                  b: Double(b255) / 255.0)
    }
}

/// Hue (0..<360), Saturation (0...1), Value/Brightness (0...1).
public struct HSV: Equatable, Sendable {
    public let h: Double
    public let s: Double
    public let v: Double

    public init(h: Double, s: Double, v: Double) {
        self.h = h
        self.s = s
        self.v = v
    }
}

// MARK: - Result

/// Outcome of analyzing a grid of pixels against a target color.
public struct ColorAnalysis: Equatable, Sendable {
    /// Fraction of all pixels (0...1) that fall inside the target color's bands.
    public let matchFraction: Double
    /// Fraction of all pixels (0...1) belonging to the single largest contiguous
    /// blob of matching pixels. This is what separates "a real object" from
    /// "scattered colored noise".
    public let largestBlobFraction: Double
    /// True if the image passes the color check for the target color.
    public let passed: Bool
}

// MARK: - Detector

/// Decides whether a downsampled image contains a meaningful region of a target
/// color. Pure value type — construct it with the thresholds you want and call
/// `analyze`.
public struct ColorDetector: Sendable {

    // ---- TUNABLE THRESHOLD #1 of 2: COLOR % ----
    // The single most important knob for color sensitivity. README points here.
    /// Minimum fraction of the image (0...1) that must match the target color
    /// for a PASS. Default ≈ 8%.
    public var minMatchFraction: Double

    /// Minimum fraction of the image (0...1) that the *largest contiguous blob*
    /// of matching pixels must cover. Guards against scattered noise passing.
    public var minBlobFraction: Double

    /// For chromatic colors, the minimum saturation a pixel needs to count as
    /// "colorful" rather than gray.
    public var minChromaSaturation: Double

    /// For chromatic colors, the minimum brightness a pixel needs (rejects near-black).
    public var minChromaValue: Double

    // Defaults are intentionally LENIENT: a small patch of the color anywhere in
    // a busy photo should count, and a wide range of shades (pale → deep) of a
    // color should all match. Tighten these if matching feels too loose.
    public init(minMatchFraction: Double = 0.03,
                minBlobFraction: Double = 0.02,
                minChromaSaturation: Double = 0.20,
                minChromaValue: Double = 0.18) {
        self.minMatchFraction = minMatchFraction
        self.minBlobFraction = minBlobFraction
        self.minChromaSaturation = minChromaSaturation
        self.minChromaValue = minChromaValue
    }

    // MARK: RGB -> HSV

    /// Convert a normalized RGB pixel to HSV. Pure math, no frameworks.
    public func hsv(from p: RGBPixel) -> HSV {
        let maxC = max(p.r, max(p.g, p.b))
        let minC = min(p.r, min(p.g, p.b))
        let delta = maxC - minC

        var h = 0.0
        if delta > 0 {
            if maxC == p.r {
                h = 60.0 * (((p.g - p.b) / delta).truncatingRemainder(dividingBy: 6.0))
            } else if maxC == p.g {
                h = 60.0 * (((p.b - p.r) / delta) + 2.0)
            } else {
                h = 60.0 * (((p.r - p.g) / delta) + 4.0)
            }
        }
        if h < 0 { h += 360.0 }

        let s = maxC == 0 ? 0.0 : delta / maxC
        let v = maxC
        return HSV(h: h, s: s, v: v)
    }

    // MARK: Per-pixel membership

    /// Does a single pixel belong to `color`?
    ///
    /// White / black / gray are decided by saturation + brightness (NOT hue),
    /// exactly as the spec requires. Chromatic colors are decided by hue band,
    /// gated by saturation/brightness so we don't match washed-out grays.
    public func pixel(_ p: RGBPixel, matches color: GameColor) -> Bool {
        let c = hsv(from: p)

        switch color {
        case .white:
            // Low saturation, bright. Relaxed so off-whites/pale things count.
            return c.s <= 0.22 && c.v >= 0.72
        case .black:
            // Dark, regardless of hue. Relaxed so deep shadows/charcoal count.
            return c.v <= 0.28
        default:
            // Chromatic: must be colorful and not too dark.
            guard c.s >= minChromaSaturation, c.v >= minChromaValue else { return false }
            return Self.hueBand(color).contains(c.h)
        }
    }

    /// Hue window (degrees) for each chromatic color. White/black are handled
    /// separately and return an empty band here.
    static func hueBand(_ color: GameColor) -> HueBand {
        switch color {
        case .red:    return HueBand(lower: 345, upper: 15)   // wraps around 0
        case .orange: return HueBand(lower: 15, upper: 45)
        case .yellow: return HueBand(lower: 45, upper: 70)
        case .green:  return HueBand(lower: 70, upper: 170)
        case .blue:   return HueBand(lower: 170, upper: 260)
        case .purple: return HueBand(lower: 260, upper: 295)
        case .pink:   return HueBand(lower: 295, upper: 345)
        case .white, .black: return HueBand(lower: 0, upper: 0)
        }
    }

    // MARK: Whole-image analysis

    /// Analyze a row-major grid of pixels (`width * height == pixels.count`)
    /// for the target color. Counts matches and measures the largest contiguous
    /// matching blob via 4-connected flood fill.
    public func analyze(pixels: [RGBPixel],
                        width: Int,
                        height: Int,
                        target: GameColor) -> ColorAnalysis {
        let total = width * height
        guard total > 0, pixels.count >= total else {
            return ColorAnalysis(matchFraction: 0, largestBlobFraction: 0, passed: false)
        }

        // 1. Build a match mask.
        var mask = [Bool](repeating: false, count: total)
        var matchCount = 0
        for i in 0..<total where pixel(pixels[i], matches: target) {
            mask[i] = true
            matchCount += 1
        }

        let matchFraction = Double(matchCount) / Double(total)

        // 2. Largest connected component (4-connectivity) via iterative flood fill.
        let largestBlob = Self.largestConnectedComponent(mask: mask,
                                                          width: width,
                                                          height: height)
        let blobFraction = Double(largestBlob) / Double(total)

        // 3. PASS requires enough total color AND a contiguous blob.
        let passed = matchFraction >= minMatchFraction && blobFraction >= minBlobFraction

        return ColorAnalysis(matchFraction: matchFraction,
                             largestBlobFraction: blobFraction,
                             passed: passed)
    }

    // MARK: Connected components

    /// Returns the size (in pixels) of the largest 4-connected blob of `true`
    /// cells. Iterative stack-based flood fill — no recursion, safe for 100x100+.
    static func largestConnectedComponent(mask: [Bool], width: Int, height: Int) -> Int {
        var visited = [Bool](repeating: false, count: mask.count)
        var best = 0
        var stack = [Int]()
        stack.reserveCapacity(mask.count)

        for start in 0..<mask.count {
            guard mask[start], !visited[start] else { continue }

            var size = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true

            while let idx = stack.popLast() {
                size += 1
                let x = idx % width
                let y = idx / width

                // Left
                if x > 0 {
                    let n = idx - 1
                    if mask[n], !visited[n] { visited[n] = true; stack.append(n) }
                }
                // Right
                if x < width - 1 {
                    let n = idx + 1
                    if mask[n], !visited[n] { visited[n] = true; stack.append(n) }
                }
                // Up
                if y > 0 {
                    let n = idx - width
                    if mask[n], !visited[n] { visited[n] = true; stack.append(n) }
                }
                // Down
                if y < height - 1 {
                    let n = idx + width
                    if mask[n], !visited[n] { visited[n] = true; stack.append(n) }
                }
            }

            if size > best { best = size }
        }
        return best
    }
}

// MARK: - HueBand

/// A hue window in degrees that may wrap around the 0/360 boundary (for red).
public struct HueBand: Equatable, Sendable {
    public let lower: Double
    public let upper: Double

    public init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    /// True if `h` (0..<360) falls inside this band. Handles wrap-around when
    /// lower > upper (e.g. red: 345 -> 15).
    public func contains(_ h: Double) -> Bool {
        if lower <= upper {
            return h >= lower && h < upper
        } else {
            return h >= lower || h < upper
        }
    }
}
