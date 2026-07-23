import Foundation
import agentmonCore

/// 无 GUI 自检：模拟一次 start→end，验证 Core 编排（摄取→计数→能量）正确后退出。
enum SelfTest {
    static func run() -> Never {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmon-selftest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let now = Date()
        do {
            try SpoolWriter.write(
                hookEventName: "UserPromptSubmit", sessionID: "s1",
                client: "Claude Code", receivedAt: now, directory: dir)
            try SpoolWriter.write(
                hookEventName: "Stop", sessionID: "s1",
                client: "Claude Code", receivedAt: now.addingTimeInterval(1), directory: dir)
        } catch {
            FileHandle.standardError.write(Data("[selftest] write failed: \(error)\n".utf8))
            exit(1)
        }

        let coordinator = MonitorCoordinator(
            ingestor: SpoolIngestor(directory: dir),
            engine: EnergyEngine(lastTick: now)
        )
        let snap = coordinator.pump(now: now)
        try? FileManager.default.removeItem(at: dir)

        let ok = snap.totalCompleted == 1 && snap.totalWorking == 0 && snap.energy >= 29.0
        print(
            "[selftest] completed=\(snap.totalCompleted) working=\(snap.totalWorking) "
                + "energy=\(snap.energy) level=\(snap.level) -> \(ok ? "OK" : "FAIL")")
        exit(ok ? 0 : 1)
    }
}
