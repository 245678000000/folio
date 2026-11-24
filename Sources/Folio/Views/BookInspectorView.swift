import FolioCore
import SwiftUI

/// 右侧书籍详情检视面板（原生 Inspector）
struct BookInspectorView: View {
    @Bindable var appState: AppState
    @State private var isDescriptionExpanded = false

    private var book: Book? {
        appState.inspectorDetail ?? appState.selectedBook
    }

    var body: some View {
        Group {
            if let book {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection(book: book)
                        actionButtonsSection(book: book)

                        if !book.description.isEmpty {
                            descriptionSection(book.description)
                        }

                        metadataGrid(book: book)

                        if !appState.inspectorSimilar.isEmpty {
                            similarBooksSection
                        }
                    }
                    .padding(20)
                }
                .background(FolioTheme.cardSurface)
                .id(book.ref)
                .onChange(of: book.ref) { _, _ in
                    isDescriptionExpanded = false
                }
            } else {
                EmptyStateView(
                    icon: "sidebar.right",
                    title: "选择一本书查看详情",
                    subtitle: "点击任意封面可查看简介、出版信息、可用格式与相似推荐。"
                )
                .background(FolioTheme.cardSurface)
            }
        }
    }

    private func headerSection(book: Book) -> some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                BookCoverView(book: book, cornerRadius: 9, showShadow: true)
                    .frame(width: 148)
                Spacer()
            }
            .padding(.top, 4)

            VStack(spacing: 5) {
                Text(book.title)
                    .font(.system(size: 17, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)

                if !book.subtitle.isEmpty {
                    Text(book.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !book.authors.isEmpty {
                    Text(book.authors)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                }

                HStack(spacing: 8) {
                    if !book.displayExtension.isEmpty {
                        FormatBadgeView(fileExtension: book.fileExtension, sizeText: book.formattedSize)
                    }
                    if let rating = book.rating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func actionButtonsSection(book: Book) -> some View {
        let saved = appState.isSaved(book)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    appState.startDownload(book: book)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("下载 \(book.displayExtension.isEmpty ? "电子书" : book.displayExtension)")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(FolioTheme.accent)
                .controlSize(.large)

                Button {
                    appState.toggleSaved(book)
                } label: {
                    Image(systemName: saved ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(saved ? Color.orange : Color.primary)
                        .frame(width: 30, height: 24)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help(saved ? "取消云端收藏" : "加入云端收藏")

                if !appState.isDemoMode {
                    Button {
                        appState.openBookOnOfficialSite(book)
                    } label: {
                        Image(systemName: "safari")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 30, height: 24)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help("在官方网站打开此书")
                }
            }

            // 多格式下拉选择（存在多版本时展示）
            if appState.isLoadingFormats {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("正在查询可用格式版本…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.top, 2)
            } else if !appState.inspectorFormats.isEmpty {
                Menu {
                    ForEach(appState.inspectorFormats, id: \.ref) { format in
                        Button {
                            appState.startDownload(book: book, format: format)
                        } label: {
                            let sizePart = format.formattedSize.isEmpty ? "" : " (\(format.formattedSize))"
                            Text("下载 \(format.displayExtension)\(sizePart)")
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11.5))
                        Text("选择其他格式（共 \(appState.inspectorFormats.count) 种）")
                            .font(.system(size: 12))
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(FolioTheme.subtleFill)
                    )
                }
                .menuStyle(.borderlessButton)
            }
        }
    }

    private func descriptionSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内容简介")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.primary.opacity(0.9))
                .lineSpacing(4)
                .lineLimit(isDescriptionExpanded ? nil : 5)
                .textSelection(.enabled)

            if text.count > 120 {
                Button(isDescriptionExpanded ? "收起简介" : "展开全文") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isDescriptionExpanded.toggle()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(FolioTheme.accent)
            }
        }
    }

    private func metadataGrid(book: Book) -> some View {
        let rows: [(String, String)] = [
            ("出版社", book.publisher),
            ("出版年份", book.year),
            ("语言", book.language.capitalized),
            ("页数", book.pages.map { "\($0) 页" } ?? ""),
            ("ISBN", book.displayISBN),
            ("版次", book.edition),
            ("分类", book.categories.joined(separator: " / ")),
        ].filter { !$0.1.isEmpty }

        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("出版信息")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 7) {
                        ForEach(rows, id: \.0) { label, value in
                            HStack(alignment: .top, spacing: 10) {
                                Text(label)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 58, alignment: .leading)
                                Text(value)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.primary.opacity(0.88))
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(11)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(FolioTheme.subtleFill)
                    )
                }
            }
        }
    }

    private var similarBooksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("相似书籍")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(appState.inspectorSimilar, id: \.ref) { item in
                        Button {
                            appState.inspect(book: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                BookCoverView(book: item, cornerRadius: 5, showShadow: false, compact: true)
                                    .frame(width: 68)
                                Text(item.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(width: 68, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
