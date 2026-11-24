import AppKit
import SwiftUI

/// Folio 视觉设计令牌（Apple Books × Things 3 原生书店极简美学）
enum FolioTheme {
    /// 宣纸暖白 / 静谧炭黑主画布色
    static let canvasBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.095, green: 0.095, blue: 0.105, alpha: 1.0)
        }
        return NSColor(calibratedRed: 0.980, green: 0.976, blue: 0.962, alpha: 1.0)
    })

    /// 卡片与检视器浮层表面色
    static let cardSurface = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.135, green: 0.135, blue: 0.150, alpha: 1.0)
        }
        return NSColor(calibratedRed: 1.0, green: 0.999, blue: 0.996, alpha: 1.0)
    })

    /// 次级胶囊与筛选栏微沉背景
    static let subtleFill = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 1.0, alpha: 0.06)
        }
        return NSColor(calibratedRed: 0.35, green: 0.31, blue: 0.25, alpha: 0.06)
    })

    /// 克制细边框线
    static let hairlineBorder = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedWhite: 1.0, alpha: 0.09)
        }
        return NSColor(calibratedRed: 0.20, green: 0.18, blue: 0.15, alpha: 0.09)
    })

    /// 主强调色（沉稳靛青书签色）
    static let accent = Color(red: 0.18, green: 0.38, blue: 0.56)

    /// 书籍封面标准宽高比（2:3 精装书比例）
    static let coverAspectRatio: CGFloat = 2.0 / 3.0

    /// 8 套学院派莫兰迪精装布面封面色板
    struct ClothPalette: Sendable {
        let top: Color
        let bottom: Color
        let accent: Color
    }

    static let clothPalettes: [ClothPalette] = [
        ClothPalette(
            top: Color(red: 0.21, green: 0.30, blue: 0.38),
            bottom: Color(red: 0.14, green: 0.21, blue: 0.28),
            accent: Color(red: 0.85, green: 0.77, blue: 0.62)
        ),
        ClothPalette(
            top: Color(red: 0.26, green: 0.36, blue: 0.31),
            bottom: Color(red: 0.17, green: 0.26, blue: 0.22),
            accent: Color(red: 0.86, green: 0.82, blue: 0.70)
        ),
        ClothPalette(
            top: Color(red: 0.44, green: 0.24, blue: 0.23),
            bottom: Color(red: 0.30, green: 0.15, blue: 0.15),
            accent: Color(red: 0.91, green: 0.82, blue: 0.69)
        ),
        ClothPalette(
            top: Color(red: 0.42, green: 0.33, blue: 0.24),
            bottom: Color(red: 0.29, green: 0.22, blue: 0.16),
            accent: Color(red: 0.92, green: 0.85, blue: 0.72)
        ),
        ClothPalette(
            top: Color(red: 0.28, green: 0.27, blue: 0.38),
            bottom: Color(red: 0.19, green: 0.18, blue: 0.27),
            accent: Color(red: 0.84, green: 0.81, blue: 0.91)
        ),
        ClothPalette(
            top: Color(red: 0.25, green: 0.28, blue: 0.29),
            bottom: Color(red: 0.16, green: 0.18, blue: 0.19),
            accent: Color(red: 0.82, green: 0.84, blue: 0.83)
        ),
        ClothPalette(
            top: Color(red: 0.38, green: 0.31, blue: 0.35),
            bottom: Color(red: 0.26, green: 0.20, blue: 0.24),
            accent: Color(red: 0.90, green: 0.82, blue: 0.84)
        ),
        ClothPalette(
            top: Color(red: 0.20, green: 0.35, blue: 0.37),
            bottom: Color(red: 0.13, green: 0.24, blue: 0.26),
            accent: Color(red: 0.82, green: 0.89, blue: 0.86)
        ),
    ]

    /// 根据书名与 ID 确定性选取封面书布色板
    static func palette(for seed: String) -> ClothPalette {
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        let index = Int(hash % UInt64(clothPalettes.count))
        return clothPalettes[index]
    }

    /// 文件格式语义色（克制柔和）
    static func formatTint(for ext: String) -> Color {
        switch ext.lowercased() {
        case "epub":
            return Color(red: 0.18, green: 0.50, blue: 0.36)
        case "pdf":
            return Color(red: 0.72, green: 0.25, blue: 0.22)
        case "mobi", "azw3":
            return Color(red: 0.68, green: 0.44, blue: 0.16)
        case "fb2", "djvu":
            return Color(red: 0.35, green: 0.36, blue: 0.62)
        default:
            return Color(red: 0.38, green: 0.41, blue: 0.46)
        }
    }
}
