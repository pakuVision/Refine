//
//  SplashView.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//
import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Camera")
                .foregroundColor(.white)
                .font(.largeTitle.bold())
        }
    }
}
