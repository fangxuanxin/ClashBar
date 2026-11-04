import CoreGraphics

/// 线条猫：主体是一个右下角截断的 C（猫头），顶上两只尖耳朵，两点眼睛。
/// 在 16×16 的单位格里设计（y 轴向下），按需缩放；不依赖其它代码，方便单独预览。
enum CatGlyph {
    /// 设计格边长
    static let unit: CGFloat = 16

    /// 头部轮廓（一笔画完）：从右下截断处出发，顺时针经过底、左，爬上左耳、右耳，再沿右侧落下停在截断上方
    static func outline(scale s: CGFloat = 1, origin o: CGPoint = .zero) -> CGPath {
        let center = CGPoint(x: 8, y: 9.4)
        let radius: CGFloat = 5.6
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func onCircle(_ degrees: CGFloat) -> CGPoint {
            let a = degrees * .pi / 180
            return p(center.x + radius * cos(a), center.y + radius * sin(a))
        }
        let path = CGMutablePath()
        // 角度按 y 向下计：0° 为正右，90° 为正下。缺口留在 5°~55° 之间
        path.move(to: onCircle(55))
        path.addArc(center: p(center.x, center.y), radius: radius * s,
                    startAngle: 55 * .pi / 180, endAngle: 218 * .pi / 180, clockwise: false)
        path.addLine(to: p(3.4, 1.6))   // 左耳尖
        path.addLine(to: p(6.6, 4.1))   // 左耳内侧落到头顶
        path.addLine(to: p(9.4, 4.1))   // 头顶
        path.addLine(to: p(12.6, 1.6))  // 右耳尖
        path.addLine(to: onCircle(322)) // 右耳外侧落回圆
        path.addArc(center: p(center.x, center.y), radius: radius * s,
                    startAngle: 322 * .pi / 180, endAngle: 365 * .pi / 180, clockwise: false)
        return path
    }

    /// 两点眼睛的圆心
    static func eyes(scale s: CGFloat = 1, origin o: CGPoint = .zero) -> [CGPoint] {
        [CGPoint(x: o.x + 6.0 * s, y: o.y + 9.0 * s), CGPoint(x: o.x + 10.0 * s, y: o.y + 9.0 * s)]
    }

    /// 线宽（设计格单位）
    static let lineWidth: CGFloat = 1.5
    static let eyeRadius: CGFloat = 0.85

    /// 在 y 向下的上下文里画猫；颜色由调用方先设置好
    static func draw(in context: CGContext, scale: CGFloat, origin: CGPoint) {
        context.saveGState()
        context.setLineWidth(lineWidth * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(outline(scale: scale, origin: origin))
        context.strokePath()
        for eye in eyes(scale: scale, origin: origin) {
            let r = eyeRadius * scale
            context.fillEllipse(in: CGRect(x: eye.x - r, y: eye.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }
}
