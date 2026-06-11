// MakeIcon.swift — renders LockIME's app-icon master, headlessly, via SwiftUI
// ImageRenderer. No design tool required.
//
//   swift scripts/MakeIcon.swift            # writes /tmp/lockime-icon/master.png (+ preview)
//
// The master is full-bleed (opaque, edge-to-edge) so the artwork has no baked
// gutter or bevel. `make-appicon.sh` downscales it, then applies the shipped
// rounded-rect alpha mask for macOS 14/15 Launchpad compatibility. A masked
// preview.png is also emitted so the post-crop look can be judged without
// installing the app.

import AppKit
import SwiftUI

// MARK: - Brand palette

private extension Color {
    /// #2A5BE0 — top of the background gradient.
    static let lockTop = Color(red: 0.165, green: 0.357, blue: 0.878)
    /// #1840B4 — bottom of the background gradient.
    static let lockBottom = Color(red: 0.094, green: 0.251, blue: 0.706)
    /// #F5F7FF — the near-white glyph.
    static let glyph = Color(red: 0.961, green: 0.969, blue: 1.0)
}

// MARK: - The padlock glyph (drawn in a 512×560 design box, centered)

private struct Padlock: View {
    /// Stroke/silhouette color of the lock.
    var color: Color = .glyph

    // Design box 600×640. Body: 480×360, centered at (300,420). Corner 112.
    private let bodyWidth: CGFloat = 480
    private let bodyHeight: CGFloat = 360
    private let bodyCornerRadius: CGFloat = 112
    private let bodyOffsetY: CGFloat = 100   // 420 − boxCenter(320)

    private var bodyShape: some Shape {
        RoundedRectangle(cornerRadius: bodyCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            ZStack {
                // Shackle — an inverted-U arch whose straight legs tuck into the
                // body so the padlock reads as closed.
                ShacklePath()
                    .stroke(color, style: StrokeStyle(lineWidth: 80, lineCap: .round))

                // Body — a generously rounded rectangle.
                bodyShape
                    .fill(color)
                    .frame(width: bodyWidth, height: bodyHeight)
                    .offset(y: bodyOffsetY)
            }
            .compositingGroup()
            // Keyhole — punched out so the background gradient shows through. A
            // round hole + slim tapered slot: a classic keyhole that also reads,
            // subtly, as a text caret (the input-method affordance).
            .overlay(
                Keyhole()
                    .fill(.black)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()

            // A whisper of top-down light on the body for dimensionality (the OS
            // supplies the real Liquid Glass lensing on top).
            bodyShape
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.14), .clear],
                        startPoint: .top, endPoint: .center
                    )
                )
                .frame(width: bodyWidth, height: bodyHeight)
                .offset(y: bodyOffsetY)
                .blendMode(.softLight)
                .mask(bodyShape.frame(width: bodyWidth, height: bodyHeight).offset(y: bodyOffsetY))
        }
        .frame(width: 600, height: 640)
    }
}

/// The shackle arch (∩): a semicircular top on two straight legs that descend
/// into the body. Drawn in the 600×640 design box.
private struct ShacklePath: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX            // 300
        let halfWidth: CGFloat = 120
        let archTopY: CGFloat = 64
        let archRadius = halfWidth    // arch center y = 184
        let archCenterY = archTopY + archRadius
        let legBottomY: CGFloat = 300 // body top is 240 → legs tuck 60px under it

        var p = Path()
        p.move(to: CGPoint(x: cx - halfWidth, y: legBottomY))
        p.addLine(to: CGPoint(x: cx - halfWidth, y: archCenterY))
        p.addArc(
            center: CGPoint(x: cx, y: archCenterY),
            radius: archRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: cx + halfWidth, y: legBottomY))
        return p
    }
}

/// Round hole + slim tapered slot, centered in the lock body. Drawn in the
/// 600×640 design box (body center ≈ y 420).
private struct Keyhole: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX             // 300
        let holeCenterY: CGFloat = 392
        let holeRadius: CGFloat = 40
        let slotTopY = holeCenterY + holeRadius * 0.55
        let slotBottomY: CGFloat = 516
        let slotTopHalf: CGFloat = 14
        let slotBottomHalf: CGFloat = 25

        var p = Path()
        p.addEllipse(in: CGRect(
            x: cx - holeRadius, y: holeCenterY - holeRadius,
            width: holeRadius * 2, height: holeRadius * 2
        ))
        // Slim tapered slot below the hole.
        p.move(to: CGPoint(x: cx - slotTopHalf, y: slotTopY))
        p.addLine(to: CGPoint(x: cx + slotTopHalf, y: slotTopY))
        p.addLine(to: CGPoint(x: cx + slotBottomHalf, y: slotBottomY))
        p.addLine(to: CGPoint(x: cx - slotBottomHalf, y: slotBottomY))
        p.closeSubpath()
        return p
    }
}

// MARK: - The full-bleed icon

private struct IconView: View {
    var body: some View {
        ZStack {
            // Opaque, edge-to-edge background gradient — the OS masks it.
            LinearGradient(
                colors: [.lockTop, .lockBottom],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // A soft top sheen for depth (kept subtle; OS adds the glass).
            LinearGradient(
                colors: [.white.opacity(0.12), .clear],
                startPoint: .top, endPoint: .center
            )

            Padlock()
                .frame(width: 600, height: 640)
                .shadow(color: .lockBottom.opacity(0.22), radius: 16, y: 10)
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Rendering

@MainActor
func writePNG(_ view: some View, size: CGFloat, to path: String) {
    let renderer = ImageRenderer(content: view.frame(width: size, height: size))
    renderer.scale = 1
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { FileHandle.standardError.write(Data("nil cgImage\n".utf8)); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: size, height: size)
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

@MainActor
func run() {
    let dir = "/tmp/lockime-icon"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    // The source master stays full-bleed; the appiconset generator masks it.
    writePNG(IconView(), size: 1024, to: "\(dir)/master.png")

    // A masked preview to judge the post-crop Tahoe look (NOT shipped).
    let masked = IconView()
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 230, style: .continuous))
        .padding(40)
        .frame(width: 1104, height: 1104)
        .background(Color(white: 0.5))
    writePNG(masked, size: 1104, to: "\(dir)/preview.png")

    print("wrote \(dir)/master.png and \(dir)/preview.png")
}

MainActor.assumeIsolated { run() }
