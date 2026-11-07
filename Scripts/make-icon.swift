import AppKit
import CoreGraphics

@main
enum IconGenerator {
    static func main() throws {
        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let body = CGRect(x: 100, y: 100, width: 824, height: 824)
        context.setFillColor(CGColor(srgbRed: 0.08, green: 0.11, blue: 0.20, alpha: 1))
        context.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
        context.fillPath()
        context.translateBy(x: 0, y: 1024)
        context.scaleBy(x: 1, y: -1)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setFillColor(NSColor.white.cgColor)
        CatGlyph.draw(in: context, scale: 40, origin: CGPoint(x: 192, y: 172))
        let representation = NSBitmapImageRep(cgImage: context.makeImage()!)
        try representation.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
        print("wrote \(output)")
    }
}
