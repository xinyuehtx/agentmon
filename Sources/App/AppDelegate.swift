import AppKit
import SwiftUI
import agentmonCore

/// 组合 Core + 菜单栏 + 宠物浮窗 + 定时 pump。契约见 specs/agent-task-monitor.md §7、§8。
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    private var petPanel: PetPanel?
    private var coordinator: MonitorCoordinator!
    private var timer: Timer?
    private let petState = PetState()
    private var lastSnapshot: MonitorSnapshot?

    private let stateStore = StateStore(
        stateURL: AgentmonPaths.stateFile,
        configURL: AgentmonPaths.configFile)
    private lazy var installer = ClaudeHookInstaller(
        settingsURL: AgentmonPaths.claudeSettings,
        reporterCommand: Self.reporterCommand()
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupCoordinator()
        setupStatusItem()
        setupPetPanel()
        startTimer()
        pump()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persist()
    }

    // MARK: - Setup

    private static func reporterCommand() -> String {
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            return dir.appendingPathComponent("agentmon-hook").path
        }
        return "agentmon-hook"
    }

    private func setupCoordinator() {
        try? FileManager.default.createDirectory(at: AgentmonPaths.spool, withIntermediateDirectories: true)
        let config = (try? stateStore.loadConfig()) ?? .default
        let loaded = (try? stateStore.loadState()) ?? nil
        let engine = EnergyEngine(
            config: config,
            energy: loaded?.energy ?? 0,
            level: loaded?.level ?? 1,
            lastTick: loaded?.lastTick ?? Date()
        )
        engine.applyOfflineDecay(now: Date())  // 离线期空闲衰减
        coordinator = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: AgentmonPaths.spool),
            engine: engine
        )
        coordinator.onEvolve = { [weak self] event in
            self?.petState.mood = .evolve
            self?.petState.level = event.newLevel
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func setupPetPanel() {
        let host = NSHostingView(rootView: CatView(state: petState))
        let panel = PetPanel(content: host)
        panel.orderFrontRegardless()
        petPanel = panel
    }

    private func startTimer() {
        let t = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pump()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Loop

    private func pump() {
        let snap = coordinator.pump(now: Date())
        lastSnapshot = snap
        updateUI(snap)
        persist()
    }

    private func persist() {
        try? stateStore.saveState(coordinator.persistentState(now: Date()))
    }

    private func updateUI(_ snap: MonitorSnapshot) {
        statusItem.button?.title = "🐱 ▶\(snap.totalWorking) ⏸\(snap.totalWaiting) ✓\(snap.totalCompleted)"
        petState.energy = snap.energy
        petState.level = snap.level
        petState.energyToNext = coordinator.engine.threshold(forLevel: snap.level)
        if petState.mood == .evolve {
            petState.mood = snap.totalWorking > 0 ? .working : .idle  // 进化演出后回落
        } else if snap.totalWorking > 0 {
            petState.mood = .working
        } else if snap.totalWaiting > 0 {
            petState.mood = .waiting
        } else {
            petState.mood = .idle
        }
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = lastSnapshot ?? coordinator.snapshot()
        let next = Int(coordinator.engine.threshold(forLevel: snap.level))

        let header = NSMenuItem(
            title: "Lv\(snap.level)   能量 \(Int(snap.energy))/\(next)",
            action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if snap.clients.isEmpty {
            let none = NSMenuItem(title: "暂无客户端事件", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        } else {
            for c in snap.clients {
                let item = NSMenuItem(
                    title: "\(c.client)   ▶\(c.counts.working) ⏸\(c.counts.waiting) ✓\(c.counts.completed)",
                    action: nil, keyEquivalent: ""
                )
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())

        let petItem = NSMenuItem(
            title: (petPanel?.isVisible ?? false) ? "隐藏宠物" : "显示宠物",
            action: #selector(togglePet), keyEquivalent: "")
        petItem.target = self
        menu.addItem(petItem)

        let installed = (try? installer.isInstalled()) ?? false
        let integ = NSMenuItem(
            title: installed ? "停用 Claude 集成" : "启用 Claude 集成",
            action: #selector(toggleIntegration), keyEquivalent: "")
        integ.target = self
        menu.addItem(integ)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 agentmon", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func togglePet() {
        guard let panel = petPanel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func toggleIntegration() {
        do {
            if (try? installer.isInstalled()) == true {
                try installer.uninstall()
            } else {
                try installer.install()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Claude 集成操作失败"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    @objc private func quit() {
        persist()
        NSApplication.shared.terminate(nil)
    }
}
