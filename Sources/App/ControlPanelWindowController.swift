import AppKit
import SwiftUI
import agentmonCore

/// 独立控制台窗口（单例复用）。LSUIElement 应用：打开时临时切 `.regular` 以获得键盘焦点，
/// 关闭复位 `.accessory` 回到菜单栏形态。契约见 rfcs/multi-client-and-control-panel.md §4.6。
final class ControlPanelWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    private let onOpen: () -> Void

    init(model: AppModel, onOpen: @escaping () -> Void) {
        self.model = model
        self.onOpen = onOpen
        super.init()
    }

    func show() {
        onOpen()  // 让 AppDelegate 先刷新集成状态/配置/宠物态
        if let window = window {
            activateRegular()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let hosting = NSHostingController(rootView: ControlPanelView().environmentObject(model))
        let w = NSWindow(contentViewController: hosting)
        w.title = "agentmon 控制台"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 880, height: 620))
        w.setFrameAutosaveName("agentmon.controlpanel")
        w.isReleasedWhenClosed = false
        w.delegate = self
        window = w
        activateRegular()
        w.center()
        w.makeKeyAndOrderFront(nil)
    }

    private func activateRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // 回到菜单栏 App 形态（无 Dock 图标）。UI 测试模式保持 .regular 便于寻址。
        if ProcessInfo.processInfo.environment["AGENTMON_UITEST"] == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
