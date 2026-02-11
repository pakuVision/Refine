//
//  CameraView.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import SwiftUI
import AVFoundation
import ComposableArchitecture

struct CameraView: View {
    let store: StoreOf<CameraFeature>
    @Dependency(\.cameraClient) var cameraClient
    @State private var showFlash: Bool = false
    
    var body: some View {

        ZStack {
            CameraPreviewView(session: cameraClient.getSession())
                .ignoresSafeArea()

            // 플래시 효과
            if showFlash {
                Color.white.opacity(0.6)
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()
                zoomButtons
                shutterButton
            }
        }
        .animation(.easeOut(duration: 0.1), value: showFlash)
        .onAppear {
            store.send(.onAppear)
        }
    }
    
    private var zoomButtons: some View {
        HStack(spacing: 16) {
            ForEach(Zoom.allCases, id: \.self) { zoom in
                Button {
                    store.send(.zoomTapped(zoom))
                } label: {
                    Text(zoom.title)
                        .foregroundColor(store.state.zoom == zoom ? .yellow : .white)
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
        .padding(.bottom, 20)
    }

    private var shutterButton: some View {
        Button {
            store.send(.shutterTapped)
            
            Task {
                withAnimation(.easeOut.speed(0.1)) {
                    showFlash = true
                }
                try await Task.sleep(nanoseconds: 100_000_000)
                withAnimation(.easeIn) {
                    showFlash = false
                }
            }
            
        } label: {
            Circle()
                .strokeBorder(.white, lineWidth: 4)
                .frame(width: 72, height: 72)
        }
    }
}

/// AVCaptureSession을 받아서
/// AVCaptureVideoPreviewLayer로 렌더링만 담당하는 View
struct CameraPreviewView: UIViewRepresentable {

    /// ⚠️ session은 View가 소유하지 않는다
    /// CameraController가 소유한 것을 참조만 한다
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        PreviewUIView(session: session)
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // session 교체가 필요한 경우만 대응
        uiView.updateSessionIfNeeded(session)
    }
}

@MainActor
final class PreviewUIView: UIView {

    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        configurePreviewLayer(with: session)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configurePreviewLayer(with session: AVCaptureSession) {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds

        self.layer.addSublayer(layer)
        self.previewLayer = layer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }

    /// session이 바뀌었을 때만 교체
    func updateSessionIfNeeded(_ session: AVCaptureSession) {
        guard previewLayer?.session !== session else { return }
        previewLayer?.session = session
        setNeedsLayout()
    }
}
