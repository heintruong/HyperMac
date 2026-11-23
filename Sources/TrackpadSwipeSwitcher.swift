// SPDX-License-Identifier: GPL-3.0-only
import AppKit

// MARK: - Swipe Tracker (logic thuần, test được)

/// Theo dõi 3 ngón trên trackpad: vuốt ngang để mở trình chuyển cửa sổ, vuốt tiếp để chọn,
/// nhấc tay (số ngón khác 3) để chuyển sang cửa sổ đang chọn.
struct SwipeTracker {
    enum Action: Equatable { case open(reverse: Bool), next, previous, release }

    // ponytail: ngưỡng cố định theo toạ độ chuẩn hoá trackpad (0…1); thêm cài đặt độ nhạy nếu cần.
    static let openThreshold: CGFloat = 0.06
    static let stepThreshold: CGFloat = 0.07

    private var last: [AnyHashable: CGPoint]?
    private var accX: CGFloat = 0
    private var accY: CGFloat = 0
    private var opened = false
    private var ignored = false // cử chỉ này là vuốt dọc → bỏ qua tới khi nhấc tay

    /// `touches`: identity của ngón → vị trí chuẩn hoá, chỉ các ngón đang chạm.
    mutating func feed(_ touches: [AnyHashable: CGPoint]) -> [Action] {
        guard touches.count == 3 else {
            let wasOpened = opened
            self = SwipeTracker()
            return wasOpened ? [.release] : []
        }
        defer { last = touches }
        guard let last, !ignored else { return [] }
        let common = touches.keys.filter { last[$0] != nil }
        guard !common.isEmpty else { return [] }
        let n = CGFloat(common.count)
        accX += common.reduce(0) { $0 + touches[$1]!.x - last[$1]!.x } / n
        accY += common.reduce(0) { $0 + touches[$1]!.y - last[$1]!.y } / n

        if !opened {
            if abs(accY) >= Self.openThreshold && abs(accY) > abs(accX) { ignored = true; return [] }
            guard abs(accX) >= Self.openThreshold else { return [] }
            opened = true
            let reverse = accX < 0
            accX = 0
            return [.open(reverse: reverse)]
        }
        var out: [Action] = []
        while accX >= Self.stepThreshold { out.append(.next); accX -= Self.stepThreshold }
        while accX <= -Self.stepThreshold { out.append(.previous); accX += Self.stepThreshold }
        return out
    }
}

// MARK: - Event Tap (chỉ nghe, không chặn sự kiện)

private let kGestureEventType: UInt32 = 29 // NSEvent.EventType.gesture

private func trackpadTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { TrackpadSwipeSwitcher.shared.reenableTap() }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == kGestureEventType, let ns = NSEvent(cgEvent: event) else {
        return Unmanaged.passUnretained(event)
    }
    var touches: [AnyHashable: CGPoint] = [:]
    for t in ns.allTouches() where NSTouch.Phase.touching.contains(t.phase) && !t.isResting {
        if let id = t.identity as? NSObject { touches[AnyHashable(id)] = t.normalizedPosition }
    }
    // Run loop source nằm trên main run loop nên callback chạy trên main thread.
    MainActor.assumeIsolated { TrackpadSwipeSwitcher.shared.handle(touches) }
    return Unmanaged.passUnretained(event)
}

// MARK: - Manager

@MainActor
final class TrackpadSwipeSwitcher: ObservableObject {
    static let shared = TrackpadSwipeSwitcher()
    static let defaultsKey = "alttab_gesture_enabled"

    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.defaultsKey)
            isEnabled ? start() : stop()
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var tracker = SwipeTracker()

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        if isEnabled { start() }
    }

    func start() {
        guard tap == nil, isEnabled else { return }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(UInt64(1) << UInt64(kGestureEventType)),
            callback: trackpadTapCallback, userInfo: nil
        ) else {
            // Chưa có quyền Accessibility → thử lại sau.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
            return
        }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        appLog("👆 TrackpadSwipeSwitcher: active")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        self.tap = nil
        source = nil
        tracker = SwipeTracker()
    }

    func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    func handle(_ touches: [AnyHashable: CGPoint]) {
        let wm = WindowManager.shared
        for action in tracker.feed(touches) {
            switch action {
            case .open(let reverse): wm.handleShortcut(isShift: reverse)
            case .next: if wm.isVisible { wm.selectNext() }
            case .previous: if wm.isVisible { wm.selectPrevious() }
            case .release: if wm.isVisible { wm.handleModifierReleased() }
            }
        }
    }
}
