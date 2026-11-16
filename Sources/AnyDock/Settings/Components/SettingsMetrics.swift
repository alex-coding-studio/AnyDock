import CoreGraphics
import PockyFoundation

enum SettingsMetrics {
    static let windowContentWidth: CGFloat = 840
    static let windowContentHeight: CGFloat = 600
    static let windowContentSize = CGSize(width: windowContentWidth, height: windowContentHeight)
    static let sidebarWidth: CGFloat = 220
    static let sidebarAppIconSide: CGFloat = 40
    static let aboutAppIconSide: CGFloat = 128
    static let aboutIconGlowRadius: CGFloat = 26
    static let appearancePreviewHeight: CGFloat = 78
    static let appearancePaneWidthFraction: CGFloat = 0.58
    static let appearancePaneHeight: CGFloat = 40
    static let appearancePaneCornerRadius: CGFloat = 6
    static let appearanceRingOutset = 2 * PKYShape.Stroke.strong
    static let heroIllustrationPointSize: CGFloat = 46
    static let heroCheckmarkPointSize: CGFloat = 18
    static let folderIconSide: CGFloat = 44
    static let manualLabelWidth: CGFloat = 96
    static let portFieldWidth: CGFloat = 72
    static let keyCapMinWidth: CGFloat = 22
    static let keyCapCornerRadius: CGFloat = 6
    static let statusBadgeSide: CGFloat = 36
    static let statusBadgeDotSide: CGFloat = 12
}
