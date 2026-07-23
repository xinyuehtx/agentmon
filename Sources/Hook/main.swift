import Foundation
import agentmonCore

// agentmon-hook: Claude Code / Qoder hook 上报器。
// 客户端在 hook 触发时把事件 JSON 通过 stdin 传入；本程序解析后原子写入 spool 目录。
// 用法：注册命令为本可执行文件路径，可选带客户端名作为参数（默认 "Claude Code"）：
//   /path/agentmon-hook            → client = "Claude Code"
//   /path/agentmon-hook Qoder      → client = "Qoder"

let inputData = FileHandle.standardInput.readDataToEndOfFile()
let obj = (try? JSONSerialization.jsonObject(with: inputData)) as? [String: Any]

let eventName = (obj?["hook_event_name"] as? String) ?? "Unknown"
let sessionID = (obj?["session_id"] as? String) ?? "unknown"
let client = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Claude Code"

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
