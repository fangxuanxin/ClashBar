import AppKit
import Combine
import Foundation
import Network

/// 当前出口节点的连通性
enum NodeHealth: Equatable {
    case unknown
    case testing
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

/// 应用状态中心：负责定时刷新、切换模式和节点、测速
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
    @Published private(set) var testingGroups: Set<String> = []
    @Published private(set) var actionError: String?

    private let prefs: Preferences
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

    init(prefs: Preferences) {
        self.prefs = prefs
    }

    func start() {
        scheduleTimer()
        refresh()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
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
        refreshTask?.cancel()
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
        refreshTask = Task { [weak self] in
            await self?.performRefresh()
            guard let self else { return }
            self.refreshTask = nil
            self.isRefreshing = false
            if self.refreshAgain {
                self.refreshAgain = false
                self.refresh()
            }
        }
    }

    private func resolveController() async throws -> ControllerConfig {
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
            let previousNode = snapshot?.exit.node
            snapshot = ClashSnapshot(controller: controller, version: Discovery.coreLabel(version), mode: configs.mode, proxies: proxies,
                                     groups: ExitResolver.orderedGroups(proxies, mode: configs.mode), exit: exit)
            phase = .ready
            startupRetries = 0
            lastUpdated = Date()
            if exit.node != previousNode, case .ok = health { health = .unknown }
            await checkHealth(client: client, exit: exit, proxies: proxies)
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

    /// 只测当前出口节点：一次请求，开销很小
    private func checkHealth(client: ClashClient, exit: ExitInfo, proxies: [String: ProxyItem]) async {
        guard let node = exit.node, let proxy = proxies[node], !proxy.isGroup, !proxy.isBuiltin,
              exit.family != .direct, exit.family != .reject else {
            health = .notApplicable
            return
        }
        if health == .unknown { health = .testing }
        let delay = await client.delay(of: node, testURL: prefs.effectiveTestURL)
        guard !Task.isCancelled, snapshot?.exit.node == node else { return }
        health = delay.map { .ok($0) } ?? .failed
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
        perform { try await $0.setMode(mode) }
    }

    func select(group: String, node: String) {
        health = .unknown
        perform { try await $0.select(group: group, node: node) }
    }

    /// 测一个分组；内核会把结果写进 history，刷新后菜单即可显示新延迟
    func testGroup(_ name: String) {
        guard let controller = snapshot?.controller, !testingGroups.contains(name) else { return }
        testingGroups.insert(name)
        let url = prefs.effectiveTestURL
        Task {
            _ = try? await ClashClient(config: controller).groupDelay(of: name, testURL: url)
            testingGroups.remove(name)
            refresh()
        }
    }

    /// 测出口路径上的分组（最多 4 组并发）；路径上没有分组时测全部
    func testLatency() {
        guard let snapshot else { return }
        let chainGroups = snapshot.exit.chain.filter { snapshot.proxies[$0]?.isGroup == true }
        var names: [String] = []
        for name in chainGroups where !names.contains(name) && name != "GLOBAL" { names.append(name) }
        if names.isEmpty { names = snapshot.groups.map(\.name).filter { $0 != "GLOBAL" } }
        let controller = snapshot.controller
        let url = prefs.effectiveTestURL
        testingGroups.formUnion(names)
        health = .testing
        Task {
            await withTaskGroup(of: Void.self) { group in
                var iterator = names.makeIterator()
                func next() -> Bool {
                    guard let name = iterator.next() else { return false }
                    group.addTask { _ = try? await ClashClient(config: controller).groupDelay(of: name, testURL: url) }
                    return true
                }
                for _ in 0..<4 { if !next() { break } }
                while await group.next() != nil { _ = next() }
            }
            testingGroups.subtract(names)
            refresh()
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
