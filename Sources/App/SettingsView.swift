import AppKit
import SwiftUI

enum SettingsTab: String, Hashable {
    case general, controllers, about
}

/// 让菜单可以指定设置窗口打开到哪一页
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// 设置窗口
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let router = SettingsRouter()
    private let prefs: Preferences
    private let model: AppModel

    init(prefs: Preferences, model: AppModel) {
        self.prefs = prefs
        self.model = model
    }

    func show(_ tab: SettingsTab) {
        router.tab = tab
        if window == nil {
            let root = SettingsView()
                .environmentObject(prefs)
                .environmentObject(model)
                .environmentObject(router)
            let window = NSWindow(contentViewController: NSHostingController(rootView: root))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 500))
            window.center()
            self.window = window
        }
        window?.title = L10n.t("settings.title")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 语言切换后同步窗口标题
    func refreshTitle() {
        window?.title = L10n.t("settings.title")
    }
}

struct SettingsView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var router: SettingsRouter

    var body: some View {
        TabView(selection: $router.tab) {
            GeneralPane()
                .tabItem { Label(L10n.t("settings.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ControllersPane()
                .tabItem { Label(L10n.t("settings.controllers"), systemImage: "server.rack") }
                .tag(SettingsTab.controllers)
            AboutPane()
                .tabItem { Label(L10n.t("settings.about"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .padding(12)
        .frame(width: 560, height: 500)
        // 读取 language 让整页随语言切换重绘
        .id(prefs.language)
    }
}

// MARK: - 通用

struct GeneralPane: View {
    @EnvironmentObject var prefs: Preferences
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(L10n.t("settings.menu_bar")) {
                HStack(spacing: 10) {
                    Image(nsImage: StatusIcon.image(for: .init(badge: "US"), height: 18))
                    Image(nsImage: StatusIcon.image(for: .init(badge: "JP", dimmed: true), height: 18))
                    Text(L10n.t("settings.legend"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle(L10n.t("settings.show_latency"), isOn: $prefs.showLatency)
            }

            Section(L10n.t("settings.behavior")) {
                Picker(L10n.t("settings.refresh"), selection: $prefs.refreshInterval) {
                    ForEach(Preferences.refreshChoices, id: \.self) { seconds in
                        Text(Self.intervalTitle(seconds)).tag(seconds)
                    }
                }
                TextField(L10n.t("settings.test_url"), text: $prefs.testURL)
                    .textFieldStyle(.roundedBorder)
                Toggle(L10n.t("settings.login"), isOn: Binding(
                    get: { prefs.launchAtLogin || prefs.launchNeedsApproval },
                    set: { enabled in
                        do {
                            try prefs.setLaunchAtLogin(enabled)
                            loginError = prefs.launchNeedsApproval ? L10n.t("settings.login.approval") : nil
                        } catch {
                            loginError = L10n.t("settings.login.failed", ["reason": error.localizedDescription])
                        }
                    }
                ))
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.orange)
                }
                Picker(L10n.t("language.title"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.nativeName).tag(language)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    static func intervalTitle(_ seconds: Int) -> String {
        if seconds < 60 { return L10n.t("settings.seconds", ["n": String(seconds)]) }
        if seconds == 60 { return L10n.t("settings.minute") }
        return L10n.t("settings.minutes", ["n": String(seconds / 60)])
    }
}

// MARK: - 控制器

struct ControllersPane: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var model: AppModel
    @State private var editing: ControllerConfig?
    @State private var detected: [DiscoveredController] = []
    @State private var scanning = false

    var body: some View {
        Form {
            Section(L10n.t("controllers.active")) {
                Picker("", selection: $prefs.activeControllerID) {
                    Text(L10n.t("controllers.auto")).tag(UUID?.none)
                    ForEach(prefs.controllers) { controller in
                        Text("\(controller.name)  ·  \(controller.displayAddress)").tag(Optional(controller.id))
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section {
                if prefs.controllers.isEmpty {
                    Text(L10n.t("controllers.none")).foregroundStyle(.secondary)
                }
                ForEach(prefs.controllers) { controller in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(controller.name)
                            Text(controller.displayAddress).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.t("controllers.edit")) { editing = controller }
                        Button(role: .destructive) { prefs.remove(controller.id) } label: {
                            Image(systemName: "trash")
                        }
                        .help(L10n.t("controllers.delete"))
                    }
                }
            } header: {
                HStack {
                    Text(L10n.t("controllers.saved"))
                    Spacer()
                    Button {
                        editing = ControllerConfig(name: L10n.t("controllers.new_name"), url: "http://127.0.0.1:9090")
                    } label: {
                        Label(L10n.t("controllers.add"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                if detected.isEmpty && !scanning {
                    Text(L10n.t("controllers.nothing_found")).foregroundStyle(.secondary)
                }
                ForEach(detected) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.config.name)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        statusLabel(item.status)
                        Button(L10n.t("controllers.use")) {
                            var config = item.config
                            config.id = UUID()
                            // 已知口令不对时不要带过去，免得用户以为填过了
                            if item.status == .needsSecret { config.secret = "" }
                            editing = config
                        }
                    }
                }
            } header: {
                HStack {
                    Text(L10n.t("controllers.detected"))
                    Spacer()
                    if scanning { ProgressView().controlSize(.small) }
                    Button(scanning ? L10n.t("controllers.scanning") : L10n.t("controllers.scan")) { scan() }
                        .buttonStyle(.borderless)
                        .disabled(scanning)
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { controller in
            ControllerEditor(original: controller) { saved in
                let isNew = !prefs.controllers.contains { $0.id == saved.id }
                prefs.upsert(saved)
                if (isNew && prefs.activeControllerID != nil) || prefs.activeControllerID == saved.id {
                    if prefs.activeControllerID == saved.id { model.controllerChanged() }
                    prefs.activeControllerID = saved.id
                }
            }
        }
        .onAppear { if detected.isEmpty { scan() } }
    }

    @ViewBuilder private func statusLabel(_ status: DiscoveredController.Status) -> some View {
        switch status {
        case .ready(let version):
            Label(L10n.t("controllers.ready", ["version": version]), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .needsSecret:
            Label(L10n.t("controllers.needs_secret"), systemImage: "key.fill")
                .foregroundStyle(.orange).font(.caption)
        case .unreachable:
            Label(L10n.t("controllers.unreachable"), systemImage: "xmark.circle")
                .foregroundStyle(.secondary).font(.caption)
        }
    }

    private func scan() {
        scanning = true
        Task {
            detected = await Discovery.discover()
            scanning = false
        }
    }
}

/// 添加 / 编辑控制器的表单（参考 Neko Dash：主机、端口、口令、HTTPS 分项填写，也可直接粘贴面板链接）
struct ControllerEditor: View {
    let original: ControllerConfig
    let onSave: (ControllerConfig) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var https: Bool
    @State private var secret: String
    @State private var socketPath: String
    @State private var showSecret = false
    @State private var showAdvanced: Bool
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    init(original: ControllerConfig, onSave: @escaping (ControllerConfig) -> Void) {
        self.original = original
        self.onSave = onSave
        let address = ControllerAddress.parse(original.url)?.address
        _name = State(initialValue: original.name)
        _host = State(initialValue: original.socketPath == nil ? (address?.host ?? "") : "")
        _port = State(initialValue: String(address?.port ?? ControllerAddress.defaultPort))
        _https = State(initialValue: address?.https ?? false)
        _secret = State(initialValue: original.secret)
        _socketPath = State(initialValue: original.socketPath ?? "")
        _showAdvanced = State(initialValue: !(original.socketPath ?? "").isEmpty)
    }

    /// 由表单拼出的配置
    private var draft: ControllerConfig {
        var config = original
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portValue = Int(port.trimmingCharacters(in: .whitespaces)) ?? ControllerAddress.defaultPort
        config.url = ControllerAddress(host: trimmedHost, port: portValue, https: https).url
        config.secret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let socket = socketPath.trimmingCharacters(in: .whitespacesAndNewlines)
        config.socketPath = socket.isEmpty ? nil : socket
        config.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if config.name.isEmpty { config.name = config.displayAddress }
        return config
    }

    private var canSave: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty || !socketPath.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Section {
                    TextField(L10n.t("controllers.name"), text: $name)
                }
                Section {
                    TextField(L10n.t("controllers.host"), text: $host, prompt: Text("192.168.1.1"))
                        .onChange(of: host) { value in absorbLink(value) }
                    TextField(L10n.t("controllers.port"), text: $port, prompt: Text("9090"))
                    Toggle("HTTPS", isOn: $https)
                    HStack {
                        Group {
                            if showSecret {
                                TextField(L10n.t("controllers.secret"), text: $secret)
                            } else {
                                SecureField(L10n.t("controllers.secret"), text: $secret)
                            }
                        }
                        Button { showSecret.toggle() } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t(showSecret ? "controllers.hide_secret" : "controllers.show_secret"))
                    }
                } footer: {
                    Text(L10n.t("controllers.paste_hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    DisclosureGroup(L10n.t("controllers.advanced"), isExpanded: $showAdvanced) {
                        TextField(L10n.t("controllers.socket"), text: $socketPath, prompt: Text("/tmp/verge/verge-mihomo.sock"))
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(testing ? L10n.t("controllers.testing") : L10n.t("controllers.test")) { test() }
                    .disabled(testing || !canSave)
                if let testResult {
                    Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(testResult.ok ? .green : .red)
                        .font(.callout)
                        .lineLimit(2)
                }
                Spacer()
                Button(L10n.t("controllers.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.t("controllers.save")) {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 480)
    }

    /// 主机栏里粘贴了完整链接（含协议、端口或路径）时，自动拆进各个字段
    private func absorbLink(_ value: String) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.contains("://") || text.contains("/") || text.filter({ $0 == ":" }).count == 1,
              let parsed = ControllerAddress.parse(text) else { return }
        host = parsed.address.host
        port = String(parsed.address.port)
        https = parsed.address.https
        if let linkSecret = parsed.secret, !linkSecret.isEmpty { secret = linkSecret }
        testResult = nil
    }

    private func test() {
        testing = true
        testResult = nil
        let config = draft
        Task {
            do {
                let version = try await ClashClient(config: config).version()
                testResult = (true, L10n.t("controllers.test_ok", ["version": Discovery.coreLabel(version)]))
            } catch let error as ClashError {
                testResult = (false, error.message)
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }
}

// MARK: - 关于

struct AboutPane: View {
    @EnvironmentObject private var prefs: Preferences
    @ObservedObject private var updater = UpdateController.shared
    @State private var showMBFeedback = false
    @State private var mbFeedbackID = 0

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .contentShape(Rectangle())
                .onTapGesture(count: 5) {
                    prefs.mbEnabled.toggle()
                    showMBFeedback = true
                    mbFeedbackID += 1
                }
                .overlay(alignment: .top) {
                    if showMBFeedback {
                        Text(L10n.t(prefs.mbEnabled ? "about.mb_enabled" : "about.mb_disabled"))
                            .font(.callout)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            .fixedSize()
                            .offset(y: -44)
                            .allowsHitTesting(false)
                    }
                }
                .task(id: mbFeedbackID) {
                    guard showMBFeedback else { return }
                    do { try await Task.sleep(nanoseconds: 2_000_000_000) }
                    catch { return }
                    showMBFeedback = false
                }
                .onDisappear { showMBFeedback = false }
            Text("ClashBar").font(.system(size: 22, weight: .bold))
            Text(versionText).foregroundStyle(.secondary)
            Text(L10n.t("about.tagline"))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            VStack(alignment: .leading, spacing: 8) {
                Text(updater.sourceTitle).font(.callout).foregroundStyle(.secondary)
                if updater.supportsChecks {
                    Toggle(L10n.t("updates.auto_check"), isOn: $updater.automaticChecks)
                }
                if updater.supportsInstallationPreference {
                    Toggle(L10n.t("updates.auto_install"), isOn: $updater.automaticInstallation)
                        .disabled(!updater.automaticChecks)
                    Picker(L10n.t("updates.channel"), selection: $updater.channel) {
                        ForEach(UpdateChannel.allCases) { channel in Text(channel.title).tag(channel) }
                    }
                }
                if let message = updater.message {
                    Text(message).font(.callout).lineLimit(3).help(message).textSelection(.enabled)
                }
                if let checked = updater.lastChecked {
                    Text(L10n.t("updates.last_check", ["time": checked.formatted(date: .abbreviated, time: .shortened)]))
                        .font(.caption).foregroundStyle(.secondary)
                }
                #if !APP_STORE
                Button(updater.menuTitle) { updater.checkForUpdates() }
                    .disabled(updater.isChecking || updater.isInstalling)
                #endif
            }
            .frame(maxWidth: 410)
            .padding(.horizontal, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var versionText: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, !version.isEmpty {
            return L10n.t("about.version", ["version": version])
        }
        return L10n.t("about.dev")
    }
}
