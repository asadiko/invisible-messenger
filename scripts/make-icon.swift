// Draws the Invisible Messenger app icon with SwiftUI.
//
//   scripts/make-icon.sh [variant]            → Resources/AppIcon.icns (default variant: ghost)
//   build/make-icon png <variant> <out.png>   → one 1024×1024 PNG
//   build/make-icon sheet <out.png>           → all variants side by side at several sizes
//
// Variants: notch, eye, ghost, glass. Everything is drawn from shapes (no symbol fonts),
// on Apple's macOS icon grid: an 824×824 continuous-corner square centred on a 1024×1024 canvas.
import AppKit
import SwiftUI

// MARK: Palette

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

let accent = Color(hex: 0x4AA8FF)
let accentDeep = Color(hex: 0x2A62C9)
let night = Color(hex: 0x06070B)
let navy = Color(hex: 0x1B2440)

// MARK: Shapes

/// Flat top, rounded bottom corners, like the MacBook notch.
struct NotchShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
    }
}

/// A chat bubble with a small tail at the bottom left (or right when mirrored).
struct BubbleShape: Shape {
    var mirrored = false
    func path(in r: CGRect) -> Path {
        let bodyHeight = r.height * 0.82
        var p = Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: bodyHeight), cornerRadius: bodyHeight * 0.32, style: .continuous)
        let base = r.minY + bodyHeight - 1
        var tail = Path()
        tail.move(to: CGPoint(x: r.minX + r.width * 0.16, y: base))
        tail.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.05, y: r.maxY),
                          control: CGPoint(x: r.minX + r.width * 0.17, y: r.maxY - r.height * 0.07))
        tail.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.36, y: base),
                          control: CGPoint(x: r.minX + r.width * 0.25, y: r.maxY - r.height * 0.03))
        tail.closeSubpath()
        p.addPath(tail)
        if mirrored {
            return p.applying(CGAffineTransform(translationX: r.midX, y: 0).scaledBy(x: -1, y: 1).translatedBy(x: -r.midX, y: 0))
        }
        return p
    }
}

/// Almond outline of an eye.
struct EyeShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.5))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.midY), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.5))
        p.closeSubpath()
        return p
    }
}

/// An eye with a diagonal slash through it; the slash is cut out with `gap` colour.
struct EyeSlash: View {
    var color: Color
    var gap: Color
    var width: CGFloat

    var body: some View {
        let h = width * 0.56
        ZStack {
            EyeShape().stroke(color, style: StrokeStyle(lineWidth: width * 0.085, lineJoin: .round))
                .frame(width: width, height: h)
            Circle().fill(color).frame(width: h * 0.62, height: h * 0.62)
            Capsule().fill(gap).frame(width: width * 0.2, height: width * 1.22).rotationEffect(.degrees(-45))
            Capsule().fill(color).frame(width: width * 0.085, height: width * 1.12).rotationEffect(.degrees(-45))
        }
        .frame(width: width * 1.2, height: width * 1.2)
    }
}

struct TypingDots: View {
    var color: Color = .white
    var dot: CGFloat
    var body: some View {
        HStack(spacing: dot * 0.62) {
            ForEach(0..<3, id: \.self) { _ in Circle().fill(color).frame(width: dot, height: dot) }
        }
    }
}

// MARK: Icon frame (Apple macOS grid)

struct IconFrame<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 185, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, y: 12)
            .frame(width: 1024, height: 1024)
    }
}

// MARK: Variants

/// The notch glows above a message that is being typed.
struct NotchIcon: View {
    var body: some View {
        IconFrame {
            ZStack {
                LinearGradient(colors: [navy, night], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [accent.opacity(0.75), accent.opacity(0.18), .clear], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 480)
                // The glow that appears around the notch when a message arrives.
                NotchShape(radius: 60)
                    .fill(accent)
                    .frame(width: 382, height: 128)
                    .blur(radius: 22)
                    .opacity(0.85)
                    .position(x: 412, y: 64)
                NotchShape(radius: 52)
                    .fill(Color.black)
                    .frame(width: 350, height: 112)
                    .overlay(NotchShape(radius: 52).stroke(Color(hex: 0x9BD2FF).opacity(0.9), lineWidth: 4))
                    .position(x: 412, y: 56)
                BubbleShape()
                    .fill(LinearGradient(colors: [Color(hex: 0x6CC0FF), accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(BubbleShape().stroke(Color.white.opacity(0.25), lineWidth: 3))
                    .frame(width: 500, height: 380)
                    .shadow(color: accent.opacity(0.45), radius: 40, y: 10)
                    .position(x: 412, y: 520)
                TypingDots(dot: 62)
                    .position(x: 412, y: 486)
            }
        }
    }
}

/// A chat bubble with a closed eye: a conversation nobody else sees.
struct EyeIcon: View {
    var body: some View {
        IconFrame {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x5CB8FF), accentDeep], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.25), .clear], center: UnitPoint(x: 0.3, y: 0.15), startRadius: 0, endRadius: 520)
                BubbleShape()
                    .fill(Color.white)
                    .frame(width: 580, height: 470)
                    .shadow(color: Color(hex: 0x0B2A66, opacity: 0.35), radius: 30, y: 18)
                    .position(x: 412, y: 440)
                EyeSlash(color: accentDeep, gap: .white, width: 290)
                    .position(x: 412, y: 395)
            }
        }
    }
}

/// One bubble fades away behind a solid one.
struct GhostIcon: View {
    var body: some View {
        IconFrame {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x20263A), night], startPoint: .topLeading, endPoint: .bottomTrailing)
                BubbleShape()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 14, lineCap: .round, dash: [2, 34]))
                    .frame(width: 420, height: 330)
                    .mask(LinearGradient(colors: [.white, .white.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .position(x: 330, y: 300)
                BubbleShape(mirrored: true)
                    .fill(LinearGradient(colors: [Color(hex: 0x6CC0FF), accentDeep], startPoint: .top, endPoint: .bottom))
                    .overlay(BubbleShape(mirrored: true).stroke(Color.white.opacity(0.3), lineWidth: 3))
                    .frame(width: 440, height: 340)
                    .shadow(color: accent.opacity(0.4), radius: 36, y: 12)
                    .position(x: 490, y: 540)
                TypingDots(dot: 52)
                    .position(x: 490, y: 509)
            }
        }
    }
}

/// Light, frosted take: a glassy bubble over a soft gradient, closed eye inside.
struct GlassIcon: View {
    var body: some View {
        IconFrame {
            ZStack {
                LinearGradient(colors: [Color(hex: 0xEAF4FF), Color(hex: 0xB9D8FF)], startPoint: .top, endPoint: .bottom)
                Circle().fill(accent.opacity(0.55)).frame(width: 420).blur(radius: 70).position(x: 600, y: 600)
                Circle().fill(Color(hex: 0x8F7CFF, opacity: 0.35)).frame(width: 360).blur(radius: 80).position(x: 220, y: 250)
                BubbleShape()
                    .fill(.white.opacity(0.55))
                    .overlay(BubbleShape().stroke(LinearGradient(colors: [.white, .white.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 6))
                    .frame(width: 580, height: 470)
                    .shadow(color: Color(hex: 0x2A62C9, opacity: 0.25), radius: 30, y: 16)
                    .position(x: 412, y: 440)
                EyeSlash(color: accentDeep, gap: Color(hex: 0xEEF5FF), width: 290)
                    .position(x: 412, y: 395)
            }
        }
    }
}

// MARK: Rendering

@MainActor
func icon(_ name: String) -> AnyView {
    switch name {
    case "eye": AnyView(EyeIcon())
    case "ghost": AnyView(GhostIcon())
    case "glass": AnyView(GlassIcon())
    default: AnyView(NotchIcon())
    }
}

@MainActor
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat, scale: CGFloat) -> CGImage {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = scale
    renderer.isOpaque = false
    guard let image = renderer.cgImage else { fatalError("render failed") }
    return image
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png failed") }
    try! data.write(to: URL(fileURLWithPath: path))
}

@MainActor
func makeICNS(variant: String, output: String) {
    let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        for factor in [1, 2] {
            let pixels = CGFloat(base * factor)
            let name = factor == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
            writePNG(render(icon(variant), width: 1024, height: 1024, scale: pixels / 1024), to: iconset.appendingPathComponent(name).path)
        }
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", output]
    try! task.run()
    task.waitUntilExit()
    try? FileManager.default.removeItem(at: iconset)
    guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("wrote \(output) (\(variant))")
}

/// All variants, large and at real Finder/Dock sizes, on light and dark backgrounds.
struct Sheet: View {
    let variants = ["notch", "eye", "ghost", "glass"]
    let titles = ["A · Notch glow", "B · Closed eye", "C · Fading bubble", "D · Glass"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                HStack(alignment: .top, spacing: 40) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 14) {
                            icon(v).scaleEffect(300 / 1024).frame(width: 300, height: 300)
                            HStack(alignment: .bottom, spacing: 14) {
                                ForEach([128, 64, 32, 16], id: \.self) { s in
                                    icon(v).scaleEffect(CGFloat(s) / 1024).frame(width: CGFloat(s), height: CGFloat(s))
                                }
                            }
                            .frame(height: 128, alignment: .bottom)
                            Text(titles[i])
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(dark ? Color.white : Color.black)
                        }
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(dark ? Color(hex: 0x1E1E20) : Color(hex: 0xF2F2F5))
            }
        }
    }
}

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    switch args.count > 1 ? args[1] : "" {
    case "icns" where args.count == 4:
        makeICNS(variant: args[2], output: args[3])
    case "png" where args.count >= 4:
        let size = args.count > 4 ? CGFloat(Double(args[4]) ?? 1024) : 1024
        writePNG(render(icon(args[2]), width: 1024, height: 1024, scale: size / 1024), to: args[3])
    case "sheet" where args.count == 3:
        writePNG(render(Sheet(), width: 1680, height: 1100, scale: 1), to: args[2])
    default:
        print("usage: make-icon icns <variant> <out.icns> | png <variant> <out.png> [size] | sheet <out.png>")
        exit(64)
    }
}
