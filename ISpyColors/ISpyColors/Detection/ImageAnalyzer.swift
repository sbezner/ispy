//
//  ImageAnalyzer.swift
//  ISpyColors
//
//  Bridges a captured photo (CGImage) into the PURE color world of
//  ColorDetector. This is the ONLY place CoreGraphics touches the color path,
//  keeping ColorDetector.swift framework-free and portable.
//
//  Responsibilities:
//   - Downsample the photo to ~100x100 (cheap, on-device).
//   - Read raw RGBA bytes and convert to [RGBPixel] (normalized 0...1).
//   - Hand off to ColorDetector for the actual decision.
//

import CoreGraphics
import Foundation

public struct ImageAnalyzer {

    /// Edge length we downsample to before per-pixel color analysis.
    /// ~100x100 = 10k pixels: plenty for a color decision, trivial to process.
    public var sampleSize: Int

    /// The pure color decision engine. Swap thresholds here to tune sensitivity.
    public var detector: ColorDetector

    public init(sampleSize: Int = 100, detector: ColorDetector = ColorDetector()) {
        self.sampleSize = sampleSize
        self.detector = detector
    }

    /// Downsample `image` and decide whether it contains the target color.
    /// Returns nil only if the image can't be rasterized.
    public func analyze(_ image: CGImage, target: GameColor) -> ColorAnalysis? {
        guard let pixels = Self.downsampledPixels(from: image, edge: sampleSize) else {
            return nil
        }
        return detector.analyze(pixels: pixels,
                                width: sampleSize,
                                height: sampleSize,
                                target: target)
    }

    /// Render `image` into a `edge`x`edge` RGBA8 bitmap and return its pixels
    /// row-major as normalized RGBPixels.
    static func downsampledPixels(from image: CGImage, edge: Int) -> [RGBPixel]? {
        let width = edge
        let height = edge
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        var raw = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        // Draw INSIDE the pointer's valid scope — the CGContext must not outlive
        // the buffer it writes into.
        let ok: Bool = raw.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo) else {
                return false
            }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }

        var pixels = [RGBPixel]()
        pixels.reserveCapacity(width * height)
        var i = 0
        while i < raw.count {
            let r = Double(raw[i]) / 255.0
            let g = Double(raw[i + 1]) / 255.0
            let b = Double(raw[i + 2]) / 255.0
            pixels.append(RGBPixel(r: r, g: g, b: b))
            i += bytesPerPixel
        }
        return pixels
    }
}
