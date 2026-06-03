//
//  CameraPreviewView.swift
//  ISpyColors
//
//  SwiftUI wrapper around an AVCaptureVideoPreviewLayer. The underlying UIView
//  hosts the preview layer and keeps it sized to the view's bounds.
//

import AVFoundation
import SwiftUI
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }

    /// A UIView whose backing layer IS the AVCaptureVideoPreviewLayer, so it
    /// resizes automatically with the view.
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
