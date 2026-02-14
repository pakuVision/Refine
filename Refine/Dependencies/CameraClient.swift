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
    var setZoomFactor: @Sendable (CGFloat) async -> Void
    var setTeleLock: @Sendable (Bool) async -> Void
    var capture: @Sendable () async throws -> Data
    var getSession: () -> AVCaptureSession = { AVCaptureSession() }
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

    private static let sharedController = CameraController()

    static var liveValue: CameraClient {
        CameraClient(

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

            startSession: {
                try await sharedController.start()
            },

            setZoom: { value in
                await sharedController.setZoomButton(value)
            },

            setZoomFactor: { factor in
                await sharedController.setZoomFactor(factor)
            },
            setTeleLock: { enabled in
                await sharedController.setTeleLock(enabled)
            },
            capture: {
                try await sharedController.capture()
            },

            getSession: {
                sharedController.session
            },

            saveToPhotoLibrary: { data in
                try await savePhotoToLibrary(data)
            },

            getAvailableZooms: {
                [.ultraWide, .wide, .tele(2), .tele(4), .tele(8)]
            }
        )
    }

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
    }
}
