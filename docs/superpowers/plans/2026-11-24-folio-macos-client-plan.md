# Folio macOS 原生客户端实施计划

> **执行指引**：按任务顺序以 TDD 与增量验证推进，每个模块完成后运行 `swift test` 或 `swift build` 确认通过后再提交。

**目标**：从零构建简洁、美观、轻量的 macOS 原生 Z-Library EAPI 客户端 `Folio.app`（支持双模式登录、自定义域名与代理、Apple Books 极简界面、离线演示模式与本地阅读器一键打开）。

**架构**：采用 Swift Package Manager 双 Target 结构——`FolioCore` 封装纯领域模型、EAPI 网络层、Keychain 存储、下载引擎与演示服务；`Folio` 构建 macOS 14+ 原生 SwiftUI 界面；`FolioCoreTests` 使用 Swift 6 原生 `Testing` 框架验证核心协议与边界条件。

**技术栈**：Swift 6.3、SwiftUI、AppKit、URLSession、Security（Keychain）、Swift Testing、CoreGraphics（图标生成）。

## 全局约束

- 最低运行系统：macOS 14.0+（本机 Apple Silicon 原生编译）。
- 零第三方库依赖，仅使用苹果官方系统框架。
- 所有 EAPI 请求必须携带 `source: android` 请求头；跨域重定向必须剥离凭据。
- 所有新增代码注释与文档使用中文。
- 所有测试与构建验收必须执行真实命令并确认退出码为 0。

---

## 文件结构规划

```text
Folio/
├── Package.swift
├── README.md
├── scripts/
│   ├── generate_icon.swift
│   └── build_app.sh
├── Sources/
│   ├── FolioCore/
│   │   ├── Models/
│   │   │   ├── Book.swift
│   │   │   ├── Session.swift
│   │   │   └── EapiError.swift
│   │   ├── Network/
│   │   │   ├── DomainPolicy.swift
│   │   │   ├── EapiHeaders.swift
│   │   │   ├── EapiJSONParser.swift
│   │   │   ├── ProxySessionFactory.swift
│   │   │   └── EapiClient.swift
│   │   ├── Service/
│   │   │   ├── LibraryService.swift
│   │   │   ├── LiveLibraryService.swift
│   │   │   └── DemoLibraryService.swift
│   │   ├── Storage/
│   │   │   ├── KeychainStore.swift
│   │   │   └── SettingsStore.swift
│   │   └── Download/
│   │       ├── DownloadFilenamePolicy.swift
│   │       └── DownloadManager.swift
│   └── Folio/
│       ├── FolioApp.swift
│       ├── State/AppState.swift
│       ├── Theme/FolioTheme.swift
│       ├── Components/
│       │   ├── BookCoverView.swift
│       │   ├── CoverImageCache.swift
│       │   ├── FormatBadgeView.swift
│       │   └── EmptyStateView.swift
│       └── Views/
│           ├── MainWindowView.swift
│           ├── SidebarView.swift
│           ├── LibraryContentView.swift
│           ├── BookGridView.swift
│           ├── BookListView.swift
│           ├── SearchFilterBar.swift
│           ├── BookInspectorView.swift
│           ├── DownloadsView.swift
│           ├── AuthSheetView.swift
│           └── SettingsView.swift
└── Tests/
    └── FolioCoreTests/
        ├── DomainPolicyTests.swift
        ├── BookMapperTests.swift
        ├── EapiClientTests.swift
        ├── DownloadFilenamePolicyTests.swift
        └── DemoLibraryServiceTests.swift
```

---

### 任务 1：初始化 SwiftPM 工程骨架与领域模型

- [ ] 创建 `Package.swift` 定义 `FolioCore`、`Folio` 与 `FolioCoreTests` 三个 Target（`platforms: [.macOS(.v14)]`）。
- [ ] 创建 `Book.swift`、`Session.swift`、`EapiError.swift` 定义全套 `Sendable`、`Codable`、`Hashable` 领域模型。
- [ ] 运行 `swift build --target FolioCore` 验证编译通过并提交。

### 任务 2：实现域名策略、EAPI JSON 解析器与单元测试

- [ ] 编写 `DomainPolicyTests.swift` 与 `BookMapperTests.swift`（覆盖合法域名清洗、非法协议/凭据注入拦截、ISBN 归一、坏封面过滤、安全引用正则）。
- [ ] 实现 `DomainPolicy.swift`、`EapiHeaders.swift`、`EapiJSONParser.swift`。
- [ ] 运行 `swift test` 验证全部测试通过并提交。

### 任务 3：实现代理会话工厂、EAPI 客户端与全链路 Mock 测试

- [ ] 编写 `EapiClientTests.swift`（基于自定义 `URLProtocol` 验证 `source: android` 请求头、登录提取 Cookie 与字段、表单数组编码、`Access denied` 映射、两阶段 `downloadLink` 解析、HTML 配额耗尽识别、跨域重定向剥离凭据）。
- [ ] 实现 `ProxySessionFactory.swift` 与 `EapiClient.swift`。
- [ ] 运行 `swift test` 验证全部测试通过并提交。

### 任务 4：实现 Keychain 安全存储、设置存储、下载管理器与演示数据源

- [ ] 编写 `DownloadFilenamePolicyTests.swift` 与 `DemoLibraryServiceTests.swift`。
- [ ] 实现 `KeychainStore.swift`、`SettingsStore.swift`、`DownloadFilenamePolicy.swift`、`DownloadManager.swift`、`LibraryService.swift`、`LiveLibraryService.swift`、`DemoLibraryService.swift`。
- [ ] 运行 `swift test` 验证全部核心测试通过并提交。

### 任务 5：构建原生 SwiftUI 应用状态与视觉主题组件

- [ ] 实现 `FolioTheme.swift`（Apple Books × Things 3 宣纸暖白/深炭配色、莫兰迪精装占位封面色板与阴影规范）。
- [ ] 实现 `CoverImageCache.swift`、`BookCoverView.swift`、`FormatBadgeView.swift`、`EmptyStateView.swift`。
- [ ] 实现 `AppState.swift`（`@MainActor @Observable`，含搜索分页、乐观收藏、详情与多格式懒加载、代理切换、下载状态联动与 Toast）。
- [ ] 运行 `swift build` 验证编译通过。

### 任务 6：构建全套极简原生视图与窗口交互

- [ ] 实现 `SidebarView.swift`、`BookGridView.swift`、`BookListView.swift`、`SearchFilterBar.swift`、`LibraryContentView.swift`。
- [ ] 实现 `BookInspectorView.swift`、`DownloadsView.swift`、`AuthSheetView.swift`、`SettingsView.swift`、`MainWindowView.swift`、`FolioApp.swift`。
- [ ] 运行 `swift build` 验证主程序零错误编译。

### 任务 7：原生图标生成、`.app` 打包脚本、全面验收与 README

- [ ] 编写 `scripts/generate_icon.swift` 生成 1024px 高清精装书图标集并编译为 `AppIcon.icns`。
- [ ] 编写 `scripts/build_app.sh` 完成 Release 构建、`.app` Bundle 装配、本地签名与体积检查。
- [ ] 编写项目 `README.md`（使用说明、认证模式与构建方法）。
- [ ] 运行完整 `swift test` 与 `./scripts/build_app.sh`，启动打包后的 `dist/Folio.app` 验证进程正常存活，无崩溃后收尾提交。
