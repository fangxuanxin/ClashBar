import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var statusController: StatusItemController!
    private var settings: SettingsWindowController!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if UPDATE_TESTING
        if Bundle.main.object(forInfoDictionaryKey: "ClashBarUpdateTest") as? Bool == true {
            let root = URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "ClashBarUpdateTestRoot") as! String)
            if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "9002" {
                let preserved = UserDefaults.standard.string(forKey: "updateSmokePreference") == "preserved"
                try? Data((preserved ? "success" : "preference-lost").utf8).write(to: root.appendingPathComponent("result.txt"))
                NSApp.terminate(nil)
            } else {
                UserDefaults.standard.set("preserved", forKey: "updateSmokePreference")
                UserDefaults.standard.set("beta", forKey: "updateChannel")
                UserDefaults.standard.synchronize()
                UpdateController.shared.start()
            }
            return
        }
        #endif
        // 单实例：已有一个在跑就退出自己
        let me = ProcessInfo.processInfo.processIdentifier
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != me }) {
            NSApp.terminate(nil)
            return
        }

        let prefs = Preferences.shared
        prefs.migrateLegacyLaunchAgent()
        Self.removeLegacySnapshots()

        model = AppModel(prefs: prefs)
        settings = SettingsWindowController(prefs: prefs, model: model)
        statusController = StatusItemController(model: model, prefs: prefs) { [weak self] tab in
            self?.settings.show(tab)
        }
        installMainMenu()
        prefs.$language.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.installMainMenu()
            self?.settings.refreshTitle()
        }.store(in: &cancellables)

        model.start()
        UpdateController.shared.start()
        UpdateController.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.installMainMenu() }
        }.store(in: &cancellables)

        // 首次启动且没有任何控制器时，稍后若检测失败就直接打开设置
        if prefs.controllers.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, case .failed = self.model.phase, self.model.snapshot == nil else { return }
                self.settings.show(.controllers)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.stop()
        UpdateController.shared.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if UpdateController.shared.isInstalling {
            let alert = NSAlert()
            alert.messageText = L10n.t("updates.busy")
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    /// 旧版遗留的快照与状态文件含有节点信息，升级后不再使用，直接删除
    private static func removeLegacySnapshots() {
        let support = Preferences.supportDirectory
        for name in ["Snapshot", "state.json"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
    }

    /// 菜单栏应用没有主菜单时，设置窗口里 ⌘C / ⌘V / ⌘W 都不生效，这里补一个最小主菜单
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t("menu.about"), action: #selector(showAbout), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: L10n.t("menu.settings"), action: #selector(showSettings), keyEquivalent: ",").target = self
        #if !APP_STORE
        let updateItem = appMenu.addItem(withTitle: UpdateController.shared.menuTitle, action: #selector(checkUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = !UpdateController.shared.isChecking && !UpdateController.shared.isInstalling
        #endif
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    @objc private func showAbout() { settings.show(.about) }
    @objc private func showSettings() { settings.show(.general) }
    @objc private func checkUpdates() { UpdateController.shared.checkForUpdates() }
}

@main
enum ClashBarMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
