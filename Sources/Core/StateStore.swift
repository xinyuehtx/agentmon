import Foundation

/// 可持久化的运行时状态。契约见 specs/agent-task-monitor.md §6。
public struct PersistentState: Codable, Equatable {
    public var energy: Double
    public var level: Int
    public var completedByClient: [String: Int]
    public var lastTick: Date
    /// 完成计数所属日期（本地 YYYY-MM-DD）；跨天清零用。旧文件无此字段 → nil。
    public var completedDay: String?
    /// 本次安装随机分配到的宠物物种 id；旧文件/首次为 nil（App 会随机并回填）。
    public var species: String?
    /// 能量归零后累计的空闲分钟数（饥饿计时）；旧文件为 nil → 0。
    public var starveMinutes: Double?
    /// 已毕业解锁的永久皮肤物种 id 列表；旧文件为 nil → []。
    public var graduated: [String]?
    /// 当前展示的收藏皮肤物种 id；nil = 展示活跃宠物。
    public var displaySkin: String?
    /// 展示皮肤时选定的形态（egg/juvenile/mature/final）；nil = final。
    public var displayStage: String?

    public init(
        energy: Double, level: Int, completedByClient: [String: Int], lastTick: Date,
        completedDay: String? = nil, species: String? = nil,
        starveMinutes: Double? = nil, graduated: [String]? = nil,
        displaySkin: String? = nil, displayStage: String? = nil
    ) {
        self.energy = energy
        self.level = level
        self.completedByClient = completedByClient
        self.lastTick = lastTick
        self.completedDay = completedDay
        self.species = species
        self.starveMinutes = starveMinutes
        self.graduated = graduated
        self.displaySkin = displaySkin
        self.displayStage = displayStage
    }
}

/// state.json / config.json 的读写（原子写、缺失回退）。
public final class StateStore {
    private let stateURL: URL
    private let configURL: URL
    private let fm = FileManager.default

    public init(stateURL: URL, configURL: URL) {
        self.stateURL = stateURL
        self.configURL = configURL
    }

    private static func isoEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func isoDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: tmp, to: url)
    }

    public func loadState() throws -> PersistentState? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try Self.isoDecoder().decode(PersistentState.self, from: data)
    }

    public func saveState(_ state: PersistentState) throws {
        try atomicWrite(Self.isoEncoder().encode(state), to: stateURL)
    }

    public func loadConfig() throws -> EnergyConfig {
        guard let data = try? Data(contentsOf: configURL) else { return .default }
        return (try? JSONDecoder().decode(EnergyConfig.self, from: data)) ?? .default
    }

    public func saveConfig(_ config: EnergyConfig) throws {
        try atomicWrite(JSONEncoder().encode(config), to: configURL)
    }
}
