import AppKit
import SnapKit

@MainActor
enum TrayGlass {
    static func surface(_ content: NSView, cornerRadius: CGFloat) -> NSView {
        let surface: NSView
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = cornerRadius
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            surface = effect
        }
        content.snp.makeConstraints { $0.edges.equalTo(surface) }
        return surface
    }

    static func setCornerRadius(_ radius: CGFloat, of surface: NSView) {
        if #available(macOS 26, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            surface.layer?.cornerRadius = radius
        }
    }
}
