#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

/// 生成 macOS 原生风格 Folio 应用图标集（.iconset）
guard CommandLine.arguments.count >= 2 else {
    fputs("用法: generate_icon.swift <输出 iconset 目录路径>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func renderIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("无法创建 CGContext")
    }

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS 图标内边距（留出标准视觉边距）
    let margin = size * 0.095
    let cardRect = CGRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let cornerRadius = cardRect.width * 0.225
    let bgPath = CGPath(roundedRect: cardRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // 图标底座柔投影
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: size * 0.036,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.26)
    )
    ctx.addPath(bgPath)
    ctx.setFillColor(CGColor(red: 0.14, green: 0.25, blue: 0.36, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 靛青深海渐变底板
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.21, green: 0.38, blue: 0.54, alpha: 1.0),
            CGColor(red: 0.11, green: 0.20, blue: 0.30, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
        end: CGPoint(x: cardRect.midX, y: cardRect.minY),
        options: []
    )

    // 顶部柔和环境光晕
    let glowGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.65, green: 0.82, blue: 0.96, alpha: 0.18),
            CGColor(red: 0.65, green: 0.82, blue: 0.96, alpha: 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.35, y: cardRect.maxY * 0.92),
        startRadius: 0,
        endCenter: CGPoint(x: cardRect.midX, y: cardRect.midY),
        endRadius: cardRect.width * 0.85,
        options: []
    )
    ctx.restoreGState()

    // 内高光细边
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(max(1, size * 0.004))
    ctx.strokePath()
    ctx.restoreGState()

    // 居中极简精装书本主体
    let bookW = cardRect.width * 0.50
    let bookH = cardRect.height * 0.64
    let bookX = cardRect.midX - bookW / 2
    let bookY = cardRect.midY - bookH / 2
    let bookRect = CGRect(x: bookX, y: bookY, width: bookW, height: bookH)
    let bookRadius = bookW * 0.095
    let bookPath = CGPath(roundedRect: bookRect, cornerWidth: bookRadius, cornerHeight: bookRadius, transform: nil)

    // 书本投影 + 宣纸白封面
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -size * 0.02),
        blur: size * 0.045,
        color: CGColor(red: 0.03, green: 0.06, blue: 0.10, alpha: 0.42)
    )
    ctx.addPath(bookPath)
    ctx.setFillColor(CGColor(red: 0.985, green: 0.978, blue: 0.955, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 书本渐变纸感与左侧装帧书脊
    ctx.saveGState()
    ctx.addPath(bookPath)
    ctx.clip()

    let paperGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 0.995, green: 0.990, blue: 0.972, alpha: 1.0),
            CGColor(red: 0.935, green: 0.918, blue: 0.875, alpha: 1.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        paperGradient,
        start: CGPoint(x: bookRect.minX, y: bookRect.maxY),
        end: CGPoint(x: bookRect.maxX, y: bookRect.minY),
        options: []
    )

    // 左侧书脊色带
    let spineWidth = bookW * 0.145
    let spineRect = CGRect(x: bookRect.minX, y: bookRect.minY, width: spineWidth, height: bookH)
    ctx.setFillColor(CGColor(red: 0.16, green: 0.27, blue: 0.39, alpha: 0.20))
    ctx.fill(spineRect)

    // 书脊折痕竖线
    ctx.setFillColor(CGColor(red: 0.12, green: 0.20, blue: 0.29, alpha: 0.18))
    ctx.fill(CGRect(x: bookRect.minX + spineWidth, y: bookRect.minY, width: max(1, size * 0.004), height: bookH))

    // 鎏金装帧横线与极简书页排版线条
    let contentX = bookRect.minX + spineWidth + bookW * 0.12
    let contentW = bookW - spineWidth - bookW * 0.24

    // 顶部暖金短标识线
    ctx.setFillColor(CGColor(red: 0.80, green: 0.56, blue: 0.24, alpha: 1.0))
    let accentBar = CGRect(x: contentX, y: bookRect.maxY - bookH * 0.22, width: contentW * 0.42, height: max(2, bookH * 0.032))
    ctx.addPath(CGPath(roundedRect: accentBar, cornerWidth: accentBar.height / 2, cornerHeight: accentBar.height / 2, transform: nil))
    ctx.fillPath()

    // 两条优雅抽象书名排版线
    ctx.setFillColor(CGColor(red: 0.18, green: 0.25, blue: 0.33, alpha: 0.82))
    let line1 = CGRect(x: contentX, y: bookRect.maxY - bookH * 0.34, width: contentW, height: max(2, bookH * 0.042))
    ctx.addPath(CGPath(roundedRect: line1, cornerWidth: line1.height / 2, cornerHeight: line1.height / 2, transform: nil))
    ctx.fillPath()

    let line2 = CGRect(x: contentX, y: bookRect.maxY - bookH * 0.43, width: contentW * 0.72, height: max(2, bookH * 0.036))
    ctx.setFillColor(CGColor(red: 0.18, green: 0.25, blue: 0.33, alpha: 0.42))
    ctx.addPath(CGPath(roundedRect: line2, cornerWidth: line2.height / 2, cornerHeight: line2.height / 2, transform: nil))
    ctx.fillPath()

    // 右上角垂下的朱红书签丝带
    let ribbonW = bookW * 0.14
    let ribbonH = bookH * 0.26
    let ribbonX = bookRect.maxX - bookW * 0.24
    let ribbonTop = bookRect.maxY + 1
    let ribbonBottom = ribbonTop - ribbonH
    let ribbonPath = CGMutablePath()
    ribbonPath.move(to: CGPoint(x: ribbonX, y: ribbonTop))
    ribbonPath.addLine(to: CGPoint(x: ribbonX + ribbonW, y: ribbonTop))
    ribbonPath.addLine(to: CGPoint(x: ribbonX + ribbonW, y: ribbonBottom))
    ribbonPath.addLine(to: CGPoint(x: ribbonX + ribbonW * 0.5, y: ribbonBottom + ribbonW * 0.42))
    ribbonPath.addLine(to: CGPoint(x: ribbonX, y: ribbonBottom))
    ribbonPath.closeSubpath()
    ctx.addPath(ribbonPath)
    ctx.setFillColor(CGColor(red: 0.79, green: 0.31, blue: 0.24, alpha: 1.0))
    ctx.fillPath()

    ctx.restoreGState()

    guard let cgImage = ctx.makeImage() else {
        fatalError("无法生成 CGImage")
    }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("无法编码 PNG 数据")
    }
    return pngData
}

let iconSpecs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in iconSpecs {
    let data = renderIcon(pixelSize: spec.pixels)
    let fileURL = outputDir.appendingPathComponent(spec.name)
    try data.write(to: fileURL)
}
print("图标集已生成：\(outputDir.path)")
