import FolioCore
import SwiftUI

/// 简洁高可读性书籍列表视图
struct BookListView: View {
    @Bindable var appState: AppState
    let books: [Book]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(books, id: \.ref) { book in
                    BookListRow(
                        book: book,
                        isSelected: appState.selectedBook?.ref == book.ref && appState.isInspectorPresented,
                        isSaved: appState.isSaved(book),
                        showHistoryDate: appState.selectedNav == .downloaded,
                        onSelect: { appState.inspect(book: book) },
                        onToggleSave: { appState.toggleSaved(book) },
                        onDownload: { appState.startDownload(book: book) },
                        onDeleteHistory: appState.selectedNav == .downloaded
                            ? { appState.deleteCloudHistoryRecord(book) }
                            : nil
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            if appState.hasMorePages {
                HStack {
                    Spacer()
                    Button {
                        Task { await appState.loadNextPage() }
                    } label: {
                        if appState.isLoadingMore {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("加载更多（第 \(appState.currentPage) / \(appState.totalPages) 页）")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.isLoadingMore)
                    Spacer()
                }
                .padding(.bottom, 24)
            }
        }
    }
}

private struct BookListRow: View {
    let book: Book
    let isSelected: Bool
    let isSaved: Bool
    let showHistoryDate: Bool
    let onSelect: () -> Void
    let onToggleSave: () -> Void
    let onDownload: () -> Void
    let onDeleteHistory: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            BookCoverView(book: book, cornerRadius: 5, showShadow: false, compact: true)
                .frame(width: 40, height: 60)

            VStack(alignment: .leading, spacing: 3.5) {
                Text(book.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                let subline = [book.authors, book.publisher].filter { !$0.isEmpty }.joined(separator: " · ")
                if !subline.isEmpty {
                    Text(subline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if !book.year.isEmpty {
                        Text(book.year)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    if !book.language.isEmpty {
                        Text(book.language.capitalized)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    if showHistoryDate, let date = book.historyDate, !date.isEmpty {
                        Text("下载于 \(date)")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 12)

            if !book.displayExtension.isEmpty {
                FormatBadgeView(fileExtension: book.fileExtension, sizeText: book.formattedSize)
            }

            HStack(spacing: 4) {
                Button(action: onToggleSave) {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isSaved ? Color.orange : Color.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(isSaved ? "取消收藏" : "加入收藏")

                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(FolioTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("下载电子书")
            }
            .opacity(isHovered || isSelected || isSaved ? 1.0 : 0.65)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? FolioTheme.accent.opacity(0.10) : (isHovered ? FolioTheme.cardSurface : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isSelected ? FolioTheme.accent.opacity(0.35) : (isHovered ? FolioTheme.hairlineBorder : Color.clear),
                    lineWidth: 0.75
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("查看详情", systemImage: "info.circle", action: onSelect)
            Button("立即下载", systemImage: "arrow.down.circle", action: onDownload)
            Button(isSaved ? "取消收藏" : "加入云端收藏", systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onToggleSave)
            if let onDeleteHistory {
                Divider()
                Button("删除云端下载记录", systemImage: "trash", role: .destructive, action: onDeleteHistory)
            }
        }
    }
}
