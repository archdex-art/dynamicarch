import AVFoundation
import SwiftUI

/// Front-camera mirror. The capture session is created lazily and torn down the
/// moment the tab closes so the camera light never stays on.
struct MirrorView: NSViewRepresentable {
    final class PreviewView: NSView {
        let session = AVCaptureSession()
        private var layerAdded = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func startSession() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted else { return }
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let self else { return }
                    if !self.layerAdded {
                        self.session.beginConfiguration()
                        self.session.sessionPreset = .high
                        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                            ?? AVCaptureDevice.default(for: .video),
                           let input = try? AVCaptureDeviceInput(device: device),
                           self.session.canAddInput(input) {
                            self.session.addInput(input)
                        }
                        self.session.commitConfiguration()
                        DispatchQueue.main.async {
                            let preview = AVCaptureVideoPreviewLayer(session: self.session)
                            preview.videoGravity = .resizeAspectFill
                            preview.frame = self.bounds
                            preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
                            // Mirror it: a mirror that is not mirrored is a camera.
                            preview.transform = CATransform3DMakeScale(-1, 1, 1)
                            self.layer?.addSublayer(preview)
                            self.layerAdded = true
                        }
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                }
            }
        }

        func stopSession() {
            DispatchQueue.global(qos: .utility).async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        override func layout() {
            super.layout()
            layer?.sublayers?.forEach { $0.frame = bounds }
        }
    }

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.startSession()
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    static func dismantleNSView(_ nsView: PreviewView, coordinator: ()) {
        nsView.stopSession()
    }
}
