import Foundation

func testHistory() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClashBar-History-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.sqlite")
    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    var proxies = fixture()
    func state(_ mode: String = "rule") -> HistoryState {
        HistoryState(mode: mode, proxies: proxies, exit: ExitResolver.resolve(mode: mode, proxies: proxies, rules: matchRules))
    }
    do {
        let store = try HistoryStore(url: url)
        func observe(_ offset: TimeInterval, session: String = "first", source: String = "observed") throws {
            try store.observe(controller: "router", label: "Router", state: state(), session: session,
                              at: origin.addingTimeInterval(offset), maximumGap: 75, source: source)
        }
        func report(_ end: TimeInterval = 1000, start: TimeInterval = -1, controller: String = "router") throws -> HistoryReport {
            try store.report(controller: controller, from: origin.addingTimeInterval(start), to: origin.addingTimeInterval(end))
        }
        try observe(0)
        try observe(30)
        var result = try report()
        expectEqual(result.intervals.count, 1, "稳定状态只更新区间，不重复写快照")
        expectEqual(result.intervals.first?.kind, "baseline", "首次连接为基线")
        expectEqual(result.observedDuration(from: origin, to: origin.addingTimeInterval(1000)), 30, "不延伸到最后观测以后的未知时间")
        proxies["US Standard"] = group("US Standard", "URLTest", now: "美国 04", all: ["美国 03", "美国 04"])
        try observe(60)
        result = try report()
        expectEqual(result.changes(group: nil).count, 1, "捕获最终节点变化")
        expectEqual(result.changes(group: "US Standard").count, 1, "捕获嵌套分组路径变化")
        expectEqual(result.changes(group: "OpenAI").count, 0, "无关分组不产生变化")
        expectEqual(result.intervals.first?.end, origin.addingTimeInterval(60), "连续观测区间衔接")
        proxies["OpenAI"] = group("OpenAI", now: "美国 02", all: ["美国 04", "美国 02"])
        try observe(90)
        result = try report()
        expectEqual(result.changes(group: nil).count, 1, "后台分组变化不计为出口切换")
        expectEqual(result.changes(group: "OpenAI").count, 1, "完整记录非当前路径分组")
        proxies["Node Select"] = group("Node Select", now: "OpenAI", all: ["Auto", "US Premium", "US Standard", "DIRECT", "美国 01"])
        proxies["OpenAI"] = group("OpenAI", now: "美国 04", all: ["美国 04", "美国 02"])
        let previous = state()
        try observe(120, source: "local")
        result = try report()
        expectEqual(result.intervals.last?.source, "local", "保留本应用操作后的观测标记")
        expectEqual(result.intervals.last?.state.terminal(for: nil), "美国 04", "分组变化后节点可以保持相同")
        expectEqual(result.changes(group: nil).count, 2, "同节点不同分组的路径变化不能漏掉")
        expectEqual(previous.terminal(for: "OpenAI"), "美国 04", "任意分组可解析最终节点")
        try observe(400)
        result = try report()
        expectEqual(result.intervals.last?.kind, "baseline", "超出轮询窗口必须断开观测")
        expectEqual(result.intervals[result.intervals.count - 2].end, origin.addingTimeInterval(120), "断档不填充成稳定区间")
        try observe(430, session: "after-wake")
        expectEqual(try report().intervals.last?.kind, "baseline", "新会话即使时间接近也不跨睡眠连接")
        proxies["Extra"] = group("Extra", now: "DIRECT", all: ["DIRECT"])
        try observe(460, session: "after-wake")
        expectEqual(try report().intervals.last?.kind, "configuration", "分组增删单独标记配置变化")
        try store.observe(controller: "router", label: "Router", state: state("direct"), session: "after-wake",
                          at: origin.addingTimeInterval(490), maximumGap: 75)
        expectEqual(try report().intervals.last?.kind, "mode", "模式变化不伪装成故障切换")
        try store.observe(controller: "other", label: "Other", state: state(), session: "first", at: origin, maximumGap: 75)
        expectEqual(try report(controller: "other").intervals.count, 1, "控制器隔离")
        expectEqual(try report().controllers.count, 2, "控制器列表不依赖当前连接")
        try store.sample(controller: "router", node: "美国 04", delay: 123, at: origin.addingTimeInterval(60))
        try store.sample(controller: "router", node: "美国 04", delay: nil, at: origin.addingTimeInterval(90))
        result = try report(90, start: 60)
        expectEqual(result.samples.count, 2, "时间筛选包含边界")
        expectEqual(result.samples.first?.delay, 123, "保存成功延迟")
        expect(result.samples.last?.delay == nil, "失败样本不伪装成零延迟")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        expectEqual(permissions?.intValue, 0o600, "历史库仅当前用户可读")
        let reopened = try HistoryStore(url: url)
        expectEqual(try reopened.report(controller: "router", from: origin, to: origin.addingTimeInterval(1000)).samples.count, 2, "重开数据库保留记录，迁移幂等")
        let malicious = "节点'); DROP TABLE samples; -- 🇯🇵"
        try store.sample(controller: "router", node: malicious, delay: 5, at: origin.addingTimeInterval(95))
        expectEqual(try report().samples.last?.node, malicious, "节点名称通过参数绑定安全保存")
        try store.backup(at: origin.addingTimeInterval(1000))
        let backupDirectory = directory.appendingPathComponent("database_backup")
        let backup = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }.first!
        let restoredURL = directory.appendingPathComponent("Restore/history.sqlite")
        try FileManager.default.createDirectory(at: restoredURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: backup, to: restoredURL)
        let restored = try HistoryStore(url: restoredURL)
        expectEqual(try restored.report(controller: "router", from: origin, to: origin.addingTimeInterval(1000)).samples.count, 3, "备份恢复演练保留全部测速样本")
        expectEqual(try restored.report(controller: "router", from: origin, to: origin.addingTimeInterval(1000)).intervals.count, try report().intervals.count, "备份恢复演练保留全部路径区间")
        for offset in 1...6 { try store.backup(at: origin.addingTimeInterval(1000 + Double(offset))) }
        expectEqual(try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path).count, 5, "备份轮转只保留5份")
        try store.maintain(at: origin.addingTimeInterval(HistoryStore.retention + 200))
        result = try report(HistoryStore.retention + 200, start: 0)
        expect(result.samples.isEmpty, "30天过期样本删除")
        expect(result.intervals.allSatisfy { $0.start >= origin.addingTimeInterval(200) }, "跨保留边界的区间裁剪")
        try store.clear()
        expectEqual(try report().intervals.isEmpty, true, "清空全部路径记录")
        expectEqual(try report().samples.isEmpty, true, "清空全部测速样本")
        expect(!FileManager.default.fileExists(atPath: backupDirectory.path), "清空同时移除恢复备份")
    } catch { expect(false, "历史持久化测试失败：\(error)") }

    let controller = ControllerConfig(name: "Private", url: "http://localhost:9090", secret: "never-store-me")
    let key = HistoryIdentity.key(for: controller)
    expectEqual(key.count, 64, "控制器历史身份使用摘要")
    expect(!key.contains(controller.secret), "历史身份不包含明文口令")
    var renamed = controller
    renamed.id = UUID()
    renamed.name = "Renamed"
    expectEqual(HistoryIdentity.key(for: renamed), key, "自动发现产生新UUID和改名不丢历史")
    renamed.secret = "another-secret"
    expect(HistoryIdentity.key(for: renamed) != key, "同地址不同控制器凭据不混淆")
    proxies["Balance"] = group("Balance", "LoadBalance", now: nil, all: ["美国 03", "美国 04"])
    expectEqual(state().terminal(for: "Balance"), nil, "负载均衡不伪造唯一节点")
    proxies["Cycle A"] = group("Cycle A", now: "Cycle B", all: ["Cycle B"])
    proxies["Cycle B"] = group("Cycle B", now: "Cycle A", all: ["Cycle A"])
    expectEqual(state().terminal(for: "Cycle A"), nil, "分组循环不伪造最终节点")
    let beforeReorder = state()
    proxies["Balance"] = group("Balance", "LoadBalance", now: nil, all: ["美国 04", "美国 03"])
    expect(beforeReorder.topologyMatches(state()), "成员顺序变化不误判配置改变")
    let largeMembers = (0..<10000).map { "Large unused member \($0)" }
    proxies["Large"] = group("Large", now: "美国 04", all: largeMembers)
    do {
        let encoded = try JSONEncoder().encode(state())
        expect(encoded.count < 15000, "万级成员列表保存摘要，不随每次切换重复存储")
        expectEqual(try JSONDecoder().decode(HistoryState.self, from: encoded), state(), "状态往返编解码一致")
    } catch { expect(false, "大分组编码失败：\(error)") }
}
