//
//  CameraClient.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
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
    var getAvailableZooms: @Sendable () async throws -> [Zoom] = { [] }
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

            // ✅ 렌즈 고정용
            setZoom: { value in
                await sharedController.setZoomButton(value)
            },

            capture: {
                try await sharedController.captureProcessed()
            },

            getSession: {
                sharedController.session
            },

            saveToPhotoLibrary: { data in
                try await savePhotoToLibrary(data)
            },

            // ✅ 사용 가능한 줌 레벨 동적 반환
            getAvailableZooms: {
                var zooms: [Zoom] = []

                // Ultra Wide 카메라가 있으면 0.5x 추가
                if await sharedController.hasUltraWide {
                    zooms.append(.ultraWide)
                }

                // 기본 줌 레벨
                zooms.append(contentsOf: [
                    .wide,          // 1x
                    .tele(2),       // 2x (Wide 2x)
                    .tele(4),       // 4x (Tele 기본)
                    .tele(8)        // 8x (Tele 2배)
                ])

                return zooms
            }
        )
    }

    // MARK: - Save Photo

    @MainActor
    private static func savePhotoToLibrary(_ imageData: Data) async throws {
        print("📸 [1/3] 사진 저장 시작 (크기: \(imageData.count) bytes)")

        // 데이터 유효성 확인
        guard UIImage(data: imageData) != nil else {
            print("❌ 이미지 데이터가 손상되었습니다")
            throw CameraError.captureFailed
        }

        // 권한 요청
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        print("📸 [2/3] Photo Library 권한 상태: \(status.rawValue) (\(statusDescription(status)))")

        guard status == .authorized || status == .limited else {
            print("❌ Photo Library 권한 거부됨")
            throw CameraError.photoLibraryPermissionDenied
        }

        // 📸 원본 데이터를 직접 저장 (메타데이터 보존)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let creationRequest = PHAssetCreationRequest.forAsset()
                creationRequest.addResource(with: .photo, data: imageData, options: nil)
            }
            print("✅ [3/3] 사진이 메타데이터와 함께 저장되었습니다!")
        } catch {
            print("❌ Photo Library 저장 실패: \(error.localizedDescription)")
            throw error
        }
    }

    private static func statusDescription(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .limited: return "limited"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }
}
