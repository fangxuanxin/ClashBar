import Foundation

// 无需 XCTest 的极简测试框架：Command Line Tools 环境即可运行

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("✗ \((file as NSString).lastPathComponent):\(line) \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    expect(actual == expected, "\(message) — expected \(expected), got \(actual)", file: file, line: line)
}

// MARK: - 测试数据：模拟一份多级分组的订阅

func group(_ name: String, _ type: String = "Selector", now: String?, all: [String]) -> ProxyItem {
    ProxyItem(name: name, type: type, now: now, all: all)
}

func node(_ name: String, delay: Int? = nil, alive: Bool? = nil) -> ProxyItem {
    ProxyItem(name: name, type: "Vmess", history: delay.map { [ProxyHistory(delay: $0)] } ?? [], alive: alive)
}

func fixture(auto: String = "US Standard", nodeSelect: String = "Auto") -> [String: ProxyItem] {
    let items: [ProxyItem] = [
        group("GLOBAL", now: "Node Select", all: ["Node Select", "Auto", "US Premium", "US Standard", "OpenAI", "Mainland"]),
        group("Node Select", now: nodeSelect, all: ["Auto", "US Premium", "US Standard", "DIRECT", "美国 01"]),
        group("Auto", "Fallback", now: auto, all: ["US Premium", "US Standard"]),
        group("US Premium", "URLTest", now: "美国 01", all: ["美国 01", "美国 02"]),
        group("US Standard", "URLTest", now: "美国 03", all: ["美国 03", "美国 04"]),
        group("OpenAI", now: "美国 04", all: ["美国 04", "美国 02"]),
        group("Mainland", now: "DIRECT", all: ["DIRECT"]),
        group("Hidden", now: "DIRECT", all: ["DIRECT"]),
        node("美国 01", delay: 120, alive: true),
        node("美国 02", delay: 0, alive: false),
        node("美国 03", delay: 170, alive: true),
        node("美国 04", delay: 300, alive: true),
        ProxyItem(name: "DIRECT", type: "Direct"),
        ProxyItem(name: "REJECT", type: "Reject"),
    ]
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
}

let matchRules = [RuleItem(type: "DomainSuffix", proxy: "OpenAI"), RuleItem(type: "Match", proxy: "Node Select")]

// MARK: - 出口解析（通用：不依赖任何分组命名约定）

func testResolveViaMatch() {
    let exit = ExitResolver.resolve(mode: "rule", proxies: fixture(), rules: matchRules)
    expectEqual(exit.policy, "Node Select", "MATCH 指向的分组")
    expectEqual(exit.chain, ["Node Select", "Auto", "US Standard", "美国 03"], "选择路径")
    expectEqual(exit.node, "美国 03", "最终节点")
    expectEqual(exit.group, "US Standard", "展示分组取路径上最深的分组")
    expectEqual(exit.family, .proxy, "走代理")
    expectEqual(exit.basis, .matchRule, "依据")
}

func testResolveOtherBranch() {
    let exit = ExitResolver.resolve(mode: "rule", proxies: fixture(auto: "US Premium"), rules: matchRules)
    expectEqual(exit.group, "US Premium", "展示分组")
    expectEqual(exit.node, "美国 01", "节点")
}

func testResolveDirectNodeSelected() {
    let exit = ExitResolver.resolve(mode: "rule", proxies: fixture(nodeSelect: "DIRECT"), rules: matchRules)
    expectEqual(exit.family, .direct, "默认分组选了 DIRECT")
}

func testResolveNodePickedDirectly() {
    // Node Select 直接选了节点：展示分组就是 Node Select
    let exit = ExitResolver.resolve(mode: "rule", proxies: fixture(nodeSelect: "美国 01"), rules: matchRules)
    expectEqual(exit.node, "美国 01", "节点")
    expectEqual(exit.group, "Node Select", "直接所在分组")
}

func testResolveModes() {
    expectEqual(ExitResolver.resolve(mode: "direct", proxies: fixture(), rules: nil).family, .direct, "直连模式")
    let global = ExitResolver.resolve(mode: "global", proxies: fixture(), rules: nil)
    expectEqual(global.policy, "GLOBAL", "全局模式起点")
    expectEqual(global.node, "美国 03", "全局模式沿 GLOBAL 走")
    let inferred = ExitResolver.resolve(mode: "rule", proxies: fixture(), rules: [])
    expectEqual(inferred.basis, .inferred, "没有 MATCH 时按常见名称推测")
    expectEqual(inferred.node, "美国 03", "推测后照样走到底")
    let empty = ExitResolver.resolve(mode: "rule", proxies: [:], rules: nil)
    expectEqual(empty.node, nil, "什么都没有")
}

func testSingBoxOutbounds() {
    // sing-box 的 Clash API：分组类型为 Selector / URLTest，拒绝出站类型为 Block
    let proxies: [String: ProxyItem] = [
        "proxy": group("proxy", now: "auto", all: ["auto", "block"]),
        "auto": group("auto", "URLTest", now: "🇯🇵 Tokyo-01", all: ["🇯🇵 Tokyo-01"]),
        "🇯🇵 Tokyo-01": node("🇯🇵 Tokyo-01"),
        "block": ProxyItem(name: "block", type: "Block"),
    ]
    let exit = ExitResolver.resolve(mode: "rule", proxies: proxies, rules: [])
    expectEqual(exit.node, "🇯🇵 Tokyo-01", "推测默认分组 proxy")
    expectEqual(Region.code(of: exit), "JP", "地区")
    var blocked = proxies
    blocked["proxy"] = group("proxy", now: "block", all: ["auto", "block"])
    expectEqual(ExitResolver.resolve(mode: "rule", proxies: blocked, rules: []).family, .reject, "Block 算拒绝")
}

func testCycleIsSafe() {
    let proxies = [
        "A": group("A", now: "B", all: ["B"]),
        "B": group("B", now: "A", all: ["A"]),
    ]
    expectEqual(ExitResolver.path(from: "A", proxies: proxies), ["A", "B"], "环路在重复处停止")
}

func testGroupOrder() {
    let ordered = ExitResolver.orderedGroups(fixture(), mode: "rule").map(\.name)
    expectEqual(Array(ordered.prefix(6)), ["Node Select", "Auto", "US Premium", "US Standard", "OpenAI", "Mainland"], "按 GLOBAL.all 原始顺序")
    expect(!ordered.contains("GLOBAL"), "规则模式隐藏 GLOBAL")
    expectEqual(ExitResolver.orderedGroups(fixture(), mode: "global").first?.name, "GLOBAL", "全局模式 GLOBAL 置顶")
}

// MARK: - 配置文件解析

func testParseConfig() {
    let yaml = """
    mixed-port: 7890
    external-controller: 0.0.0.0:9090 # 注释
    secret: "s3cr#t"
    external-controller-unix: /tmp/verge/verge-mihomo.sock
    proxies:
      - name: x
        secret: nested-should-be-ignored
    """
    let parsed = Discovery.parseConfig(yaml)
    expectEqual(parsed.controller, "0.0.0.0:9090", "控制器地址去掉行尾注释")
    expectEqual(parsed.secret, "s3cr#t", "引号内的 # 不当注释")
    expectEqual(parsed.unix, "/tmp/verge/verge-mihomo.sock", "Unix 套接字")
    expectEqual(Discovery.parseConfig("secret: ''\nexternal-controller: ''").controller, nil, "空控制器视为无")
    expectEqual(Discovery.normalize("0.0.0.0:9090"), "http://127.0.0.1:9090", "通配地址")
    expectEqual(Discovery.normalize(":9097"), "http://127.0.0.1:9097", "省略主机")
    expectEqual(Discovery.normalize("192.168.1.1:9090"), "http://192.168.1.1:9090", "补协议")
    expectEqual(Discovery.normalize("https://r.lan:9090"), "https://r.lan:9090", "已有协议")
    expectEqual(Discovery.appName(for: "/x/io.github.clash-verge-rev.clash-verge-rev"), "Clash Verge", "Verge 名称")
}

func testDiscoveryNaming() {
    // 你的场景：Verge 配置里写的是路由器地址，应当显示为路由器而不是 Clash Verge
    let verge = "/Users/x/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/config.yaml"
    let files: [(ControllerConfig, String)] = [
        (ControllerConfig(name: "Clash Verge", url: "http://192.168.50.1:9090", secret: "verge"), verge),
        (ControllerConfig(name: "Clash Verge", url: "http://localhost", socketPath: "/tmp/verge/verge-mihomo.sock"), verge),
        (ControllerConfig(name: "Clash Verge", url: "http://10.0.0.8:9090"), verge),
    ]
    let found = Discovery.collectCandidates(configFiles: files, gateway: "192.168.50.1")
    let router = found.first { $0.config.url == "http://192.168.50.1:9090" }
    expectEqual(router?.location, .gateway("192.168.50.1"), "网关地址识别为路由器")
    expectEqual(router?.config.name, L10n.t("discovery.router", ["host": "192.168.50.1"]), "名称是路由器")
    expectEqual(router?.foundVia.count, 2, "配置文件与网关扫描合并为一条")
    expectEqual(router?.config.secret, "verge", "保留配置里的口令")
    expectEqual(router?.isProbeOnly, false, "有配置声明")
    let socket = found.first { $0.config.socketPath != nil }
    expectEqual(socket?.config.name, L10n.t("discovery.local_app", ["app": "Clash Verge"]), "本机套接字用客户端名")
    expectEqual(found.first { $0.config.url == "http://10.0.0.8:9090" }?.config.name, "10.0.0.8", "其他主机用主机名")
    expectEqual(found.first { $0.config.url == "http://127.0.0.1:9090" }?.isProbeOnly, true, "纯端口扫描")
    expectEqual(Discovery.coreLabel(VersionResponse(version: "v1.19.29", meta: true)), "Mihomo v1.19.29", "识别 Mihomo")
    expectEqual(Discovery.coreLabel(VersionResponse(version: "2023.08.17", meta: nil)), "Clash 2023.08.17", "识别 Clash")
    expectEqual(Discovery.coreLabel(VersionResponse(version: "sing-box 1.11.0", meta: true)), "sing-box 1.11.0", "识别 sing-box，不重复前缀")
    expectEqual(ClashError.http(404).message, L10n.t("error.not_found"), "404 有专门提示")
}

func testControllerAddress() {
    let zash = ControllerAddress.parse("http://192.168.50.1:9090/ui/zashboard/#/")
    expectEqual(zash?.address.url, "http://192.168.50.1:9090", "zashboard 面板链接取 API 根地址")
    expectEqual(zash?.secret, nil, "链接没带口令")
    expectEqual(ControllerAddress.parse("  192.168.1.1:9097\n")?.address.port, 9097, "IP:端口，去空白")
    expectEqual(ControllerAddress.parse("10.0.0.1")?.address.url, "http://10.0.0.1:9090", "纯 IP 默认 9090")
    expectEqual(ControllerAddress.parse("https://clash.example.com/")?.address.url, "https://clash.example.com:443", "HTTPS 默认 443")
    let yacd = ControllerAddress.parse("http://yacd.haishan.me/?hostname=192.168.1.2&port=9091&secret=abc")
    expectEqual(yacd?.address.url, "http://192.168.1.2:9091", "yacd 参数里的主机端口")
    expectEqual(yacd?.secret, "abc", "yacd 参数里的口令")
    let meta = ControllerAddress.parse("http://d.metacubex.one/#/setup?hostname=192.168.1.3&port=9090&secret=xyz&https=true")
    expectEqual(meta?.address.url, "https://192.168.1.3:9090", "metacubexd 片段参数")
    expectEqual(meta?.secret, "xyz", "片段里的口令")
    expectEqual(ControllerAddress.parse("ftp://x")?.address, nil, "非 HTTP 协议")
    expectEqual(ControllerAddress.parse("")?.address, nil, "空输入")
}

// MARK: - API 解码与套接字响应解析

func testDecoding() {
    let json = """
    {"proxies":{"Auto":{"name":"Auto","type":"Fallback","now":"B","all":["B"],"history":[]},
     "B":{"name":"B","type":"Trojan","history":[{"time":"x","delay":88}],"alive":true,"extra":{}},
     "W":{"name":"W","type":"Ss"}}}
    """
    let decoded = try? JSONDecoder().decode(ProxiesResponse.self, from: Data(json.utf8))
    expectEqual(decoded?.proxies["B"]?.lastDelay, 88, "history 最后一次延迟")
    expectEqual(decoded?.proxies["Auto"]?.isGroup, true, "有 all 即分组")
    expectEqual(decoded?.proxies["W"]?.history.count, 0, "缺字段不报错")
    let config = try? JSONDecoder().decode(ConfigsResponse.self, from: Data(#"{"mode":"Rule","port":0}"#.utf8))
    expectEqual(config?.mode, "rule", "模式统一小写")
}

func testHTTPParse() {
    let plain = Data("HTTP/1.0 200 OK\r\nContent-Type: application/json\r\n\r\n{\"a\":1}".utf8)
    let parsed = try? UnixSocketHTTP.parse(plain)
    expectEqual(parsed?.0, 200, "状态码")
    expectEqual(parsed.map { String(decoding: $0.1, as: UTF8.self) }, "{\"a\":1}", "响应体")
    let chunked = Data("HTTP/1.1 401 Unauthorized\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nabcd\r\n3\r\nefg\r\n0\r\n\r\n".utf8)
    let decoded = try? UnixSocketHTTP.parse(chunked)
    expectEqual(decoded?.0, 401, "chunked 状态码")
    expectEqual(decoded.map { String(decoding: $0.1, as: UTF8.self) }, "abcdefg", "chunked 解码")
    expectEqual(ClashClient.encode("🚀 节点/选择"), "%F0%9F%9A%80%20%E8%8A%82%E7%82%B9%2F%E9%80%89%E6%8B%A9", "路径片段编码")
}

// MARK: - 多语言

func testLocalization() {
    let en = L10n.catalog["en"]!, zh = L10n.catalog["zh-Hans"]!
    expectEqual(Set(en.keys), Set(zh.keys), "中英文案键完全一致")
    let pattern = try! NSRegularExpression(pattern: "\\{[a-z_]+\\}")
    func placeholders(_ text: String) -> Set<String> {
        Set(pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) })
    }
    for (key, value) in en {
        expectEqual(placeholders(value), placeholders(zh[key] ?? ""), "占位符一致：\(key)")
    }
    expectEqual(L10n.resolve(.system, preferred: ["zh-Hans-CN"]), "zh-Hans", "系统中文")
    expectEqual(L10n.resolve(.system, preferred: ["zh-Hant-TW"]), "zh-Hans", "繁体回落简体")
    expectEqual(L10n.resolve(.system, preferred: ["fr-FR", "en-US"]), "en", "跳过不支持的语言")
    expectEqual(L10n.resolve(.system, preferred: ["fr-FR"]), "en", "默认英文")
    expectEqual(L10n.resolve(.chinese, preferred: ["en"]), "zh-Hans", "手动指定")
    expectEqual(L10n.t("card.alive", ["alive": "3", "total": "9"], language: "zh-Hans"), "3/9 个节点在线", "具名占位符")
}

// MARK: - 地区识别

func testRegion() {
    expectEqual(Region.code(of: "🇺🇸 Premium 美国1"), "US", "国旗优先")
    expectEqual(Region.code(of: "🇬🇧 London"), "UK", "GB 显示为 UK")
    expectEqual(Region.code(of: "Premium US 01"), "US", "大写缩写")
    expectEqual(Region.code(of: "日本 05 - 东京"), "JP", "中文关键词")
    expectEqual(Region.code(of: "中国香港 IPLC 01"), "HK", "香港先于中国")
    expectEqual(Region.code(of: "印度尼西亚 01"), "ID", "印尼先于印度")
    expectEqual(Region.code(of: "Singapore-02"), "SG", "英文关键词")
    expectEqual(Region.code(of: "JPN-Premium"), "JP", "三字母缩写")
    expectEqual(Region.code(of: "爱沙尼亚 01 - Harjumaa"), "EE", "爱沙尼亚")
    expectEqual(Region.code(of: "Romania 01"), "RO", "罗马尼亚不被误认为阿曼")
    expectEqual(Region.code(of: "🇧🇷 São Paulo"), "BR", "任意国旗")
    expectEqual(Region.code(of: "Premium"), nil, "认不出")
    expectEqual(Region.code(of: "Auto in group"), nil, "小写 in 不算印度")
    let exit = ExitResolver.resolve(mode: "rule", proxies: fixture(), rules: matchRules)
    expectEqual(Region.code(of: exit), "US", "出口节点 美国 03")
    let direct = ExitResolver.resolve(mode: "direct", proxies: fixture(), rules: nil)
    expectEqual(Region.code(of: direct), nil, "直连没有地区")
}

@main
enum TestMain {
    static func main() async {
        await testSavedControllerSelection()
        testResolveViaMatch()
        testResolveOtherBranch()
        testResolveDirectNodeSelected()
        testResolveNodePickedDirectly()
        testResolveModes()
        testSingBoxOutbounds()
        testCycleIsSafe()
        testGroupOrder()
        testRegion()
        testParseConfig()
        testDiscoveryNaming()
        testControllerAddress()
        testDecoding()
        testHTTPParse()
        testLocalization()
        print(failures == 0 ? "✓ \(passes) checks passed" : "✗ \(failures) failed, \(passes) passed")
        exit(failures == 0 ? 0 : 1)
    }
}

func testSavedControllerSelection() async {
    let first = ControllerConfig(name: "路由器一", url: "http://192.168.1.1:9090", secret: "first")
    let second = ControllerConfig(name: "路由器二", url: first.url, secret: "second")
    let third = ControllerConfig(name: "路由器三", url: first.url, secret: "third")
    var visited: [UUID] = []
    do {
        let selected = try await Discovery.firstReachable([first, second, third]) { controller in
            visited.append(controller.id)
            return controller.secret == "second" ? .ready(version: "test") : .needsSecret
        }
        expectEqual(selected, second, "同 IP 使用各自口令，保留配置身份")
        expectEqual(visited, [first.id, second.id], "依次轮询，成功即停止")
    } catch { expect(false, "应选中可用配置：\(error)") }
    do {
        _ = try await Discovery.firstReachable([first, second]) { _ in .unreachable }
        expect(false, "全部离线应报错")
    } catch let error as ClashError {
        if case .unreachable = error { expect(true, "全部离线") }
        else { expect(false, "离线不应报告缺少配置") }
    } catch { expect(false, "错误类型") }
    do {
        _ = try await Discovery.firstReachable([first, second]) { controller in
            controller.id == first.id ? .needsSecret : .unreachable
        }
        expect(false, "口令错误应报错")
    } catch { expectEqual(error as? ClashError, .unauthorized, "保留口令错误") }
    do {
        _ = try await Discovery.firstReachable([]) { _ in
            expect(false, "空列表无需探测")
            return .unreachable
        }
        expect(false, "空列表应报错")
    } catch { expectEqual(error as? ClashError, .notConfigured, "空列表") }
}
