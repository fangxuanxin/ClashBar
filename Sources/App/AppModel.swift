import AppKit
import Combine
import Foundation
import Network

/// 当前出口节点已有的内核健康检查结果
enum NodeHealth: Equatable {
    case unknown
    case ok(Int)
    case failed
    /// DIRECT / REJECT 等无需测速
    case notApplicable
}

/// 一次成功读取到的控制器状态
struct ClashSnapshot {
    var controller: ControllerConfig
    var version: String
    var mode: String
    var proxies: [String: ProxyItem]
    var groups: [ProxyItem]
    var exit: ExitInfo

    /// 所有真实节点中，内核最近一次自测仍存活的数量
    var aliveCount: (alive: Int, total: Int) {
        let nodes = proxies.values.filter { !$0.isGroup && !$0.isBuiltin }
        return (nodes.filter { $0.alive == true }.count, nodes.count)
    }
}

/// 应用状态中心：读取控制器状态，并响应用户切换模式和节点
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case starting
        case ready
        case failed(ClashError)
    }

    @Published private(set) var phase: Phase = .starting
    @Published private(set) var snapshot: ClashSnapshot?
    @Published private(set) var health: NodeHealth = .unknown
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var actionError: String?

    private let prefs: Preferences
    private let controllerOverride: ControllerConfig?
    let history: HistoryModel
    private var refreshGeneration = 0
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    private var autoController: ControllerConfig?
    private var rulesCache: (key: String, fetched: Date, rules: [RuleItem])?
    private var pathMonitor: NWPathMonitor?
    private var networkDebounce: DispatchWorkItem?
    private var pathSeen = false
    /// 还没成功连上过时的快速重试次数：刚启动时首个局域网请求常会失败（系统还在评估本地网络权限）
    private var startupRetries = 0
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences, history: HistoryModel? = nil, controller: ControllerConfig? = nil) {
        self.prefs = prefs
        controllerOverride = controller
        self.history = history ?? HistoryModel()
    }

    func start() {
        scheduleTimer()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.history.interrupt(); self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.history.interrupt(); self?.refreshTask?.cancel() }
        }
        // 网络变化（换 Wi-Fi、插拔网线）后稍等再刷新，并重新检测控制器
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                // 第一次回调只是报告当前网络，不算变化
                guard self.pathSeen else { self.pathSeen = true; return }
                self.networkDebounce?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    self?.controllerChanged()
                }
                self.networkDebounce = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
            }
        }
        monitor.start(queue: DispatchQueue(label: "ClashBar.network"))
        pathMonitor = monitor

        prefs.$refreshInterval.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleTimer() }
        }.store(in: &cancellables)
        prefs.$activeControllerID.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.controllerChanged() }
        }.store(in: &cancellables)
        prefs.$controllers.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.controllerChanged() }
        }.store(in: &cancellables)
    }

    func stop() {
        history.interrupt()
        timer?.invalidate()
        refreshTask?.cancel()
        pathMonitor?.cancel()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: TimeInterval(prefs.refreshInterval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        // common 模式：菜单展开时也照常刷新
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 控制器切换或编辑后：清空旧数据立即重读
    func controllerChanged() {
        refreshGeneration += 1
        history.interrupt()
        refreshTask?.cancel()
        refreshTask = nil
        refreshAgain = false
        autoController = nil
        rulesCache = nil
        snapshot = nil
        health = .unknown
        phase = .starting
        refresh()
    }

    // MARK: - 刷新

    func refresh() {
        if refreshTask != nil {
            refreshAgain = true
            return
        }
        isRefreshing = true
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            guard let self, self.refreshGeneration == generation else { return }
            self.refreshTask = nil
            self.isRefreshing = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    private func resolveController() async throws -> ControllerConfig {
        if let controllerOverride { return controllerOverride }
        if let active = prefs.activeController { return active }
        if let autoController { return autoController }
        if !prefs.controllers.isEmpty {
            let controller = try await Discovery.firstReachable(prefs.controllers)
            autoController = controller
            return controller
        }
        let found = await Discovery.discover()
        try Task.checkCancellation()
        guard let ready = found.first(where: { if case .ready = $0.status { return true } else { return false } }) else {
            if found.contains(where: { $0.status == .needsSecret }) { throw ClashError.unauthorized }
            throw ClashError.notConfigured
        }
        autoController = ready.config
        return ready.config
    }

    private func performRefresh(retryAutomatic: Bool = true) async {
        let historyToken = history.observationGeneration
        let wasLocked = prefs.activeControllerID == nil && autoController != nil
        do {
            let controller = try await resolveController()
            let client = ClashClient(config: controller)
            async let versionValue = client.version()
            async let configsValue = client.configs()
            async let proxiesValue = client.proxies()
            let (version, configs, proxies) = try await (versionValue, configsValue, proxiesValue)

            // 规则表可能很大：只在规则模式下读，且 5 分钟内复用
            var rules: [RuleItem]? = nil
            if configs.mode == "rule" {
                if let cache = rulesCache, cache.key == controller.endpointKey, Date().timeIntervalSince(cache.fetched) < 300 {
                    rules = cache.rules
                } else if let fresh = try? await client.rules() {
                    rulesCache = (controller.endpointKey, Date(), fresh)
                    rules = fresh
                } else {
                    rules = rulesCache?.rules
                }
            }
            if Task.isCancelled { return }

            let exit = ExitResolver.resolve(mode: configs.mode, proxies: proxies, rules: rules)
            snapshot = ClashSnapshot(controller: controller, version: Discovery.coreLabel(version), mode: configs.mode, proxies: proxies,
                                     groups: ExitResolver.orderedGroups(proxies, mode: configs.mode), exit: exit)
            phase = .ready
            startupRetries = 0
            let observedAt = Date()
            lastUpdated = observedAt
            if let snapshot { await history.observe(snapshot, interval: prefs.refreshInterval, at: observedAt, token: historyToken) }
            if Task.isCancelled { return }
            await readHealth(controller: controller, exit: exit, proxies: proxies, historyToken: historyToken, observedAt: observedAt)
        } catch is CancellationError {
            return
        } catch let error as ClashError {
            if wasLocked && retryAutomatic {
                autoController = nil
                rulesCache = nil
                await performRefresh(retryAutomatic: false)
                return
            }
            fail(error)
        } catch {
            if wasLocked && retryAutomatic {
                autoController = nil
                rulesCache = nil
                await performRefresh(retryAutomatic: false)
                return
            }
            fail(.unreachable(error.localizedDescription))
        }
    }

    private func fail(_ error: ClashError) {
        history.interrupt()
        // 自动模式下失败就丢弃缓存的控制器，下次重新检测
        autoController = nil
        health = .unknown
        // 从没成功过、且不是缺配置 / 口令错：先保持「连接中」，2 秒后重试，最多 3 次
        if snapshot == nil, startupRetries < 3, error != .notConfigured, error != .unauthorized {
            startupRetries += 1
            phase = .starting
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refresh() }
            return
        }
        phase = .failed(error)
    }

    private func readHealth(controller: ControllerConfig, exit: ExitInfo, proxies: [String: ProxyItem], historyToken: Int, observedAt: Date) async {
        guard let node = exit.node, let proxy = proxies[node], !proxy.isGroup, !proxy.isBuiltin,
              exit.family != .direct, exit.family != .reject else {
            health = .notApplicable
            return
        }
        guard let reading = PassiveLatency.read(exit: exit, proxies: proxies), reading.isRecent(at: observedAt),
              let measuredAt = reading.sample.date else {
            health = .unknown
            return
        }
        health = reading.sample.delay > 0 ? .ok(reading.sample.delay) : .failed
        await history.sample(controller: controller, node: node, delay: reading.sample.delay > 0 ? reading.sample.delay : nil,
                             at: measuredAt, token: historyToken, origin: "core", testURL: reading.testURL ?? "")
    }

    // MARK: - 操作

    private func perform(_ action: @escaping (ClashClient) async throws -> Void) {
        guard let controller = snapshot?.controller else { return }
        actionError = nil
        Task {
            do {
                try await action(ClashClient(config: controller))
            } catch let error as ClashError {
                actionError = L10n.t("error.action_failed", ["reason": error.message])
                NSSound.beep()
            } catch {
                actionError = L10n.t("error.action_failed", ["reason": error.localizedDescription])
                NSSound.beep()
            }
            refresh()
        }
    }

    func setMode(_ mode: OutboundMode) {
        perform { client in
            try await client.setMode(mode)
            self.history.requested(controller: client.config, group: nil, value: mode.rawValue)
        }
    }

    func select(group: String, node: String) {
        health = .unknown
        perform { client in
            try await client.select(group: group, node: node)
            self.history.requested(controller: client.config, group: group, value: node)
        }
    }

    /// 复制到剪贴板的出口信息
    func copyExitInfo() {
        guard let snapshot else { return }
        let text = L10n.t("copy.text", [
            "group": snapshot.exit.group ?? "-",
            "node": snapshot.exit.node ?? "-",
            "path": snapshot.exit.chain.joined(separator: " → "),
            "mode": OutboundMode(rawValue: snapshot.mode)?.title ?? snapshot.mode,
            "controller": snapshot.controller.displayAddress,
        ])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
