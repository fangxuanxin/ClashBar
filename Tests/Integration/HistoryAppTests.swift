import AppKit
import SwiftUI

@main
enum HistoryAppTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task {
            do {
                try await run()
                print("✓ 历史采集、暂停恢复、清空隔离、离线窗口与中英文渲染通过")
                exit(0)
            } catch {
                print("✗ 历史集成测试失败：\(error)")
                exit(1)
            }
        }
        app.run()
    }

    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLASHBAR_HISTORY_TEST_ROOT"]!)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("Fixture/history.sqlite")
        let suite = "ClashBarHistoryTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HistoryModel(url: database, defaults: defaults)
        let prefs = Preferences.shared
        let model = AppModel(prefs: prefs, history: history)
        let controller = ControllerConfig(name: "Demo Router · 演示控制器", url: "http://127.0.0.1:1", secret: "history-never-saves-this-secret")
        let key = HistoryIdentity.key(for: controller)
        let now = Date()
        let origin = now.addingTimeInterval(-3600)
        var proxies: [String: ProxyItem] = [
            "代理选择": ProxyItem(name: "代理选择", type: "Selector", now: "自动优选", all: ["自动优选", "备用分组"]),
            "自动优选": ProxyItem(name: "自动优选", type: "URLTest", now: "🇭🇰 香港 A", all: ["🇭🇰 香港 A", "🇯🇵 日本 B"]),
            "备用分组": ProxyItem(name: "备用分组", type: "Fallback", now: "🇯🇵 日本 B", all: ["🇭🇰 香港 A", "🇯🇵 日本 B"]),
            "负载均衡": ProxyItem(name: "负载均衡", type: "LoadBalance", all: ["🇭🇰 香港 A", "🇯🇵 日本 B"]),
            "🇭🇰 香港 A": ProxyItem(name: "🇭🇰 香港 A", type: "Vmess"),
            "🇯🇵 日本 B": ProxyItem(name: "🇯🇵 日本 B", type: "Vmess"),
        ]
        func snapshot() -> ClashSnapshot {
            let exit = ExitResolver.resolve(mode: "rule", proxies: proxies, rules: [RuleItem(type: "Match", proxy: "代理选择")])
            return ClashSnapshot(controller: controller, version: "fixture", mode: "rule", proxies: proxies, groups: [], exit: exit)
        }
        func record(_ offset: TimeInterval) async {
            let token = history.observationGeneration
            await history.observe(snapshot(), interval: 30, at: origin.addingTimeInterval(offset), token: token)
        }
        func report() async throws -> HistoryReport {
            try await history.report(controller: key, from: origin.addingTimeInterval(-1), to: now)
        }
        func verify(_ condition: Bool, _ message: String = "历史集成断言") {
            precondition(condition, message)
        }
        await record(0)
        await record(30)
        verify(try await report().intervals.count == 1)
        let oldToken = history.observationGeneration
        history.enabled = false
        await record(60)
        verify(try await report().intervals.count == 1, "暂停后不记录")
        history.enabled = true
        await history.sample(controller: controller, node: "stale", delay: 1, at: origin, token: oldToken)
        verify(try await report().samples.isEmpty, "暂停恢复后拒绝旧任务的测速结果")
        await record(90)
        verify(try await report().intervals.last?.kind == "baseline", "恢复后建立新基线")
        var otherSnapshot = snapshot()
        otherSnapshot.controller = ControllerConfig(name: "Other", url: "http://127.0.0.2:1")
        await history.observe(otherSnapshot, interval: 30, at: origin.addingTimeInterval(95), token: history.observationGeneration)
        await record(100)
        verify(try await report().intervals.last?.kind == "baseline", "自动切换控制器后返回也不跨控制器填充区间")
        let exportURL = root.appendingPathComponent("history-export.json")
        await history.export(to: exportURL)
        verify(history.error == nil, "导出成功不显示错误")
        let exported = try JSONSerialization.jsonObject(with: Data(contentsOf: exportURL)) as! [String: Any]
        let exportedIntervals = exported["intervals"] as! [[String: Any]]
        verify(Set(exportedIntervals.compactMap { $0["controller"] as? String }).count == 2, "导出包含全部控制器")
        await history.clear()
        verify(try await report().intervals.isEmpty, "清空记录")
        await history.sample(controller: controller, node: "stale", delay: 1, at: origin, token: oldToken)
        verify(try await report().samples.isEmpty, "清空后拒绝旧任务的数据")
        for offset in stride(from: 0, through: 3570, by: 30) {
            if offset == 1200 { proxies["自动优选"] = ProxyItem(name: "自动优选", type: "URLTest", now: "🇯🇵 日本 B", all: ["🇭🇰 香港 A", "🇯🇵 日本 B"]) }
            if offset == 2400 {
                proxies["代理选择"] = ProxyItem(name: "代理选择", type: "Selector", now: "备用分组", all: ["自动优选", "备用分组"])
                history.requested(controller: controller, group: "代理选择", value: "备用分组")
            }
            if offset == 1800 { history.interrupt() }
            await record(Double(offset))
            await history.sample(controller: controller, node: snapshot().exit.node!, delay: offset % 300 == 0 ? nil : 90 + offset % 150,
                                 at: origin.addingTimeInterval(Double(offset)), token: history.observationGeneration, origin: "core")
        }
        let populated = try await report()
        precondition(populated.changes(group: nil).count == 2, "节点变化和同节点换分组均记录")
        precondition(populated.samples.count == 120, "测速样本完整")
        for hours in [1, 24, 168, 720] {
            let ranged = try await history.report(controller: key, from: now.addingTimeInterval(-Double(hours) * 3600), to: now)
            precondition(ranged.changes(group: nil).count == 2, "四个时间范围都保留切换")
        }
        let raw = try Data(contentsOf: database)
        precondition(raw.range(of: Data(controller.secret.utf8)) == nil, "数据库不包含明文口令")
        for language in [AppLanguage.chinese, .english] {
            L10n.selection = language
            for tab in 0...1 {
                let view = HistoryView(history: history, model: model, prefs: prefs, initialTab: tab, initialHours: 1)
                let window = NSWindow(contentViewController: NSHostingController(rootView: view))
                window.styleMask = [.titled, .closable, .resizable]
                window.setContentSize(NSSize(width: 960, height: 760))
                window.title = HistoryText.title
                window.center()
                window.makeKeyAndOrderFront(nil)
                try await Task.sleep(nanoseconds: 800_000_000)
                guard let content = window.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
                    throw HistoryStore.StoreError.database("Cannot render history window")
                }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: root.appendingPathComponent("history-\(language.rawValue)-\(tab).png"))
                precondition(content.bounds.width >= 900, "历史窗口布局尺寸")
                window.orderOut(nil)
            }
        }
        let balance = HistoryView(history: history, model: model, prefs: prefs, initialGroup: "负载均衡")
        let balanceWindow = NSWindow(contentViewController: NSHostingController(rootView: balance))
        balanceWindow.setContentSize(NSSize(width: 800, height: 620))
        balanceWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        balanceWindow.orderOut(nil)
        L10n.selection = prefs.language
    }
}
