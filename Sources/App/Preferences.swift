import Foundation
import ServiceManagement

/// 用户偏好：简单设置放 UserDefaults，控制器列表（含口令）放仅本人可读的 JSON 文件
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    static let refreshChoices = [10, 30, 60, 300]

    private let defaults = UserDefaults.standard

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "language"); L10n.selection = language }
    }
    @Published var refreshInterval: Int {
        didSet { defaults.set(refreshInterval, forKey: "refreshInterval") }
    }
    @Published var showLatency: Bool {
        didSet { defaults.set(showLatency, forKey: "showLatency") }
    }
    @Published var mbEnabled: Bool {
        didSet { defaults.set(mbEnabled, forKey: "mbEnabled") }
    }
    /// nil 表示自动检测
    @Published var activeControllerID: UUID? {
        didSet { defaults.set(activeControllerID?.uuidString, forKey: "activeController") }
    }
    @Published private(set) var controllers: [ControllerConfig] = []

    var activeController: ControllerConfig? {
        activeControllerID.flatMap { id in controllers.first { $0.id == id } }
    }

    static var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ClashBar", isDirectory: true)
    }
    private var controllersURL: URL { Self.supportDirectory.appendingPathComponent("controllers.json") }

    private init() {
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "") ?? .system
        let interval = defaults.integer(forKey: "refreshInterval")
        refreshInterval = Self.refreshChoices.contains(interval) ? interval : 30
        showLatency = defaults.bool(forKey: "showLatency")
        mbEnabled = defaults.bool(forKey: "mbEnabled")
        activeControllerID = defaults.string(forKey: "activeController").flatMap(UUID.init(uuidString:))
        L10n.selection = language
        loadControllers()
        if activeController == nil { activeControllerID = nil }
    }

    // MARK: - 控制器列表

    private func loadControllers() {
        guard let data = try? Data(contentsOf: controllersURL),
              let list = try? JSONDecoder().decode([ControllerConfig].self, from: data) else { return }
        controllers = list
    }

    private func saveControllers() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(controllers).write(to: controllersURL, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: controllersURL.path)
        } catch {
            NSLog("ClashBar: failed to save controllers: \(error.localizedDescription)")
        }
    }

    func upsert(_ controller: ControllerConfig) {
        if let index = controllers.firstIndex(where: { $0.id == controller.id }) {
            controllers[index] = controller
        } else {
            controllers.append(controller)
        }
        saveControllers()
    }

    func remove(_ id: UUID) {
        controllers.removeAll { $0.id == id }
        if activeControllerID == id { activeControllerID = nil }
        saveControllers()
    }

    // MARK: - 登录时启动（SMAppService，macOS 13+）

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    var launchNeedsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        objectWillChange.send()
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// 旧版用 LaunchAgent 实现开机启动；迁移到 SMAppService 并删掉旧文件
    func migrateLegacyLaunchAgent() {
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/org.clashbar.ClashBar.plist")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.removeItem(at: legacy)
        try? SMAppService.mainApp.register()
    }
}
