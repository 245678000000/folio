import AppKit
import FolioCore
import SwiftUI

/// 精致书封视图：支持真实封面异步缓存加载 + 无图时的实体精装书排版占位封
struct BookCoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 7
    var showShadow: Bool = true
    var compact: Bool = false

    @State private var loadedImage: NSImage?

    private var palette: FolioTheme.ClothPalette {
        FolioTheme.palette(for: "\(book.id)-\(book.title)")
    }

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                typographicClothCover
            }

            // 模拟真实实体精装书左侧微弱书脊折痕与顶部微高光
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.24),
                        Color.white.opacity(0.14),
                        Color.black.opacity(0.08),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: compact ? 5 : 9)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        }
        .aspectRatio(FolioTheme.coverAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
        )
        .shadow(
            color: showShadow ? Color.black.opacity(0.16) : .clear,
            radius: showShadow ? (compact ? 3 : 8) : 0,
            x: 0,
            y: showShadow ? (compact ? 2 : 5) : 0
        )
        .task(id: book.coverURL) {
            loadedImage = nil
            guard !book.coverURL.isEmpty else { return }
            let fetched = await CoverImageCache.shared.image(for: book.coverURL)
            if !Task.isCancelled {
                loadedImage = fetched
            }
        }
    }

    /// 实体精装书布质感排版封面
    private var typographicClothCover: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // 细雅装帧内框
            if !compact {
                RoundedRectangle(cornerRadius: max(3, cornerRadius - 3), style: .continuous)
                    .strokeBorder(palette.accent.opacity(0.28), lineWidth: 0.75)
                    .padding(8)
            }

            VStack(alignment: .leading, spacing: compact ? 3 : 6) {
                // 顶部装帧金线
                Rectangle()
                    .fill(palette.accent.opacity(0.75))
                    .frame(width: compact ? 12 : 22, height: compact ? 1.5 : 2)

                Text(book.title)
                    .font(.system(size: compact ? 9 : 13.5, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.95))
                    .lineLimit(compact ? 3 : 4)
                    .multilineTextAlignment(.leading)

                if !compact && !book.subtitle.isEmpty {
                    Text(book.subtitle)
                        .font(.system(size: 9.5, weight: .regular))
                        .foregroundStyle(palette.accent.opacity(0.82))
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                if !compact {
                    VStack(alignment: .leading, spacing: 2) {
                        if !book.authors.isEmpty {
                            Text(book.authors)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(1)
                        }
                        if !book.year.isEmpty || !book.displayExtension.isEmpty {
                            Text([book.year, book.displayExtension].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                                .foregroundStyle(palette.accent.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.leading, compact ? 8 : 16)
            .padding(.trailing, compact ? 6 : 13)
            .padding(.vertical, compact ? 7 : 15)
        }
    }
}
