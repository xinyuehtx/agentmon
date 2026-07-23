import AppKit
import agentmonCore

// agentmon —— macOS 菜单栏 App + 桌面宠物浮窗。
// `--selftest`：无 GUI 地跑通 Core 编排链路后退出（供 CI / 无窗口环境验证）。

if CommandLine.arguments.contains("--selftest") {
    SelfTest.run()
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // 菜单栏 App，无 Dock 图标
app.run()
