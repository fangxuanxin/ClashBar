import Foundation

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, beta
    var id: String { rawValue }
    var title: String { L10n.t("updates.channel." + rawValue) }
}

struct UpdateVersion: Comparable, Equatable {
    let raw: String
    private let numbers: [Int]
    private let prerelease: String?

    init?(_ raw: String) {
        guard raw.range(of: "^[0-9]+(\\.[0-9]+){1,3}(-(alpha|beta|rc)\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        let parts = raw.split(separator: "-", maxSplits: 1)
        let components = parts[0].split(separator: ".").compactMap { Int($0) }
        guard components.count == parts[0].split(separator: ".").count else { return nil }
        self.raw = raw
        numbers = components + Array(repeating: 0, count: 4 - components.count)
        prerelease = parts.count == 2 ? String(parts[1]) : nil
    }

    static func == (left: Self, right: Self) -> Bool {
        left.numbers == right.numbers && left.prerelease == right.prerelease
    }

    static func < (left: Self, right: Self) -> Bool {
        if left.numbers != right.numbers { return left.numbers.lexicographicallyPrecedes(right.numbers) }
        switch (left.prerelease, right.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }
}

enum UpdateFailure: LocalizedError {
    case invalidReceipt, ambiguousInstallation, invalidResponse, pinned, unchanged, timeout
    case command(String)

    var errorDescription: String? {
        switch self {
        case .command(let detail): return L10n.t("updates.command_failed", ["reason": detail])
        default: return L10n.t("updates.error." + String(describing: self))
        }
    }
}

struct HomebrewInstallation: Equatable {
    let prefix: URL
    let tap: String
    var executable: URL { prefix.appendingPathComponent("bin/brew") }
    var qualifiedName: String { tap + "/clashbar" }

    static func find(app: URL, roots: [URL] = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"), URL(fileURLWithPath: "/usr/local/Caskroom")]) throws -> Self? {
        let manager = FileManager.default
        let resolved = app.resolvingSymlinksInPath().standardizedFileURL
        var matches: [HomebrewInstallation] = []
        for root in roots {
            let cask = root.appendingPathComponent("clashbar")
            let versions = (try? manager.contentsOfDirectory(at: cask, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let managed = versions.contains { version in
                let artifact = version.appendingPathComponent("ClashBar.app")
                return (try? manager.destinationOfSymbolicLink(atPath: artifact.path)) != nil && artifact.resolvingSymlinksInPath().standardizedFileURL == resolved
            } || (resolved.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == cask.standardizedFileURL)
            guard managed else { continue }
            let receipt = cask.appendingPathComponent(".metadata/INSTALL_RECEIPT.json")
            guard let data = try? Data(contentsOf: receipt),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let source = json["source"] as? [String: Any],
                  let tap = source["tap"] as? String,
                  ["fangxuanxin/tap", "fxx/tap", "homebrew/cask"].contains(tap) else { throw UpdateFailure.invalidReceipt }
            matches.append(Self(prefix: root.deletingLastPathComponent(), tap: tap))
        }
        guard matches.count <= 1 else { throw UpdateFailure.ambiguousInstallation }
        return matches.first
    }
}

struct BrewUpgradePlan {
    let command: String
    let version: String

    static func parse(_ data: Data, installation: HomebrewInstallation, target: String) throws -> Self {
        struct Response: Decodable {
            struct Cask: Decodable {
                let token: String
                let tap: String
                let version: String
                let installed: String?
                let disabled: Bool?
                let pinned: Bool?
            }
            let casks: [Cask]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.casks.count == 1, let cask = response.casks.first,
              cask.token == "clashbar", cask.tap == installation.tap, cask.disabled != true,
              let available = UpdateVersion(cask.version), let requested = UpdateVersion(target), available >= requested else { throw UpdateFailure.invalidResponse }
        guard cask.pinned != true else { throw UpdateFailure.pinned }
        return Self(command: cask.installed == cask.version ? "reinstall" : "upgrade", version: cask.version)
    }
}
