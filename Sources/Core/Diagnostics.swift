import Foundation

/// 生成人类可读的诊断报告，帮助用户自查「Agent 监控为何不工作」。
/// 纯逻辑（依赖注入路径与 installer），可单测；由 `--doctor` CLI 与菜单「运行诊断」复用。
public enum Diagnostics {

    private static func loadState(_ url: URL) -> PersistentState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistentState.self, from: data)
    }

    public static func report(
        appVersion: String,
        claudeSettings: URL,
        reporterCommand: String,
        installer: ClaudeHookInstaller,
        spool: URL,
        stateFile: URL,
        now: Date,
        recentLog: [String]
    ) -> String {
        let fm = FileManager.default
        var out: [String] = []
        func line(_ s: String = "") { out.append(s) }

        line("agentmon 诊断报告  v\(appVersion)")
        line("时间：\(ISO8601DateFormatter().string(from: now))")
        line(String(repeating: "─", count: 44))

        line("【Claude 集成】")
        line("settings 路径：\(claudeSettings.path)")
        line("settings 存在：\(fm.fileExists(atPath: claudeSettings.path) ? "是" : "否")")
        let installed = (try? installer.isInstalled()) ?? false
        line("agentmon hooks：\(installed ? "已启用 ✓" : "未启用 ✗")")
        line("上报器路径：\(reporterCommand)")
        let hookExists = fm.fileExists(atPath: reporterCommand)
        line("上报器存在：\(hookExists ? "是" : "否")")
        line("上报器可执行：\(hookExists && fm.isExecutableFile(atPath: reporterCommand) ? "是" : "否")")
        line("提示：启用集成后需在 Claude Code【新开会话】，hooks 才会加载。")
        line()

        line("【事件队列 spool】")
        line("路径：\(spool.path)")
        let spoolExists = fm.fileExists(atPath: spool.path)
        line("存在：\(spoolExists ? "是" : "否")")
        if spoolExists {
            let pending =
                (try? fm.contentsOfDirectory(atPath: spool.path).filter { $0.hasSuffix(".json") }.count) ?? 0
            line("待处理文件：\(pending)")
            line("可写：\(fm.isWritableFile(atPath: spool.path) ? "是" : "否")")
        }
        line()

        line("【运行状态】")
        if let st = loadState(stateFile) {
            line("能量：\(Int(st.energy))   等级：Lv\(st.level)")
            let age = Int(now.timeIntervalSince(st.lastTick))
            line("最近心跳：\(age) 秒前 \(age <= 10 ? "(运行中)" : "(可能未运行)")")
            if st.completedByClient.isEmpty {
                line("客户端：尚无（未收到任何事件）")
            } else {
                for (client, n) in st.completedByClient.sorted(by: { $0.key < $1.key }) {
                    line("客户端 \(client)：累计完成 \(n)")
                }
            }
        } else {
            line("state.json 未生成（App 尚未运行或无数据）")
        }
        line()

        line("【最近日志】")
        if recentLog.isEmpty {
            line("（无——App 未运行或未产生事件）")
        } else {
            recentLog.forEach { line($0) }
        }
        line()

        line("【建议】")
        if !installed {
            line("• 未启用集成：点击菜单「启用 Claude 集成」。")
        } else {
            line("• 已启用集成。若计数不动：在 Claude Code【新开会话】后再跑任务。")
        }
        line("• 完整日志：\(AgentmonPaths.logFile.path)")

        return out.joined(separator: "\n")
    }
}
