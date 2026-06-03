//
//  DuplicateDetector.swift
//  ISpyColors
//
//  Wraps Vision's image feature prints to answer one question:
//  "Have we already photographed this object this session?"
//
//  Design notes:
//   - generateFeaturePrint(...) and distance(...) are split so the comparison
//     threshold is an explicit parameter -> testable and tunable.
//   - The detector itself holds NO session state; the session's stored feature
//     prints live in the GameViewModel and are passed in. That keeps the game's
//     "new game clears everything" rule trivial to honor.
//

import Foundation
import Vision

public struct DuplicateResult {
    /// True if the candidate matches a previously stored object this session.
    public let isDuplicate: Bool
    /// Smallest distance found against the stored prints (lower = more similar).
    /// nil when there were no stored prints to compare against.
    public let nearestDistance: Float?
}

public struct DuplicateDetector {

    // ---- TUNABLE THRESHOLD #2 of 2: DUPLICATE DISTANCE ----
    // If the nearest stored feature print is CLOSER than this, it's a duplicate.
    // Vision feature-print distances are typically ~0 for identical images and
    // grow with visual difference. README points here.
    /// Distance below which two feature prints are considered the same object.
    public var duplicateThreshold: Float

    public init(duplicateThreshold: Float = 0.30) {
        self.duplicateThreshold = duplicateThreshold
    }

    /// Generate a Vision feature print for an image. Throws if Vision can't
    /// process the image. Returns nil if Vision produced no observation.
    public func generateFeaturePrint(for image: CGImage) throws -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return request.results?.first as? VNFeaturePrintObservation
    }

    /// Distance between two feature prints (lower = more similar).
    public func distance(_ a: VNFeaturePrintObservation,
                         _ b: VNFeaturePrintObservation) throws -> Float {
        var d = Float(0)
        try a.computeDistance(&d, to: b)
        return d
    }

    /// Compare `candidate` against all `stored` prints from this session.
    /// Returns whether it's a duplicate and the nearest distance observed.
    public func evaluate(candidate: VNFeaturePrintObservation,
                         against stored: [VNFeaturePrintObservation]) -> DuplicateResult {
        var nearest: Float?
        for print in stored {
            guard let d = try? distance(candidate, print) else { continue }
            if nearest == nil || d < nearest! {
                nearest = d
            }
        }
        let isDup = (nearest != nil) && (nearest! < duplicateThreshold)
        return DuplicateResult(isDuplicate: isDup, nearestDistance: nearest)
    }
}
