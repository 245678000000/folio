<h1 align="center">Folio</h1>

<p align="center">
  <strong>简洁、美观、轻量的 macOS 原生 Z-Library EAPI 电子书客户端</strong>
</p>

<p align="center">
  基于 Swift 6 与 SwiftUI 纯原生构建 · 零第三方依赖 · 适用于 Apple Silicon（macOS 14.0+）
</p>

<p align="center">
  <img src="docs/screenshots/main-window.jpg" alt="Folio 主界面预览" width="900" />
</p>

## 核心特性

- **原生书店极简界面**：`NavigationSplitView` 柔和毛玻璃侧边栏 + 宣纸浅色 / 静谧深色自适应画布 + 封面网格 / 简洁列表切换 + 右侧滑出书籍详情检视面板（`Inspector`）。无封面书籍自动生成实体精装书布质感排版封面。
- **直达官网一键登录与多模式认证**：
  - 支持应用内直接打开官方网站登录并自动捕获个人专属域名与 `remix_userid` / `remix_userkey` 会话，免去手动找域名与翻 Cookie。
  - 同时支持邮箱密码登录、Cookie / Token 智能粘贴导入，以及一键并发探测最快可用官方入口。
  - 账号凭据加密存储于 macOS 原生钥匙串（Keychain）。
- **完整 Z-Library EAPI 支持**：
  - 发现：热门精选（`/eapi/book/most-popular`）、最新上架（`/eapi/book/recently`）、个性推荐（`/eapi/user/book/recommended`）
  - 检索：统一搜索与高级筛选（`/eapi/book/search`，支持精确匹配、语言、格式、年份区间、排序与分页）
  - 详情与多格式：详情简介、多格式版本切换下载（`/formats`）、相似书籍推荐（`/similar`）
  - 我的书库：云端收藏同步（`/saved`、`/save`、`/unsave`）、云端下载记录与单条清理（`/downloaded`、`/delete`）
  - 账户配额：侧边栏实时展示今日剩余下载额度进度条（`/eapi/user/profile`）
- **协议兼容与安全防护**：
  - 全链路内置 `source: android` 客户端标识头，规避搜索接口 `Access denied` 报错。
  - 下载接口兼容直接文件流与 JSON `file.downloadLink` 两阶段拉取，跨域重定向自动剥离认证头与 Cookie。
  - 默认跟随 macOS 系统代理，亦支持手动配置 HTTP / SOCKS5 代理。
- **开箱体验与本地阅读联动**：
  - 内置**离线演示书库**，无账号亦可完整体验检索、多格式下载与阅读联动。
  - 下载完成后可在传输队列一键调用系统默认阅读器（Apple Books / Readest / 预览）打开或定位至 Finder。

## 快速安装

前往 [GitHub Releases](https://github.com/245678000000/folio/releases/latest) 下载最新版本：

- **安装包（推荐）**：下载 `Folio-1.0.0-arm64.dmg`（2.6 MB），双击挂载后将 `Folio.app` 拖入 `Applications` 即可。
- **便携压缩包**：下载 `Folio-1.0.0-arm64.zip`（2.1 MB），解压后移入「应用程序」打开。

> 首次打开提示：开源版本暂未经过 Apple Developer 付费公证，若 macOS 提示“无法验证开发者”或“文件已损坏”，在终端执行一次以下命令移除下载隔离标记即可正常打开：
>
> ```bash
> xattr -cr /Applications/Folio.app
> ```

## 常用快捷键

- `⌘K` / `⌘F`：聚焦顶部搜索栏
- `⌘R`：刷新当前页面
- `⌘1` ~ `⌘5`：快速切换热门精选 / 最新上架 / 搜索书库 / 云端收藏 / 传输队列
- `⌘,`：打开原生偏好设置
- `Esc`：收起右侧详情面板

## 本地测试与构建

```bash
# 1. 运行 FolioCore 全部单元测试（Swift Testing）
./scripts/test.sh

# 2. 编译 Release 并打包 dist/Folio.app（含原生图标与本地签名）
./scripts/build_app.sh

# 3. 启动应用
open dist/Folio.app
```
