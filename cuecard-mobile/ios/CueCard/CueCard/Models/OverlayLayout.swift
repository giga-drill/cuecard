import CoreGraphics

enum OverlayOrientation: String, Equatable {
    case portrait
    case landscape
}

enum OverlayLayout {
    static func orientation(for size: CGSize, previous: OverlayOrientation = .portrait) -> OverlayOrientation {
        guard size.width > 0, size.height > 0, size.width != size.height else {
            return previous
        }
        return size.width > size.height ? .landscape : .portrait
    }

    static func aspectRatio(baseLandscapeRatio: CGFloat, orientation: OverlayOrientation) -> CGFloat {
        let safeRatio = max(baseLandscapeRatio, 0.01)
        switch orientation {
        case .portrait:
            return 1 / safeRatio
        case .landscape:
            return safeRatio
        }
    }

    static func preferredContentSize(
        in screenBounds: CGRect,
        baseLandscapeRatio: CGFloat,
        orientation: OverlayOrientation
    ) -> CGSize {
        let ratio = aspectRatio(baseLandscapeRatio: baseLandscapeRatio, orientation: orientation)
        var width = screenBounds.width
        var height = width / ratio

        if height > screenBounds.height {
            height = screenBounds.height
            width = height * ratio
        }

        return CGSize(width: width, height: height)
    }
}
