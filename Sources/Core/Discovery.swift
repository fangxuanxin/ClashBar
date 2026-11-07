import Foundation

/// 检测到的控制器及其可用状态
struct DiscoveredController: Identifiable, Equatable {
    enum Status: Equatable {
        /// version 形如「Mihomo v1.19.29」
        case ready(version: String)
        case needsSecret
        case unreachable
    }

    /// 控制器实际所在位置：决定显示名称，和「从哪里读到地址」无关
    enum Location: Equatable {
        case thisMac
        case gateway(String)
        case remote(String)
    }

    var config: ControllerConfig
    var location: Location
    /// 发现途径，如「来自 Clash Verge 配置」「默认网关」「本机端口」
    var foundVia: [String]
    var status: Status

    var id: String { config.socketPath ?? config.url }

    /// 详情行：地址 · 发现途径
    var detail: String { ([config.displayAddress] + foundVia).joined(separator: " · ") }

    /// 只靠端口扫描得到的条目（没有任何配置文件声明它）
    var isProbeOnly: Bool {
        foundVia.allSatisfy { $0 == L10n.t("discovery.via_port") || $0 == L10n.t("discovery.via_gateway") }
    }
}

/// 在本机常见配置文件、默认端口和默认网关上寻找控制器
enum Discovery {
    static let commonPorts = [9090, 9097]

    /// 从 YAML 顶层取出 external-controller / external-controller-unix / secret
    /// 只做逐行解析，避免引入 YAML 依赖
    static func parseConfig(_ text: String) -> (controller: String?, unix: String?, secret: String?) {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let first = line.first, !first.isWhitespace, first != "#" else { continue }
            for key in ["external-controller", "external-controller-unix", "secret"] where values[key] == nil {
                guard line.hasPrefix(key + ":") else { continue }
                values[key] = scalar(String(line.dropFirst(key.count + 1)))
            }
        }
        func nonEmpty(_ key: String) -> String? { values[key].flatMap { $0.isEmpty ? nil : $0 } }
        return (nonEmpty("external-controller"), nonEmpty("external-controller-unix"), values["secret"])
    }

    /// 解析 YAML 标量：去掉行尾注释与引号
    static func scalar(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if let quote = text.first, quote == "\"" || quote == "'" {
            text.removeFirst()
            if let end = text.firstIndex(of: quote) { text = String(text[..<end]) }
            return text
        }
        if let comment = text.range(of: " #") { text = String(text[..<comment.lowerBound]) }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// 0.0.0.0:9090 / :9090 / [::]:9090 → http://127.0.0.1:9090
    static func normalize(_ address: String) -> String {
        var value = address.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return value }
        for wildcard in ["0.0.0.0:", "*:", "[::]:", "::"] where value.hasPrefix(wildcard) {
            value = "127.0.0.1:" + value.dropFirst(wildcard.count)
            break
        }
        if value.hasPrefix(":") { value = "127.0.0.1" + value }
        return "http://" + value
    }

    /// 按配置所在目录给一个好认的名字
    static func appName(for directory: String) -> String {
        let name = (directory as NSString).lastPathComponent
        let lower = name.lowercased()
        if lower.contains("clash-verge") || lower.contains("verge") { return "Clash Verge" }
        if lower.contains("clashx.meta") || lower.contains("clash.meta") { return "ClashX Meta" }
        if lower.contains("mihomo-party") || lower.contains("mihomo party") { return "Mihomo Party" }
        if lower.contains("flclash") { return "FlClash" }
        if lower.contains("mihomo") { return "Mihomo" }
        if lower.contains("clash") { return "Clash" }
        return name
    }

    /// 本机配置文件里声明的控制器
    static func configFileCandidates(home: String = NSHomeDirectory()) -> [(ControllerConfig, String)] {
        let fm = FileManager.default
        var roots = [".config/clash", ".config/mihomo", ".config/clash.meta"].map { (home as NSString).appendingPathComponent($0) }
        let support = (home as NSString).appendingPathComponent("Library/Application Support")
        if let names = try? fm.contentsOfDirectory(atPath: support) {
            roots += names.filter { $0.range(of: "clash|mihomo|verge", options: [.regularExpression, .caseInsensitive]) != nil }
                .map { (support as NSString).appendingPathComponent($0) }
        }
        let fileNames = ["config.yaml", "config.yml", "clash-verge.yaml", "mihomo.yaml", "clash.yaml"]
        var results: [(ControllerConfig, String)] = []
        var seen = Set<String>()
        for root in roots {
            for file in fileNames {
                let path = (root as NSString).appendingPathComponent(file)
                guard let attributes = try? fm.attributesOfItem(atPath: path),
                      (attributes[.size] as? Int ?? 0) < 8 * 1024 * 1024,
                      let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let parsed = parseConfig(text)
                let name = appName(for: root)
                var candidates: [ControllerConfig] = []
                if let unix = parsed.unix {
                    candidates.append(ControllerConfig(name: name, url: "http://localhost", secret: parsed.secret ?? "", socketPath: unix))
                }
                if let controller = parsed.controller {
                    candidates.append(ControllerConfig(name: name, url: normalize(controller), secret: parsed.secret ?? ""))
                }
                for candidate in candidates where seen.insert(candidate.endpointKey).inserted {
                    results.append((candidate, path))
                }
            }
        }
        return results
    }

    /// 读取默认网关（路由器上的 OpenClash 等）
    static func defaultGateway() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "gateway" { return parts[1] }
        }
        return nil
    }

    /// 测试一个控制器：能读 /version 即可用；401 说明需要口令
    static func probe(_ config: ControllerConfig) async -> DiscoveredController.Status {
        do {
            return .ready(version: coreLabel(try await ClashClient(config: config).version()))
        } catch ClashError.unauthorized {
            return .needsSecret
        } catch {
            return .unreachable
        }
    }

    static func firstReachable(_ controllers: [ControllerConfig],
                               probe: (ControllerConfig) async -> DiscoveredController.Status = Discovery.probe) async throws -> ControllerConfig {
        var needsSecret = false
        for controller in controllers {
            try Task.checkCancellation()
            let status = await probe(controller)
            try Task.checkCancellation()
            switch status {
            case .ready: return controller
            case .needsSecret: needsSecret = true
            case .unreachable: break
            }
        }
        if needsSecret { throw ClashError.unauthorized }
        if controllers.isEmpty { throw ClashError.notConfigured }
        throw ClashError.unreachable(L10n.t("controllers.none_reachable"))
    }

    /// 内核标签：Mihomo 会在 /version 里带 meta: true
    static func coreLabel(_ version: VersionResponse) -> String {
        // 判定顺序参考 Clash-Dash：sing-box → Meta(Mihomo) → 原版 Clash
        let lower = version.version.lowercased()
        if lower.contains("sing") { return lower.hasPrefix("sing") ? version.version : "sing-box \(version.version)" }
        let core = version.meta == true || lower.contains("meta") ? "Mihomo" : "Clash"
        return "\(core) \(version.version)"
    }

    static func isLoopback(_ host: String) -> Bool {
        ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host.lowercased())
    }

    /// 根据地址判断控制器在哪
    static func location(of config: ControllerConfig, gateway: String?) -> DiscoveredController.Location {
        if let socket = config.socketPath, !socket.isEmpty { return .thisMac }
        let host = URL(string: config.url)?.host ?? ""
        if host.isEmpty || isLoopback(host) { return .thisMac }
        if host == gateway { return .gateway(host) }
        return .remote(host)
    }

    /// 名称只由位置决定：本机用客户端名，网关叫「路由器」，其他主机直接用主机名
    static func displayName(_ location: DiscoveredController.Location, appName: String?) -> String {
        switch location {
        case .thisMac: return appName.map { L10n.t("discovery.local_app", ["app": $0]) } ?? L10n.t("discovery.this_mac")
        case .gateway(let host): return L10n.t("discovery.router", ["host": host])
        case .remote(let host): return host
        }
    }

    /// 汇总候选：同一地址只保留一条，合并发现途径；口令优先取配置文件里的
    static func collectCandidates(configFiles: [(ControllerConfig, String)], gateway: String?) -> [DiscoveredController] {
        var found: [DiscoveredController] = []
        func add(_ config: ControllerConfig, appName: String?, via: String) {
            let key = config.socketPath ?? config.url
            if let i = found.firstIndex(where: { $0.id == key }) {
                if found[i].config.secret.isEmpty { found[i].config.secret = config.secret }
                if !found[i].foundVia.contains(via) { found[i].foundVia.append(via) }
                return
            }
            let place = location(of: config, gateway: gateway)
            var named = config
            named.name = displayName(place, appName: place == .thisMac ? appName : nil)
            found.append(DiscoveredController(config: named, location: place, foundVia: [via], status: .unreachable))
        }
        for (config, path) in configFiles {
            let app = appName(for: (path as NSString).deletingLastPathComponent)
            add(config, appName: app, via: L10n.t("discovery.via_config", ["app": app]))
        }
        for port in commonPorts {
            add(ControllerConfig(name: "", url: "http://127.0.0.1:\(port)"), appName: nil, via: L10n.t("discovery.via_port"))
            if let gateway {
                add(ControllerConfig(name: "", url: "http://\(gateway):\(port)"), appName: nil, via: L10n.t("discovery.via_gateway"))
            }
        }
        return found
    }

    /// 全量检测：配置文件 + 本机默认端口 + 网关默认端口，并发探测
    static func discover() async -> [DiscoveredController] {
        var found = collectCandidates(configFiles: configFileCandidates(), gateway: defaultGateway())
        let statuses = await withTaskGroup(of: (Int, DiscoveredController.Status).self) { group in
            for (i, item) in found.enumerated() {
                group.addTask { (i, await probe(item.config)) }
            }
            var result: [Int: DiscoveredController.Status] = [:]
            for await (i, status) in group { result[i] = status }
            return result
        }
        for i in found.indices { found[i].status = statuses[i] ?? .unreachable }
        // 端口扫描没回应的直接丢掉；配置文件声明却连不上的保留，提示该客户端没在运行
        return found
            .filter { $0.status != .unreachable || !$0.isProbeOnly }
            .sorted { rank($0.status) < rank($1.status) }
    }

    private static func rank(_ status: DiscoveredController.Status) -> Int {
        switch status {
        case .ready: return 0
        case .needsSecret: return 1
        case .unreachable: return 2
        }
    }
}
