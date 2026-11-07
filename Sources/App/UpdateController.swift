import AppKit
import Combine
import Foundation
import Security
#if !APP_STORE
import Sparkle
#endif

#if !APP_STORE
@MainActor
final class UpdateController: NSObject, ObservableObject {
    enum Mode {
        case homebrew(HomebrewInstallation), direct, development, appStore, unavailable
    }

    static let shared = UpdateController()
    static let releasesURL = URL(string: "https://github.com/fangxuanxin/ClashBar/releases")!
    private let defaults: UserDefaults
    private let bundle: Bundle
    private var automaticTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var syncPreferences = false
    private var preferenceObservation: AnyCancellable?
    private(set) var mode: Mode = .development
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published private(set) var readyToInstall = false
    @Published private(set) var availableVersion: String?
    @Published private(set) var message: String?
    @Published private(set) var lastChecked: Date?
    @Published var automaticChecks: Bool {
        didSet {
            guard !syncPreferences else { return }
            defaults.set(automaticChecks, forKey: "updateAutomaticChecks")
            #if !APP_STORE
            sparkle?.updater.automaticallyChecksForUpdates = automaticChecks
            #endif
            scheduleChecks()
        }
    }
    @Published var automaticInstallation: Bool {
        didSet {
            guard !syncPreferences else { return }
            #if !APP_STORE
            sparkle?.updater.automaticallyDownloadsUpdates = automaticInstallation
            #endif
        }
    }
    @Published var channel: UpdateChannel {
        didSet {
            defaults.set(channel.rawValue, forKey: "updateChannel")
            #if !APP_STORE
            sparkle?.updater.resetUpdateCycle()
            #endif
        }
    }
    #if !APP_STORE
    private var sparkle: SPUStandardUpdaterController?
    #endif

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.defaults = defaults
        automaticChecks = defaults.object(forKey: "updateAutomaticChecks") as? Bool ?? true
        automaticInstallation = defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? true
        channel = UpdateChannel(rawValue: defaults.string(forKey: "updateChannel") ?? "") ?? .stable
        lastChecked = defaults.object(forKey: "updateLastChecked") as? Date
        super.init()
    }

    var supportsChecks: Bool {
        switch mode {
        case .homebrew, .direct: return true
        default: return false
        }
    }

    var supportsInstallationPreference: Bool {
        if case .direct = mode { return true }
        return false
    }

    var menuTitle: String {
        if isInstalling { return L10n.t("updates.installing") }
        if isChecking { return L10n.t("updates.checking") }
        if readyToInstall { return L10n.t("updates.ready") }
        if availableVersion != nil { return L10n.t("updates.upgrade") }
        return L10n.t(supportsChecks ? "updates.check" : "updates.open_release")
    }

    var sourceTitle: String {
        switch mode {
        case .homebrew: return L10n.t("updates.source.brew")
        case .direct: return L10n.t("updates.source.direct")
        case .appStore: return L10n.t("updates.source.store")
        case .development: return L10n.t("updates.dev_hint")
        case .unavailable: return L10n.t("updates.error.unavailable")
        }
    }

    func start() {
        #if APP_STORE
        mode = .appStore
        #else
        do {
            if let installation = try HomebrewInstallation.find(app: bundle.bundleURL) {
                mode = .homebrew(installation)
                scheduleChecks()
                return
            }
            #if UPDATE_TESTING
            let trustedBuild = bundle.object(forInfoDictionaryKey: "ClashBarUpdateTest") as? Bool == true
            #else
            let trustedBuild = Self.isDeveloperIDSigned(bundle.bundleURL)
            #endif
            guard trustedBuild,
                  let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  Data(base64Encoded: key)?.count == 32 else {
                mode = .development
                return
            }
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
            sparkle = controller
            mode = .direct
            controller.updater.automaticallyChecksForUpdates = automaticChecks
            preferenceObservation = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification, object: defaults)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self else { return }
                    let enabled = defaults.object(forKey: "SUAutomaticallyUpdate") as? Bool ?? true
                    guard enabled != automaticInstallation else { return }
                    syncPreferences = true
                    automaticInstallation = enabled
                    syncPreferences = false
                }
            try controller.updater.start()
            #if UPDATE_TESTING
            controller.updater.checkForUpdatesInBackground()
            #endif
        } catch {
            mode = .unavailable
            message = L10n.t("updates.failed", ["reason": error.localizedDescription])
        }
        #endif
    }

    func checkForUpdates() {
        guard !isInstalling && !isChecking else { return }
        switch mode {
        case .homebrew(let installation):
            if let availableVersion { confirmUpgrade(installation, target: availableVersion) }
            else { checkHomebrew(installation, manual: true) }
        case .direct:
            #if !APP_STORE
            sparkle?.checkForUpdates(nil)
            #endif
        case .development, .unavailable:
            NSWorkspace.shared.open(Self.releasesURL)
        case .appStore: break
        }
    }

    func stop() {
        automaticTask?.cancel()
        checkTask?.cancel()
    }

    private func scheduleChecks() {
        automaticTask?.cancel()
        guard automaticChecks, case .homebrew(let installation) = mode else { return }
        automaticTask = Task { [weak self] in
            if let last = self?.lastChecked {
                let remaining = max(0, 86400 - Date().timeIntervalSince(last))
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            while !Task.isCancelled {
                self?.checkHomebrew(installation, manual: false)
                do { try await Task.sleep(nanoseconds: 86_400_000_000_000) }
                catch { return }
            }
        }
    }

    private func checkHomebrew(_ installation: HomebrewInstallation, manual: Bool) {
        guard !isChecking && !isInstalling else { return }
        isChecking = true
        message = nil
        checkTask = Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false }
            do {
                let path = installation.tap == "homebrew/cask" ? "Homebrew/homebrew-cask/HEAD/Casks/c/clashbar.rb" : "fangxuanxin/homebrew-tap/main/Casks/clashbar.rb"
                let url = URL(string: "https://raw.githubusercontent.com/" + path)!
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.setValue("ClashBar", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let source = String(data: data, encoding: .utf8),
                      let range = source.range(of: "(?m)^\\s*version\\s+\"([^\"\\r\\n]+)\"", options: .regularExpression),
                      let raw = source[range].split(separator: "\"").dropFirst().first,
                      let latest = UpdateVersion(String(raw)),
                      let current = UpdateVersion(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") else { throw UpdateFailure.invalidResponse }
                lastChecked = Date()
                defaults.set(lastChecked, forKey: "updateLastChecked")
                availableVersion = latest > current ? latest.raw : nil
                message = latest > current ? L10n.t("updates.found", ["version": latest.raw]) : (manual ? L10n.t("updates.up_to_date") : nil)
            } catch {
                guard !Task.isCancelled else { return }
                if manual { message = L10n.t("updates.failed", ["reason": error.localizedDescription]) }
            }
        }
    }

    private func confirmUpgrade(_ installation: HomebrewInstallation, target: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("updates.title")
        alert.informativeText = L10n.t("updates.confirm", ["version": target])
        alert.addButton(withTitle: L10n.t("updates.upgrade"))
        alert.addButton(withTitle: L10n.t("updates.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        isInstalling = true
        message = L10n.t("updates.installing")
        Task {
            do {
                let original = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                _ = try await Self.runBrew(installation, arguments: ["update"], autoUpdate: true)
                let output = try await Self.runBrew(installation, arguments: ["info", "--json=v2", "--cask", installation.qualifiedName])
                let plan = try BrewUpgradePlan.parse(output, installation: installation, target: target)
                _ = try await Self.runBrew(installation, arguments: [plan.command, "--cask", installation.qualifiedName])
                let infoURL = bundle.bundleURL.appendingPathComponent("Contents/Info.plist")
                guard let data = try? Data(contentsOf: infoURL),
                      let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let version = UpdateVersion(plist["CFBundleShortVersionString"] as? String ?? ""),
                      let starting = UpdateVersion(original), let requested = UpdateVersion(target), version > starting && version >= requested else { throw UpdateFailure.unchanged }
                isInstalling = false
                try relaunch()
            } catch {
                isInstalling = false
                message = L10n.t("updates.failed", ["reason": error.localizedDescription])
            }
        }
    }

    private func relaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "remaining=100; while kill -0 \"$1\" 2>/dev/null && [ \"$remaining\" -gt 0 ]; do sleep 0.2; remaining=$((remaining - 1)); done; /usr/bin/open \"$2\"", "clashbar-relaunch", String(ProcessInfo.processInfo.processIdentifier), bundle.bundleURL.path]
        try process.run()
        NSApp.terminate(nil)
    }

    nonisolated static func runBrew(_ installation: HomebrewInstallation, arguments: [String], autoUpdate: Bool = false) async throws -> Data {
        try await Task.detached {
            guard FileManager.default.isExecutableFile(atPath: installation.executable.path) else { throw UpdateFailure.invalidReceipt }
            let process = Process()
            let pipe = Pipe()
            let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("clashbar-brew-\(UUID().uuidString).log")
            guard FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw UpdateFailure.invalidResponse }
            let errors = try FileHandle(forWritingTo: errorURL)
            defer {
                try? errors.close()
                try? FileManager.default.removeItem(at: errorURL)
            }
            process.executableURL = installation.executable
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = installation.prefix.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
            environment["HOMEBREW_NO_AUTO_UPDATE"] = autoUpdate ? nil : "1"
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
            environment.removeValue(forKey: "DEVELOPER_DIR")
            environment.removeValue(forKey: "DYLD_LIBRARY_PATH")
            environment.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
            process.environment = environment
            process.standardOutput = pipe
            process.standardError = errors
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 900, execute: timeout)
            var output = Data()
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
                output.append(chunk)
                if output.count > 1024 * 1024 { output = output.suffix(1024 * 1024) }
            }
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0 else {
                let reader = try FileHandle(forReadingFrom: errorURL)
                defer { try? reader.close() }
                let length = try reader.seekToEnd()
                try reader.seek(toOffset: length > 4000 ? length - 4000 : 0)
                output.append(try reader.readToEnd() ?? Data())
                throw UpdateFailure.command(String(decoding: output.suffix(4000), as: UTF8.self))
            }
            return output
        }.value
    }

    private static func isDeveloperIDSigned(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists" as CFString, [], &requirement) == errSecSuccess else { return false }
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let leaf = certificates.first else { return false }
        return (SecCertificateCopySubjectSummary(leaf) as String?)?.hasPrefix("Developer ID Application:") == true
    }
}

#if !APP_STORE
extension UpdateController: SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated { channel == .beta ? ["beta"] : [] }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        lastChecked = Date()
        defaults.set(lastChecked, forKey: "updateLastChecked")
    }

    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
        readyToInstall = true
        #if UPDATE_TESTING
        DispatchQueue.main.async { immediateInstallationBlock() }
        return true
        #else
        return false
        #endif
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        message = L10n.t("updates.failed", ["reason": error.localizedDescription])
        #if UPDATE_TESTING
        if let root = bundle.object(forInfoDictionaryKey: "ClashBarUpdateTestRoot") as? String {
            try? Data(error.localizedDescription.utf8).write(to: URL(fileURLWithPath: root).appendingPathComponent("error.txt"))
            NSApp.terminate(nil)
        }
        #endif
    }
}
#endif
#else
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()
    @Published var automaticChecks = false
    @Published var automaticInstallation = false
    @Published var channel = UpdateChannel.stable
    let isChecking = false
    let isInstalling = false
    let supportsChecks = false
    let supportsInstallationPreference = false
    let message: String? = nil
    let lastChecked: Date? = nil
    var sourceTitle: String { L10n.t("updates.source.store") }
    var menuTitle: String { L10n.t("updates.check") }
    func start() {}
    func stop() {}
    func checkForUpdates() {}
}
#endif
