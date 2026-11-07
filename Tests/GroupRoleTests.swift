import Foundation

func testGroupRole() {
    let proxies: [String: ProxyItem] = [
        "Node Select": group("Node Select", now: "Auto", all: ["Auto", "Main JP", "Backup JP"]),
        "Auto": group("Auto", "Fallback", now: "Main JP", all: ["Main JP", "Backup JP"]),
        "Main JP": group("Main JP", "URLTest", now: "JP 01", all: ["JP 01"]),
        "Backup JP": group("Backup JP", "URLTest", now: "JP 02", all: ["JP 02"]),
        "JP 01": node("JP 01"),
        "JP 02": node("JP 02"),
    ]
    let main = ExitResolver.resolve(mode: "rule", proxies: proxies, rules: matchRules)
    expectEqual(GroupRole.current(exit: main, proxies: proxies), .main, "沿自动分组路径识别主分组")
    var backupProxies = proxies
    backupProxies["Auto"] = group("Auto", "Fallback", now: "Backup JP", all: ["Main JP", "Backup JP"])
    let backup = ExitResolver.resolve(mode: "rule", proxies: backupProxies, rules: matchRules)
    expectEqual(GroupRole.current(exit: backup, proxies: backupProxies), .backup, "自动切换后识别备用分组")
    var onlyMain = proxies
    onlyMain.removeValue(forKey: "Backup JP")
    expectEqual(GroupRole.current(exit: main, proxies: onlyMain), nil, "缺少备用分组不启用标记")
    var onlyBackup = backupProxies
    onlyBackup.removeValue(forKey: "Main JP")
    expectEqual(GroupRole.current(exit: backup, proxies: onlyBackup), nil, "缺少主分组不启用标记")
    var neutral = main
    neutral.chain = ["Node Select", "JP 01"]
    expectEqual(GroupRole.current(exit: neutral, proxies: proxies), nil, "当前路径不经过主备分组时不推测")
    var namedNode = proxies
    namedNode["Main JP"] = node("Main JP")
    expectEqual(GroupRole.current(exit: main, proxies: namedNode), nil, "节点名称不能冒充分组")
    var direct = main
    direct.family = .direct
    expectEqual(GroupRole.current(exit: direct, proxies: proxies), nil, "直连不显示主备标记")
    direct.family = .reject
    expectEqual(GroupRole.current(exit: direct, proxies: proxies), nil, "拒绝连接不显示主备标记")
    var decorated = proxies
    decorated["Main JP"] = nil
    decorated["🚀 mAiN-JP"] = group("🚀 mAiN-JP", now: "JP 01", all: ["JP 01"])
    var decoratedExit = main
    decoratedExit.chain = ["Node Select", "🚀 mAiN-JP", "JP 01"]
    expectEqual(GroupRole.current(exit: decoratedExit, proxies: decorated), .main, "支持大小写和图标分隔")
    decorated["🚀 mAiN-JP"] = nil
    decorated["Mainland JP"] = group("Mainland JP", now: "JP 01", all: ["JP 01"])
    decoratedExit.chain = ["Node Select", "Mainland JP", "JP 01"]
    expectEqual(GroupRole.current(exit: decoratedExit, proxies: decorated), nil, "不把 Mainland 等子串误认为 Main")
}
