import AppKit

struct ScreenGeometry {
    struct NotchInfo {
        let minX: CGFloat
        let maxX: CGFloat
        let centerX: CGFloat
        let bottomY: CGFloat
        let width: CGFloat
    }

    private static func defaultTargetScreen() -> NSScreen? {
        if let main = NSScreen.main,
           main.auxiliaryTopLeftArea != nil,
           main.auxiliaryTopRightArea != nil {
            return main
        }
        if let notched = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }) {
            return notched
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func notchInfo(for screen: NSScreen? = nil) -> NotchInfo? {
        let target = screen ?? defaultTargetScreen()
        guard let target else { return nil }
        guard let left = target.auxiliaryTopLeftArea,
              let right = target.auxiliaryTopRightArea else {
            return nil
        }

        // Auxiliary areas can be local or global; choose whichever maps best to this screen's bounds.
        let globalLeft = left
        let globalRight = right
        let localLeft = left.offsetBy(dx: target.frame.minX, dy: target.frame.minY)
        let localRight = right.offsetBy(dx: target.frame.minX, dy: target.frame.minY)

        func score(_ rect: NSRect, in frame: NSRect) -> Int {
            var total = 0
            if rect.minX >= frame.minX - 2, rect.maxX <= frame.maxX + 2 { total += 1 }
            if rect.minY >= frame.minY - 2, rect.maxY <= frame.maxY + 2 { total += 1 }
            return total
        }

        let globalScore = score(globalLeft, in: target.frame) + score(globalRight, in: target.frame)
        let localScore = score(localLeft, in: target.frame) + score(localRight, in: target.frame)
        let resolvedLeft = localScore > globalScore ? localLeft : globalLeft
        let resolvedRight = localScore > globalScore ? localRight : globalRight

        let notchMinX = resolvedLeft.maxX
        let notchMaxX = resolvedRight.minX
        guard notchMaxX > notchMinX else { return nil }

        let centerX = (notchMinX + notchMaxX) / 2.0
        let auxBottomY = min(resolvedLeft.minY, resolvedRight.minY)
        let safeAreaBottomY = target.frame.maxY - target.safeAreaInsets.top
        // Prefer auxiliary top areas for notch alignment.
        // safeAreaInsets can sit lower depending on menu bar/safe-zone policy, which creates a visible gap.
        let bottomY = max(auxBottomY, safeAreaBottomY)
        let width = notchMaxX - notchMinX

        return NotchInfo(
            minX: notchMinX,
            maxX: notchMaxX,
            centerX: centerX,
            bottomY: bottomY,
            width: width
        )
    }

    static func notchCutoutWidth(for screen: NSScreen? = nil) -> CGFloat {
        guard let notch = notchInfo(for: screen) else { return 170 }
        return max(120, min(260, notch.width))
    }

    static func pulseFrame(for screen: NSScreen? = nil) -> NSRect {
        let target = screen ?? defaultTargetScreen()
        var width = Constants.Layout.pulseWidth
        let height = Constants.Layout.pulseHeight

        if let notch = notchInfo(for: target) {
            width = max(Constants.Layout.pulseWidth, min(460, notch.width + 300))
            return NSRect(
                x: notch.centerX - width / 2,
                y: notch.bottomY - height + Constants.Layout.pulseTopOverlap,
                width: width,
                height: height
            )
        }

        // Fallback: top-center of screen
        let screenFrame = target?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - 40,
            width: width,
            height: height
        )
    }

    /// Compact notch-aligned capsule used as the visual "origin" for pulse morph animations.
    static func pulseCompactFrame(for screen: NSScreen? = nil) -> NSRect {
        let target = screen ?? defaultTargetScreen()
        let expanded = pulseFrame(for: target)
        let compactHeight: CGFloat = 32

        if let notch = notchInfo(for: target) {
            let compactWidth = notchCutoutWidth(for: target)
            return NSRect(
                x: notch.centerX - compactWidth / 2,
                y: notch.bottomY - compactHeight + Constants.Layout.pulseTopOverlap,
                width: compactWidth,
                height: compactHeight
            )
        }

        return NSRect(
            x: expanded.midX - 90,
            y: expanded.midY - compactHeight / 2,
            width: 180,
            height: compactHeight
        )
    }

    static func expandedCardFrame(for screen: NSScreen? = nil, height: CGFloat = Constants.Layout.cardHeight) -> NSRect {
        let target = screen ?? defaultTargetScreen()
        var width = Constants.Layout.cardWidth

        if let notch = notchInfo(for: target) {
            let topMorph = Constants.Layout.cardTopMorphExtension
            let effectiveHeight = height + topMorph
            width = max(Constants.Layout.cardWidth, min(420, notch.width + 160))
            return NSRect(
                x: notch.centerX - width / 2,
                y: notch.bottomY
                    - Constants.Layout.notchCutoutBottomInset
                    - effectiveHeight
                    + Constants.Layout.cardVerticalLift
                    + topMorph,
                width: width,
                height: effectiveHeight
            )
        }

        let screenFrame = target?.frame ?? NSScreen.main?.frame ?? .zero
        return NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height - 40,
            width: width,
            height: height
        )
    }
}
