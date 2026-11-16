import CoreGraphics

enum Space {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
}

enum TrayMetrics {
    static let margin = Space.s24
    static let framePadding = Space.s8
    static let scopeBarHeight: CGFloat = 36
    static let scopeBarInset = Space.s4
    static let scopeFade = Space.s32
    static let badgeHeight: CGFloat = 16
    static let dot: CGFloat = 6
    static let cornerRadius: CGFloat = 6
    static let innerCornerRadius: CGFloat = 4
}
