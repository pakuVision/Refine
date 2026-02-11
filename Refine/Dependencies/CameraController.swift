//
//  CameraController.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import AVFoundation

@MainActor
final class CameraController {
    
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var device: AVCaptureDevice?
    private var inFlightDelegate: AVCapturePhotoCaptureDelegate?
    
    func start() async throws {
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard let device = AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: .back
            ) else {
                session.commitConfiguration()
                throw CameraError.deviceNotFound
            }

            self.device = device

            // 🔴 중복 추가 방지 (재호출 대비)
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                throw CameraError.cannotAddInput
            }
            session.addInput(input)

            guard session.canAddOutput(photoOutput) else {
                session.commitConfiguration()
                throw CameraError.cannotAddOutput
            }
            session.addOutput(photoOutput)

            session.commitConfiguration()

            if !session.isRunning {
                session.startRunning()
            }
        }
    
    func setZoom(_ zoom: CGFloat) async {
        guard let device else { return }
        
        do {
            try device.lockForConfiguration()
            let clamped = min(max(zoom, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("❌ zoom error:", error)
        }
    }
    
    func capture() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let delegate = PhotoCaptureDelegate { result in
                // delegate 생명주기 정리
                self.inFlightDelegate = nil
                cont.resume(with: result)
            }
            self.inFlightDelegate = delegate
            
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
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
