import AppKit
import SwiftUI
import Charts

enum HistoryText {
    static func text(_ english: String, _ chinese: String) -> String {
        L10n.code == "zh-Hans" ? chinese : english
    }
    static var title: String { text("Switch History", "切换历史") }
    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = max(0, Int(seconds))
        if seconds >= 86400 { return String(format: "%.1f", Double(seconds) / 86400) + text(" d", " 天") }
        if seconds >= 3600 { return String(format: "%.1f", Double(seconds) / 3600) + text(" h", " 小时") }
        return String(seconds / 60) + text(" min", " 分钟")
    }
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: AppModel
    private let prefs: Preferences

    init(model: AppModel, prefs: Preferences) {
        self.model = model
        self.prefs = prefs
        super.init()
    }

    func show() {
        if window == nil {
            let view = HistoryView(history: model.history, model: model, prefs: prefs)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 960, height: 760))
            window.minSize = NSSize(width: 800, height: 620)
            window.center()
            self.window = window
        }
        refreshTitle()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refreshTitle() { window?.title = HistoryText.title }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

struct HistoryView: View {
    @ObservedObject var history: HistoryModel
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var hours = 24
    @State private var controller = ""
    @State private var group = ""
    @State private var tab = 0
    @State private var report = HistoryReport()
    @State private var reportEnd = Date()
    @State private var selectedInterval: String?
    @State private var loadError: String?
    @State private var confirmingClear = false
    @State private var eventLimit = 100
    @State private var sampleOrigin = "core"

    init(history: HistoryModel, model: AppModel, prefs: Preferences, initialTab: Int = 0, initialGroup: String = "", initialHours: Int = 24) {
        self.history = history
        self.model = model
        self.prefs = prefs
        _tab = State(initialValue: initialTab)
        _group = State(initialValue: initialGroup)
        _hours = State(initialValue: initialHours)
    }

    private var start: Date { reportEnd.addingTimeInterval(-Double(hours) * 3600) }
    private var selectedGroup: String? { group.isEmpty ? nil : group }
    private var groups: [String] { Array(Set(report.intervals.flatMap { $0.state.groups.keys })).sorted() }
    private var changes: [HistoryInterval] {
        report.changes(group: selectedGroup).filter { $0.start >= start }
    }
    private var intervals: [HistoryInterval] {
        report.intervals.filter { $0.end >= start && $0.start <= reportEnd }
    }
    private var observed: TimeInterval {
        intervals.filter { selectedGroup == nil || $0.state.groups[group] != nil }.reduce(0) {
            $0 + max(0, min(reportEnd, $1.end).timeIntervalSince(max(start, $1.start)))
        }
    }
    private var scopedSamples: [HistorySample] {
        let samples = report.samples.filter { $0.origin == sampleOrigin }
        guard let selectedGroup else { return samples }
        let records = intervals
        var intervalIndex = 0
        return samples.filter { sample in
            while intervalIndex + 1 < records.count && records[intervalIndex + 1].start <= sample.time { intervalIndex += 1 }
            guard intervalIndex < records.count else { return false }
            let interval = records[intervalIndex]
            return interval.start <= sample.time && sample.time.timeIntervalSince(interval.end) <= Double(prefs.refreshInterval) + 10
                && interval.state.chain.contains(selectedGroup)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            controls
            if let error = loadError ?? history.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).textSelection(.enabled)
            }
            HStack(spacing: 30) {
                metric(HistoryText.text("Observed changes", "观测到的切换"), String(changes.count))
                metric(HistoryText.text("Observed time", "有效观测时长"), HistoryText.duration(observed))
                metric(HistoryText.text("Coverage", "观测覆盖率"), String(format: "%.1f%%", min(100, observed / (Double(hours) * 3600) * 100)))
                metric(HistoryText.text("Test failures / samples", "测速失败 / 样本"), "\(scopedSamples.filter { $0.delay == nil }.count) / \(scopedSamples.count)")
                Spacer()
            }
            Divider()
            Picker(HistoryText.text("Sample source", "测速样本来源"), selection: $sampleOrigin) {
                Text(HistoryText.text("Existing core records", "内核已有记录")).tag("core")
                Text(HistoryText.text("Legacy ClashBar tests", "旧版 ClashBar 主动测速")).tag("clashbar")
            }.frame(maxWidth: 400)
            if intervals.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text(HistoryText.text("No observations in this period", "这个时间段还没有记录")).font(.headline)
                    Text(HistoryText.text("History accumulates while ClashBar is running and connected.", "ClashBar 运行并连接控制器后开始积累记录。")).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity)
                Spacer()
            } else {
                Picker("", selection: $tab) {
                    Text(HistoryText.text("Timeline & events", "时间线与事件")).tag(0)
                    Text(HistoryText.text("Node statistics", "节点统计")).tag(1)
                }.pickerStyle(.segmented)
                if tab == 0 { timelineAndEvents } else { nodeStatistics }
            }
            Divider()
            Text(HistoryText.text(
                "ClashBar reads existing core tests without initiating probes. Samples retain the core timestamp and are deduplicated. Gaps mean no data; a failed test does not prove an outage. Records stay locally for 30 days plus up to 5 recovery backups.",
                "ClashBar 只读取内核已有测速，不主动探测；按内核时间记录并去重。空白表示无数据，检测失败不代表断网。本地保留 30 天，另有最多 5 份恢复备份。"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.locale, Locale(identifier: L10n.code))
        .task(id: "\(controller)|\(hours)|\(history.revision)") { await reload() }
        .onChange(of: model.snapshot?.controller.endpointKey) { _ in
            if controller.isEmpty, let current = model.snapshot?.controller { controller = HistoryIdentity.key(for: current) }
        }
        .alert(HistoryText.text("Clear all history?", "清空全部历史？"), isPresented: $confirmingClear) {
            Button(HistoryText.text("Cancel", "取消"), role: .cancel) {}
            Button(HistoryText.text("Clear", "清空"), role: .destructive) {
                Task { await history.clear(); model.refresh() }
            }
        } message: {
            Text(HistoryText.text("This deletes observations, tests and recovery backups for every controller.", "将删除所有控制器的观测记录、测速样本和恢复备份。"))
        }
        .onChange(of: group) { _ in selectedInterval = nil; eventLimit = 100 }
        .onChange(of: hours) { _ in selectedInterval = nil; eventLimit = 100 }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(HistoryText.title).font(.title2.weight(.semibold))
                Spacer()
                Toggle(HistoryText.text("Record", "记录"), isOn: $history.enabled).toggleStyle(.switch)
                Button(HistoryText.text("Clear…", "清空…")) { confirmingClear = true }
            }
            HStack {
                Picker(HistoryText.text("Controller", "控制器"), selection: $controller) {
                    if report.controllers.isEmpty { Text("—").tag("") }
                    ForEach(report.controllers) { info in
                        Text(info.name + (report.controllers.filter { $0.name == info.name }.count > 1 ? " · " + info.id.prefix(6) : "")).tag(info.id)
                    }
                }.frame(maxWidth: 280)
                Picker(HistoryText.text("Scope", "范围"), selection: $group) {
                    Text(HistoryText.text("Default exit", "默认出口")).tag("")
                    ForEach(groups, id: \.self) { name in Text(name).tag(name) }
                }.frame(maxWidth: 300)
                Spacer()
                Picker("", selection: $hours) {
                    Text(HistoryText.text("1 hour", "1 小时")).tag(1)
                    Text(HistoryText.text("24 hours", "24 小时")).tag(24)
                    Text(HistoryText.text("7 days", "7 天")).tag(168)
                    Text(HistoryText.text("30 days", "30 天")).tag(720)
                }.frame(width: 110)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.medium))
        }
    }

    private var timelineAndEvents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(HistoryText.text("Selection timeline · click a segment for its path", "选择时间线 · 点击色块查看路径")).font(.subheadline.weight(.medium))
            GeometryReader { geometry in
                Canvas { context, size in
                    for interval in intervals {
                        let left = max(0, interval.start.timeIntervalSince(start) / (Double(hours) * 3600)) * size.width
                        let right = min(1, interval.end.timeIntervalSince(start) / (Double(hours) * 3600)) * size.width
                        guard right > left else { continue }
                        let path = interval.state.path(for: selectedGroup)
                        if !path.isEmpty {
                            context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(color(path.joined(separator: " → "))))
                        }
                    }
                }
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    let time = start.addingTimeInterval(value.location.x / max(1, geometry.size.width) * Double(hours) * 3600)
                    selectedInterval = intervals.last { $0.start <= time && $0.end >= time }?.id
                })
                .accessibilityLabel(HistoryText.text("Selection timeline; use the event list for details", "选择时间线，详细路径可通过事件列表查看"))
            }.frame(height: 36)
            HStack {
                Text(start, format: .dateTime.month().day().hour().minute())
                Spacer()
                Text(reportEnd, format: .dateTime.month().day().hour().minute())
            }.font(.caption).foregroundStyle(.secondary)
            if let selected = intervals.first(where: { $0.id == selectedInterval }) {
                Text(selected.state.path(for: selectedGroup).joined(separator: " → "))
                    .font(.callout).textSelection(.enabled)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(eventRows.prefix(eventLimit)), id: \.id) { interval in eventRow(interval) }
                    if eventRows.count > eventLimit {
                        Button(HistoryText.text("Load more", "加载更多")) { eventLimit += 100 }.padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var eventRows: [HistoryInterval] {
        let changedIDs = Set(changes.map(\.id))
        return intervals.filter { $0.kind != "change" || changedIDs.contains($0.id) }.reversed()
    }

    private func eventRow(_ interval: HistoryInterval) -> some View {
        let index = intervals.firstIndex { $0.id == interval.id } ?? 0
        let previous = index > 0 ? intervals[index - 1] : nil
        let path = interval.state.path(for: selectedGroup)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color(path.joined(separator: " → "))).frame(width: 8, height: 8)
                Text(interval.start, format: .dateTime.month().day().hour().minute().second()).monospacedDigit()
                Text(eventTitle(interval, previous: previous)).fontWeight(.medium)
                Spacer()
                if interval.source == "local" {
                    Text(HistoryText.text("After a ClashBar action", "本应用操作后观测")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if interval.kind == "change", let previous {
                Text(previous.state.path(for: selectedGroup).joined(separator: " → "))
                    .foregroundStyle(.secondary)
            }
            Text(path.isEmpty ? HistoryText.text("No resolvable path", "无法解析选择路径") : path.joined(separator: " → "))
                .textSelection(.enabled)
            if let terminal = path.last, let type = interval.state.groups[terminal]?.type {
                Text(HistoryText.text("No single terminal node", "没有唯一的最终节点") + " · " + type).font(.caption).foregroundStyle(.secondary)
            }
            Text((OutboundMode(rawValue: interval.state.mode)?.title ?? interval.state.mode) + " · " + HistoryText.duration(min(reportEnd, interval.end).timeIntervalSince(max(start, interval.start))))
                .font(.caption).foregroundStyle(.secondary)
            if selectedGroup == nil, interval.state.basis == "inferred" {
                Text(HistoryText.text("Default policy inferred from group names", "默认策略根据分组名称推测"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.top, 6)
        }
        .font(.callout)
        .padding(.vertical, 9)
    }

    private func eventTitle(_ interval: HistoryInterval, previous: HistoryInterval?) -> String {
        switch interval.kind {
        case "baseline": return HistoryText.text("Observation started / resumed", "开始 / 恢复观测")
        case "configuration": return HistoryText.text("Group configuration changed", "分组配置变化")
        case "mode": return HistoryText.text("Mode changed", "模式变化")
        default:
            if previous?.state.terminal(for: selectedGroup) == interval.state.terminal(for: selectedGroup) {
                return HistoryText.text("Path changed · same node", "路径变化 · 节点未变")
            }
            return HistoryText.text("Node changed", "节点变化")
        }
    }

    private var nodeStatistics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(HistoryText.text("Default exit latency samples", "默认出口延迟样本")).font(.headline)
                if scopedSamples.isEmpty {
                    Text(HistoryText.text("No test samples for this scope", "这个范围没有测速样本")).foregroundStyle(.secondary)
                } else {
                    Chart(Array(chartSamples.enumerated()), id: \.offset) { entry in
                        if let delay = entry.element.delay {
                            PointMark(x: .value("Time", entry.element.time), y: .value("ms", delay))
                                .foregroundStyle(color(entry.element.node)).symbolSize(12)
                        } else {
                            PointMark(x: .value("Time", entry.element.time), y: .value("ms", 0))
                                .foregroundStyle(.red).symbol(.cross).symbolSize(25)
                        }
                    }
                    .chartXScale(domain: start...reportEnd)
                    .chartYAxisLabel("ms")
                    .frame(height: 150)
                    Text(HistoryText.text("Red crosses: failed tests. Dense samples are grouped; failures and peak latency are preserved.", "红叉表示测速失败。密集样本合并显示，保留失败与最高延迟。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(nodeRows, id: \.name) { row in
                    HStack {
                        Circle().fill(color(row.name)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.name).textSelection(.enabled)
                            Text(HistoryText.text("Observed selection time", "观测选择时长") + " · " + HistoryText.duration(row.duration))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(row.samples.isEmpty ? HistoryText.text("No samples", "样本不足") : "\(row.samples.filter { $0.delay == nil }.count) / \(row.samples.count) " + HistoryText.text("failed", "失败"))
                            .foregroundStyle(.secondary)
                        if let median = row.median { Text("\(median) ms").monospacedDigit().frame(width: 85, alignment: .trailing) }
                    }.padding(.vertical, 5)
                    Divider()
                }
                Text(HistoryText.text("Latency values in the list are medians. Selection time is not traffic usage or uptime.", "列表延迟为中位数。选择时长不代表实际流量或在线时长。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var chartSamples: [HistorySample] {
        let buckets = Dictionary(grouping: scopedSamples) { Int($0.time.timeIntervalSince(start) / max(1, Double(hours) * 3600 / 300)) }
        return buckets.keys.sorted().flatMap { key -> [HistorySample] in
            let samples = buckets[key] ?? []
            var result: [HistorySample] = []
            if let failure = samples.first(where: { $0.delay == nil }) { result.append(failure) }
            if let peak = samples.filter({ $0.delay != nil }).max(by: { ($0.delay ?? 0) < ($1.delay ?? 0) }) { result.append(peak) }
            return result
        }
    }

    private struct NodeRow {
        var name: String
        var duration: TimeInterval
        var samples: [HistorySample]
        var median: Int? {
            let delays = samples.compactMap(\.delay).sorted()
            guard !delays.isEmpty else { return nil }
            let middle = delays.count / 2
            return delays.count.isMultiple(of: 2) ? (delays[middle - 1] + delays[middle]) / 2 : delays[middle]
        }
    }

    private var nodeRows: [NodeRow] {
        var durations: [String: TimeInterval] = [:]
        for interval in intervals {
            guard let node = interval.state.terminal(for: selectedGroup) else { continue }
            durations[node, default: 0] += max(0, min(reportEnd, interval.end).timeIntervalSince(max(start, interval.start)))
        }
        let samples = Dictionary(grouping: scopedSamples, by: \.node)
        return Set(durations.keys).union(samples.keys).map { name in
            NodeRow(name: name, duration: durations[name] ?? 0, samples: samples[name] ?? [])
        }.sorted { $0.duration == $1.duration ? $0.name < $1.name : $0.duration > $1.duration }
    }

    private func color(_ name: String) -> Color {
        let palette: [Color] = [.blue, .teal, .purple, .orange, .pink, .indigo, .green, .brown]
        let index = name.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x7fffffff } % palette.count
        return palette[index]
    }

    private func reload() async {
        do {
            let end = Date()
            let available = try await history.report(controller: nil, from: end.addingTimeInterval(-Double(hours) * 3600), to: end)
            try Task.checkCancellation()
            let current = model.snapshot.map { HistoryIdentity.key(for: $0.controller) }
            let key = available.controllers.contains(where: { $0.id == controller }) ? controller
                : (available.controllers.first(where: { $0.id == current })?.id ?? available.controllers.first?.id ?? "")
            let loaded = try await history.report(controller: key, from: end.addingTimeInterval(-Double(hours) * 3600), to: end)
            try Task.checkCancellation()
            reportEnd = end
            report = loaded
            if controller != key { controller = key }
            if !group.isEmpty, !groups.contains(group) { group = "" }
            loadError = nil
        } catch is CancellationError {} catch { loadError = error.localizedDescription }
    }
}
