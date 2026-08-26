import CoreGraphics

public enum ExpandedFrameSnapEdge {
    case left
    case right
}

/// 计算折叠便签恢复为完整窗口时的目标位置。
/// 左右吸附分别保持对应屏幕边缘不动。
public enum ExpandedFrameGeometry {
    /// 判断完整窗口当前是否贴近可见区域的左／右边缘。
    /// 折叠时重新检测，而不是依赖展开前已经清除的旧吸附状态。
    public static func snappedEdge(
        for frame: CGRect,
        visibleFrame: CGRect,
        threshold: CGFloat = 16
    ) -> ExpandedFrameSnapEdge? {
        let leftDistance = abs(frame.minX - visibleFrame.minX)
        let rightDistance = abs(visibleFrame.maxX - frame.maxX)
        let nearLeft = leftDistance <= threshold
        let nearRight = rightDistance <= threshold

        if nearLeft && nearRight {
            return leftDistance <= rightDistance ? .left : .right
        }
        if nearLeft { return .left }
        if nearRight { return .right }
        return nil
    }

    /// 计算缩成标题条后的 frame。吸附状态存在时直接对齐对应屏幕边缘，
    /// 避免先按左上角缩小、再要求用户手动拖回边缘。
    public static func collapsedTargetFrame(
        currentFrame: CGRect,
        collapsedWidth: CGFloat,
        barHeight: CGFloat,
        snappedEdge: ExpandedFrameSnapEdge?,
        visibleFrame: CGRect
    ) -> CGRect {
        let preferredX: CGFloat
        switch snappedEdge {
        case .left:
            preferredX = visibleFrame.minX
        case .right:
            preferredX = visibleFrame.maxX - collapsedWidth
        case nil:
            preferredX = currentFrame.minX
        }
        return CGRect(
            x: preferredX,
            y: currentFrame.maxY - barHeight,
            width: collapsedWidth,
            height: barHeight)
    }

    public static func targetFrame(
        collapsedFrame: CGRect,
        savedExpandedFrame: CGRect,
        snappedEdge: ExpandedFrameSnapEdge?,
        visibleFrame: CGRect
    ) -> CGRect {
        let preferredX: CGFloat
        switch snappedEdge {
        case .left:
            preferredX = visibleFrame.minX
        case .right:
            preferredX = visibleFrame.maxX - savedExpandedFrame.width
        case nil:
            preferredX = collapsedFrame.minX
        }

        return CGRect(
            x: preferredX,
            y: collapsedFrame.maxY - savedExpandedFrame.height,
            width: savedExpandedFrame.width,
            height: savedExpandedFrame.height)
    }
}
