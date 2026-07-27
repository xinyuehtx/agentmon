import Foundation

/// 向 opencode 写入/移除 agentmon 插件文件（`~/.config/opencode/plugins/agentmon.js`）。
/// opencode 无 settings hooks：插件订阅 `event` 钩子，shell 调用上报器 `agentmon-hook <client> <kind> <sid>`。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.3。
public final class OpencodePluginInstaller: IntegrationInstaller {

    static let marker = "agentmon-plugin v1"

    private let pluginURL: URL
    private let reporterCommand: String  // agentmon-hook 绝对路径（不含参数）
    private let clientLabel: String
    private let fm = FileManager.default

    public init(pluginURL: URL, reporterCommand: String, clientLabel: String) {
        self.pluginURL = pluginURL
        self.reporterCommand = reporterCommand
        self.clientLabel = clientLabel
    }

    private var backupURL: URL {
        pluginURL.deletingLastPathComponent()
            .appendingPathComponent(pluginURL.lastPathComponent + ".agentmon.bak")
    }

    /// 生成插件源码（首行标记 + 内嵌上报器路径与客户端标签）。
    func pluginSource() -> String {
        """
        // \(Self.marker) (managed by agentmon; delete this file to uninstall)
        const HOOK = \(jsString(reporterCommand));
        const CLIENT = \(jsString(clientLabel));
        export const agentmon = async ({ $ }) => {
          const working = new Set();
          const send = (kind, id) =>
            $`${HOOK} ${CLIENT} ${kind} ${id || "unknown"}`.quiet().catch(() => {});
          return {
            event: async ({ event }) => {
              const p = (event && event.properties) || {};
              const id =
                p.sessionID || p.sessionId || (p.info && p.info.id) || (p.session && p.session.id) || "unknown";
              switch (event && event.type) {
                case "message.part.updated":
                  if (!working.has(id)) {
                    working.add(id);
                    await send("start", id);
                  }
                  break;
                case "permission.updated":
                case "permission.asked":
                  await send("pause", id);
                  break;
                case "permission.replied":
                  if (!working.has(id)) working.add(id);
                  await send("start", id);
                  break;
                case "session.idle":
                case "session.error":
                  working.delete(id);
                  await send("end", id);
                  break;
                default:
                  break;
              }
            },
          };
        };
        """
    }

    private func jsString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public func install() throws {
        try fm.createDirectory(
            at: pluginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 已存在他人的同名文件（非本插件）→ 先备份，避免覆盖用户内容。
        if fm.fileExists(atPath: pluginURL.path), try !isInstalled() {
            if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
            try fm.copyItem(at: pluginURL, to: backupURL)
        }
        let tmp = pluginURL.appendingPathExtension("tmp")
        try Data(pluginSource().utf8).write(to: tmp)
        if fm.fileExists(atPath: pluginURL.path) { try fm.removeItem(at: pluginURL) }
        try fm.moveItem(at: tmp, to: pluginURL)
        AgentmonLog.shared.info("hook", "已启用 opencode 集成（写入插件文件）")
    }

    public func uninstall() throws {
        guard try isInstalled() else { return }  // 只删本插件
        try fm.removeItem(at: pluginURL)
        AgentmonLog.shared.info("hook", "已停用 opencode 集成（移除插件文件）")
    }

    public func isInstalled() throws -> Bool {
        guard let data = try? Data(contentsOf: pluginURL) else { return false }
        return String(decoding: data, as: UTF8.self).contains(Self.marker)
    }
}
