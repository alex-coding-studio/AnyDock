import CoreGraphics
import PockyFoundation

enum TrayMetrics {
    static let popoverWidth: CGFloat = 480
    static let popoverHeight: CGFloat = 640
    static let popoverSize = CGSize(width: popoverWidth, height: popoverHeight)
    static let multiColumnCount = 4
    static let singleColumnCount = 1
    static let floatingControlsClearance: CGFloat = 64
    static let contentTopInset = PKYLayout.Inset.page(.wide)
        + PKYLayout.Size.button(.compact) + PKYLayout.Gap.group(.standard)
    static let scopeFade = PKYLayout.Space.s32
    static let badgeHeight: CGFloat = 16
    static let updateDotOffset = PKYIcon.Size.control.pointSize / 2
    static let fileThumbnailSide: CGFloat = 240
    static let polaroidPreviewRadius: CGFloat = 4
    static let cardBodyFontSize: CGFloat = 12
    static let denseBadgeFontSize: CGFloat = 9
    static let fileLinesFontSize: CGFloat = 9
}
