import AppKit
import Combine
import SwiftUI

/// 菜单栏图标与下拉菜单。左右键都弹出同一个原生菜单：顶部状态卡片 + 模式 + 分组子菜单 + 常用操作
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let prefs: Preferences
    private let openSettings: (SettingsTab) -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    /// 菜单里右对齐列的位置
    private let columnStop: CGFloat = 300

    init(model: AppModel, prefs: Preferences, openSettings: @escaping (SettingsTab) -> Void) {
        self.model = model
        self.prefs = prefs
        self.openSettings = openSettings
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.setAccessibilityTitle("ClashBar")

        // 任何相关状态变化都重画图标
        Publishers.MergeMany(
            model.$phase.map { _ in () }.eraseToAnyPublisher(),
            model.$snapshot.map { _ in () }.eraseToAnyPublisher(),
            model.$health.map { _ in () }.eraseToAnyPublisher(),
            prefs.$showLatency.map { _ in () }.eraseToAnyPublisher(),
            prefs.$language.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.updateButton() }
        .store(in: &cancellables)
        updateButton()
    }

    // MARK: - 菜单栏按钮

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let kind = StatusIcon.kind(phase: model.phase, snapshot: model.snapshot, health: model.health)
        button.image = StatusIcon.image(for: kind)
        if prefs.showLatency, model.phase == .ready, case .ok(let ms) = model.health {
            button.title = " \(ms)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        } else {
            button.title = ""
        }
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        if case .failed(let error) = model.phase { return "ClashBar — \(error.message)" }
        guard let exit = model.snapshot?.exit else { return "ClashBar" }
        let values = ["group": exit.group ?? "-", "node": exit.node ?? "-"]
        var text = L10n.t("tooltip.other", values)
        if let region = Region.code(of: exit) { text = region + " · " + text }
        if model.health == .failed { text += "\n" + L10n.t("tooltip.unhealthy") }
        return text
    }

    // MARK: - 菜单构建（每次打开时重建，保证内容最新）

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuild()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        // 打开菜单时数据若已超过 10 秒，顺手刷新一次
        if let last = model.lastUpdated, Date().timeIntervalSince(last) > 10 { model.refresh() }
    }

    private func rebuild() {
        menu.removeAllItems()

        let header = NSMenuItem()
        let hosting = NSHostingView(rootView: HeaderCard(model: model, prefs: prefs))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        // 跟随菜单宽度拉伸
        hosting.autoresizingMask = [.width]
        header.view = hosting
        menu.addItem(header)

        if let error = model.actionError {
            let item = NSMenuItem(title: error, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = NSImage(systemSymbolName: "exclamationmark.circle", accessibilityDescription: nil)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        if let snapshot = model.snapshot, model.phase == .ready {
            menu.addItem(modeItem(snapshot))
            menu.addItem(.separator())
            addGroups(snapshot)
            menu.addItem(.separator())
            let testing = !model.testingGroups.isEmpty
            menu.addItem(action(testing ? L10n.t("card.testing") : L10n.t("menu.test_latency"), "t", "speedometer",
                                #selector(testLatency), enabled: !testing))
            menu.addItem(action(L10n.t("menu.refresh"), "r", "arrow.clockwise", #selector(refresh)))
            menu.addItem(action(L10n.t("menu.copy"), "c", "doc.on.doc", #selector(copyInfo)))
        } else {
            if case .failed = model.phase {
                menu.addItem(action(L10n.t("menu.setup"), "", "slider.horizontal.3", #selector(openControllers)))
            }
            menu.addItem(action(L10n.t("menu.refresh"), "r", "arrow.clockwise", #selector(refresh)))
        }

        menu.addItem(.separator())
        if !prefs.controllers.isEmpty { menu.addItem(controllerItem()) }
        menu.addItem(action(L10n.t("menu.settings"), ",", "gearshape", #selector(openGeneral)))
        menu.addItem(action(L10n.t("menu.about"), "", "info.circle", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(action(L10n.t("menu.quit"), "q", "power", #selector(quit)))
    }

    private func action(_ title: String, _ key: String, _ symbol: String?, _ selector: Selector, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    /// 左列名称 + 右对齐的次要信息
    private func twoColumn(_ left: String, _ right: String, bold: Bool = false, rightColor: NSColor = .secondaryLabelColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: columnStop)]
        let text = NSMutableAttributedString(string: Self.shorten(left, 34), attributes: [
            .font: bold ? NSFont.menuFont(ofSize: 0).withWeight(.semibold) : NSFont.menuFont(ofSize: 0),
            .paragraphStyle: paragraph,
        ])
        if !right.isEmpty {
            text.append(NSAttributedString(string: "\t" + Self.shorten(right, 26), attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular),
                .foregroundColor: rightColor,
                .paragraphStyle: paragraph,
            ]))
        }
        return text
    }

    /// 过长的名字取中间省略
    static func shorten(_ value: String, _ limit: Int) -> String {
        guard value.count > limit else { return value }
        let head = value.prefix(limit / 2)
        let tail = value.suffix(limit - head.count - 1)
        return head + "…" + tail
    }

    // MARK: - 模式

    private func modeItem(_ snapshot: ClashSnapshot) -> NSMenuItem {
        let current = OutboundMode(rawValue: snapshot.mode)
        let item = NSMenuItem(title: L10n.t("menu.mode"), action: nil, keyEquivalent: "")
        item.attributedTitle = twoColumn(L10n.t("menu.mode"), current?.title ?? snapshot.mode)
        item.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for (index, mode) in OutboundMode.allCases.enumerated() {
            let entry = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: String(index + 1))
            entry.keyEquivalentModifierMask = [.command]
            entry.target = self
            entry.representedObject = mode.rawValue
            entry.state = mode == current ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - 分组

    private func addGroups(_ snapshot: ClashSnapshot) {
        menu.addItem(sectionHeader(L10n.t("menu.groups")))
        if snapshot.groups.isEmpty {
            let empty = NSMenuItem(title: L10n.t("menu.no_groups"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        let chain = Set(snapshot.exit.chain)
        for group in snapshot.groups {
            let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
            let testing = model.testingGroups.contains(group.name)
            item.attributedTitle = twoColumn(group.name, testing ? L10n.t("card.testing") : (group.now ?? ""), bold: chain.contains(group.name))
            item.image = groupImage(group)
            item.submenu = memberMenu(group, snapshot)
            menu.addItem(item)
        }
    }

    private func groupImage(_ group: ProxyItem) -> NSImage? {
        let symbol: String
        switch group.type.lowercased() {
        case "urltest": symbol = "bolt"
        case "fallback": symbol = "arrow.uturn.down"
        case "loadbalance": symbol = "scale.3d"
        case "relay": symbol = "link"
        default: symbol = "list.bullet"
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func memberMenu(_ group: ProxyItem, _ snapshot: ClashSnapshot) -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let test = action(L10n.t("menu.test_group"), "", "speedometer", #selector(testGroup(_:)),
                          enabled: !model.testingGroups.contains(group.name))
        test.representedObject = group.name
        submenu.addItem(test)
        if !group.isSelectable {
            let note = NSMenuItem(title: L10n.t("menu.auto_group", ["type": group.type]), action: nil, keyEquivalent: "")
            note.isEnabled = false
            submenu.addItem(note)
        }
        submenu.addItem(.separator())

        for name in group.all ?? [] {
            let member = snapshot.proxies[name]
            let right: String
            var color = NSColor.secondaryLabelColor
            if let member, member.isGroup {
                right = "→ " + (member.now ?? "")
            } else if let delay = member?.lastDelay, !(member?.isBuiltin ?? true) {
                if delay > 0 {
                    right = "\(delay) ms"
                    color = delay < 300 ? .systemGreen : (delay < 800 ? .systemOrange : .systemRed)
                } else {
                    right = L10n.t("card.timeout")
                    color = .systemRed
                }
            } else {
                right = ""
            }
            let entry = NSMenuItem(title: name, action: group.isSelectable ? #selector(selectMember(_:)) : nil, keyEquivalent: "")
            entry.attributedTitle = twoColumn(name, right, rightColor: color)
            entry.target = self
            entry.state = name == group.now ? .on : .off
            entry.isEnabled = group.isSelectable
            entry.representedObject = [group.name, name]
            submenu.addItem(entry)
        }
        return submenu
    }

    private func controllerItem() -> NSMenuItem {
        let item = NSMenuItem(title: L10n.t("menu.controller"), action: nil, keyEquivalent: "")
        item.attributedTitle = twoColumn(L10n.t("menu.controller"), prefs.activeController?.name ?? L10n.t("menu.controller.auto"))
        item.image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let auto = NSMenuItem(title: L10n.t("menu.controller.auto"), action: #selector(selectController(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = prefs.activeControllerID == nil ? .on : .off
        submenu.addItem(auto)
        submenu.addItem(.separator())
        for controller in prefs.controllers {
            let entry = NSMenuItem(title: controller.name, action: #selector(selectController(_:)), keyEquivalent: "")
            entry.attributedTitle = twoColumn(controller.name, controller.displayAddress)
            entry.target = self
            entry.representedObject = controller.id.uuidString
            entry.state = prefs.activeControllerID == controller.id ? .on : .off
            submenu.addItem(entry)
        }
        item.submenu = submenu
        return item
    }

    // MARK: - 动作

    @objc private func refresh() { model.refresh() }
    @objc private func testLatency() { model.testLatency() }
    @objc private func copyInfo() { model.copyExitInfo() }
    @objc private func openGeneral() { openSettings(.general) }
    @objc private func openControllers() { openSettings(.controllers) }
    @objc private func openAbout() { openSettings(.about) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = OutboundMode(rawValue: raw) else { return }
        model.setMode(mode)
    }

    @objc private func selectMember(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        model.select(group: pair[0], node: pair[1])
    }

    @objc private func testGroup(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        model.testGroup(name)
    }

    @objc private func selectController(_ sender: NSMenuItem) {
        prefs.activeControllerID = (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
    }
}

private extension NSFont {
    func withWeight(_ weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: pointSize, weight: weight)
    }
}
