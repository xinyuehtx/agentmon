import AppKit

/// 桌面宠物浮窗：无边框、透明、置顶、点击不抢焦点、可拖拽。契约见 specs/agent-task-monitor.md §8.2。
final class PetPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 214),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        content.frame = contentView?.bounds ?? content.frame
        content.autoresizingMask = [.width, .height]
        contentView?.addSubview(content)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrameOrigin(NSPoint(x: visible.maxX - 200, y: visible.maxY - 230))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
