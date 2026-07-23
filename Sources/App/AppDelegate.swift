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
    private let rasterStore = RasterPetStore.load()
    private var lastCompleted = 0
    private var lastStateKey = ""
    private var lastStage = ""

    private let stateStore = StateStore(
        stateURL: AgentmonPaths.stateFile,
        configURL: AgentmonPaths.configFile)
    private lazy var installer = ClaudeHookInstaller(
        settingsURL: AgentmonPaths.claudeSettings,
        reporterCommand: AppInfo.reporterCommand()
    )
    // Qoder 与 Claude Code 共用同一 hooks 机制；上报器带 "Qoder" 参数以区分客户端。
    private lazy var qoderInstaller = ClaudeHookInstaller(
        settingsURL: AgentmonPaths.qoderSettings,
        reporterCommand: "\(AppInfo.reporterCommand()) Qoder",
        events: ["UserPromptSubmit", "Notification", "Stop", "SubagentStart"]
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentmonLog.shared.configure(fileURL: AgentmonPaths.logFile)
        AgentmonLog.shared.info("app", "启动 agentmon v\(AppInfo.version)")
        setupCoordinator()
        setupStatusItem()
        setupPetPanel()
        startTimer()
        pump()
    }

    func applicationWillTerminate(_ notification: Notification) {
        persist()
        AgentmonLog.shared.info("app", "退出")
        AgentmonLog.shared.flush()
    }

    // MARK: - Setup

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
        coordinator.restore(
            completedByClient: loaded?.completedByClient ?? [:],
            day: loaded?.completedDay, now: Date())

        // 宠物物种：读持久化，否则从图集包中随机分配一次（卸载重装因 state.json 丢失而重掷）。
        let activeIDs = rasterStore?.manifest.speciesIDs ?? []
        let resolvedSpecies: String
        if let persisted = loaded?.species, activeIDs.contains(persisted) {
            resolvedSpecies = persisted
        } else {
            var rng = SystemRandomNumberGenerator()
            resolvedSpecies = PetSelection.choose(speciesIDs: activeIDs, using: &rng) ?? activeIDs.first ?? ""
        }
        coordinator.species = resolvedSpecies
        petState.species = resolvedSpecies
        lastCompleted = (loaded?.completedByClient.values.reduce(0, +)) ?? 0
        AgentmonLog.shared.info("pet", "物种=\(resolvedSpecies)")
        AgentmonLog.shared.info(
            "app",
            "集成状态=\((try? installer.isInstalled()) == true ? "已启用" : "未启用") "
                + "spool=\(AgentmonPaths.spool.path)")
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = Self.menubarImage() {
            statusItem.button?.image = image
            statusItem.button?.imagePosition = .imageLeading
        } else {
            statusItem.button?.title = "🐱"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    /// 菜单栏图标：优先 SF Symbol "cat"（macOS 14+），回退 "pawprint.fill"（11+），皆无则 nil。
    private static func menubarImage() -> NSImage? {
        for name in ["cat", "pawprint.fill"] {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "agentmon") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    private func setupPetPanel() {
        // 始终创建宠物窗（保证 pet.state 无障碍节点存在）；无图集时仅显示状态文案，不画精灵。
        if rasterStore == nil { AgentmonLog.shared.error("pet", "宠物图集缺失，仅显示状态") }
        let store =
            rasterStore
            ?? RasterPetStore(
                manifest: RasterManifest(schemaVersion: 0, frameHeight: 0, species: []),
                baseDir: URL(fileURLWithPath: "/"))
        let host = NSHostingView(
            rootView: RasterPetView(state: petState, store: store, onHide: { [weak self] in self?.hidePet() }))
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
        let prefix = statusItem.button?.image == nil ? "🐱 " : " "
        statusItem.button?.title = "\(prefix)▶\(snap.totalWorking) ⏸\(snap.totalWaiting) ✓\(snap.totalCompleted)"
        petState.energy = snap.energy
        petState.level = snap.level
        petState.energyToNext = coordinator.engine.threshold(forLevel: snap.level)
        petState.working = snap.totalWorking
        petState.waiting = snap.totalWaiting
        petState.completed = snap.totalCompleted
        petState.stage = PetSelection.stage(forLevel: snap.level)
        if snap.totalCompleted > lastCompleted {
            petState.mood = .celebrate  // 刚完成任务 → 撒花演出
        } else if petState.mood == .evolve || petState.mood == .celebrate {
            petState.mood = snap.totalWorking > 0 ? .working : (snap.totalWaiting > 0 ? .waiting : .idle)
        } else if snap.totalWorking > 0 {
            petState.mood = .working
        } else if snap.totalWaiting > 0 {
            petState.mood = .waiting
        } else {
            petState.mood = .idle
        }
        lastCompleted = snap.totalCompleted
        refreshVariant()
    }

    /// mood → 状态键（idle/working/waiting/complete）。
    private func stateKey(for mood: PetState.Mood) -> String {
        switch mood {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .celebrate, .evolve: return "complete"
        }
    }

    /// 进入新状态/阶段时，随机挑一个动作变体并重置播放起点。
    /// 状态/阶段变化时重置动画播放起点（用于循环与一次性 complete 计时）。
    private func refreshVariant() {
        let key = stateKey(for: petState.mood)
        guard key != lastStateKey || petState.stage != lastStage else { return }
        lastStateKey = key
        lastStage = petState.stage
        petState.variantStart = Date()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = lastSnapshot ?? coordinator.snapshot()
        let next = Int(coordinator.engine.threshold(forLevel: snap.level))

        func disabled(_ title: String) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        disabled("● 监控中")
        disabled("最近事件：\(lastEventText(snap))")
        disabled("Lv\(snap.level)   能量 \(Int(snap.energy))/\(next)")
        menu.addItem(.separator())

        let installed = (try? installer.isInstalled()) ?? false
        let qoderInstalled = (try? qoderInstaller.isInstalled()) ?? false
        disabled("Claude 集成：\(installed ? "已启用 ✓" : "未启用 ✗")")
        disabled("Qoder 集成：\(qoderInstalled ? "已启用 ✓" : "未启用 ✗")")
        if snap.clients.isEmpty {
            disabled("尚未收到事件 —— 启用集成并在客户端新开会话")
        } else {
            for c in snap.clients {
                disabled("\(c.client)   ▶\(c.counts.working) ⏸\(c.counts.waiting) ✓\(c.counts.completed)")
            }
        }
        menu.addItem(.separator())

        addAction(
            to: menu, title: (petPanel?.isVisible ?? false) ? "隐藏宠物" : "显示宠物",
            action: #selector(togglePet))
        addAction(
            to: menu, title: installed ? "停用 Claude 集成" : "启用 Claude 集成",
            action: #selector(toggleClaude))
        addAction(
            to: menu, title: qoderInstalled ? "停用 Qoder 集成" : "启用 Qoder 集成",
            action: #selector(toggleQoder))
        addAction(to: menu, title: "运行诊断…", action: #selector(runDiagnostics))
        addAction(to: menu, title: "打开日志文件", action: #selector(openLog))

        menu.addItem(.separator())
        addAction(to: menu, title: "退出 agentmon", action: #selector(quit), key: "q")
    }

    private func addAction(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func lastEventText(_ snap: MonitorSnapshot) -> String {
        guard let at = snap.lastEventAt else { return "暂无（尚未收到事件）" }
        let age = Int(Date().timeIntervalSince(at))
        if age < 0 { return "刚刚" }
        if age < 60 { return "\(age) 秒前" }
        if age < 3600 { return "\(age / 60) 分钟前" }
        return "\(age / 3600) 小时前"
    }

    // MARK: - Actions

    private func hidePet() { petPanel?.orderOut(nil) }

    @objc private func togglePet() {
        guard let panel = petPanel else { return }
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFrontRegardless() }
    }

    @objc private func toggleClaude() { toggleIntegration(installer, name: "Claude Code") }
    @objc private func toggleQoder() { toggleIntegration(qoderInstaller, name: "Qoder") }

    private func toggleIntegration(_ installer: ClaudeHookInstaller, name: String) {
        do {
            if (try? installer.isInstalled()) == true {
                try installer.uninstall()
            } else {
                try installer.install()
                notifyIntegrationEnabled(name)
            }
        } catch {
            AgentmonLog.shared.error("hook", "\(name) 集成操作失败：\(error)")
            let alert = NSAlert()
            alert.messageText = "\(name) 集成操作失败"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
    }

    private func notifyIntegrationEnabled(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "\(name) 集成已启用"
        alert.informativeText = "请在 \(name) 中新开一个会话，hooks 才会生效。之后跑任务即可在此看到计数。"
        alert.runModal()
    }

    @objc private func runDiagnostics() {
        let report = Diagnostics.report(
            appVersion: AppInfo.version,
            claudeSettings: AgentmonPaths.claudeSettings,
            reporterCommand: AppInfo.reporterCommand(),
            installer: installer,
            spool: AgentmonPaths.spool,
            stateFile: AgentmonPaths.stateFile,
            now: Date(),
            recentLog: AgentmonLog.shared.recentLines(20),
            qoderSettings: AgentmonPaths.qoderSettings,
            qoderInstaller: qoderInstaller)
        let url = AgentmonPaths.diagnosticsFile
        try? report.data(using: .utf8)?.write(to: url)
        NSWorkspace.shared.open(url)
    }

    @objc private func openLog() {
        let url = AgentmonPaths.logFile
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data("(暂无日志)\n".utf8).write(to: url)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        persist()
        NSApplication.shared.terminate(nil)
    }
}
