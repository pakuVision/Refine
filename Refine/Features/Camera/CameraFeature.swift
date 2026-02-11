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
        var zoom: Zoom = .x1
        var permissionDenied = false
        var isSessionReady = false
        var lastCaptureSize: Int?
    }
    
    enum Action {
        case onAppear
        case zoomTapped(Zoom)
        case shutterTapped
        case permissionResult(Bool)
        case sessionStarted
        case captureResult(Result<Data, Error>)
        case photoSaved(Result<Void, Error>)
    }
    
    @Dependency(\.cameraClient) var cameraClient
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            
            switch action {
            case .onAppear:
                return .run { send in
                    let granted = try await cameraClient.requestPermission()
                    await send(.permissionResult(granted))
                }
                
                // 권한 허용 -> 세션 시작
            case .permissionResult(true):
                return .run { send in
                    try await cameraClient.startSession()
                    await send(.sessionStarted)
                }
            case .permissionResult(false):
                state.permissionDenied = true
                return .none
                
            case .sessionStarted:
                state.isSessionReady = true
                return .none
                
            case .zoomTapped(let zoom):
                state.zoom = zoom
                
                return .run { send in
                    await cameraClient.setZoom(zoom.value)
                }
                
            case .shutterTapped:
                return .run { send in
                    do {
                        let data = try await cameraClient.capture()
                        await send(.captureResult(.success(data)))
                    } catch {
                        await send(.captureResult(.failure(error)))
                    }
                }

            case .captureResult(.success(let data)):
                state.lastCaptureSize = data.count

                return .run { send in
                    // 사진 저장
                    do {
                        try await cameraClient.saveToPhotoLibrary(data)
                        await send(.photoSaved(.success(())))
                    } catch {
                        await send(.photoSaved(.failure(error)))
                    }
                }

            case .captureResult(.failure(let error)):
                print("❌ capture error:", error)
                return .none

            case .photoSaved(.success):
                print("✅ 사진이 카메라롤에 저장되었습니다")
                return .none

            case .photoSaved(.failure(let error)):
                print("❌ 사진 저장 실패:", error)
                return .none
            }
        }
    }
}
