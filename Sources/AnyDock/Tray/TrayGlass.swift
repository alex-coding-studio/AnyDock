import AppKit
import SnapKit

@MainActor
enum TrayGlass {
    @available(macOS 26, *)
    private final class LayeredSurface: NSView {
        let glass: NSGlassEffectView

        init(glass: NSGlassEffectView) {
            self.glass = glass
            super.init(frame: .zero)
        }

        required init?(coder _: NSCoder) {
            nil
        }
    }

    @available(macOS 26, *)
    private final class BackgroundGlass: NSGlassEffectView {
        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }
    }

    static func surface(
        _ content: NSView,
        cornerRadius: CGFloat,
        contentAboveGlass: Bool = false
    ) -> NSView {
        let surface: NSView
        if #available(macOS 26, *) {
            let glass = contentAboveGlass ? BackgroundGlass() : NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            if contentAboveGlass {
                let container = LayeredSurface(glass: glass)
                container.addSubview(glass)
                container.addSubview(content)
                glass.snp.makeConstraints { $0.edges.equalToSuperview() }
                surface = container
            } else {
                glass.contentView = content
                surface = glass
            }
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
        if #available(macOS 26, *), let layered = surface as? LayeredSurface {
            layered.glass.cornerRadius = radius
        } else if #available(macOS 26, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = radius
        } else {
            surface.layer?.cornerRadius = radius
        }
    }
}
