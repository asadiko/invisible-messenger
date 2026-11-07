import CoreGraphics
import Testing
@testable import MessengerCore

@Suite struct PanelGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
    let notch = CGRect(x: 790, y: 1131, width: 220, height: 38)

    @Test func notchFromAuxiliaryAreas() {
        let m = PanelGeometry.notchMetrics(
            screenFrame: screen, safeAreaTop: 38,
            auxiliaryLeft: CGRect(x: 0, y: 1131, width: 790, height: 38),
            auxiliaryRight: CGRect(x: 1010, y: 1131, width: 790, height: 38),
            menuBarHeight: 38
        )
        #expect(m == NotchMetrics(rect: notch, hasHardwareNotch: true))
    }

    @Test func fakeNotchWithoutHardware() {
        let m = PanelGeometry.notchMetrics(
            screenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), safeAreaTop: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: 24
        )
        #expect(m == NotchMetrics(rect: CGRect(x: 860, y: 1056, width: 200, height: 24), hasHardwareNotch: false))
    }

    @Test func fakeNotchOnSecondaryScreenUsesItsOrigin() {
        let m = PanelGeometry.notchMetrics(
            screenFrame: CGRect(x: 1800, y: 0, width: 1000, height: 800), safeAreaTop: 0,
            auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: 24
        )
        #expect(m.rect == CGRect(x: 2200, y: 776, width: 200, height: 24))
    }

    @Test func defaultIsThreeNotches() {
        #expect(PanelGeometry.defaultSize(notchWidth: 220) == CGSize(width: 660, height: 520))
    }

    @Test func clampLimits() {
        let size = CGSize(width: 1800, height: 1169)
        #expect(PanelGeometry.clamp(CGSize(width: 100, height: 100), screenSize: size) == CGSize(width: 440, height: 280))
        let big = PanelGeometry.clamp(CGSize(width: 5000, height: 5000), screenSize: size)
        #expect(big.width == 1620)
        #expect(abs(big.height - 993.65) < 0.001)
    }

    @Test func frameCenteredOnNotch() {
        let f = PanelGeometry.panelFrame(size: CGSize(width: 660, height: 520), notch: notch, screenFrame: screen)
        #expect(f == CGRect(x: 570, y: 649, width: 660, height: 520))
    }

    @Test func frameStaysOnScreen() {
        let offCenter = CGRect(x: 1700, y: 1131, width: 100, height: 38)
        let f = PanelGeometry.panelFrame(size: CGSize(width: 660, height: 520), notch: offCenter, screenFrame: screen)
        #expect(f.maxX == 1800)
    }

    @Test func resizeIsSymmetric() {
        let size = CGSize(width: 660, height: 520), screenSize = CGSize(width: 1800, height: 1169)
        #expect(PanelGeometry.resized(size, edge: .right, delta: CGSize(width: 50, height: 0), screenSize: screenSize) == CGSize(width: 760, height: 520))
        #expect(PanelGeometry.resized(size, edge: .left, delta: CGSize(width: -50, height: 0), screenSize: screenSize) == CGSize(width: 760, height: 520))
        #expect(PanelGeometry.resized(size, edge: .bottom, delta: CGSize(width: 0, height: -100), screenSize: screenSize) == CGSize(width: 660, height: 620))
        #expect(PanelGeometry.resized(size, edge: .right, delta: CGSize(width: -1000, height: 0), screenSize: screenSize).width == 440)
    }
}
