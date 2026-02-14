//
//  CameraFeature.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import AVFoundation
import ComposableArchitecture

@Reducer
struct CameraFeature {
    
    @ObservableState
    struct State: Equatable {
        var zoom: Zoom = .wide
        var permissionDenied = false
        var isSessionReady = false
        var lastCaptureSize: Int?
        var availableZooms: [Zoom] = []
    }
    
    enum Action {
        case onAppear
        case zoomTapped(Zoom)
        case pinchZoomChanged(CGFloat)
        case teleLockToggled(Bool)

        case shutterTapped
        case permissionResult(Bool)
        case sessionStarted
        case availableZoomsLoaded([Zoom])
        case captureResult(Result<Data, Error>)
        case photoSaved(Result<Void, Error>)
    }
    
    @Dependency(\.cameraClient) var cameraClient
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            
            switch action {
            case .onAppear:
                print("🔵 CameraFeature.onAppear")
                return .run { send in
                    print("🔵 권한 요청 중...")
                    let granted = try await cameraClient.requestPermission()
                    print("🔵 권한 결과: \(granted)")
                    await send(.permissionResult(granted))
                }

                // 권한 허용 -> 세션 시작
            case .permissionResult(true):
                print("🔵 권한 허용됨 - 세션 시작")
                return .run { send in
                    do {
                        print("🔵 startSession 호출")
                        try await cameraClient.startSession()
                        print("🔵 startSession 완료")
                        await send(.sessionStarted)
                    } catch {
                        print("❌ startSession 실패: \(error)")
                    }
                }
            case .permissionResult(false):
                print("❌ 권한 거부됨")
                state.permissionDenied = true
                return .none

            case .sessionStarted:
                print("🔵 sessionStarted")
                state.isSessionReady = true

                // 세션이 시작되면 사용 가능한 줌 레벨 로드
                return .run { send in
                    let zooms = try await cameraClient.getAvailableZooms()
                    print("🔵 사용 가능한 줌: \(zooms)")
                    await send(.availableZoomsLoaded(zooms))
                }

            case .availableZoomsLoaded(let zooms):
                state.availableZooms = zooms

                // 기본 줌이 사용 불가능하면 첫 번째 사용 가능한 줌으로 설정
                if !zooms.contains(state.zoom), let firstZoom = zooms.first {
                    state.zoom = firstZoom
                }

                return .none
                
            case .zoomTapped(let zoom):
                state.zoom = zoom
                
                return .run { send in
                    await cameraClient.setZoom(zoom.displayValue)
                }
            case .pinchZoomChanged(let factor):
                return .run { _ in
                    await cameraClient.setZoomFactor(factor)
                }
                
            case .teleLockToggled(let enabled):
                return .run { _ in
                    await cameraClient.setTeleLock(enabled)
                }
            case .shutterTapped:
                print("🔵 셔터 버튼 탭됨")
                return .run { send in
                    do {
                        print("🔵 사진 촬영 시작...")
                        let data = try await cameraClient.capture()
                        print("🔵 사진 촬영 완료: \(data.count) bytes")
                        await send(.captureResult(.success(data)))
                    } catch {
                        print("🔴 사진 촬영 실패: \(error)")
                        await send(.captureResult(.failure(error)))
                    }
                }

            case .captureResult(.success(let data)):
                state.lastCaptureSize = data.count
                print("🔵 captureResult success - 이제 저장 시작")

                return .run { send in
                    // 사진 저장
                    do {
                        try await cameraClient.saveToPhotoLibrary(data)
                        await send(.photoSaved(.success(())))
                    } catch {
                        print("🔴 saveToPhotoLibrary 호출 실패: \(error)")
                        await send(.photoSaved(.failure(error)))
                    }
                }

            case .captureResult(.failure(let error)):
                print("❌ capture error:", error)
                return .none

            case .photoSaved(.success):
                print("✅✅✅ 사진이 카메라롤에 저장되었습니다! ✅✅✅")
                return .none

            case .photoSaved(.failure(let error)):
                print("❌❌❌ 사진 저장 실패:", error)
                return .none
            }
        }
    }
}
