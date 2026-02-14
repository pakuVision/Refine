//
//  CameraController.swift
//  Refine
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
    private var inFlightDelegate: PhotoCaptureDelegate?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // MARK: - Start Session

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

        guard session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            throw CameraError.cannotAddOutput
        }

        session.addInput(input)
        session.addOutput(photoOutput)

        photoOutput.isAppleProRAWEnabled = true
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        currentInput = input

        configureMaxResolution(for: wide)

        session.commitConfiguration()

        sessionQueue.async {
            self.session.startRunning()
        }
    }

    // MARK: - 최대 해상도 자동 설정

    private func configureMaxResolution(for device: AVCaptureDevice) {

        let supported = device.activeFormat.supportedMaxPhotoDimensions

        var maxDim: CMVideoDimensions?
        var maxPixels = 0

        for dim in supported {
            let pixels = Int(dim.width) * Int(dim.height)
            if pixels > maxPixels {
                maxPixels = pixels
                maxDim = dim
            }
        }

        if let maxDim {
            photoOutput.maxPhotoDimensions = maxDim

            let mp = Double(maxDim.width * maxDim.height) / 1_000_000
            print("📸 현재 렌즈 최대 해상도: \(maxDim.width)x\(maxDim.height) (~\(String(format: "%.1f", mp))MP)")
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

    // MARK: - Zoom & Lens

    func setZoomButton(_ value: CGFloat) async {

        switch value {
        case 0.5:
            await switchTo(device: ultraWide, zoom: 1.0)
        case 1:
            await switchTo(device: wide, zoom: 1.0)
        case 2:
            await switchTo(device: wide, zoom: 2.0)
        case 4:
            await switchTo(device: tele, zoom: 1.0)
        case 8:
            await switchTo(device: tele, zoom: 2.0)
        default:
            break
        }
    }

    private func switchTo(device: AVCaptureDevice?, zoom: CGFloat) async {

        guard let device else { return }

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
            
            device.exposureMode = .continuousAutoExposure
            await device.setExposureTargetBias(0.2)

            device.whiteBalanceMode = .continuousAutoWhiteBalance
            device.focusMode = .continuousAutoFocus
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            device.videoZoomFactor = min(zoom, device.activeFormat.videoMaxZoomFactor)
            device.unlockForConfiguration()
        } catch {
            print("❌ zoom error:", error)
        }

        configureMaxResolution(for: device)
    }

    // MARK: - Capture

    func capture() async throws -> Data {

        return try await withCheckedThrowingContinuation { cont in

            let delegate = PhotoCaptureDelegate { [weak self] result in
                self?.inFlightDelegate = nil
                cont.resume(with: result)
            }

            self.inFlightDelegate = delegate

            let settings: AVCapturePhotoSettings

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [
                    AVVideoCodecKey: AVVideoCodecType.hevc
                ])
            } else {
                settings = AVCapturePhotoSettings()
            }

            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
            settings.isHighResolutionPhotoEnabled = true
            settings.isAutoStillImageStabilizationEnabled = true
            settings.flashMode = .off

            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    var hasUltraWide: Bool {
        ultraWide != nil
    }
}

// MARK: - Delegate

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

        print("✅ 촬영 완료: \(data.count) bytes")
        completion(.success(data))
    }
}
