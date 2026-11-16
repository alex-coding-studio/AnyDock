import CoreGraphics
import PockyFoundation

enum TrayMetrics {
    static let popoverWidth: CGFloat = 480
    static let popoverHeight: CGFloat = 640
    static let popoverSize = CGSize(width: popoverWidth, height: popoverHeight)
    static let margin = PKYLayout.Space.s24
    static let cardSpacing = PKYLayout.Space.s12
    static let multiColumnCount = 4
    static let singleColumnCount = 1
    static let floatingControlsClearance: CGFloat = 64
    static let framePadding = PKYLayout.Space.s8
    static let scopeBarHeight: CGFloat = 36
    static let scopeBarInset = PKYLayout.Space.s4
    static let contentTopInset = margin + scopeBarHeight + PKYLayout.Space.s16
    static let scopeFade = PKYLayout.Space.s32
    static let badgeHeight: CGFloat = 16
    static let dot: CGFloat = 6
    static let fileThumbnailSide: CGFloat = 240
}
