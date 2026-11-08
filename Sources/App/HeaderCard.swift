import SwiftUI

/// 菜单顶部的状态卡片：当前出口、节点、延迟、模式与更新时间
struct HeaderCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                badge
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                healthLabel
            }
            .frame(minHeight: 44)

            Divider()

            HStack(spacing: 6) {
                Text(footerLeft)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                Text(footerRight)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(minWidth: Self.width, maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 左侧徽标

    private var badge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.gradient)
            badgeContent
                .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        .overlay(alignment: .bottomTrailing) {
            if model.health == .failed, model.snapshot != nil, model.phase == .ready {
                Circle()
                    .fill(Color.red)
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .offset(x: 3, y: 3)
            }
        }
    }

    @ViewBuilder private var badgeContent: some View {
        // 有地区缩写就写缩写，否则画线条猫
        if let badge = StatusIcon.kind(phase: model.phase, snapshot: model.snapshot, health: .unknown).badge {
            Text(badge).font(.system(size: badge.count > 1 ? 18 : 22, weight: .bold, design: .rounded))
        } else {
            Image(nsImage: StatusIcon.cat(side: 26)).renderingMode(.template)
        }
    }

    private var tint: Color {
        if case .failed = model.phase { return .red }
        switch model.snapshot?.exit.family {
        case .proxy: return .indigo
        case .direct: return .teal
        case .reject: return .pink
        case nil: return .gray
        }
    }

    // MARK: - 文案

    private var title: String {
        switch model.phase {
        case .starting: return L10n.t("card.connecting")
        case .failed(.notConfigured): return L10n.t("card.not_configured")
        case .failed: return L10n.t("card.error")
        case .ready: break
        }
        guard let exit = model.snapshot?.exit else { return L10n.t("card.connecting") }
        switch exit.family {
        case .direct where exit.basis == .directMode: return L10n.t("card.direct")
        case .reject: return L10n.t("card.reject")
        default: return exit.group ?? exit.policy ?? "—"
        }
    }

    private var subtitle: String {
        switch model.phase {
        case .starting: return model.snapshot?.controller.displayAddress ?? " "
        case .failed(.notConfigured): return L10n.t("card.not_configured.hint")
        case .failed(let error): return error.message
        case .ready: break
        }
        guard let exit = model.snapshot?.exit else { return " " }
        if exit.family == .direct && exit.basis == .directMode { return L10n.t("card.direct.hint") }
        return exit.node ?? "—"
    }

    @ViewBuilder private var healthLabel: some View {
        if model.phase == .ready {
            switch model.health {
            case .ok(let ms):
                pill(text: "\(ms) ms", color: Self.delayColor(ms))
            case .failed:
                pill(text: L10n.t("card.timeout"), color: .red)
            case .unknown, .notApplicable:
                EmptyView()
            }
        }
    }

    private func pill(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11, weight: .medium).monospacedDigit())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }

    private var footerLeft: String {
        guard let snapshot = model.snapshot else {
            return prefs.activeController?.displayAddress ?? L10n.t("menu.controller.auto")
        }
        var parts: [String] = []
        if let mode = OutboundMode(rawValue: snapshot.mode) { parts.append(mode.title) }
        if model.health == .failed {
            let count = snapshot.aliveCount
            if count.total > 0 { parts.append(L10n.t("card.alive", ["alive": String(count.alive), "total": String(count.total)])) }
        } else if !snapshot.version.isEmpty {
            parts.append(snapshot.version)
        }
        parts.append(snapshot.controller.displayAddress)
        return parts.joined(separator: " · ")
    }

    private var footerRight: String {
        guard let date = model.lastUpdated else { return "" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 5 { return L10n.t("card.updated", ["time": L10n.t("card.just_now")]) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: L10n.code)
        formatter.unitsStyle = .short
        return L10n.t("card.updated", ["time": formatter.localizedString(for: date, relativeTo: Date())])
    }

    static func delayColor(_ ms: Int) -> Color {
        if ms < 300 { return .green }
        if ms < 800 { return .orange }
        return .red
    }
}
