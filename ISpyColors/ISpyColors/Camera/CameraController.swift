//
//  CameraController.swift
//  ISpyColors
//
//  Owns the AVCaptureSession + AVCapturePhotoOutput. Uses the rear camera and a
//  live preview. Survives backgrounding/foregrounding cleanly: the session is
//  stopped when the app resigns active and restarted when it becomes active,
//  and all session mutation happens on a dedicated serial queue (Apple's
//  requirement) so the UI never blocks.
//

import AVFoundation
import CoreGraphics
import Foundation
import UIKit

@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status: Equatable {
        case unconfigured
        case authorized
        case denied
        case failed
    }

    // `session` and `photoOutput` are deliberately confined to `sessionQueue`
    // (Apple's requirement). They're marked nonisolated(unsafe) so the serial-
    // queue closures can touch them without tripping strict-concurrency checks;
    // serialization through `sessionQueue` is what actually makes that safe.
    /// Live capture session the preview layer renders.
    nonisolated(unsafe) let session = AVCaptureSession()

    @Published private(set) var status: Status = .unconfigured
    @Published private(set) var isCapturing = false

    private let sessionQueue = DispatchQueue(label: "com.ispycolors.camera.session")
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    private var configured = false

    /// Continuation used to deliver a captured photo back to the async caller.
    private var captureContinuation: CheckedContinuation<CGImage?, Never>?

    // MARK: Permission + configuration

    /// Ask for camera permission (if needed) and configure the session once.
    func prepare() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            status = granted ? .authorized : .denied
        default:
            status = .denied
        }

        guard status == .authorized else { return }
        configureIfNeeded()
        start()
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Rear camera.
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                       for: .video,
                                                       position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in self.status = .failed }
                return
            }
            self.session.addInput(input)

            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                Task { @MainActor in self.status = .failed }
                return
            }
            self.session.addOutput(self.photoOutput)
            self.photoOutput.maxPhotoQualityPrioritization = .balanced
            self.session.commitConfiguration()
        }
    }

    // MARK: Lifecycle (background/foreground safe)

    func start() {
        guard status == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    // MARK: Capture

    /// Capture a single photo and return it as a CGImage (nil on failure).
    func capturePhoto() async -> CGImage? {
        guard status == .authorized, !isCapturing else { return nil }
        isCapturing = true
        defer { isCapturing = false }

        // Call capturePhoto on the main actor (this method's isolation). We avoid
        // hopping to sessionQueue here precisely so the non-Sendable
        // CheckedContinuation isn't captured across a queue boundary. capturePhoto
        // is safe to invoke off the session queue; the delegate callback resumes
        // the continuation back on the main actor.
        let image: CGImage? = await withCheckedContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
        return image
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        // Convert to an orientation-corrected CGImage off the main actor, then
        // resume the awaiting capture call on the main actor.
        let cgImage: CGImage? = {
            guard error == nil,
                  let data = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: data) else { return nil }
            return uiImage.normalizedCGImage()
        }()

        Task { @MainActor in
            self.captureContinuation?.resume(returning: cgImage)
            self.captureContinuation = nil
        }
    }
}

// MARK: - Orientation helper

private extension UIImage {
    /// Returns a CGImage with the UIImage's orientation baked in (so downstream
    /// pixel reads see the image the way the user framed it).
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let redrawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return redrawn.cgImage
    }
}
