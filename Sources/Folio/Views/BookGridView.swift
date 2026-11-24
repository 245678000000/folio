import FolioCore
import SwiftUI

/// 极简书店封面网格视图（宽敞留白 + 实体精装书封悬停抬升动效）
struct BookGridView: View {
    @Bindable var appState: AppState
    let books: [Book]

    private let columns = [
        GridItem(.adaptive(minimum: 152, maximum: 184), spacing: 24, alignment: .top),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                ForEach(books, id: \.ref) { book in
                    BookGridCard(
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
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 32)

            if appState.hasMorePages {
                loadMoreFooter
                    .padding(.bottom, 28)
            }
        }
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            Button {
                Task { await appState.loadNextPage() }
            } label: {
                if appState.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 14)
                } else {
                    Text("加载更多（第 \(appState.currentPage) / \(appState.totalPages) 页）")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 8)
                }
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoadingMore)
            Spacer()
        }
    }
}

private struct BookGridCard: View {
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                BookCoverView(book: book, cornerRadius: 8, showShadow: true)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? FolioTheme.accent : Color.clear, lineWidth: 2.2)
                    )
                    .scaleEffect(isHovered ? 1.02 : 1.0)
                    .offset(y: isHovered ? -3 : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)

                // 悬停或已收藏时显示克制角标收藏按钮
                if isHovered || isSaved {
                    Button(action: onToggleSave) {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isSaved ? Color.orange : Color.white)
                            .frame(width: 26, height: 26)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .help(isSaved ? "取消收藏" : "加入云端收藏")
                    .transition(.opacity)
                }
            }

            VStack(alignment: .leading, spacing: 3.5) {
                Text(book.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !book.authors.isEmpty {
                    Text(book.authors)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if !book.displayExtension.isEmpty {
                        FormatBadgeView(fileExtension: book.fileExtension, sizeText: book.formattedSize)
                    }
                    Spacer(minLength: 0)
                    if !book.year.isEmpty {
                        Text(book.year)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)

                if showHistoryDate, let date = book.historyDate, !date.isEmpty {
                    Text("下载于 \(date)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .onTapGesture(perform: onSelect)
        .contextMenu {
            Button("查看详情", systemImage: "info.circle", action: onSelect)
            Button("立即下载 (\(book.displayExtension.isEmpty ? "默认" : book.displayExtension))", systemImage: "arrow.down.circle", action: onDownload)
            Button(isSaved ? "取消收藏" : "加入云端收藏", systemImage: isSaved ? "bookmark.slash" : "bookmark", action: onToggleSave)
            if let onDeleteHistory {
                Divider()
                Button("删除云端下载记录", systemImage: "trash", role: .destructive, action: onDeleteHistory)
            }
        }
    }
}
