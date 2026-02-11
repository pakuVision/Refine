//
//  CameraController.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import AVFoundation
import Photos
enum CameraError: Error {
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    case captureFailed
    case photoLibraryPermissionDenied
}

final class CameraController {

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    private var ultraWide: AVCaptureDevice?
    private var wide: AVCaptureDevice?
    private var tele: AVCaptureDevice?

    private var currentInput: AVCaptureDeviceInput?

    // 📸 delegate를 강하게 유지 (중요!)
    private var inFlightDelegate: PhotoCaptureDelegate?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    private let processor = AppleAIImageProcessor()
    private let visionProcessor = VisionNeuralProcessor()

    func start() async throws {
        discoverDevices()

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let wide else {
            session.commitConfiguration()
            throw CameraError.deviceNotFound
        }

        let input = try AVCaptureDeviceInput(device: wide)
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw CameraError.cannotAddInput
        }

        session.addInput(input)
        session.addOutput(photoOutput)

        photoOutput.maxPhotoQualityPrioritization = .quality
        photoOutput.isAppleProRAWEnabled = false

        currentInput = input

        session.commitConfiguration()

        // ✅ 전용 큐에서 실행
        sessionQueue.async {
            self.session.startRunning()
        }
    }

    // MARK: - Device Discovery
    
    private func discoverDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        for device in discovery.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                ultraWide = device
            case .builtInWideAngleCamera:
                wide = device
            case .builtInTelephotoCamera:
                tele = device
            default:
                break
            }
        }
    }

    // MARK: - Lens Selection

    func setZoomButton(_ value: CGFloat) async {
        switch value {
        case 0.5:
            await useUltraWide(zoom: 1.0)
        case 1:
            await useWide(zoom: 1.0)
        case 2:
            await useWide(zoom: 2.0)
        case 4:
            await useTele(zoom: 1.0)
        case 8:
            await useTele(zoom: 2.0)
        default:
            break
        }
    }

    // MARK: - Ultra Wide

    private func useUltraWide(zoom: CGFloat) async {
        guard let ultraWide else { return }
        await switchTo(device: ultraWide, zoom: zoom)
    }

    // MARK: - Wide
    
    private func useWide(zoom: CGFloat) async {
        guard let wide else { return }
        await switchTo(device: wide, zoom: zoom)
    }

    // MARK: - Tele
    
    private func useTele(zoom: CGFloat) async {
        guard let tele else { return }
        await switchTo(device: tele, zoom: zoom)
    }

    // MARK: - Switch Core
    
    private func switchTo(device: AVCaptureDevice, zoom: CGFloat) async {
        session.beginConfiguration()

        if let currentInput {
            session.removeInput(currentInput)
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)
            currentInput = input
        } catch {
            print("❌ input error:", error)
        }

        session.commitConfiguration()

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoom
            device.unlockForConfiguration()
        } catch {
            print("❌ zoom set error:", error)
        }
    }

    // MARK: - Capture
    
    /// 원본 캡처 (처리 없음)
    func captureRaw() async throws -> Data {
        return try await capture()
    }
    
    /// 캡처 + 자동 처리
    func captureProcessed() async throws -> Data {
        print("📸 CameraController.captureProcessed() 호출됨")
        
        // 1. 원본 캡처
        let rawData = try await capture()
        print("📸 원본 캡처 완료: \(rawData.count) bytes")
        
        // 2. 이미지 처리
        print("🎨 이미지 처리 시작...")
        let processedData = try await visionProcessor.process(rawData)
        print("✅ 이미지 처리 완료: \(processedData.count) bytes")
        
        return processedData
    }
    
    func capture() async throws -> Data {
        print("📸 CameraController.capture() 호출됨")
        print("📸 세션 실행 중: \(session.isRunning)")
        print("📸 현재 디바이스: \(currentInput?.device.localizedName ?? "없음")")
        print("📸 현재 디바이스 타입: \(currentInput?.device.deviceType.rawValue ?? "없음")")

        return try await withCheckedThrowingContinuation { cont in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                print("📸 PhotoCaptureDelegate 콜백 호출됨")
                // delegate 생명주기 정리
                self?.inFlightDelegate = nil
                cont.resume(with: result)
            }

            // delegate를 강하게 유지 (매우 중요!)
            self.inFlightDelegate = delegate

            // 📸 최고 품질 HEIF 촬영 설정
            let settings: AVCapturePhotoSettings

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                // HEIF 코덱으로 최고 품질 촬영
                settings = AVCapturePhotoSettings(format: [
                    AVVideoCodecKey: AVVideoCodecType.hevc
                ])
                print("📸 HEIF 최고 품질로 촬영")
            } else {
                // 기본 포맷
                settings = AVCapturePhotoSettings()
                print("📸 기본 JPEG 포맷으로 촬영")
            }


            // 플래시 비활성화 (자동 노출 최적화)
            settings.flashMode = .off

            print("📸 capturePhoto 호출 (무손실 설정)")
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Device Info

    /// Ultra Wide 카메라 사용 가능 여부
    var hasUltraWide: Bool {
        ultraWide != nil
    }
}

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    typealias Completion = (Result<Data, Error>) -> Void
    private let completion: Completion

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraError.captureFailed))
            return
        }
        completion(.success(data))
    }
}
