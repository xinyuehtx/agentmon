import Foundation
import agentmonCore

// agentmon-hook: 多客户端 hook 上报器。
// 客户端在 hook 触发时把事件 JSON 通过 stdin 传入（Claude 家族 / Codex），或由 opencode 插件以
// 归一化参数直传：`agentmon-hook <client> [<kind> [<sid>]]`。解析后原子写入 spool 目录。
// 契约见 Sources/Core/HookInvocation.swift。

let args = CommandLine.arguments
let stdin =
    HookInvocation.needsStdin(arguments: args)
    ? FileHandle.standardInput.readDataToEndOfFile() : Data()
let inv = HookInvocation.resolve(arguments: args, stdin: stdin)

do {
    try SpoolWriter.write(
        hookEventName: inv.eventName,
        sessionID: inv.sessionID,
        client: inv.client,
        receivedAt: Date(),
        directory: AgentmonPaths.spool
    )
} catch {
    FileHandle.standardError.write(Data("agentmon-hook: \(error)\n".utf8))
    exit(1)
}
