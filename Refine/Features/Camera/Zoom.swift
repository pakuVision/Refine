//
//  Zoom.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import Foundation

enum Zoom: Equatable, Hashable {
    case ultraWide
    case wide
    case tele(CGFloat)

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

    /// 실제 카메라 줌 팩터 (렌즈 전환 지점 기준)
    /// 렌즈 전환 지점: [2.0, 8.0]
    var actualZoomFactor: CGFloat {
        switch self {
        case .ultraWide:
            return 1.0  // 🔥 Ultra Wide 최소 줌 (순정 0.5x와 동일)
        case .wide:
            return 2.0  // Wide 메인 (전환 지점)
        case .tele(let value):
            // 2x → 4.0 (Wide 영역)
            // 4x → 8.0 (Tele 전환 지점)
            // 8x → 16.0 (Tele 영역)
            switch value {
            case 2.0: return 4.0
            case 4.0: return 8.0
            case 8.0: return 16.0
            default: return value * 2.0  // 기본 매핑
            }
        }
    }
}
