import Foundation

/// 出口类型：走代理、直连还是拒绝
enum ExitFamily: Equatable {
    case proxy, direct, reject
}

/// 判断默认出口的依据
enum ExitBasis: Equatable {
    case matchRule, globalMode, directMode, inferred, none
}

/// 当前默认出口的解析结果
struct ExitInfo: Equatable {
    /// 起点策略（MATCH 规则指向的分组、GLOBAL 或 DIRECT）
    var policy: String?
    /// 从起点沿着各分组 now 一路走到最终节点的路径
    var chain: [String]
    /// 最终节点
    var node: String?
    /// 展示用分组名：路径上最深的那个分组
    var group: String?
    var family: ExitFamily
    var basis: ExitBasis
}

enum ExitResolver {
    /// 没有 MATCH 规则时按常见命名猜测默认分组
    static let fallbackPolicies = ["Node Select", "节点选择", "🚀 节点选择", "PROXY", "Proxy", "Proxies", "proxy", "select"]

    /// 沿分组的 now 字段走到底；遇到环、负载均衡或未选择时停止
    static func path(from name: String, proxies: [String: ProxyItem]) -> [String] {
        var chain: [String] = []
        var current = name
        while true {
            if chain.contains(current) { return chain }
            chain.append(current)
            guard let proxy = proxies[current], proxy.isGroup else { return chain }
            if proxy.type.caseInsensitiveCompare("LoadBalance") == .orderedSame { return chain }
            guard let next = proxy.now, !next.isEmpty else { return chain }
            current = next
        }
    }

    static func resolve(mode: String, proxies: [String: ProxyItem], rules: [RuleItem]?) -> ExitInfo {
        let policy: String?
        let basis: ExitBasis
        switch mode.lowercased() {
        case "direct":
            return ExitInfo(policy: "DIRECT", chain: ["DIRECT"], node: "DIRECT", group: nil, family: .direct, basis: .directMode)
        case "global":
            policy = proxies["GLOBAL"] != nil ? "GLOBAL" : nil
            basis = .globalMode
        default:
            if let match = rules?.last(where: { $0.type.caseInsensitiveCompare("Match") == .orderedSame }) {
                policy = match.proxy
                basis = .matchRule
            } else if let guess = fallbackPolicies.first(where: { proxies[$0]?.isGroup == true }) {
                policy = guess
                basis = .inferred
            } else {
                policy = nil
                basis = .none
            }
        }
        guard let policy else {
            return ExitInfo(policy: nil, chain: [], node: nil, group: nil, family: .proxy, basis: .none)
        }

        let chain = path(from: policy, proxies: proxies)
        let node = chain.last
        let group = chain.filter { proxies[$0]?.isGroup == true }.last ?? policy

        // 按最终节点的类型判断直连 / 拒绝（sing-box 的 direct / block 也算）
        var family = ExitFamily.proxy
        if let node {
            let type = (proxies[node]?.type ?? node).lowercased()
            if type == "direct" || node == "DIRECT" {
                family = .direct
            } else if type.hasPrefix("reject") || type == "block" || node.hasPrefix("REJECT") {
                family = .reject
            }
        }
        return ExitInfo(policy: policy, chain: chain, node: node, group: group, family: family, basis: basis)
    }

    /// 分组展示顺序：GLOBAL.all 保留了配置文件里的原始顺序，其余按名称排
    static func orderedGroups(_ proxies: [String: ProxyItem], mode: String) -> [ProxyItem] {
        let groups = proxies.values.filter { $0.isGroup && $0.hidden != true }
        let order = proxies["GLOBAL"]?.all ?? []
        var index: [String: Int] = [:]
        for (i, name) in order.enumerated() where index[name] == nil { index[name] = i }
        return groups
            .filter { $0.name != "GLOBAL" || mode == "global" }
            .sorted { a, b in
                if a.name == "GLOBAL" { return true }
                if b.name == "GLOBAL" { return false }
                switch (index[a.name], index[b.name]) {
                case let (x?, y?): return x < y
                case (_?, nil): return true
                case (nil, _?): return false
                default: return a.name.localizedStandardCompare(b.name) == .orderedAscending
                }
            }
    }
}
