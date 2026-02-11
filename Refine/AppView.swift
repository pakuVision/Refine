//
//  ContentView.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import SwiftUI
import ComposableArchitecture

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    var body: some View {
        switch store.state.route {
        case .splash:
            SplashView()
                .onAppear {
                    store.send(.onAppear)
                }

        case .camera:
            if let store = store.scope(state: \.route.camera, action: \.camera) {
                CameraView(store: store)
            }
            
        }
    }
}
