import QuartzCore

struct TrayElevation {
    static let none = TrayElevation(opacity: 0, radius: 0, offset: .zero)
    static let card = TrayElevation(
        opacity: 0.14,
        radius: Space.s4,
        offset: CGSize(width: 0, height: -1)
    )
    static let cardDark = TrayElevation(
        opacity: 0.35,
        radius: Space.s4,
        offset: CGSize(width: 0, height: -1)
    )
    static let scopeIndicator = TrayElevation(opacity: 0.08, radius: 2, offset: .zero)

    let opacity: Float
    let radius: CGFloat
    let offset: CGSize
}

extension CALayer {
    func apply(_ elevation: TrayElevation) {
        shadowColor = CGColor.black
        // swiftlint:disable:next magic_shadow_param
        shadowOpacity = elevation.opacity
        // swiftlint:disable:next magic_shadow_param
        shadowRadius = elevation.radius
        // swiftlint:disable:next magic_shadow_param
        shadowOffset = elevation.offset
    }
}
