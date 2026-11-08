import Foundation

// MARK: - Clash / Mihomo REST API 返回结构（宽松解码，字段缺失不报错）

struct ProxyHistory: Decodable, Equatable {
    let delay: Int
    var time: String? = nil

    var date: Date? {
        guard let time else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: time) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: time)
    }
}

struct ProxyTestState: Decodable, Equatable {
    var history: [ProxyHistory]
    var alive: Bool?
}

/// /proxies 里的一项：可能是节点，也可能是分组（有 all 字段即为分组）
struct ProxyItem: Decodable, Equatable {
    let name: String
    let type: String
    let now: String?
    let all: [String]?
    let history: [ProxyHistory]
    let alive: Bool?
    let hidden: Bool?
    let testURL: String?
    let extra: [String: ProxyTestState]

    enum CodingKeys: String, CodingKey { case name, type, now, all, history, alive, hidden, extra; case testURL = "testUrl" }

    init(name: String, type: String, now: String? = nil, all: [String]? = nil,
         history: [ProxyHistory] = [], alive: Bool? = nil, hidden: Bool? = nil,
         testURL: String? = nil, extra: [String: ProxyTestState] = [:]) {
        self.name = name; self.type = type; self.now = now; self.all = all
        self.history = history; self.alive = alive; self.hidden = hidden
        self.testURL = testURL; self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        now = try? c.decodeIfPresent(String.self, forKey: .now)
        all = try? c.decodeIfPresent([String].self, forKey: .all)
        history = (try? c.decodeIfPresent([ProxyHistory].self, forKey: .history)) ?? []
        alive = try? c.decodeIfPresent(Bool.self, forKey: .alive)
        hidden = try? c.decodeIfPresent(Bool.self, forKey: .hidden)
        testURL = try? c.decodeIfPresent(String.self, forKey: .testURL)
        extra = (try? c.decodeIfPresent([String: ProxyTestState].self, forKey: .extra)) ?? [:]
    }

    var isGroup: Bool { all != nil }
    /// 只有 Selector 允许手动切换
    var isSelectable: Bool { type.caseInsensitiveCompare("Selector") == .orderedSame }
    /// 最近一次内核自测的延迟；0 表示失败
    var lastDelay: Int? { history.last?.delay }

    /// DIRECT / REJECT 等内置出站不参与测速
    var isBuiltin: Bool {
        ["direct", "reject", "reject-drop", "rejectdrop", "pass", "compatible", "dns", "block"].contains(type.lowercased())
    }
}

struct ProxiesResponse: Decodable {
    let proxies: [String: ProxyItem]
}

struct ConfigsResponse: Decodable {
    let mode: String
    enum CodingKeys: String, CodingKey { case mode }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = ((try? c.decode(String.self, forKey: .mode)) ?? "rule").lowercased()
    }
}

struct VersionResponse: Decodable {
    let version: String
    let meta: Bool?
}

struct RuleItem: Decodable, Equatable {
    let type: String
    let proxy: String
}

struct RulesResponse: Decodable {
    let rules: [RuleItem]
}

/// 出站模式
enum OutboundMode: String, CaseIterable {
    case rule, global, direct

    var title: String { L10n.t("mode.\(rawValue)") }
}
