import CoreGraphics
import PockyFoundation

enum SettingsMetrics {
    static let windowContentWidth: CGFloat = 960
    static let windowContentHeight: CGFloat = 680
    static let windowContentSize = CGSize(width: windowContentWidth, height: windowContentHeight)
    static let windowMinimumWidth: CGFloat = 900
    static let windowMinimumHeight: CGFloat = 600
    static let windowMinimumSize = CGSize(width: windowMinimumWidth, height: windowMinimumHeight)
    static let sidebarWidth: CGFloat = 240
    static let sidebarAppIconSide: CGFloat = 40
    static let compactLabelPointSize: CGFloat = 12
    static let emphasisTitlePointSize: CGFloat = 14
    static let aboutAppIconSide: CGFloat = 128
    static let aboutIconGlowRadius: CGFloat = 26
    static let aboutIconTopOffset: CGFloat = 56
    static let aboutNamePointSize: CGFloat = 30
    static let aboutTaglinePointSize: CGFloat = 15
    static let appearancePreviewHeight: CGFloat = 78
    static let appearancePaneWidthFraction: CGFloat = 0.58
    static let appearancePaneHeight: CGFloat = 40
    static let appearancePaneCornerRadius: CGFloat = 6
    static let appearanceRingOutset = 2 * PKYShape.Stroke.strong
    static let heroIllustrationPointSize: CGFloat = 46
    static let heroCheckmarkPointSize: CGFloat = 18
    static let folderIconSide: CGFloat = 44
    static let portFieldWidth: CGFloat = 72
    static let keyCapMinWidth: CGFloat = 22
    static let keyCapCornerRadius: CGFloat = 6
    static let statusBadgeSide: CGFloat = 36
    static let statusBadgeDotSide: CGFloat = 12
}
