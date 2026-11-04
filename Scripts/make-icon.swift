// 生成 ClashBar 应用图标（1024×1024 PNG），再由 make-icon.sh 转成 AppIcon.icns。
// 图形含义：一条线路从底部出发，分成两条——亮色的主线（Main）与琥珀色的备用线（Backup）。
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// macOS 图标网格：824 的主体，四周留 100 的边距，圆角约 185
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// 投影
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(squircle)
ctx.setFillColor(color(0x101a33))
ctx.fillPath()
ctx.restoreGState()

// 背景渐变：深靛蓝 → 夜蓝
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let background = CGGradient(colorsSpace: space, colors: [color(0x2f3f86), color(0x141d3d)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 200, y: 924), end: CGPoint(x: 824, y: 100), options: [])
// 顶部柔光
let glow = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.16), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 900), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 900), endRadius: 560, options: [])
// 细网格线，暗示「网络」
ctx.setStrokeColor(color(0xffffff, 0.05))
ctx.setLineWidth(3)
for x in stride(from: 100 as CGFloat, through: 924, by: 103) {
    ctx.move(to: CGPoint(x: x, y: 100)); ctx.addLine(to: CGPoint(x: x, y: 924))
}
for y in stride(from: 100 as CGFloat, through: 924, by: 103) {
    ctx.move(to: CGPoint(x: 100, y: y)); ctx.addLine(to: CGPoint(x: 924, y: y))
}
ctx.strokePath()
ctx.restoreGState()

// 线路
let base = CGPoint(x: 512, y: 270)
let fork = CGPoint(x: 512, y: 470)
let mainEnd = CGPoint(x: 330, y: 745)
let backupEnd = CGPoint(x: 694, y: 745)

func branch(to end: CGPoint) -> CGPath {
    let path = CGMutablePath()
    path.move(to: fork)
    path.addCurve(to: end, control1: CGPoint(x: fork.x, y: 610), control2: CGPoint(x: end.x, y: 590))
    return path
}

func stroke(_ path: CGPath, _ stroke: CGColor, width: CGFloat, glow glowColor: CGColor? = nil) {
    ctx.saveGState()
    if let glowColor { ctx.setShadow(offset: .zero, blur: 40, color: glowColor) }
    ctx.addPath(path)
    ctx.setStrokeColor(stroke)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

func dot(_ center: CGPoint, radius: CGFloat, fill: CGColor, ring: CGColor? = nil, glow glowColor: CGColor? = nil) {
    ctx.saveGState()
    if let glowColor { ctx.setShadow(offset: .zero, blur: 48, color: glowColor) }
    ctx.setFillColor(fill)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    ctx.restoreGState()
    if let ring {
        ctx.setStrokeColor(ring)
        ctx.setLineWidth(14)
        let r = radius + 22
        ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
    }
}

// 备用线：琥珀色、稍细
stroke(branch(to: backupEnd), color(0xffb547, 0.9), width: 54, glow: color(0xffa02e, 0.45))
// 主线 + 主干：亮白偏青
let trunk = CGMutablePath()
trunk.move(to: base)
trunk.addLine(to: fork)
trunk.addPath(branch(to: mainEnd))
stroke(trunk, color(0xf2f7ff), width: 66, glow: color(0x6fb6ff, 0.75))

dot(backupEnd, radius: 50, fill: color(0xffc061))
dot(mainEnd, radius: 58, fill: color(0xffffff), ring: color(0x8cc8ff, 0.55), glow: color(0x6fb6ff, 0.9))
dot(base, radius: 56, fill: color(0xf2f7ff), glow: color(0x6fb6ff, 0.6))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
