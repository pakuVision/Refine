//
//  Zoom.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import Foundation
import AVFoundation

enum Zoom: Equatable, Hashable {
    case ultraWide
    case wide
    case tele(CGFloat)   // 예: 4.0, 5.0

    var displayValue: CGFloat {
        switch self {
        case .ultraWide: return 0.5
        case .wide: return 1.0
        case .tele(let value): return value
        }
    }

    var title: String {
        switch self {
        case .ultraWide: return "0.5"
        case .wide: return "1"
        case .tele(let value):
            return String(format: "%.0f", value)
        }
    }
}
