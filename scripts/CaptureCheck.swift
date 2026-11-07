// Checks that Invisible Messenger's windows are absent from screen captures.
//
// Usage: capture-check <pid of the running app>
//
// It captures the display with ScreenCaptureKit (the API screen-sharing and recording apps use) twice:
// once normally and once with the app excluded. Where a window is truly hidden, both captures show the
// same pixels. A red control window owned by this checker (not hidden) must show up, or the check is invalid.
import AppKit
import ScreenCaptureKit

guard CommandLine.arguments.count == 2, let appPID = pid_t(CommandLine.arguments[1]) else {
    print("usage: capture-check <pid>")
    exit(64)
}

let panelService = "com.apple.appkit.xpc.openAndSavePanelService"
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let control = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 220, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
control.backgroundColor = .red
control.level = .statusBar
control.orderFrontRegardless()

struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = data
    }
}

/// Mean absolute RGB difference inside `rect` (display points, top-left origin).
func meanDifference(_ a: Bitmap, _ b: Bitmap, in rect: CGRect, scale: CGFloat) -> Double {
    let x0 = max(0, Int(rect.minX * scale)), x1 = min(a.width, Int(rect.maxX * scale))
    let y0 = max(0, Int(rect.minY * scale)), y1 = min(a.height, Int(rect.maxY * scale))
    guard x1 > x0, y1 > y0 else { return 0 }
    var total = 0, count = 0
    var y = y0
    while y < y1 {
        var x = x0
        while x < x1 {
            let i = (y * a.width + x) * 4
            total += abs(Int(a.pixels[i]) - Int(b.pixels[i]))
                + abs(Int(a.pixels[i + 1]) - Int(b.pixels[i + 1]))
                + abs(Int(a.pixels[i + 2]) - Int(b.pixels[i + 2]))
            count += 3
            x += 2
        }
        y += 2
    }
    return Double(total) / Double(max(count, 1))
}

func capture(_ filter: SCContentFilter, display: SCDisplay) async throws -> Bitmap {
    let config = SCStreamConfiguration()
    config.width = display.width * 2
    config.height = display.height * 2
    config.showsCursor = false
    return Bitmap(try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config))
}

Task {
    do {
        try await Task.sleep(for: .seconds(1))
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.applications.first(where: { $0.processID == appPID }),
              let me = content.applications.first(where: { $0.processID == getpid() }) else {
            print("FAIL: app with pid \(appPID) not found")
            exit(1)
        }
        let services = content.applications.filter { $0.bundleIdentifier == panelService }
        let watched = content.windows.filter { window in
            guard window.isOnScreen, window.frame.width > 4, window.frame.height > 4 else { return false }
            return window.owningApplication?.processID == appPID || window.owningApplication?.bundleIdentifier == panelService
        }
        var failures = 0
        var byDisplay: [CGDirectDisplayID: [SCWindow]] = [:]
        for window in watched {
            let display = content.displays.first { $0.frame.intersects(window.frame) } ?? content.displays[0]
            byDisplay[display.displayID, default: []].append(window)
        }
        let mainDisplay = content.displays.first { $0.frame.contains(CGPoint(x: 41, y: 41)) } ?? content.displays[0]
        if byDisplay[mainDisplay.displayID] == nil { byDisplay[mainDisplay.displayID] = [] }

        for (displayID, windows) in byDisplay {
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { continue }
            let scale = CGFloat(display.width * 2) / display.frame.width
            let full = try await capture(SCContentFilter(display: display, excludingWindows: []), display: display)
            let withoutApp = try await capture(
                SCContentFilter(display: display, excludingApplications: [target] + services, exceptingWindows: []), display: display
            )
            if displayID == mainDisplay.displayID {
                let withoutMe = try await capture(SCContentFilter(display: display, excludingApplications: [me], exceptingWindows: []), display: display)
                let controlRect = CGRect(x: 40 - display.frame.minX, y: display.frame.height - 200, width: 220, height: 160)
                let sanity = meanDifference(full, withoutMe, in: controlRect, scale: scale)
                guard sanity > 20 else {
                    print(String(format: "INVALID: the visible control window did not show up in the capture (difference %.1f). Is Screen Recording allowed for this terminal?", sanity))
                    exit(2)
                }
                print(String(format: "OK    control window (not hidden) is visible in captures (difference %.1f)", sanity))
            }
            for window in windows {
                let rect = window.frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                let difference = meanDifference(full, withoutApp, in: rect, scale: scale)
                let owner = window.owningApplication?.bundleIdentifier == panelService ? "open panel" : "app window"
                let label = String(format: "%@ %.0f×%.0f at (%.0f, %.0f)", owner, window.frame.width, window.frame.height, window.frame.minX, window.frame.minY)
                if difference < 2.0 {
                    print(String(format: "PASS  %@ hidden (difference %.2f)", label, difference))
                } else {
                    print(String(format: "FAIL  %@ VISIBLE in capture (difference %.2f)", label, difference))
                    failures += 1
                }
            }
        }
        print(failures == 0 ? "All \(watched.count) windows are hidden from screen capture." : "\(failures) window(s) visible.")
        exit(failures == 0 ? 0 : 1)
    } catch {
        print("ERROR: \(error.localizedDescription)")
        exit(3)
    }
}

app.run()
