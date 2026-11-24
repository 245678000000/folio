import AppKit
import FolioCore
import SwiftUI

/// 本地下载传输队列视图（实时进度 + 一键调系统阅读器打开 + Finder 定位）
struct DownloadsView: View {
    @Bindable var appState: AppState

    private var activeTasks: [DownloadTaskItem] {
        appState.downloadTasks.filter { $0.status.isActive }
    }

    private var finishedTasks: [DownloadTaskItem] {
        appState.downloadTasks.filter { !$0.status.isActive }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("传输队列")
                    .font(.system(size: 22, weight: .bold, design: .serif))

                if !appState.downloadTasks.isEmpty {
                    Text("\(appState.downloadTasks.count) 项")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Button {
                    let url = appState.settings.downloadDirectoryURL
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("打开保存目录", systemImage: "folder")
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !finishedTasks.isEmpty {
                    Button("清除已完成") {
                        appState.clearFinishedDownloads()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if appState.downloadTasks.isEmpty {
                EmptyStateView(
                    icon: "arrow.down.circle",
                    title: "暂无下载任务",
                    subtitle: "在书墙或详情面板点击下载，电子书将保存至 \(appState.settings.downloadDirectoryPath)，完成后可直接调用系统默认阅读器打开。"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !activeTasks.isEmpty {
                            taskSection(title: "正在下载", tasks: activeTasks)
                        }
                        if !finishedTasks.isEmpty {
                            taskSection(title: "最近完成与记录", tasks: finishedTasks)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func taskSection(title: String, tasks: [DownloadTaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(tasks) { item in
                    DownloadTaskRow(
                        item: item,
                        onOpen: { url in appState.openDownloadedFile(url) },
                        onReveal: { url in appState.revealInFinder(url) },
                        onCancel: { appState.cancelDownload(item) },
                        onRetry: { appState.retryDownload(item) }
                    )
                }
            }
        }
    }
}

private struct DownloadTaskRow: View {
    let item: DownloadTaskItem
    let onOpen: (URL) -> Void
    let onReveal: (URL) -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            BookCoverView(book: item.book, cornerRadius: 5, showShadow: false, compact: true)
                .frame(width: 38, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.book.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    FormatBadgeView(fileExtension: item.targetExtension)
                }

                statusDetailView
            }

            Spacer(minLength: 12)

            actionButtons
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(FolioTheme.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(FolioTheme.hairlineBorder, lineWidth: 0.75)
        )
    }

    @ViewBuilder
    private var statusDetailView: some View {
        switch item.status {
        case .queued:
            Text("排队等待中…")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        case .resolving:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在获取下载地址…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        case .downloading(let received, let total):
            VStack(alignment: .leading, spacing: 4) {
                if let total, total > 0 {
                    ProgressView(value: Double(received), total: Double(total))
                        .tint(FolioTheme.accent)
                    HStack {
                        Text("\(formatBytes(received)) / \(formatBytes(total))")
                        Spacer()
                        Text("\(Int(Double(received) / Double(total) * 100))%")
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(FolioTheme.accent)
                    Text("已接收 \(formatBytes(received))")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        case .completed(let path, let size):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text("\(URL(fileURLWithPath: path).lastPathComponent) · \(formatBytes(size))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        case .cancelled:
            Text("已取消下载")
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.status {
        case .queued, .resolving, .downloading:
            Button("取消", role: .destructive, action: onCancel)
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .completed(let path, _):
            let url = URL(fileURLWithPath: path)
            HStack(spacing: 6) {
                Button {
                    onOpen(url)
                } label: {
                    Label("打开阅读", systemImage: "book.open")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(FolioTheme.accent)
                .controlSize(.small)

                Button {
                    onReveal(url)
                } label: {
                    Image(systemName: "magnifyingglass.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("在 Finder 中显示")
            }
        case .failed, .cancelled:
            Button("重试", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
