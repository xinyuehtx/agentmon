import Foundation

/// 生成人类可读的诊断报告，帮助用户自查「Agent 监控为何不工作」。
/// 纯逻辑（依赖注入路径与安装器），可单测；由 `--doctor` CLI 与控制台「运行诊断」复用。
public enum Diagnostics {

    /// 一个客户端的诊断输入：描述符 + 其安装器。
    public struct IntegrationStatus {
        public let descriptor: ClientIntegration
        public let installer: IntegrationInstaller
        public init(descriptor: ClientIntegration, installer: IntegrationInstaller) {
            self.descriptor = descriptor
            self.installer = installer
        }
    }

    private static func loadState(_ url: URL) -> PersistentState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PersistentState.self, from: data)
    }

    public static func report(
        appVersion: String,
        reporterCommand: String,
        integrations: [IntegrationStatus],
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

        line("【上报器】")
        line("路径：\(reporterCommand)")
        let hookExists = fm.fileExists(atPath: reporterCommand)
        line("存在：\(hookExists ? "是" : "否")")
        line("可执行：\(hookExists && fm.isExecutableFile(atPath: reporterCommand) ? "是" : "否")")
        line()

        var anyInstalled = false
        for status in integrations {
            let d = status.descriptor
            let installed = (try? status.installer.isInstalled()) ?? false
            anyInstalled = anyInstalled || installed
            line("【\(d.displayName) 集成】")
            line("配置路径：\(d.defaultPath.path)")
            line("配置存在：\(fm.fileExists(atPath: d.defaultPath.path) ? "是" : "否")")
            line("agentmon 接入：\(installed ? "已启用 ✓" : "未启用 ✗")")
            if let note = d.note { line("说明：\(note)") }
            if !d.verified { line("注意：该客户端路径为最佳猜测，未经验证。") }
            line()
        }

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
            for entry in recentLog { line(entry) }
        }
        line()

        line("【建议】")
        if !anyInstalled {
            line("• 尚未启用任何集成：在控制台「监控设置」里为某个客户端打开开关。")
        } else {
            line("• 已启用集成。若计数不动：在对应客户端【新开会话】后再跑任务。")
        }
        line("• 完整日志：\(AgentmonPaths.logFile.path)")

        return out.joined(separator: "\n")
    }
}
