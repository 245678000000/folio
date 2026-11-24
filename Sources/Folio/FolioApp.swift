import AppKit
import FolioCore
import SwiftUI

/// 应用委托：确保独立二进制或 .app 启动时正确激活 Dock 图标并前置主窗口
final class FolioAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct FolioApp: App {
    @NSApplicationDelegateAdaptor(FolioAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Folio") {
            MainWindowView(appState: appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1160, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("书库") {
                Button("聚焦搜索栏") {
                    appState.shouldFocusSearchField = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("查找电子书") {
                    appState.selectedNav = .search
                    appState.shouldFocusSearchField = true
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("刷新当前页面") {
                    Task { await appState.loadCurrentSection() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("热门精选") { appState.selectNavigation(.mostPopular) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("最新上架") { appState.selectNavigation(.recently) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("搜索书库") {
                    appState.selectNavigation(.search)
                    appState.shouldFocusSearchField = true
                }
                .keyboardShortcut("3", modifiers: .command)
                Button("云端收藏") { appState.selectNavigation(.saved) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("传输队列") { appState.selectNavigation(.transfers) }
                    .keyboardShortcut("5", modifiers: .command)

                Divider()

                Button("连接或切换账号…") {
                    appState.isAuthSheetPresented = true
                }
            }
        }

        Settings {
            SettingsView(appState: appState)
                .preferredColorScheme(appState.preferredColorScheme)
        }
    }
}
