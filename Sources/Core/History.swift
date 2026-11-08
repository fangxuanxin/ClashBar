import Foundation
import CryptoKit

struct HistoryGroup: Codable, Equatable {
    var type: String
    var selection: String?
    var membership: String
    var path: [String]
}

struct HistoryState: Codable, Equatable {
    var mode: String
    var chain: [String]
    var basis: String
    var groups: [String: HistoryGroup]

    init(mode: String, proxies: [String: ProxyItem], exit: ExitInfo) {
        self.mode = mode
        chain = exit.chain
        basis = String(describing: exit.basis)
        groups = proxies.filter { $0.value.isGroup }.mapValues { proxy in
            let members = (proxy.all ?? []).sorted()
            let membership = HistoryIdentity.digest((try? JSONEncoder().encode(members)) ?? Data())
            return HistoryGroup(type: proxy.type, selection: proxy.now, membership: membership,
                         path: ExitResolver.path(from: proxy.name, proxies: proxies))
        }
    }

    func path(for group: String?) -> [String] {
        guard let group else { return chain }
        return groups[group]?.path ?? []
    }

    func terminal(for group: String?) -> String? {
        let path = path(for: group)
        guard let terminal = path.last, groups[terminal] == nil else { return nil }
        return terminal
    }

    func topologyMatches(_ other: Self) -> Bool {
        guard groups.keys.sorted() == other.groups.keys.sorted() else { return false }
        return groups.allSatisfy { name, group in
            other.groups[name]?.type == group.type && other.groups[name]?.membership == group.membership
        }
    }
}

enum HistoryIdentity {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func key(for controller: ControllerConfig) -> String {
        let address = controller.socketPath.flatMap { $0.isEmpty ? nil : "unix:\($0)" }
            ?? controller.url.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")).lowercased()
        let value = address + "|" + controller.secret
        return digest(Data(value.utf8))
    }
}

struct HistoryInterval: Identifiable {
    var id: String
    var start: Date
    var end: Date
    var session: String
    var state: HistoryState
    var kind: String
    var source: String
}

struct HistorySample {
    var time: Date
    var node: String
    var delay: Int?
    var origin: String = "clashbar"
    var testURL: String = ""
}

struct HistoryControllerInfo: Identifiable, Equatable {
    var id: String
    var name: String
}

struct HistoryReport {
    var intervals: [HistoryInterval] = []
    var samples: [HistorySample] = []
    var controllers: [HistoryControllerInfo] = []

    func observedDuration(from start: Date, to end: Date) -> TimeInterval {
        intervals.reduce(0) { total, interval in
            total + max(0, min(end, interval.end).timeIntervalSince(max(start, interval.start)))
        }
    }

    func changes(group: String?) -> [HistoryInterval] {
        var previous: HistoryInterval?
        return intervals.filter { interval in
            defer { previous = interval }
            guard let previous, previous.session == interval.session, interval.kind == "change" else { return false }
            return previous.state.path(for: group) != interval.state.path(for: group)
        }
    }
}
