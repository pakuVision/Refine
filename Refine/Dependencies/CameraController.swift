import AVFoundation
import Photos

enum CameraError: Error {
    case deviceNotFound
    case cannotAddInput
    case cannotAddOutput
    case captureFailed
    case photoLibraryPermissionDenied
}

final class CameraController: @unchecked Sendable {

    // Exposed for preview
    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()

    private var device: AVCaptureDevice?
    private var currentInput: AVCaptureDeviceInput?

    private var tripleDevice: AVCaptureDevice?
    private var ultraWideDevice: AVCaptureDevice?
    private var wideDevice: AVCaptureDevice?
    private var teleDevice: AVCaptureDevice?

    private var isTeleLocked = false
    private var inFlightDelegate: PhotoCaptureDelegate?

    private let sessionQueue = DispatchQueue(label: "camera.session.queue")

    // MARK: - Public

    func start() async throws {
        try await runOnSessionQueue {
            // Virtual device 사용 (자동 렌즈 전환)
            let initialDevice =
                AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) ??
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

            guard let initialDevice else { throw CameraError.deviceNotFound }

            self.tripleDevice = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back)
            self.ultraWideDevice = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
            self.wideDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            self.teleDevice = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)

            self.device = initialDevice

            // 2) session configure
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            let input = try AVCaptureDeviceInput(device: initialDevice)
            guard self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                throw CameraError.cannotAddInput
            }
            guard self.session.canAddOutput(self.photoOutput) else {
                self.session.commitConfiguration()
                throw CameraError.cannotAddOutput
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.currentInput = input

            // 3) quality
            self.photoOutput.maxPhotoQualityPrioritization = .quality

            // 4) 모든 렌즈의 48MP 포맷 미리 설정 (전환 속도 향상)
            if let ultraWide = self.ultraWideDevice {
                self.applyBest48MPFormatIfPossible(to: ultraWide)
            }
            if let wide = self.wideDevice {
                self.applyBest48MPFormatIfPossible(to: wide)
            }
            if let tele = self.teleDevice {
                self.applyBest48MPFormatIfPossible(to: tele)
            }

            // 5) 현재 디바이스의 maxPhotoDimensions 설정
            self.syncMaxPhotoDimensions(for: initialDevice)

            self.session.commitConfiguration()

            // 6) start running (already on background sessionQueue)
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func setTeleLock(_ enabled: Bool) async {
        await runOnSessionQueueNoThrow {
            guard let triple = self.tripleDevice,
                  let tele = self.teleDevice else { return }

            if enabled {
                self.isTeleLocked = true
                self.switchInputLocked(to: tele)

                // Tele에서도 48MP 지원하면 포맷 재선택 + max dims 동기화
                self.applyBest48MPFormatIfPossible(to: tele)
                self.syncMaxPhotoDimensions(for: tele)

                self.configureContinuousAFIfPossible(device: tele)
            } else {
                self.isTeleLocked = false
                self.switchInputLocked(to: triple)

                // virtual triple 복귀 후 Wide로 맞춤
                self.setVirtualToWideIfPossible(device: triple)

                // (virtual device에도 48MP 포맷이 있으면 다시 적용)
                self.applyBest48MPFormatIfPossible(to: triple)
                self.syncMaxPhotoDimensions(for: triple)
            }
        }
    }

    func setZoomButton(_ value: CGFloat) async {
        await runOnSessionQueueNoThrow {
            if self.isTeleLocked {
                // Tele Lock: 망원 렌즈 내부 디지털 줌만
                guard let device = self.device,
                      device.deviceType == .builtInTelephotoCamera else { return }

                let target: CGFloat
                switch value {
                case 4.0: target = 1.0
                case 8.0: target = 2.0
                default: return
                }
                self.setZoomLocked(device: device, zoom: target)
                return
            }

            // 🔥 Auto 모드: 버튼마다 단일 렌즈로 전환 (순정 카메라 방식)
            var targetDevice: AVCaptureDevice?
            var internalZoom: CGFloat = 1.0

            switch value {
            case 0.5:
                targetDevice = self.ultraWideDevice
                internalZoom = 1.0
            case 1.0:
                targetDevice = self.wideDevice
                internalZoom = 1.0
            case 2.0:
                targetDevice = self.wideDevice
                internalZoom = 2.0
            case 4.0:
                targetDevice = self.teleDevice
                internalZoom = 1.0
            case 8.0:
                targetDevice = self.teleDevice
                internalZoom = 2.0
            default:
                targetDevice = self.wideDevice
                internalZoom = 1.0
            }

            guard let newDevice = targetDevice else { return }

            // 같은 디바이스면 줌만 변경
            if self.device === newDevice {
                self.setZoomLocked(device: newDevice, zoom: internalZoom)
                return
            }

            // 🔥 빠른 전환: 모든 작업을 하나의 configuration 블록에서 처리
            self.session.beginConfiguration()

            // 1) Input 교체
            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.currentInput = newInput
                    self.device = newDevice

                    // 2) 줌 설정 (configuration 안에서)
                    try newDevice.lockForConfiguration()
                    newDevice.videoZoomFactor = internalZoom
                    newDevice.unlockForConfiguration()

                    // 3) MaxPhotoDimensions 동기화
                    let supported = newDevice.activeFormat.supportedMaxPhotoDimensions
                    if let best = supported.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) {
                        self.photoOutput.maxPhotoDimensions = best
                    }
                }
            } catch {
                // 실패 시 원래대로 복구
            }

            self.session.commitConfiguration()
        }
    }

    func setZoomFactor(_ factor: CGFloat) async {
        await runOnSessionQueueNoThrow {
            guard let device = self.device else { return }
            self.setZoomLocked(device: device, zoom: factor)
        }
    }

    func capture() async throws -> Data {
        // 🔥 촬영 직전에 48MP 포맷 재적용
        await runOnSessionQueueNoThrow {
            guard let device = self.device else { return }

            print("📸 촬영 준비 중...")
            print("   - Device: \(device.deviceType.rawValue)")
            print("   - Zoom: \(device.videoZoomFactor)")

            // 현재 줌 레벨에서 48MP 포맷 재적용
            self.applyBest48MPFormatIfPossible(to: device)
            self.syncMaxPhotoDimensions(for: device)
        }

        return try await withCheckedThrowingContinuation { continuation in

            let delegate = PhotoCaptureDelegate { [weak self] result in
                self?.inFlightDelegate = nil
                continuation.resume(with: result)
            }

            self.inFlightDelegate = delegate

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

            let dims = settings.maxPhotoDimensions
            let mp = Double(dims.width * dims.height) / 1_000_000.0
            print("   - 설정 해상도: \(dims.width)x\(dims.height) (~\(String(format: "%.1f", mp))MP)")

            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
    
    func getZoomRange() async -> ClosedRange<CGFloat>? {
        await runOnSessionQueueNoThrowReturn {
            guard let device = self.device else { return nil }

            let minZoom = device.minAvailableVideoZoomFactor
            let hardwareMax = device.activeFormat.videoMaxZoomFactor
            let maxZoom = min(hardwareMax, 40.0)

            return minZoom...maxZoom
        }
    }

    // MARK: - Private (sessionQueue only)

    private func runOnSessionQueueNoThrowReturn<T>(
        _ work: @escaping () -> T
    ) async -> T {
        await withCheckedContinuation { cont in
            sessionQueue.async {
                cont.resume(returning: work())
            }
        }
    }
    
    private func switchInputLocked(to newDevice: AVCaptureDevice) {
        self.session.beginConfiguration()

        if let currentInput {
            self.session.removeInput(currentInput)
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            guard self.session.canAddInput(newInput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(newInput)
            self.currentInput = newInput
            self.device = newDevice
        } catch {
            self.session.commitConfiguration()
            return
        }

        self.session.commitConfiguration()
    }

    private func setZoomLocked(device: AVCaptureDevice, zoom: CGFloat) {
        let minZoom = device.minAvailableVideoZoomFactor
        
        let hardwareMax = device.activeFormat.videoMaxZoomFactor
        let maxZoom = min(hardwareMax, 40.0)
      
        let finalZoom = min(max(zoom, minZoom), maxZoom)

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = finalZoom
            device.unlockForConfiguration()
        } catch {
            // ignore
        }
    }

    private func setVirtualToWideIfPossible(device: AVCaptureDevice) {
        guard let wideSwitch = device.virtualDeviceSwitchOverVideoZoomFactors.first else { return }
        // 경계 튐 방지용으로 살짝 안쪽으로
        let zoom = CGFloat(wideSwitch.doubleValue + 0.01)
        self.setZoomLocked(device: device, zoom: zoom)
    }

    private func applyBest48MPFormatIfPossible(to device: AVCaptureDevice) {
        var bestFormat: AVCaptureDevice.Format?
        var bestPixels = 0

        for format in device.formats {
            for dim in format.supportedMaxPhotoDimensions {
                let pixels = Int(dim.width) * Int(dim.height)
                let mp = Double(pixels) / 1_000_000.0
                if mp >= 48.0 && pixels > bestPixels {
                    bestPixels = pixels
                    bestFormat = format
                }
            }
        }

        guard let bestFormat else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = bestFormat
            device.unlockForConfiguration()
        } catch {
            // Silent fail
        }
    }

    private func syncMaxPhotoDimensions(for device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        guard let best = supported.max(by: { ($0.width * $0.height) < ($1.width * $1.height) }) else { return }
        self.photoOutput.maxPhotoDimensions = best
    }

    private func configureContinuousAFIfPossible(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            device.isSubjectAreaChangeMonitoringEnabled = true
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            device.unlockForConfiguration()
        } catch {
            // ignore
        }
    }

    private func captureLocked() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                self?.inFlightDelegate = nil
                cont.resume(with: result)
            }
            self.inFlightDelegate = delegate

            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            settings.flashMode = .off

            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Queue bridges

    private func runOnSessionQueue<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            sessionQueue.async {
                do { cont.resume(returning: try work()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private func runOnSessionQueueNoThrow(_ work: @escaping () -> Void) async {
        await withCheckedContinuation { cont in
            sessionQueue.async {
                work()
                cont.resume()
            }
        }
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

        // 🔍 실제 촬영된 해상도 확인
        let dims = photo.resolvedSettings.photoDimensions
        let mp = Double(dims.width * dims.height) / 1_000_000.0
        let sizeMB = Double(data.count) / 1_000_000.0

        print("✅ 촬영 완료")
        print("   - 해상도: \(dims.width)x\(dims.height) (~\(String(format: "%.1f", mp))MP)")
        print("   - 파일 크기: \(String(format: "%.2f", sizeMB))MB")

        completion(.success(data))
    }
}

