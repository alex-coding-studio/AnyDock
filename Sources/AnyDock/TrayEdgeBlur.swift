import AppKit

@MainActor
final class EdgeBlurView: NSVisualEffectView {
  private let fromTop: Bool
  private let fade: CGFloat
  private var maskedSize = NSSize.zero

  init(fromTop: Bool, fade: CGFloat) {
    self.fromTop = fromTop
    self.fade = fade
    super.init(frame: .zero)
    material = .popover
    blendingMode = .withinWindow
    state = .active
  }

  required init?(coder: NSCoder) { nil }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    guard bounds.size != maskedSize, bounds.height > 0 else { return }
    maskedSize = bounds.size
    let size = bounds.size
    let solid = max(0, min(1, fade / size.height))
    let fromTop = fromTop
    maskImage = NSImage(size: size, flipped: false) { rect in
      let gradient = NSGradient(colorsAndLocations: (.clear, 0), (.black, solid), (.black, 1))
      gradient?.draw(in: rect, angle: fromTop ? 90 : 270)
      return true
    }
  }
}
