import Testing
import CoreGraphics
@testable import HyperMac

struct SwipeTrackerTests {
    /// 3 ngón cùng dịch một khoảng (dx, dy) so với vị trí gốc.
    func three(_ dx: CGFloat, _ dy: CGFloat = 0) -> [AnyHashable: CGPoint] {
        [1: CGPoint(x: 0.3 + dx, y: 0.5 + dy), 2: CGPoint(x: 0.4 + dx, y: 0.5 + dy), 3: CGPoint(x: 0.5 + dx, y: 0.5 + dy)]
    }

    @Test func swipeRightOpensSelectsAndReleases() {
        var t = SwipeTracker()
        #expect(t.feed(three(0)).isEmpty)
        #expect(t.feed(three(0.03)).isEmpty)                         // under threshold
        #expect(t.feed(three(0.07)) == [.open(reverse: false)])
        #expect(t.feed(three(0.15)) == [.next])                      // +0.08 → one step
        #expect(t.feed(three(0.00)) == [.previous, .previous])       // -0.15 → two steps back
        #expect(t.feed([1: .zero, 2: .zero]) == [.release])          // lift a finger
        #expect(t.feed([:]).isEmpty)                                 // nothing left to release
    }

    @Test func swipeLeftOpensReversed() {
        var t = SwipeTracker()
        _ = t.feed(three(0))
        #expect(t.feed(three(-0.08)) == [.open(reverse: true)])
    }

    @Test func verticalSwipeAndOtherFingerCountsAreIgnored() {
        var t = SwipeTracker()
        _ = t.feed(three(0))
        #expect(t.feed(three(0, 0.1)).isEmpty)        // vertical → ignored for this gesture
        #expect(t.feed(three(0.2, 0.1)).isEmpty)
        #expect(t.feed([:]).isEmpty)                  // never opened → no release
        var two = SwipeTracker()
        _ = two.feed([1: .zero, 2: .zero])
        #expect(two.feed([1: CGPoint(x: 0.3, y: 0), 2: CGPoint(x: 0.3, y: 0)]).isEmpty)
    }
}
