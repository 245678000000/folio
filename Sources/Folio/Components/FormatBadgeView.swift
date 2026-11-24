import SwiftUI

/// 电子书文件格式柔和语义胶囊
struct FormatBadgeView: View {
    let fileExtension: String
    var sizeText: String = ""

    private var label: String {
        let clean = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return clean.isEmpty ? "FILE" : clean
    }

    private var tint: Color {
        FolioTheme.formatTint(for: fileExtension)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
            if !sizeText.isEmpty {
                Text("· \(sizeText)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.11))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
        )
    }
}
