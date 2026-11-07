import CoreGraphics

/// Where the notch is on a screen (screen coordinates, bottom-left origin).
public struct NotchMetrics: Equatable, Sendable {
    public var rect: CGRect
    public var hasHardwareNotch: Bool

    public init(rect: CGRect, hasHardwareNotch: Bool) {
        self.rect = rect
        self.hasHardwareNotch = hasHardwareNotch
    }
}

public enum ResizeEdge: Sendable {
    case left, right, bottom
}

/// Size and placement rules for the panel that drops out of the notch.
public enum PanelGeometry {
    public static let fakeNotchWidth: CGFloat = 200
    public static let defaultHeight: CGFloat = 520
    public static let minWidth: CGFloat = 440
    public static let minHeight: CGFloat = 280
    public static let maxWidthFraction: CGFloat = 0.9
    public static let maxHeightFraction: CGFloat = 0.85

    public static func notchMetrics(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeft: CGRect?,
        auxiliaryRight: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchMetrics {
        if safeAreaTop > 0, let left = auxiliaryLeft, let right = auxiliaryRight, right.minX > left.maxX {
            let rect = CGRect(
                x: left.maxX,
                y: screenFrame.maxY - safeAreaTop,
                width: right.minX - left.maxX,
                height: safeAreaTop
            )
            return NotchMetrics(rect: rect, hasHardwareNotch: true)
        }
        let rect = CGRect(
            x: screenFrame.midX - fakeNotchWidth / 2,
            y: screenFrame.maxY - menuBarHeight,
            width: fakeNotchWidth,
            height: menuBarHeight
        )
        return NotchMetrics(rect: rect, hasHardwareNotch: false)
    }

    /// Three notch-widths wide: one to the left of the notch, the notch itself, one to the right.
    public static func defaultSize(notchWidth: CGFloat) -> CGSize {
        CGSize(width: notchWidth * 3, height: defaultHeight)
    }

    public static func clamp(_ size: CGSize, screenSize: CGSize) -> CGSize {
        let maxW = max(minWidth, screenSize.width * maxWidthFraction)
        let maxH = max(minHeight, screenSize.height * maxHeightFraction)
        return CGSize(
            width: min(max(size.width, minWidth), maxW),
            height: min(max(size.height, minHeight), maxH)
        )
    }

    /// Centered under the notch, hanging from the top of the screen, kept inside the screen horizontally.
    public static func panelFrame(size: CGSize, notch: CGRect, screenFrame: CGRect) -> CGRect {
        var x = notch.midX - size.width / 2
        x = min(max(x, screenFrame.minX), screenFrame.maxX - size.width)
        return CGRect(x: x, y: screenFrame.maxY - size.height, width: size.width, height: size.height)
    }

    /// Side edges resize symmetrically around the notch; the bottom edge changes height.
    /// `delta` is in AppKit coordinates (y up), so dragging the bottom edge down is a negative dy.
    public static func resized(_ size: CGSize, edge: ResizeEdge, delta: CGSize, screenSize: CGSize) -> CGSize {
        var out = size
        switch edge {
        case .left: out.width -= 2 * delta.width
        case .right: out.width += 2 * delta.width
        case .bottom: out.height -= delta.height
        }
        return clamp(out, screenSize: screenSize)
    }
}
