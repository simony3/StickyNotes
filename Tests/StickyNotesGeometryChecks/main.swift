import CoreGraphics
import Foundation
import StickyNotesGeometry

private var checks = 0

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    guard condition() else {
        FileHandle.standardError.write(Data("FAILED: \(message)\n".utf8))
        exit(1)
    }
}

let mainScreen = CGRect(x: 0, y: 0, width: 1470, height: 932)
let expanded = CGRect(x: 900, y: 250, width: 300, height: 560)

var buttonClick = CollapsedWindowDragTracker()
buttonClick.mouseDown()
expect(!buttonClick.mouseUpShouldSettle(),
       "clicking a button without moving the window must not trigger snap settling")

var collapsedDrag = CollapsedWindowDragTracker()
collapsedDrag.mouseDown()
collapsedDrag.recordMove(isCollapsed: true, isLeftMousePressed: true)
expect(collapsedDrag.mouseUpShouldSettle(),
       "dragging a collapsed window should settle its snap on mouse up")
expect(!collapsedDrag.mouseUpShouldSettle(),
       "the drag signal should be consumed by the first mouse up")

var expandedMove = CollapsedWindowDragTracker()
expandedMove.mouseDown()
expandedMove.recordMove(isCollapsed: false, isLeftMousePressed: true)
expect(!expandedMove.mouseUpShouldSettle(),
       "moving an expanded window must not arm collapsed snap settling")

expect(ExpandedFrameGeometry.snappedEdge(
    for: CGRect(x: 1170, y: 294, width: 300, height: 560),
    visibleFrame: mainScreen) == .right,
    "an expanded window touching the right edge should be detected before collapse")
expect(ExpandedFrameGeometry.snappedEdge(
    for: CGRect(x: 0, y: 294, width: 300, height: 560),
    visibleFrame: mainScreen) == .left,
    "an expanded window touching the left edge should be detected before collapse")
expect(ExpandedFrameGeometry.snappedEdge(
    for: CGRect(x: 500, y: 294, width: 300, height: 560),
    visibleFrame: mainScreen) == nil,
    "an expanded window away from both edges should not be treated as snapped")
expect(ExpandedFrameGeometry.snappedEdge(
    for: CGRect(x: 1160, y: 294, width: 300, height: 560),
    visibleFrame: mainScreen) == .right,
    "an expanded window within the snap threshold should retain the right edge")

let collapsedFromRight = ExpandedFrameGeometry.collapsedTargetFrame(
    currentFrame: CGRect(x: 1170, y: 294, width: 300, height: 560),
    collapsedWidth: 147,
    barHeight: 30,
    snappedEdge: .right,
    visibleFrame: mainScreen)
expect(collapsedFromRight == CGRect(x: 1323, y: 824, width: 147, height: 30),
       "collapsing a right-aligned expanded window should keep the right edge attached")

let leftResult = ExpandedFrameGeometry.targetFrame(
    collapsedFrame: CGRect(x: 0, y: 824, width: 180, height: 30),
    savedExpandedFrame: expanded,
    snappedEdge: .left,
    visibleFrame: mainScreen)
expect(leftResult == CGRect(x: 0, y: 294, width: 300, height: 560),
       "left snap should keep the expanded window on screen")

let rightResult = ExpandedFrameGeometry.targetFrame(
    collapsedFrame: CGRect(x: 1290, y: 824, width: 180, height: 30),
    savedExpandedFrame: expanded,
    snappedEdge: .right,
    visibleFrame: mainScreen)
expect(rightResult == CGRect(x: 1170, y: 294, width: 300, height: 560),
       "right snap should anchor the expanded window to the right edge")
expect(rightResult.maxX == mainScreen.maxX,
       "right-snapped expanded window should not exceed the visible frame")

print("StickyNotes geometry checks passed: \(checks)")
