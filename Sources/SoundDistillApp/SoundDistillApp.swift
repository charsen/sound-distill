import AppKit
import SwiftUI
import SoundDistillCore

@main
struct SoundDistillApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("音萃 SoundDistill", id: "main") {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(Theme.brandPrimary)
                .frame(minWidth: 1020, minHeight: 660)
        }
        .defaultSize(width: 1160, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加视频…") { model.addFiles() }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("添加文件夹…") { model.addFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("任务") {
                Button("开始转换") { model.startConversion() }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!model.canStart)
                Button("取消全部") { model.cancelAll() }
                    .keyboardShortcut(".", modifiers: [.command])
                    .disabled(!model.isRunning)
                Divider()
                Button("清空已完成") { model.clearFinished() }
                    .disabled(model.isRunning || !model.jobs.contains(where: { $0.status.isFinished }))
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 冷启动时系统可能先于 SwiftUI 模型发送 openFiles，这里暂存给 AppModel 消费。
    static var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // 设计稿指定固定深色方案：即使系统处于浅色模式，窗口、菜单与面板也统一使用深色外观。
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppDelegate.pendingOpenURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .audioExtractOpenFiles, object: urls)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        RunningProcessRegistry.shared.terminateAll()
    }
}
