import Foundation

func testPassiveLatency() {
    let now = Date()
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestamp = formatter.string(from: now.addingTimeInterval(-20))
    let cloudflare = "https://www.cloudflare.com/cdn-cgi/trace"
    let google = "https://www.gstatic.com/generate_204"
    let success = ProxyHistory(delay: 170, time: timestamp)
    let failure = ProxyHistory(delay: 0, time: timestamp)
    let proxy = ProxyItem(name: "美国三", type: "Vless", history: [failure], alive: false,
                          extra: [cloudflare: ProxyTestState(history: [success], alive: true),
                                  google: ProxyTestState(history: [failure], alive: false)])
    let group = ProxyItem(name: "Main US", type: "URLTest", now: proxy.name, all: [proxy.name], testURL: cloudflare)
    let reading = PassiveLatency.read(node: proxy, group: group)
    expectEqual(reading?.sample.delay, 170, "优先采用FXProxy分组网址记录，不受Google失败和总alive污染")
    expectEqual(reading?.testURL, cloudflare, "保留测速来源")
    expectEqual(reading?.isRecent(at: now), true, "识别内核带小数秒的时间")
    expectEqual(reading?.isRecent(at: now.addingTimeInterval(700)), false, "过期记录不显示成实时健康")
    expectEqual(reading?.isRecent(at: now.addingTimeInterval(-100)), false, "未来异常时间不视为当前结果")
    let absent = ProxyItem(name: "Other", type: "URLTest", all: [proxy.name], testURL: "https://other.test/")
    expectEqual(PassiveLatency.read(node: proxy, group: absent), nil, "指定网址没记录时不冒用其他网址")
    let legacy = ProxyItem(name: "Legacy", type: "Vmess", history: [success])
    expectEqual(PassiveLatency.read(node: legacy, group: group)?.testURL, nil, "旧内核没有分网址记录时明确来源未知")
    expectEqual(PassiveLatency.read(node: ProxyItem(name: "Empty", type: "Vmess"), group: group), nil, "没有记录就未知，不补发探测")
    expectEqual(PassiveLatency(sample: ProxyHistory(delay: 1), testURL: nil).isRecent(at: now), false, "没有时间不编造新样本")
    let proxies = [proxy.name: proxy, group.name: group]
    let exit = ExitResolver.resolve(mode: "rule", proxies: proxies, rules: [RuleItem(type: "Match", proxy: group.name)])
    expectEqual(PassiveLatency.read(exit: exit, proxies: proxies), reading, "嵌套出口按实际分组选择来源")
    expectEqual(PassiveLatency.read(exit: ExitResolver.resolve(mode: "direct", proxies: proxies, rules: nil), proxies: proxies), nil, "直连不伪造测速")
    let decoded = try? JSONDecoder().decode(ProxyItem.self, from: Data("""
    {"name":"n","type":"Vless","extra":{"cf":{"history":[{"delay":123,"time":"2026-11-08T20:00:00+08:00"}],"alive":true}},"testUrl":"cf"}
    """.utf8))
    expectEqual(decoded?.extra["cf"]?.history.last?.delay, 123, "解码真实extra结构")
    expect(decoded?.extra["cf"]?.history.last?.date != nil, "兼容没有小数秒的内核时间")
    testPassiveHistoryMigration()
}

func testPassiveHistoryMigration() {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClashBar-Passive-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("history.sqlite")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, "CREATE TABLE intervals (id TEXT PRIMARY KEY,controller TEXT,label TEXT,start REAL,end REAL,session TEXT,state TEXT,kind TEXT,source TEXT); CREATE TABLE samples(controller TEXT,time REAL,node TEXT,delay INTEGER); INSERT INTO samples VALUES ('router',1800000000,'美国三',NULL); PRAGMA user_version=1;"]
        try process.run()
        process.waitUntilExit()
        expectEqual(process.terminationStatus, 0, "创建旧版历史库用于迁移验证")
        let store = try HistoryStore(url: url)
        let now = Date(timeIntervalSince1970: 1800000000)
        for _ in 0..<4 {
            try store.sample(controller: "router", node: "美国三", delay: 170, at: now, origin: "core", testURL: "cf")
        }
        let report = try store.report(controller: "router", from: now.addingTimeInterval(-1), to: now.addingTimeInterval(1))
        expectEqual(report.samples.count, 2, "多次刷新同一内核结果只保存一次")
        expectEqual(report.samples.filter { $0.origin == "clashbar" }.count, 1, "旧样本保留并标记原主动测速来源")
        expectEqual(report.samples.first(where: { $0.origin == "core" })?.testURL, "cf", "内核来源与网址单独存储")
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("database_backup"), includingPropertiesForKeys: nil)
        expectEqual(backups.count, 1, "升级旧库前自动备份")
        let restored = root.appendingPathComponent("restored.sqlite")
        try FileManager.default.copyItem(at: backups[0], to: restored)
        let restoredStore = try HistoryStore(url: restored)
        expectEqual(try restoredStore.report(controller: "router", from: now.addingTimeInterval(-1), to: now.addingTimeInterval(1)).samples.count, 1, "旧库备份可恢复，迁移可重复")
    } catch { expect(false, "被动历史测试失败：\(error)") }
}
