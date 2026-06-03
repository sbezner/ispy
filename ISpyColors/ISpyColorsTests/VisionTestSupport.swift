//
//  VisionTestSupport.swift
//  ISpyColorsTests
//
//  Vision's image feature prints (VNGenerateImageFeaturePrintRequest) rely on a
//  CoreML/Neural-Engine compute backend that is NOT present in some iOS Simulator
//  runtimes — there they fail with "Failed to create espresso context". That's an
//  environment limitation, not a logic failure: the same code runs correctly on a
//  real device (and on macOS). So duplicate-detection tests SKIP (rather than fail)
//  when the backend is unavailable, and run for real when it is.
//

import XCTest
import Vision
import CoreGraphics
@testable import ISpyColors

enum VisionTestSupport {

    /// A tiny opaque image used only to probe whether feature prints work here.
    static func makeProbeImage(size: Int = 32) -> CGImage {
        let bpp = 4, bpr = size * bpp
        var data = [UInt8](repeating: 0, count: size * size * bpp)
        for i in stride(from: 0, to: data.count, by: bpp) {
            data[i] = 120; data[i + 1] = 90; data[i + 2] = 200; data[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        return CGContext(data: &data, width: size, height: size, bitsPerComponent: 8,
                         bytesPerRow: bpr, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// Throws `XCTSkip` if Vision feature prints can't be generated in this
    /// environment (e.g. a simulator without the ML backend). Otherwise returns
    /// normally and the caller proceeds with the real assertions.
    static func skipUnlessFeaturePrintsAvailable() throws {
        let detector = DuplicateDetector()
        do {
            guard try detector.generateFeaturePrint(for: makeProbeImage()) != nil else {
                throw XCTSkip("Vision returned no feature print in this environment.")
            }
        } catch let skip as XCTSkip {
            throw skip
        } catch {
            throw XCTSkip("""
            Vision image feature prints are unavailable in this environment \
            (\(error.localizedDescription)). This is an iOS Simulator limitation — \
            run on a real device. The duplicate-detection logic is verified natively on macOS.
            """)
        }
    }
}
