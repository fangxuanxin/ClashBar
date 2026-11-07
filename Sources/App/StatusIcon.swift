import AppKit

/// 菜单栏图标：线条猫（右下截断的 C）+ 出口所在地区的两字母缩写（US、JP……）。
/// 全部为模板图，自动适配深浅色。
enum StatusIcon {
    struct Kind: Equatable {
        /// 猫右侧的短标：地区缩写，或 → 直连、× 拒绝、! 出错；nil 表示只画猫
        var badge: String?
        /// 变淡：当前节点无响应，或还没连上
        var dimmed: Bool = false
    }

    static func kind(phase: AppModel.Phase, snapshot: ClashSnapshot?, health: NodeHealth, mbEnabled: Bool = false) -> Kind {
        if case .failed = phase { return Kind(badge: "!") }
        guard let snapshot else { return Kind(badge: nil, dimmed: true) }
        switch snapshot.exit.family {
        case .direct: return Kind(badge: "→")
        case .reject: return Kind(badge: "×")
        default:
            let region = Region.code(of: snapshot.exit)
            let role = mbEnabled ? GroupRole.current(exit: snapshot.exit, proxies: snapshot.proxies) : nil
            let badge = region.map { region in role.map { "\($0.rawValue) \(region)" } ?? region }
            return Kind(badge: badge, dimmed: health == .failed)
        }
    }

    /// 菜单栏用：猫 + 短标，高度默认 16pt
    static func image(for kind: Kind, height: CGFloat = 16) -> NSImage {
        let font = NSFont.systemFont(ofSize: height * 0.72, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let text = kind.badge.map { NSAttributedString(string: $0, attributes: attributes) }
        let gap = height * 0.12
        let textWidth = text.map { ceil($0.size().width) } ?? 0
        let width = height + (text == nil ? 0 : gap + textWidth)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if kind.dimmed { context.setAlpha(0.4) }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            CatGlyph.draw(in: context, scale: height / CatGlyph.unit, origin: .zero)
            if let text {
                // 文字按字形高度垂直居中，和猫头中心大致对齐
                let y = (height - font.capHeight) / 2 - (font.ascender - font.capHeight) + height * 0.04
                text.draw(at: NSPoint(x: height + gap, y: y))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 只有猫：设置页、卡片等处用
    static func cat(side: CGFloat) -> NSImage {
        image(for: Kind(badge: nil), height: side)
    }
}
