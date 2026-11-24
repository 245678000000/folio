# Folio — macOS 原生 Z-Library EAPI 电子书客户端

**简洁、美观、轻量**的 macOS 原生电子书检索与下载客户端。基于 Swift 6 + SwiftUI 纯原生构建，零第三方依赖，成品 `.app` 仅数 MB。

## 核心特性

- **原生书店极简界面**：`NavigationSplitView` 柔和毛玻璃侧边栏 + 宣纸浅色 / 静谧深色自适应画布 + 实体精装书封排版占位封 + 右侧滑出书籍详情检视面板（`Inspector`）。
- **完整 Z-Library EAPI 支持**：
  - 发现：热门精选（`/eapi/book/most-popular`）、最新上架（`/eapi/book/recently`）、个性推荐（`/eapi/user/book/recommended`）
  - 检索：统一搜索与高级筛选（`/eapi/book/search`，支持精确匹配、语言、格式、年份区间、排序与分页）
  - 详情与多格式：详情简介、多格式版本切换下载（`/formats`）、相似书籍推荐（`/similar`）
  - 我的书库：云端收藏同步（`/saved`、`/save`、`/unsave`）、云端下载记录与单条清理（`/downloaded`、`/delete`）
  - 账户配额：侧边栏实时展示今日剩余下载额度进度条（`/eapi/user/profile`）
- **最新 EAPI 协议兼容与安全防护**：
  - 内置 `source: android` 客户端标识头，解决 2026-11 搜索接口 `Access denied` 问题。
  - 下载接口兼容直接文件流与 JSON `file.downloadLink` 两阶段拉取，跨域重定向自动剥离 `remix-userid`、`remix-userkey` 与 `Cookie`。
  - 账号凭据加密存储于 macOS 原生钥匙串（Keychain）。
- **双模式认证与代理支持**：
  - 支持「邮箱密码登录」与「`remix_userid` / `remix_userkey` Token 直连」。
  - 支持自定义个人专属域名、一键域名测速、跟随 macOS 系统代理或手动配置 HTTP / SOCKS5 代理。
  - 内置**离线演示书库**，无账号即可完整体验搜索、筛选、多格式下载与调用 Apple Books / 预览打开。

## 常用快捷键

- `⌘K` / `⌘F`：聚焦顶部搜索栏
- `⌘R`：刷新当前页面
- `⌘1` ~ `⌘5`：快速切换热门精选 / 最新上架 / 搜索书库 / 云端收藏 / 传输队列
- `⌘,`：打开原生偏好设置
- `Esc`：收起右侧详情面板

## 本地测试与打包

```bash
# 1. 运行 FolioCore 全部单元测试（Swift Testing）
./scripts/test.sh

# 2. 编译 Release 并打包 dist/Folio.app（含原生图标与本地签名）
./scripts/build_app.sh

# 3. 启动应用
open dist/Folio.app
```

> 建议将 `dist/Folio.app` 拖入 `/Applications` 文件夹即可像常规 macOS 应用一样从启动台或聚焦搜索直接打开。
