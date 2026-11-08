import Foundation
import Combine

@MainActor
final class HistoryModel: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var error: String?
    @Published var enabled: Bool {
        didSet {
            defaults.set(!enabled, forKey: "historyPaused")
            interrupt()
        }
    }
    private var service: HistoryService?
    private let defaults: UserDefaults
    private var session = UUID().uuidString
    private var generation = 0
    private var lastController: String?
    private var pendingAction: (controller: String, group: String?, value: String, expires: Date)?

    var observationGeneration: Int { generation }

    init(url: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = !defaults.bool(forKey: "historyPaused")
        do {
            service = try HistoryService(url: url ?? Preferences.supportDirectory.appendingPathComponent("History/history.sqlite"))
        } catch { self.error = error.localizedDescription }
    }

    func interrupt() {
        session = UUID().uuidString
        pendingAction = nil
        generation += 1
        revision += 1
    }

    func requested(controller: ControllerConfig, group: String?, value: String) {
        pendingAction = (HistoryIdentity.key(for: controller), group, value, Date().addingTimeInterval(20))
    }

    func observe(_ snapshot: ClashSnapshot, interval: Int, at time: Date, token: Int) async {
        guard enabled, token == generation, let service else { return }
        let capturedGeneration = generation
        let key = HistoryIdentity.key(for: snapshot.controller)
        if lastController != key {
            session = UUID().uuidString
            lastController = key
        }
        var source = "observed"
        if let action = pendingAction, action.controller == key, time <= action.expires {
            let matches = action.group.map { snapshot.proxies[$0]?.now == action.value } ?? (snapshot.mode == action.value)
            if matches { source = "local"; pendingAction = nil }
        }
        do {
            try await service.observe(controller: key, label: snapshot.controller.name,
                                      state: HistoryState(mode: snapshot.mode, proxies: snapshot.proxies, exit: snapshot.exit),
                                      session: session, at: time, maximumGap: max(15, Double(interval) * 2.5), source: source)
            if capturedGeneration == generation { error = nil; revision += 1 }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    func sample(controller: ControllerConfig, node: String, delay: Int?, at time: Date, token: Int) async {
        guard enabled, token == generation, let service else { return }
        do {
            try await service.sample(controller: HistoryIdentity.key(for: controller), node: node, delay: delay, at: time)
            revision += 1
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    func report(controller: String?, from start: Date, to end: Date) async throws -> HistoryReport {
        guard let service else { throw HistoryStore.StoreError.database(error ?? "History unavailable") }
        return try await service.report(controller: controller, from: start, to: end)
    }

    func clear() async {
        interrupt()
        guard let service else { return }
        do {
            try await service.clear()
            error = nil
            revision += 1
        } catch { self.error = error.localizedDescription }
    }
}
