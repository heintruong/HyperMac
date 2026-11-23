import Testing
import CoreGraphics
@testable import HyperMac

@MainActor
struct CascadeTests {
    let visible = CGRect(x: 0, y: 30, width: 2000, height: 1200)

    @Test func singleWindowFillsScreen() {
        #expect(WindowSnapManager.cascadeRects(count: 1, visible: visible, anchor: .topLeft) == [visible])
        #expect(WindowSnapManager.cascadeRects(count: 0, visible: visible, anchor: .topLeft).isEmpty)
    }

    @Test func topLeftFrontWindowAnchoredAndOthersPeek() {
        let rects = WindowSnapManager.cascadeRects(count: 3, visible: visible, anchor: .topLeft)
        #expect(rects.count == 3)
        #expect(rects[0] == CGRect(x: 0, y: 30, width: 1800, height: 1080))  // front: top-left, 90%
        #expect(rects[2].maxX == visible.maxX && rects[2].maxY == visible.maxY) // back: bottom-right
        #expect(rects[1] == CGRect(x: 100, y: 90, width: 1800, height: 1080)) // evenly spaced
        for r in rects { #expect(visible.contains(r)) }
    }

    @Test func bottomRightIsMirrored() {
        let rects = WindowSnapManager.cascadeRects(count: 3, visible: visible, anchor: .bottomRight)
        #expect(rects[0].maxX == visible.maxX && rects[0].maxY == visible.maxY) // front: bottom-right
        #expect(rects[2].origin == visible.origin)                               // back: top-left
    }

    @Test func portraitWindowsGoToARightColumn() {
        let phone = CGRect(x: 0, y: 0, width: 400, height: 800)   // portrait (emulator)
        let wide = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let rects = WindowSnapManager.cascadeLayout(frames: [wide, phone, wide], visible: visible, anchor: .topLeft)
        #expect(rects[1] == CGRect(x: 1600, y: 30, width: 400, height: 800))     // same size, right edge, top
        #expect(rects[0].origin == visible.origin)                               // landscape cascade in remaining area
        #expect(rects[2].maxX == 1600 && rects[2].maxY == visible.maxY)
        // Only portrait windows → plain cascade.
        #expect(WindowSnapManager.cascadeLayout(frames: [phone, phone], visible: visible, anchor: .topLeft)
                == WindowSnapManager.cascadeRects(count: 2, visible: visible, anchor: .topLeft))
        // Several portrait windows sit side by side, sizes untouched.
        let col = WindowSnapManager.cascadeLayout(frames: [wide, phone, phone], visible: visible, anchor: .topLeft)
        #expect(col[1] == CGRect(x: 1200, y: 30, width: 400, height: 800) && col[2].minX == 1600)
    }

    @Test func cascadeShortcutsHaveNoDefaultConflicts() {
        let config = ShortcutConfiguration()
        #expect(config.match(33, flags: [.maskControl, .maskAlternate])?.action == .cascadeTopLeft)
        #expect(config.match(30, flags: [.maskControl, .maskAlternate])?.action == .cascadeBottomRight)
        for action in ShortcutAction.allCases {
            for (i, b) in action.defaults.enumerated() {
                #expect(config.conflict(for: b, action: action, replacing: i) == nil)
            }
        }
    }
}
