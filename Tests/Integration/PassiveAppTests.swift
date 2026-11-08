import Foundation

@main
enum PassiveAppTests {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLASHBAR_PASSIVE_TEST_ROOT"]!)
        let port = try String(contentsOf: root.appendingPathComponent("port")).trimmingCharacters(in: .whitespacesAndNewlines)
        let controller = ControllerConfig(name: "Passive fixture", url: "http://127.0.0.1:\(port)")
        let suite = "ClashBarPassiveTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = HistoryModel(url: root.appendingPathComponent("History/history.sqlite"), defaults: defaults)
        let model = AppModel(prefs: .shared, history: history, controller: controller)
        for iteration in 0..<3 {
            model.refresh()
            let deadline = Date().addingTimeInterval(5)
            while model.isRefreshing && Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
            precondition(!model.isRefreshing && model.phase == .ready, "刷新应成功且不等待主动测速")
            precondition(model.health == (iteration < 2 ? .ok(170) : .failed), "使用Cloudflare已有结果，不受Google失败干扰")
        }
        let report = try await history.report(controller: HistoryIdentity.key(for: controller), from: Date().addingTimeInterval(-100), to: Date())
        precondition(report.samples.count == 2, "三轮刷新只有两个不同内核样本")
        precondition(report.samples.allSatisfy { $0.origin == "core" && $0.testURL == "https://www.cloudflare.com/cdn-cgi/trace" }, "内核样本带真实来源")
        precondition(report.samples.last?.delay == nil, "失败样本保留且不额外重试")
        let requests = try String(contentsOf: root.appendingPathComponent("requests.jsonl"))
        precondition(!requests.contains("delay") && !requests.contains("healthcheck"), "不得发起任何额外测速")
        precondition(requests.split(separator: "\n").count == 10, "仅3轮版本/配置/节点读取和1次规则读取")
        print("✓ 三轮真实HTTP刷新零测速请求、按分组网址读取、失败展示和历史去重通过")
    }
}
