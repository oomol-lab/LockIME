// ComposeAppIcon.swift — compose a macOS-grid-correct app icon from full-bleed
// square art.
//
//   swift scripts/icon-tools/ComposeAppIcon.swift <in.png> <out.png> [noshadow]
//
// The source master stays full-bleed (blue art edge-to-edge, no gutter), but a
// shipped macOS app icon must *not* fill its canvas: every native icon insets a
// rounded "body" onto a transparent margin and casts a soft system shadow, and
// that shared grid is exactly what makes every app look the same size in
// Launchpad/Dock/Finder. A full-bleed PNG renders ~24% larger than its
// neighbours on older Launchpad/Finder surfaces that draw the resource verbatim
// instead of applying the system mask.
//
// Numbers are matched empirically against /System/Applications/*.app icons,
// which render an 842px opaque box (824px squircle body + ~9px shadow bleed) in
// a 1024px canvas — i.e. an 824/1024 body centred with a 100px margin.

import AppKit
import CoreGraphics

private let bodyRatio: CGFloat = 824.0 / 1024.0  // squircle body side ÷ canvas
private let cornerRatio: CGFloat = 185.4 / 824.0 // corner radius ÷ body side

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

private func loadCGImage(from path: String) -> CGImage {
    guard let data = FileManager.default.contents(atPath: path),
          let rep = NSBitmapImageRep(data: data),
          let image = rep.cgImage else {
        fail("cannot read \(path)")
    }
    return image
}

private func composeIcon(inputPath: String, outputPath: String, shadow: Bool) {
    let source = loadCGImage(from: inputPath)
    let side = source.width
    guard source.height == side else {
        fail("input must be square: \(inputPath)")
    }
    let canvas = CGFloat(side)
    let body = (canvas * bodyRatio).rounded()
    let inset = ((canvas - body) / 2).rounded()
    let radius = body * cornerRatio
    let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)

    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    guard let context = CGContext(
        data: &pixels,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("cannot create bitmap context")
    }

    context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    if shadow {
        // Bottom-left origin: a negative y offset casts the shadow downward.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -(canvas * 0.011)),
            blur: canvas * 0.016,
            color: NSColor(white: 0, alpha: 0.30).cgColor
        )
        context.addPath(bodyPath)
        context.setFillColor(NSColor(white: 0, alpha: 1).cgColor)
        context.fillPath()
        context.restoreGState()
    }

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    context.draw(source, in: bodyRect)
    context.restoreGState()

    guard let composed = context.makeImage() else {
        fail("cannot render icon: \(inputPath)")
    }
    let rep = NSBitmapImageRep(cgImage: composed)
    rep.size = NSSize(width: side, height: side)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        fail("cannot encode png: \(outputPath)")
    }

    let outputURL = URL(fileURLWithPath: outputPath)
    try? FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    do {
        try png.write(to: outputURL, options: .atomic)
    } catch {
        fail("cannot write \(outputPath): \(error)")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else {
    fail("usage: ComposeAppIcon.swift <input.png> <output.png> [noshadow]")
}
composeIcon(inputPath: args[0], outputPath: args[1], shadow: !(args.count >= 3 && args[2] == "noshadow"))
