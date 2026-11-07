import Foundation

enum GroupRole: String {
    case main = "M"
    case backup = "B"

    private static func role(of name: String) -> Self? {
        let words = Set(name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        switch (words.contains("main"), words.contains("backup")) {
        case (true, false): return .main
        case (false, true): return .backup
        default: return nil
        }
    }

    static func current(exit: ExitInfo, proxies: [String: ProxyItem]) -> Self? {
        guard exit.family == .proxy else { return nil }
        let groups = proxies.values.filter(\.isGroup)
        let roles = Set(groups.compactMap { role(of: $0.name) })
        guard roles.contains(.main), roles.contains(.backup) else { return nil }
        return exit.chain.reversed().compactMap { name in
            guard proxies[name]?.isGroup == true else { return nil }
            return role(of: name)
        }.first
    }
}
