//
//  CameraClient.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import ComposableArchitecture
import Foundation
import AVFoundation
import Photos

@DependencyClient
struct CameraClient {
    var requestPermission: @Sendable () async throws -> Bool
    var startSession: @Sendable () async throws -> Void
    var setZoom: @Sendable (CGFloat) async -> Void
    var capture: @Sendable () async throws -> Data
    var getSession: @Sendable () -> AVCaptureSession = { AVCaptureSession() }
    var saveToPhotoLibrary: @Sendable (Data) async throws -> Void
}

extension DependencyValues {
    var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}

extension CameraClient: DependencyKey {

    // 🎯 shared controller를 사용하여 View와 Client가 같은 session 공유
    @MainActor
    private static let sharedController = CameraController()

    static var liveValue: CameraClient {
        return CameraClient(
            requestPermission: {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: return true
                case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
                default: return false
                }
            },
            startSession: {
                try await sharedController.start()
            },
            setZoom: { zoom in
                await sharedController.setZoom(zoom)
            },
            capture: {
                try await sharedController.capture()
            },
            getSession: {
                sharedController.session
            },
            saveToPhotoLibrary: { data in
                try await savePhotoToLibrary(data)
            }
        )
    }
   
    // 사진을 Photo Library에 저장
    private static func savePhotoToLibrary(_ imageData: Data) async throws {
        // Photo Library 권한 요청
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        guard status == .authorized || status == .limited else {
            throw CameraError.photoLibraryPermissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
        }
    }
}

enum CameraError: Error {
  case deviceNotFound
  case cannotAddInput
  case cannotAddOutput
  case captureFailed
  case photoLibraryPermissionDenied
}
