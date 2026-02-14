//
//  CameraClient.swift
//  Refine
//

import ComposableArchitecture
import AVFoundation
import Photos
import UIKit

@DependencyClient
struct CameraClient {
    var requestPermission: @Sendable () async throws -> Bool
    var startSession: @Sendable () async throws -> Void
    var setZoom: @Sendable (CGFloat) async -> Void
    var capture: @Sendable () async throws -> Data
    var getSession: @Sendable () -> AVCaptureSession = { AVCaptureSession() }
    var saveToPhotoLibrary: @Sendable (Data) async throws -> Void
    var getAvailableZooms: @Sendable () async throws -> [Zoom]
}

extension DependencyValues {
    var cameraClient: CameraClient {
        get { self[CameraClient.self] }
        set { self[CameraClient.self] = newValue }
    }
}

extension CameraClient: DependencyKey {

    @MainActor
    private static let sharedController = CameraController()

    static var liveValue: CameraClient {
        CameraClient(

            // MARK: - Camera Permission

            requestPermission: {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    return true
                case .notDetermined:
                    return await AVCaptureDevice.requestAccess(for: .video)
                default:
                    return false
                }
            },

            // MARK: - Start Session

            startSession: {
                try await sharedController.start()
            },

            // MARK: - Zoom

            setZoom: { value in
                await sharedController.setZoomButton(value)
            },

            // MARK: - Capture (48MP HEIF)

            capture: {
                try await sharedController.captureProcessed()
            },

            // MARK: - Get Session

            getSession: {
                sharedController.session
            },

            // MARK: - Save Photo

            saveToPhotoLibrary: { data in
                try await savePhotoToLibrary(data)
            },

            // MARK: - Zoom Levels

            getAvailableZooms: {
                var zooms: [Zoom] = []

                if sharedController.hasUltraWide {
                    zooms.append(.ultraWide)
                }

                zooms.append(contentsOf: [
                    .wide,
                    .tele(2),
                    .tele(4),
                    .tele(8)
                ])

                return zooms
            }
        )
    }

    // MARK: - Save to Photo Library

    @MainActor
    private static func savePhotoToLibrary(_ imageData: Data) async throws {

        guard UIImage(data: imageData) != nil else {
            throw CameraError.captureFailed
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        guard status == .authorized || status == .limited else {
            throw CameraError.photoLibraryPermissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: imageData, options: nil)
        }

        print("✅ 48MP 사진 저장 완료")
    }
}
