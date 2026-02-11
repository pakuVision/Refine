//
//  AppFeature.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import ComposableArchitecture

@Reducer
struct AppFeature {
    
    @ObservableState
    struct State: Equatable {
        var route: Route = .splash
        
        enum Route: Equatable {
            case splash
            case camera(CameraFeature.State)
        }
    }
    
    enum Action {
        case onAppear
        case splashFinished
        case camera(CameraFeature.Action)
    }
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
                
            case .onAppear:
                
                return .run { send in
                    try await Task.sleep(for: .seconds(0.5))
                    await send(.splashFinished)
                }
                
            case .splashFinished:
                state.route = .camera(CameraFeature.State())
                return .none
                
            case .camera:
                return .none
            }
        }
        .ifLet(\.route.camera, action: \.camera) {
            CameraFeature()
        }
    }
}

extension AppFeature.State.Route {
    var camera: CameraFeature.State? {
        get {
            if case .camera(let state) = self {
                return state
            } else {
                return nil
            }
        }
        set {
            if let newValue {
                self = .camera(newValue)
            }
        }
    }
}
