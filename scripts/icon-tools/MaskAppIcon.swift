// MaskAppIcon.swift - apply LockIME's legacy-safe app icon alpha mask.
//
//   swift scripts/icon-tools/MaskAppIcon.swift <input.png> <output.png> [...]
//
// The source artwork can stay full-bleed, but the shipped macOS 14+ app icon
// must carry its own rounded-rect alpha. Older Launchpad/Finder surfaces may
// draw the icon resource verbatim instead of applying the newer system mask.

import AppKit
import CoreGraphics

private let cornerRadiusRatio: CGFloat = 0.2237

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

private func writeMaskedIcon(inputPath: String, outputPath: String) {
    let source = loadCGImage(from: inputPath)
    let width = source.width
    let height = source.height
    guard width == height else {
        fail("input must be square: \(inputPath)")
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fail("cannot create bitmap context")
    }

    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let radius = CGFloat(width) * cornerRadiusRatio
    context.clear(rect)
    context.setShouldAntialias(true)
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    context.draw(source, in: rect)

    guard let masked = context.makeImage() else {
        fail("cannot render masked icon: \(inputPath)")
    }
    let rep = NSBitmapImageRep(cgImage: masked)
    rep.size = NSSize(width: width, height: height)
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
guard args.count >= 2, args.count.isMultiple(of: 2) else {
    fail("usage: MaskAppIcon.swift <input.png> <output.png> [<input.png> <output.png> ...]")
}

var index = 0
while index < args.count {
    writeMaskedIcon(inputPath: args[index], outputPath: args[index + 1])
    index += 2
}
