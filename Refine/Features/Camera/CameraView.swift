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
    @State private var gestureBaseZoom: CGFloat = 1.0  // 기본 줌 = Wide 렌즈 내부 줌
    @State private var zoomRange: ClosedRange<CGFloat> = 1.0...40.0


    var body: some View {

        ZStack {
            CameraPreviewView(session: cameraClient.getSession())
                .ignoresSafeArea()

            // 플래시 효과
            if showFlash {
                Color.white.opacity(0.5)
                    .ignoresSafeArea()
            }

            VStack {
                Spacer()
                zoomButtons
                
                HStack {
                    Button {
                        store.send(.teleLockToggled(true))
                    } label: {
                        Text("Tele Lock")
                            .foregroundColor(.yellow)
                    }
                    
                    Button {
                        store.send(.teleLockToggled(false))
                    } label: {
                        Text("Auto")
                            .foregroundColor(.white)
                    }
                }
                shutterButton
            }
        }
        .gesture(
            // 제스처는 value = 1.0 부터시작
            MagnificationGesture()
                .onChanged { value in
                    let clampedZoom = self.clampedZoom(value)
                    
                    Task {
                        // Factor - 곱셈계수
                        // zoom factor - 줌곱셈계수를 셋팅
                        await cameraClient.setZoomFactor(clampedZoom)
                    }
                }
                .onEnded { value in
                    // 핀치가 끝난 시점에서 다시 시작하도록 값을 보유
                    gestureBaseZoom = self.clampedZoom(value)
                }
        )
        .onChange(of: store.zoom) {
            Task {
                if let range = await cameraClient.getZoomRange() {
                    zoomRange = range
                }
            }
        }
        .onAppear {
            print("🔵 CameraView.onAppear")
            store.send(.onAppear)
        }
    }

    private var zoomButtons: some View {
        HStack(spacing: 30) {
            // 사용 가능한 줌만 표시
            ForEach(store.availableZooms, id: \.self) { zoom in
                Button {
                    store.send(.zoomTapped(zoom))
                    // 🔥 각 렌즈의 내부 줌으로 동기화 (핀치 제스처 자연스럽게)
                    gestureBaseZoom = self.clampedZoom(zoom.internalZoomFactor)
                } label: {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Text(zoom.title)
                                .foregroundColor(store.zoom == zoom ? .yellow : .white)
                                .font(.system(size: 13, weight: .regular))
                        }
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

extension CameraView {
    // clamped - 어떤 값을 일정 범위 안에 "고정하다"
    // 핀치제스처를 설정한 범위내의 값으로 줌 인아웃 하도록
    private func clampedZoom(_ valueOfMagnification: CGFloat) -> CGFloat {
        let rawZoom = gestureBaseZoom * valueOfMagnification
        
        // rawZoom이 zoomRange를 벗어나지 못하게 함
        let clampedZoom = min(
                            // 1.0                    // 40.0
            max(rawZoom,zoomRange.lowerBound), zoomRange.upperBound
        )
        return clampedZoom
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

        layer.videoGravity = .resizeAspect

        // 🎯 초기 frame은 layoutSubviews에서 설정됨
        layer.frame = .zero

        self.layer.addSublayer(layer)
        self.previewLayer = layer

        // 디버그 로그
        print("📹 PreviewLayer 생성됨")
        print("   - Session running: \(session.isRunning)")
        print("   - Inputs: \(session.inputs.count)")
        print("   - Outputs: \(session.outputs.count)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 🎯 레이아웃 시 프레임 업데이트
        previewLayer?.frame = bounds

        if bounds != .zero {
            print("📐 PreviewLayer frame 업데이트: \(bounds)")
        }
    }

    /// session이 바뀌었을 때만 교체
    func updateSessionIfNeeded(_ session: AVCaptureSession) {
        guard previewLayer?.session !== session else { return }

        print("🔄 Session 교체")
        previewLayer?.session = session
        setNeedsLayout()
    }
}
