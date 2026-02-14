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

    /// 각 단일 렌즈의 내부 줌 팩터 (핀치 제스처 동기화용)
    var internalZoomFactor: CGFloat {
        switch self {
        case .ultraWide:
            return 1.0  // Ultra Wide 기본
        case .wide:
            return 1.0  // Wide 기본
        case .tele(let value):
            switch value {
            case 2.0: return 2.0  // Wide 렌즈에서 2배 디지털 줌
            case 4.0: return 1.0  // Tele 렌즈 기본
            case 8.0: return 2.0  // Tele 렌즈에서 2배 디지털 줌
            default: return 1.0
            }
        }
    }
}
