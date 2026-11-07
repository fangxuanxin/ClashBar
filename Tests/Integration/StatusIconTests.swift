import AppKit
import Foundation

@main
enum StatusIconTests {
    @MainActor static func main() throws {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.environment["CLASHBAR_VERIFY_PREFERENCE"] == "1" {
            precondition(Preferences.shared.mbEnabled, "重启后应保留开关状态")
            return
        }
        let previous = defaults.object(forKey: "mbEnabled")
        defaults.removeObject(forKey: "mbEnabled")
        defer {
            if let previous { defaults.set(previous, forKey: "mbEnabled") }
            else { defaults.removeObject(forKey: "mbEnabled") }
        }
        let prefs = Preferences.shared
        precondition(!prefs.mbEnabled, "功能默认应关闭")
        let proxies = [
            "Node Select": ProxyItem(name: "Node Select", type: "Selector", now: "Main JP", all: ["Main JP", "Backup JP"]),
            "Main JP": ProxyItem(name: "Main JP", type: "URLTest", now: "JP 01", all: ["JP 01"]),
            "Backup JP": ProxyItem(name: "Backup JP", type: "URLTest", now: "JP 02", all: ["JP 02"]),
            "JP 01": ProxyItem(name: "JP 01", type: "Vmess"),
            "JP 02": ProxyItem(name: "JP 02", type: "Vmess"),
        ]
        let exit = ExitResolver.resolve(mode: "rule", proxies: proxies, rules: [RuleItem(type: "Match", proxy: "Node Select")])
        var snapshot = ClashSnapshot(controller: ControllerConfig(name: "Test", url: "http://127.0.0.1:1"), version: "test", mode: "rule", proxies: proxies, groups: [], exit: exit)
        func badge() -> String? {
            StatusIcon.kind(phase: .ready, snapshot: snapshot, health: .unknown, mbEnabled: prefs.mbEnabled).badge
        }
        precondition(badge() == "JP", "未开启时仅显示地区")
        prefs.mbEnabled.toggle()
        precondition(badge() == "M JP", "开启后显示主分组")
        defaults.synchronize()
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        child.environment = ProcessInfo.processInfo.environment.merging(["CLASHBAR_VERIFY_PREFERENCE": "1"]) { _, value in value }
        try child.run()
        child.waitUntilExit()
        precondition(child.terminationStatus == 0, "开关状态未持久保存")
        snapshot.proxies["Node Select"] = ProxyItem(name: "Node Select", type: "Selector", now: "Backup JP", all: ["Main JP", "Backup JP"])
        snapshot.exit = ExitResolver.resolve(mode: "rule", proxies: snapshot.proxies, rules: [RuleItem(type: "Match", proxy: "Node Select")])
        precondition(badge() == "B JP", "切换后显示备用分组")
        snapshot.proxies.removeValue(forKey: "Main JP")
        precondition(badge() == "JP", "缺少配对分组时开启也不生效")
        prefs.mbEnabled.toggle()
        precondition(badge() == "JP" && !defaults.bool(forKey: "mbEnabled"), "再次切换应关闭并保存")
        print("✓ 图标开关默认关闭、主备显示、分组条件、再次关闭和跨进程状态保留通过")
    }
}
