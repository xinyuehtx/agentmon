import Foundation

/// 应用级设置（区别于各客户端自身的 settings.json）：自定义集成路径 + 桌宠 UI 偏好。
/// 「是否启用集成」不持久化——以各安装器 `isInstalled()`（读客户端自身配置）为准，避免与手改漂移。
/// 契约见 rfcs/multi-client-and-control-panel.md §4.5。
public struct AppSettings: Codable, Equatable {
    public var schemaVersion: Int
    /// integration.id → 用户覆盖的绝对路径。
    public var customPaths: [String: String]
    public var petVisible: Bool
    public var petScale: Double?
    public var petOrigin: [Double]?  // [x, y]

    public init(
        schemaVersion: Int = 1,
        customPaths: [String: String] = [:],
        petVisible: Bool = true,
        petScale: Double? = nil,
        petOrigin: [Double]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.customPaths = customPaths
        self.petVisible = petVisible
        self.petScale = petScale
        self.petOrigin = petOrigin
    }

    /// 向后兼容解码：旧文件缺字段用默认值（仿 EnergyConfig）。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        customPaths = try c.decodeIfPresent([String: String].self, forKey: .customPaths) ?? [:]
        petVisible = try c.decodeIfPresent(Bool.self, forKey: .petVisible) ?? true
        petScale = try c.decodeIfPresent(Double.self, forKey: .petScale)
        petOrigin = try c.decodeIfPresent([Double].self, forKey: .petOrigin)
    }

    public static let `default` = AppSettings()
}

/// app-settings.json 的读写（原子写、缺失回退默认，仿 StateStore）。
public final class AppSettingsStore {
    private let url: URL
    private let fm = FileManager.default

    public init(url: URL) {
        self.url = url
    }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url) else { return .default }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? .default
    }

    public func save(_ settings: AppSettings) throws {
        let data = try JSONEncoder().encode(settings)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp")
        try data.write(to: tmp)
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: tmp, to: url)
    }
}
