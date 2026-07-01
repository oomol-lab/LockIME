// MakeTrayIcon.swift - renders LockIME's menu-bar (tray) template glyphs:
// a centered rounded input panel with a keyhole symbol. Both states share the
// same panel geometry; locked uses a filled keyhole, while unlocked uses an
// outlined keyhole. Drawn vector-crisp with CoreGraphics at 1x/2x as solid
// black + alpha for template rendering.
//
//   swift scripts/icon-tools/MakeTrayIcon.swift <outDir>
//   -> tray-locked.png/tray-locked@2x.png/tray-unlocked.png/tray-unlocked@2x.png
//
// If <outDir> is an asset catalog containing TrayLocked.imageset and
// TrayUnlocked.imageset, files are written directly into those imagesets.

import AppKit
import CoreGraphics

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let outRoot = URL(fileURLWithPath: outputPath, isDirectory: true)
let pointSize: CGFloat = 18

struct TrayState {
    let locked: Bool
    let baseName: String
    let imagesetName: String
}

let states = [
    TrayState(locked: true, baseName: "tray-locked", imagesetName: "TrayLocked.imageset"),
    TrayState(locked: false, baseName: "tray-unlocked", imagesetName: "TrayUnlocked.imageset"),
]

func outputURL(for state: TrayState, scale: CGFloat) -> URL {
    let imageset = outRoot.appendingPathComponent(state.imagesetName, isDirectory: true)
    let targetDir = FileManager.default.fileExists(atPath: imageset.path) ? imageset : outRoot
    let suffix = scale == 2 ? "@2x" : ""
    return targetDir.appendingPathComponent("\(state.baseName)\(suffix).png")
}

func keyholePath(inset: CGFloat = 0) -> CGPath {
    let path = CGMutablePath()
    let centerX: CGFloat = 9
    let circleRadius = max(0.55, 1.7 - inset)
    let circleCenterY: CGFloat = 10.55
    let stemTopY: CGFloat = 9.0 - inset * 0.3
    let stemBottomY: CGFloat = 6.85 + inset * 0.85
    let stemTopHalfWidth = max(0.35, 0.82 - inset * 0.28)
    let stemBottomHalfWidth = max(0.5, 1.28 - inset * 0.6)

    path.addEllipse(in: CGRect(
        x: centerX - circleRadius,
        y: circleCenterY - circleRadius,
        width: circleRadius * 2,
        height: circleRadius * 2
    ))

    path.move(to: CGPoint(x: centerX - stemTopHalfWidth, y: stemTopY))
    path.addLine(to: CGPoint(x: centerX + stemTopHalfWidth, y: stemTopY))
    path.addLine(to: CGPoint(x: centerX + stemBottomHalfWidth, y: stemBottomY + 0.25))
    path.addQuadCurve(
        to: CGPoint(x: centerX + stemBottomHalfWidth - 0.35, y: stemBottomY),
        control: CGPoint(x: centerX + stemBottomHalfWidth, y: stemBottomY)
    )
    path.addLine(to: CGPoint(x: centerX - stemBottomHalfWidth + 0.35, y: stemBottomY))
    path.addQuadCurve(
        to: CGPoint(x: centerX - stemBottomHalfWidth, y: stemBottomY + 0.25),
        control: CGPoint(x: centerX - stemBottomHalfWidth, y: stemBottomY)
    )
    path.closeSubpath()
    return path
}

func drawPanel(in ctx: CGContext) {
    ctx.setLineWidth(1.75)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    let left: CGFloat = 2.2
    let right: CGFloat = 15.8
    let bottom: CGFloat = 2.95
    let top: CGFloat = 15.0
    let radius: CGFloat = 2.45

    let panel = CGMutablePath()
    panel.move(to: CGPoint(x: 5.45, y: bottom))
    panel.addLine(to: CGPoint(x: left + radius, y: bottom))
    panel.addQuadCurve(to: CGPoint(x: left, y: bottom + radius), control: CGPoint(x: left, y: bottom))
    panel.addLine(to: CGPoint(x: left, y: top - radius))
    panel.addQuadCurve(to: CGPoint(x: left + radius, y: top), control: CGPoint(x: left, y: top))
    panel.addLine(to: CGPoint(x: right - radius, y: top))
    panel.addQuadCurve(to: CGPoint(x: right, y: top - radius), control: CGPoint(x: right, y: top))
    panel.addLine(to: CGPoint(x: right, y: bottom + radius))
    panel.addQuadCurve(to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
    panel.addLine(to: CGPoint(x: 12.55, y: bottom))
    ctx.addPath(panel)
    ctx.strokePath()

    let keyCorner: CGFloat = 0.48
    for key in [
        CGRect(x: 4.45, y: 5.15, width: 2.05, height: 0.95),
        CGRect(x: 11.5, y: 5.15, width: 2.05, height: 0.95),
        CGRect(x: 8.35, y: 2.85, width: 1.3, height: 2.6),
    ] {
        ctx.addPath(CGPath(roundedRect: key, cornerWidth: keyCorner, cornerHeight: keyCorner, transform: nil))
        ctx.fillPath()
    }
}

func draw(locked: Bool, scale: CGFloat) -> CGImage? {
    let px = Int(pointSize * scale)
    guard let ctx = CGContext(
        data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    ctx.setStrokeColor(.black)
    ctx.setFillColor(.black)

    drawPanel(in: ctx)
    ctx.addPath(keyholePath())
    ctx.fillPath()
    if locked {
        return ctx.makeImage()
    }

    ctx.setBlendMode(.clear)
    ctx.addPath(keyholePath(inset: 0.55))
    ctx.fillPath()
    ctx.setBlendMode(.normal)

    return ctx.makeImage()
}

for state in states {
    for scale in [CGFloat(1), 2] {
        guard let img = draw(locked: state.locked, scale: scale) else { continue }
        let rep = NSBitmapImageRep(cgImage: img)
        guard let png = rep.representation(using: .png, properties: [:]) else { continue }
        let url = outputURL(for: state, scale: scale)
        do {
            try png.write(to: url)
            print("wrote \(url.path)")
        } catch {
            FileHandle.standardError.write(Data("failed to write \(url.path): \(error)\n".utf8))
            exit(1)
        }
    }
}
