import Foundation
import agentmonCore

// agentmon-hook: Claude Code hook 上报器。
// Claude 在 hook 触发时把事件 JSON 通过 stdin 传入；本程序解析后原子写入 spool 目录。
// 注册命令即为本可执行文件路径（读 stdin，无需参数）。

let inputData = FileHandle.standardInput.readDataToEndOfFile()
let obj = (try? JSONSerialization.jsonObject(with: inputData)) as? [String: Any]

let eventName = (obj?["hook_event_name"] as? String) ?? "Unknown"
let sessionID = (obj?["session_id"] as? String) ?? "unknown"
let client = "Claude Code"

do {
    try SpoolWriter.write(
        hookEventName: eventName,
        sessionID: sessionID,
        client: client,
        receivedAt: Date(),
        directory: AgentmonPaths.spool
    )
} catch {
    FileHandle.standardError.write(Data("agentmon-hook: \(error)\n".utf8))
    exit(1)
}
