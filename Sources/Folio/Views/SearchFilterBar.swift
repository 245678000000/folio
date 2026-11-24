import FolioCore
import SwiftUI

/// 搜索页轻量折叠筛选栏
struct SearchFilterBar: View {
    @Bindable var appState: AppState

    @State private var yearFromText: String = ""
    @State private var yearToText: String = ""

    private let quickFormats = ["epub", "pdf", "mobi", "azw3", "txt", "fb2"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // 排序方式
                Picker("排序", selection: Binding(
                    get: { appState.searchQuery.sort },
                    set: {
                        appState.searchQuery.sort = $0
                        appState.applySearchFilters()
                    }
                )) {
                    ForEach(SearchSort.allCases) { sort in
                        Text(sort.displayName).tag(sort)
                    }
                }
                .labelsHidden()
                .frame(width: 112)

                // 语言单选快捷筛选
                Picker("语言", selection: Binding(
                    get: { appState.searchQuery.languages.first ?? "" },
                    set: { newCode in
                        appState.searchQuery.languages = newCode.isEmpty ? [] : [newCode]
                        appState.applySearchFilters()
                    }
                )) {
                    Text("全部语言").tag("")
                    ForEach(appState.filterOptions.languages) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .labelsHidden()
                .frame(width: 126)

                // 年份区间
                HStack(spacing: 4) {
                    TextField("起始年", text: $yearFromText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                        .onSubmit(commitYears)
                    Text("–")
                        .foregroundStyle(.tertiary)
                    TextField("截止年", text: $yearToText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                        .onSubmit(commitYears)
                }

                Toggle("精确匹配", isOn: Binding(
                    get: { appState.searchQuery.exact },
                    set: {
                        appState.searchQuery.exact = $0
                        appState.applySearchFilters()
                    }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))

                Spacer(minLength: 8)

                if appState.searchQuery.hasActiveFilters {
                    Button("重置筛选") {
                        yearFromText = ""
                        yearToText = ""
                        appState.clearSearchFilters()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }

            // 文件格式多选胶囊
            HStack(spacing: 6) {
                Text("格式")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 2)

                ForEach(quickFormats, id: \.self) { ext in
                    let active = appState.searchQuery.extensions.contains(ext)
                    Button {
                        toggleFormat(ext)
                    } label: {
                        Text(ext.uppercased())
                            .font(.system(size: 11, weight: active ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(active ? Color.white : Color.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(active ? FolioTheme.formatTint(for: ext) : FolioTheme.subtleFill)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(FolioTheme.cardSurface.opacity(0.65))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
        .onAppear {
            yearFromText = appState.searchQuery.yearFrom.map(String.init) ?? ""
            yearToText = appState.searchQuery.yearTo.map(String.init) ?? ""
        }
    }

    private func toggleFormat(_ ext: String) {
        if let idx = appState.searchQuery.extensions.firstIndex(of: ext) {
            appState.searchQuery.extensions.remove(at: idx)
        } else {
            appState.searchQuery.extensions.append(ext)
        }
        appState.applySearchFilters()
    }

    private func commitYears() {
        appState.searchQuery.yearFrom = Int(yearFromText.trimmingCharacters(in: .whitespaces))
        appState.searchQuery.yearTo = Int(yearToText.trimmingCharacters(in: .whitespaces))
        appState.applySearchFilters()
    }
}
