import Foundation

struct PassiveLatency: Equatable {
    var sample: ProxyHistory
    var testURL: String?

    func isRecent(at now: Date) -> Bool {
        guard let date = sample.date else { return false }
        return now.timeIntervalSince(date) >= -5 && now.timeIntervalSince(date) <= 600
    }

    static func read(node: ProxyItem, group: ProxyItem?) -> Self? {
        if let url = group?.testURL, !url.isEmpty {
            if let sample = node.extra[url]?.history.last { return Self(sample: sample, testURL: url) }
            if !node.extra.isEmpty { return nil }
        }
        if let sample = node.history.last { return Self(sample: sample, testURL: nil) }
        return nil
    }

    static func read(exit: ExitInfo, proxies: [String: ProxyItem]) -> Self? {
        guard let name = exit.node, let node = proxies[name], !node.isGroup, !node.isBuiltin,
              exit.family == .proxy else { return nil }
        let group = exit.chain.reversed().compactMap { proxies[$0] }.first { $0.isGroup && !($0.testURL ?? "").isEmpty }
        return read(node: node, group: group)
    }
}
