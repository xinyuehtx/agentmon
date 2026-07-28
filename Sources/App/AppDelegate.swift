import AppKit
import SwiftUI
import agentmonCore

/// 组合 Core + 菜单栏 + 宠物浮窗 + 控制台窗口 + 定时 pump。
/// 契约见 specs/agent-task-monitor.md §7、§8、rfcs/multi-client-and-control-panel.md。
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
    private let appSettingsStore = AppSettingsStore(url: AgentmonPaths.appSettingsFile)
    private var appSettings = AppSettings.default

    // 集成：由数据驱动注册表构建，按自定义路径重建。
    private var descriptors: [ClientIntegration] = []
    private var installers: [String: IntegrationInstaller] = [:]
    private var integrationErrors: [String: String] = [:]

    // 控制台
    let appModel = AppModel()
    private var panelController: ControlPanelWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AgentmonLog.shared.configure(fileURL: AgentmonPaths.logFile)
        AgentmonLog.shared.info("app", "启动 agentmon v\(AppInfo.version)")
        appSettings = appSettingsStore.load()
        rebuildInstallers()
        setupCoordinator()
        wireModel()
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

    /// 依据当前自定义路径重建描述符与安装器字典。
    private func rebuildInstallers() {
        let reporter = AppInfo.reporterCommand()
        descriptors = IntegrationRegistry.descriptors(customPaths: appSettings.customPaths)
        installers = Dictionary(
            uniqueKeysWithValues: descriptors.map {
                ($0.id, IntegrationRegistry.installer(for: $0, reporterCommand: reporter))
            })
    }

    private func setupCoordinator() {
        try? FileManager.default.createDirectory(at: AgentmonPaths.spool, withIntermediateDirectories: true)
        let config = (try? stateStore.loadConfig()) ?? .default
        let loaded = (try? stateStore.loadState()) ?? nil
        let engine = EnergyEngine(
            config: config,
            energy: loaded?.energy ?? 0,
            level: loaded?.level ?? 1,
            starveMinutes: loaded?.starveMinutes ?? 0,
            lastTick: loaded?.lastTick ?? Date()
        )
        engine.applyOfflineDecay(now: Date())  // 离线期空闲衰减（含饥饿累计）
        coordinator = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: AgentmonPaths.spool),
            engine: engine
        )
        coordinator.onEvolve = { [weak self] event in
            self?.petState.mood = .evolve
            self?.petState.level = event.newLevel
        }
        coordinator.onGraduate = { [weak self] species in self?.notifyGraduated(species) }
        coordinator.onDeath = { [weak self] old in self?.notifyDeath(old) }
        coordinator.restore(
            completedByClient: loaded?.completedByClient ?? [:],
            day: loaded?.completedDay, now: Date())

        // 宠物元素：读持久化，否则从图集包中随机分配一次（卸载重装因 state.json 丢失而重掷）。
        let activeIDs = rasterStore?.manifest.elementIDs ?? []
        coordinator.availableSpecies = activeIDs
        let resolvedSpecies: String
        if let persisted = loaded?.species, activeIDs.contains(persisted) {
            resolvedSpecies = persisted
        } else {
            var rng = SystemRandomNumberGenerator()
            resolvedSpecies = PetSelection.choose(speciesIDs: activeIDs, using: &rng) ?? activeIDs.first ?? ""
        }
        // 生命周期：恢复毕业收藏与展示皮肤（仅保留仍在图集内的物种）。
        let restoredGraduated = (loaded?.graduated ?? []).filter { activeIDs.contains($0) }
        coordinator.restoreLifecycle(
            species: resolvedSpecies, graduated: restoredGraduated,
            displaySkin: loaded?.displaySkin, displayStage: loaded?.displayStage)
        petState.species = resolvedSpecies
        lastCompleted = (loaded?.completedByClient.values.reduce(0, +)) ?? 0
        AgentmonLog.shared.info(
            "pet", "物种=\(resolvedSpecies) 收藏=\(restoredGraduated) 展示=\(loaded?.displaySkin ?? "活跃")")
        AgentmonLog.shared.info("app", "spool=\(AgentmonPaths.spool.path) 集成数=\(descriptors.count)")
    }

    private func wireModel() {
        appModel.onToggleIntegration = { [weak self] id, on in self?.toggleIntegration(id: id, enable: on) }
        appModel.onSetPath = { [weak self] id, path in self?.setCustomPath(id: id, path: path) }
        appModel.onResetPath = { [weak self] id in self?.resetCustomPath(id: id) }
        appModel.onSaveConfig = { [weak self] c in self?.saveConfig(c) }
        appModel.onTogglePet = { [weak self] on in self?.setPetVisible(on) }
        appModel.onHatch = { [weak self] in self?.hatchNew() }
        appModel.onShowActive = { [weak self] in self?.showActive() }
        appModel.onShowSkin = { [weak self] element in self?.selectSkin(element: element) }
        appModel.onRunDiagnostics = { [weak self] in self?.runDiagnostics() }
        appModel.onOpenLog = { [weak self] in self?.openLog() }
        panelController = ControlPanelWindowController(
            model: appModel, onOpen: { [weak self] in self?.refreshModelSettings() })
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
                manifest: RasterManifest(
                    schemaVersion: 0, character: "", frameHeight: 0, actions: [:], elements: []),
                baseDir: URL(fileURLWithPath: "/"))
        let host = NSHostingView(
            rootView: RasterPetView(state: petState, store: store, onHide: { [weak self] in self?.hidePet() }))
        let panel = PetPanel(content: host)
        panel.orderFrontRegardless()
        if !appSettings.petVisible { panel.orderOut(nil) }
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
        petState.species = snap.displaySpecies
        petState.stage = snap.displayStage
        petState.isSkin = snap.isSkinMode
        petState.growth = growthValue(snap)
        if snap.totalCompleted > lastCompleted {
            petState.mood = .celebrate  // 刚完成任务 → 撒花演出
        } else if petState.mood == .evolve || petState.mood == .celebrate {
            petState.mood = liveMood(snap)
        } else {
            petState.mood = liveMood(snap)
        }
        lastCompleted = snap.totalCompleted
        refreshVariant()
        feedDashboard(snap)
    }

    /// 由快照推导常驻情绪：工作 > 等待 > （空闲且能量为 0 → 饿了）> 发呆。
    private func liveMood(_ snap: MonitorSnapshot) -> PetState.Mood {
        if snap.totalWorking > 0 { return .working }
        if snap.totalWaiting > 0 { return .waiting }
        if snap.energy == 0 && !snap.isSkinMode && !snap.isGraduated { return .hungry }
        return .idle
    }

    /// 成长度 0..1：等级从 1 长到毕业门槛。展示收藏/已毕业视为成年（1.0）。
    private func growthValue(_ snap: MonitorSnapshot) -> Double {
        if snap.isSkinMode || snap.isGraduated { return 1.0 }
        let g = Double(coordinator.engine.config.graduationLevel)
        let t = g > 1 ? Double(snap.level - 1) / (g - 1) : 1
        return min(1.0, max(0.0, 0.55 + 0.45 * t))
    }

    /// 把快照 + 看板/活动流灌入控制台数据源。
    private func feedDashboard(_ snap: MonitorSnapshot) {
        appModel.working = snap.totalWorking
        appModel.waiting = snap.totalWaiting
        appModel.completed = snap.totalCompleted
        appModel.activeClients = snap.clients.filter { $0.counts.working + $0.counts.waiting > 0 }.count
        appModel.energy = snap.energy
        appModel.level = snap.level
        appModel.energyToNext = coordinator.engine.threshold(forLevel: snap.level)
        appModel.isGraduated = snap.isGraduated
        appModel.growth = growthValue(snap)
        appModel.clients = snap.clients
        appModel.sessions = coordinator.store.sessionRows()
        appModel.activity = coordinator.recentActivity(limit: 50)
        appModel.lastEventAt = snap.lastEventAt
        appModel.eventsSeen = snap.eventsSeen
        appModel.displaySpecies = snap.displaySpecies
        appModel.displayStage = snap.displayStage
        appModel.isSkinMode = snap.isSkinMode
        appModel.graduated = snap.graduated
        appModel.activeElement = coordinator.species ?? ""
    }

    /// mood → 状态键（idle/working/waiting/complete/hungry）。
    private func stateKey(for mood: PetState.Mood) -> String {
        switch mood {
        case .idle: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .celebrate, .evolve: return "complete"
        case .hungry: return "hungry"
        }
    }

    /// 进入新状态/阶段时，随机挑一个动作变体并重置播放起点。
    private func refreshVariant() {
        let key = stateKey(for: petState.mood)
        guard key != lastStateKey || petState.stage != lastStage else { return }
        lastStateKey = key
        lastStage = petState.stage
        petState.variantStart = Date()
    }

    // MARK: - Menu（精简：仅总数标题 + 打开控制台 + 退出）

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addAction(to: menu, title: "打开控制台…", action: #selector(openControlPanel))
        menu.addItem(.separator())
        addAction(to: menu, title: "退出 agentmon", action: #selector(quit), key: "q")
    }

    private func addAction(to menu: NSMenu, title: String, action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    // MARK: - 控制台

    @objc private func openControlPanel() {
        panelController?.show()
    }

    /// 面板打开时刷新设置态（集成状态、能量参数、宠物态、图鉴、仪表盘）。
    private func refreshModelSettings() {
        appModel.energyConfig = coordinator.engine.config
        appModel.petVisible = petPanel?.isVisible ?? appSettings.petVisible
        appModel.elements = (rasterStore?.manifest.elements ?? []).map {
            PetElementInfo(
                id: $0.id, name: $0.name, tint: $0.tint,
                portraitPath: rasterStore?.elementPortraitURL($0.id)?.path ?? "")
        }
        refreshIntegrationRows()
        if let snap = lastSnapshot { feedDashboard(snap) }
    }

    private func refreshIntegrationRows() {
        appModel.integrations = descriptors.map { d in
            var installed = false
            if let inst = installers[d.id] { installed = (try? inst.isInstalled()) ?? false }
            return IntegrationRow(
                id: d.id, name: d.displayName, symbol: d.symbol, mechanism: d.mechanism,
                path: d.defaultPath.path, installed: installed,
                error: integrationErrors[d.id], verified: d.verified, note: d.note)
        }
    }

    // MARK: - Actions

    private func toggleIntegration(id: String, enable: Bool) {
        guard let installer = installers[id], let d = descriptors.first(where: { $0.id == id }) else { return }
        integrationErrors[id] = nil
        do {
            if enable {
                try installer.install()
                notifyIntegrationEnabled(d)
            } else {
                try installer.uninstall()
            }
        } catch {
            integrationErrors[id] = "\(error)"
            AgentmonLog.shared.error("hook", "\(d.displayName) 集成操作失败：\(error)")
            let alert = NSAlert()
            alert.messageText = "\(d.displayName) 集成操作失败"
            alert.informativeText = "\(error)"
            alert.runModal()
        }
        refreshIntegrationRows()
    }

    private func notifyIntegrationEnabled(_ d: ClientIntegration) {
        let alert = NSAlert()
        alert.messageText = "\(d.displayName) 集成已启用"
        var info = "请在 \(d.displayName) 中新开一个会话，hooks 才会生效。之后跑任务即可在控制台看到计数。"
        if let note = d.note { info += "\n\n\(note)" }
        alert.informativeText = info
        alert.runModal()
    }

    private func setCustomPath(id: String, path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        appSettings.customPaths[id] = trimmed.isEmpty ? nil : trimmed
        saveAppSettings()
        rebuildInstallers()
        refreshIntegrationRows()
    }

    private func resetCustomPath(id: String) {
        appSettings.customPaths[id] = nil
        saveAppSettings()
        rebuildInstallers()
        refreshIntegrationRows()
    }

    private func saveConfig(_ config: EnergyConfig) {
        try? stateStore.saveConfig(config)
        appModel.energyConfig = config
        let alert = NSAlert()
        alert.messageText = "能量参数已保存"
        alert.informativeText = "新参数将在下次启动 agentmon 后生效。"
        alert.runModal()
    }

    private func setPetVisible(_ on: Bool) {
        if on { petPanel?.orderFrontRegardless() } else { petPanel?.orderOut(nil) }
        appSettings.petVisible = on
        appModel.petVisible = on
        saveAppSettings()
    }

    private func saveAppSettings() {
        try? appSettingsStore.save(appSettings)
    }

    private func hidePet() {
        petPanel?.orderOut(nil)
        appSettings.petVisible = false
        appModel.petVisible = false
        saveAppSettings()
    }

    private func hatchNew() {
        // 未毕业时孵化 = 放弃当前宠物，需确认。
        if let snap = lastSnapshot, !snap.isGraduated, !snap.isSkinMode {
            let alert = NSAlert()
            alert.messageText = "孵化新宠物？"
            alert.informativeText = "当前宠物尚未毕业，孵化新宠物会放弃它（不会进入收藏）。确定继续吗？"
            alert.addButton(withTitle: "孵化")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        coordinator.hatchNewPet(now: Date())
        pump()
    }

    private func showActive() {
        coordinator.showActivePet()
        pump()
    }

    private func selectSkin(element: String) {
        coordinator.showSkin(element, stage: nil)
        pump()
    }

    private func notifyGraduated(_ species: String) {
        petState.mood = .celebrate
        let alert = NSAlert()
        alert.messageText = "🎓 \(PetNaming.species(species)) 毕业啦！"
        alert.informativeText = "它已解锁为永久皮肤，可在控制台「桌宠设置 · 收藏皮肤」里随时切换展示与形态。你可以选择「孵化新宠物」开启下一只。"
        alert.runModal()
    }

    private func notifyDeath(_ old: String) {
        petState.mood = .idle
        AgentmonLog.shared.warn("pet", "\(PetNaming.species(old)) 因长期空闲饿死，新蛋孵化中")
    }

    @objc private func runDiagnostics() {
        let integrations = descriptors.compactMap { d -> Diagnostics.IntegrationStatus? in
            guard let installer = installers[d.id] else { return nil }
            return Diagnostics.IntegrationStatus(descriptor: d, installer: installer)
        }
        let report = Diagnostics.report(
            appVersion: AppInfo.version,
            reporterCommand: AppInfo.reporterCommand(),
            integrations: integrations,
            spool: AgentmonPaths.spool,
            stateFile: AgentmonPaths.stateFile,
            now: Date(),
            recentLog: AgentmonLog.shared.recentLines(20))
        let url = AgentmonPaths.diagnosticsFile
        try? Data(report.utf8).write(to: url)
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
