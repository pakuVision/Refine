//
//  Zoom.swift
//  Refine
//
//  Created by boardguy.vision on 2026/02/09.
//

import Foundation

enum Zoom: CaseIterable, Equatable {
    case x0_5
    case x1
    case x2
    case x4
    case x8

    var value: CGFloat {
        switch self {
        case .x0_5: return 0.5
        case .x1:   return 1
        case .x2:   return 2
        case .x4:   return 4
        case .x8:   return 8
        }
    }

    var title: String {
        switch self {
        case .x0_5: return "0.5"
        case .x1:   return "1"
        case .x2:   return "2"
        case .x4:   return "4"
        case .x8:   return "8"
        }
    }
}
