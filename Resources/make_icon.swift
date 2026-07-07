// 生成 app 图标: 一张带折角的黄色便签
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// macOS 图标标准留白 (约 10%)
let inset: CGFloat = size * 0.10
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let corner: CGFloat = size * 0.18

// 阴影
ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.015), blur: size * 0.04,
              color: NSColor.black.withAlphaComponent(0.35).cgColor)

// 便签主体: 柔和的黄色渐变
let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
path.addClip()
let gradient = NSGradient(
    starting: NSColor(red: 1.00, green: 0.93, blue: 0.55, alpha: 1),
    ending:   NSColor(red: 0.99, green: 0.85, blue: 0.35, alpha: 1))!
gradient.draw(in: rect, angle: -90)

// 顶部深色条
let barRect = CGRect(x: rect.minX, y: rect.maxY - size * 0.14,
                     width: rect.width, height: size * 0.14)
NSColor(red: 0.96, green: 0.76, blue: 0.22, alpha: 1).setFill()
barRect.fill()

// 正文横线 (模拟文字)
NSColor(red: 0.45, green: 0.35, blue: 0.10, alpha: 0.55).setFill()
let lineHeight = size * 0.035
let lineGap = size * 0.10
let lineX = rect.minX + size * 0.12
var lineY = rect.maxY - size * 0.30
let lineWidths: [CGFloat] = [0.55, 0.42, 0.50, 0.30]
for w in lineWidths {
    let lineRect = CGRect(x: lineX, y: lineY, width: rect.width * w, height: lineHeight)
    NSBezierPath(roundedRect: lineRect, xRadius: lineHeight / 2, yRadius: lineHeight / 2).fill()
    lineY -= lineGap
}

// 右下折角
let fold: CGFloat = size * 0.20
let foldPath = NSBezierPath()
foldPath.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
foldPath.line(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
foldPath.line(to: CGPoint(x: rect.maxX, y: rect.minY))
foldPath.close()
NSColor(red: 0.85, green: 0.68, blue: 0.20, alpha: 1).setFill()
foldPath.fill()

image.unlockFocus()

// 保存 PNG
let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("saved: \(out)")
