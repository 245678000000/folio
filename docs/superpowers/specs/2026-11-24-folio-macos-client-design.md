# Folio — macOS 原生 Z-Library EAPI 电子书客户端设计规格书

- **日期**：2026-11-24
- **平台**：macOS 14.0+（Apple Silicon 原生构建）
- **技术栈**：Swift 6.3 + SwiftUI + AppKit + URLSession + Security（Keychain），Swift Package Manager 构建，零第三方依赖
- **产品定位**：简洁、美观、轻量的极简搜书与下载器（下载后调用系统默认阅读器打开）

---

## 1. 产品目标与全局约束

1. **极致轻量**：最终 `.app` 包体积控制在 5MB 以内，冷启动毫秒级，零外部框架或运行时打包负担。
2. **原生书店极简美学**：以 Apple Books × Things 3 为视觉参考——柔和毛玻璃侧边栏（`NavigationSplitView`）、纯净暖白/深炭画布、2:3 书封比例与克制书脊阴影、右侧原生检视器（`inspector`）、无缝适配深浅色模式。
3. **聚焦核心链路**：不内置笨重阅读引擎，专注「发现 → 搜索筛选 → 详情与多格式选择 → 云端收藏与历史同步 → 一键下载 → 调系统默认阅读器打开」。
4. **认证与网络稳健性**：
   - 双模式登录：邮箱密码登录（`POST /eapi/user/login`）与 Token/Cookie 直连（`remix_userid` + `remix_userkey`）。
   - 自定义服务器域名 + 域名连通性检测。
   - 遵循 macOS 系统代理，并支持手动配置 HTTP / SOCKS5 代理。
   - 内置**离线演示模式（Demo Mode）**，无账号即可完整体验搜索、筛选、详情、多格式、收藏、下载与系统打开流程。
5. **EAPI 安全与最新协议兼容**：
   - 所有 EAPI 请求统一携带 `source: android`、`User-Agent`、`Accept: application/json`，规避 2026-11 出现的 `/eapi/book/search` `Access denied` 问题。
   - 认证凭据存储于 macOS Keychain，日志与重定向过程中严防泄露（跨域重定向自动剥离 `remix-userid`、`remix-userkey` 与 `Cookie`）。

---

## 2. 界面与交互设计

### 2.1 主窗口骨架（三段式自适应）
- **左侧毛玻璃导航栏（~210pt）**：
  - **发现**：热门精选（`most-popular`）、最新上架（`recently`）、个性推荐（`recommended`）
  - **检索**：搜索书库（聚合筛选与历史）
  - **我的书库**：云端收藏（`saved`）、下载记录（`downloaded`）
  - **传输**：本地下载队列（展示活跃下载数量角标）
  - **底部账户卡**：显示账号邮箱/演示标识、今日下载配额进度条（`已用 / 上限`）、账号切换与设置入口。
- **主内容区**：
  - 一体化顶部工具栏：原生搜索输入（`⌘K` / `⌘F` 聚焦）、网格/列表视图切换、刷新（`⌘R`）、详情检视器开关。
  - 搜索页专属轻量折叠筛选条：精确匹配（`e=1`）、语言、文件格式、出版年份起止、排序方式。
  - 书籍网格卡片：2:3 书封（带微弱书脊折痕与自然阴影；无图时生成莫兰迪精装书排版占位封）、书名、作者、格式胶囊与快捷收藏。
  - 简洁列表视图：封面缩略图 + 书名/作者/出版社 + 年份/语言/格式/文件大小对齐列。
- **右侧书籍详情检视器（~340pt，`Esc` 关闭）**：
  - 大尺寸居中书封与核心元信息（作者、年份、语言、页数、ISBN、评分）。
  - **主操作区**：一键下载主按钮 + 多格式下拉菜单（异步拉取 `/formats` 展示全部可用格式与体积）+ 云端收藏星标切换。
  - 简介正文（可展开/收起）、详细出版信息表、横向「相似书籍」轻推荐列表。
- **原生设置窗口（`⌘,`）**：
  - **常规**：默认下载保存目录（支持 Finder 选择）、外观模式（跟随系统 / 浅色 / 深色）、默认视图模式。
  - **账号与域名**：当前连接状态、切换登录/Token 配置、切换演示模式、退出登录与清除凭据。
  - **网络与代理**：跟随系统代理 / 自定义 HTTP / 自定义 SOCKS5 代理配置及域名测速。

### 2.2 下载与本地阅读联动
- 传输页按「进行中」与「已完成 / 失败」分区展示。
- 活跃任务展示字节进度条、百分比与取消按钮；失败任务支持一键重试。
- 已完成任务单击「打开阅读」调用 `NSWorkspace.shared.open(fileURL)` 直接在 Apple Books / Readest / 预览等默认应用打开，辅助操作支持「在 Finder 中显示」。

---

## 3. 架构与模块边界

采用双 Target SwiftPM 分层架构，业务逻辑与界面彻底解耦：

### 3.1 `FolioCore`（核心领域与网络库）
| 模块 | 职责 | 关键类型 |
|---|---|---|
| `Models` | 领域模型、搜索条件、会话与错误定义 | `Book`, `BookFormat`, `BookPage`, `SearchQuery`, `Session`, `AccountProfile`, `EapiError`, `ProxyConfiguration` |
| `Network` | EAPI 协议封装、域名安全策略、代理会话与跨域防泄密重定向代理 | `DomainPolicy`, `EapiHeaders`, `EapiJSONParser`, `BookMapper`, `ProxySessionFactory`, `EapiClient` |
| `Service` | 统一书库服务协议、真实 EAPI 服务与高保真离线演示服务 | `LibraryServiceProtocol`, `LiveLibraryService`, `DemoLibraryService` |
| `Storage` | macOS Keychain 会话安全存取与用户偏好配置存储 | `SessionStoreProtocol`, `KeychainSessionStore`, `InMemorySessionStore`, `SettingsStore` |
| `Download` | 流式下载任务管理、防重名文件落地、HTML 误返与配额拦截 | `DownloadManager`, `DownloadTaskItem`, `DownloadFilenamePolicy` |

### 3.2 `Folio`（macOS 原生 SwiftUI 应用）
- `FolioApp.swift`：应用生命周期、菜单栏命令与快捷键注册、设置场景。
- `State/AppState.swift`：`@MainActor @Observable` 单一数据源状态容器，负责任务取消、防抖搜索、收藏乐观更新与 Toast 提示。
- `Theme/FolioTheme.swift`：颜色、字体、圆角、阴影及书封配色令牌。
- `Components/`：`BookCoverView`、`FormatBadgeView`、`EmptyStateView`、`ToastBannerView`。
- `Views/`：`MainWindowView`、`SidebarView`、`LibraryContentView`、`BookGridView`、`BookListView`、`SearchFilterBar`、`BookInspectorView`、`DownloadsView`、`AuthSheetView`、`SettingsView`。

---

## 4. EAPI 协议与防坑规范

1. **统一请求头**：
   - `source: android`（关键：避免 `/eapi/book/search` 触发 HTTP 400 `Access denied`）
   - `Accept: application/json`
   - `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36`
   - 认证请求附加 `remix-userid`、`remix-userkey` 及标准 `Cookie: remix_userid=...; remix_userkey=...`
2. **覆盖接口清单**：
   - `POST /eapi/user/login`
   - `GET /eapi/user/profile`
   - `POST /eapi/book/search`（`application/x-www-form-urlencoded`，支持 `languages[]`、`extensions[]`、`e=1`、`yearFrom`、`yearTo`、`order`）
   - `GET /eapi/book/most-popular`、`GET /eapi/book/recently`、`GET /eapi/user/book/recommended`
   - `GET /eapi/book/{id}/{hash}`、`GET /eapi/book/{id}/{hash}/formats`、`GET /eapi/book/{id}/{hash}/similar`
   - `GET /eapi/book/{id}/{hash}/file`（同时兼容直接文件流与 JSON `file.downloadLink` 二次拉取）
   - `GET /eapi/user/book/saved`、`GET /eapi/user/book/{id}/save`、`GET /eapi/user/book/{id}/unsave`
   - `GET /eapi/user/book/downloaded`、`GET /eapi/user/book/{id}/delete`
   - `GET /eapi/info/languages`、`GET /eapi/info/extensions`、`GET /eapi/info/domains`
3. **错误处理与降级**：
   - 识别 HTTP 400 + `Access denied` 映射为 `EapiError.searchRefused`，提示检查域名或切换个人专属域名。
   - 识别 `text/html` 返回体中的 `daily limit` / `daily download` 映射为 `EapiError.quotaExhausted`。
   - 401/403 或 `please login` 映射为 `EapiError.sessionExpired`，引导用户重新登录或刷新 Token。

---

## 5. 测试与打包验证标准

- **单元测试（Swift Testing，`swift test`）**：覆盖 `DomainPolicy`、`BookMapper`、`EapiClient`（自定义 `URLProtocol` 全链路 Mock 请求头/搜索/登录/两阶段下载/重定向凭据剥离/错误处理）、`DemoLibraryService` 与 `DownloadFilenamePolicy`。
- **原生应用打包（`scripts/build_app.sh`）**：通过 `swift build -c release` 构建 arm64 二进制，生成 CoreGraphics 原生精装书图标（`AppIcon.icns`），装配标准 `dist/Folio.app` 并执行本地签名与启动烟雾验证。
