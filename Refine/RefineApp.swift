//
//  RefineApp.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import SwiftUI
import ComposableArchitecture

@main
struct RefineApp: App {
    let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
    var body: some Scene {
        WindowGroup {
            AppView(store: store)
        }
    }
}
