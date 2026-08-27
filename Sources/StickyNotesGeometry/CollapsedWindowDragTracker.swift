/// 区分“拖动折叠条后松手”和“点击折叠条上的按钮”。
/// 两者都会产生 mouseUp，但只有前者应该触发边缘归位。
public struct CollapsedWindowDragTracker {
    private var movedWhilePressed = false

    public init() {}

    public mutating func mouseDown() {
        movedWhilePressed = false
    }

    public mutating func recordMove(isCollapsed: Bool, isLeftMousePressed: Bool) {
        if isCollapsed && isLeftMousePressed {
            movedWhilePressed = true
        }
    }

    public mutating func mouseUpShouldSettle() -> Bool {
        let shouldSettle = movedWhilePressed
        movedWhilePressed = false
        return shouldSettle
    }
}
