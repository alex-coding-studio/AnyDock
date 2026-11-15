import AnyDockCore
import AppKit
import QuartzCore

@MainActor
final class TrayScopeBar: NSView {
  struct Segment: Equatable {
    let title: String
    let accessibilityLabel: String
    let filter: TrayFilter
  }

  var onSelect: ((TrayFilter) -> Void)?
  var onSelectAll: ((TrayFilter) -> Void)?
  private(set) var segments: [Segment] = []
  private(set) var selected: TrayFilter = .all
  private let scroll = NSScrollView()
  private let content = FlippedView()
  private let stack = NSStackView()
  private let indicator = ScopeIndicator()
  private let fade = CAGradientLayer()
  private var buttons: [ScopeSegmentButton] = []
  private var widthConstraint: NSLayoutConstraint?
  private var isAnimating = false

  init(surface: NSView) {
    super.init(frame: .zero)
    surface.translatesAutoresizingMaskIntoConstraints = false
    addSubview(surface)
    scroll.drawsBackground = false
    scroll.hasHorizontalScroller = false
    scroll.hasVerticalScroller = false
    scroll.verticalScrollElasticity = .none
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsetsZero
    scroll.documentView = content
    scroll.wantsLayer = true
    scroll.layer?.mask = fade
    scroll.contentView.postsBoundsChangedNotifications = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .horizontal
    stack.spacing = 0
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(indicator)
    content.addSubview(stack)
    addSubview(scroll)
    let inset = TrayMetrics.scopeBarInset
    let width = widthAnchor.constraint(equalToConstant: 0)
    width.priority = .defaultHigh
    widthConstraint = width
    NSLayoutConstraint.activate([
      heightAnchor.constraint(equalToConstant: TrayMetrics.scopeBarHeight),
      width,
      surface.leadingAnchor.constraint(equalTo: leadingAnchor),
      surface.trailingAnchor.constraint(equalTo: trailingAnchor),
      surface.topAnchor.constraint(equalTo: topAnchor),
      surface.bottomAnchor.constraint(equalTo: bottomAnchor),
      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
      scroll.topAnchor.constraint(equalTo: topAnchor, constant: inset),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
      content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
      content.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
      content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      stack.topAnchor.constraint(equalTo: content.topAnchor),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
      object: scroll.contentView)
    setAccessibilityRole(.tabGroup)
  }

  required init?(coder: NSCoder) { nil }

  var selectedButtonFrame: NSRect? {
    guard let index = segments.firstIndex(where: { $0.filter == selected }) else { return nil }
    return buttons[index].convert(buttons[index].bounds, to: self)
  }

  var indicatorFrame: NSRect { indicator.convert(indicator.bounds, to: self) }

  func update(_ next: [Segment], selected filter: TrayFilter) {
    let animate =
      next.map(\.filter) == segments.map(\.filter) && filter != selected
      && window != nil
    if next != segments {
      for button in buttons { button.removeFromSuperview() }
      buttons = next.enumerated().map { index, segment in
        let button = ScopeSegmentButton(
          title: segment.title, target: self, action: #selector(tapped))
        button.tag = index
        button.setAccessibilityLabel(segment.accessibilityLabel)
        stack.addArrangedSubview(button)
        return button
      }
      segments = next
    }
    selected = filter
    for (button, segment) in zip(buttons, segments) {
      button.isChosen = segment.filter == filter
    }
    layoutSubtreeIfNeeded()
    widthConstraint?.constant = stack.fittingSize.width + TrayMetrics.scopeBarInset * 2
    layoutSubtreeIfNeeded()
    moveIndicator(animated: animate)
    reveal(animated: animate)
    updateFade()
  }

  override func layout() {
    super.layout()
    if !isAnimating { moveIndicator(animated: false) }
    updateFade()
  }

  private func moveIndicator(animated: Bool) {
    guard let index = segments.firstIndex(where: { $0.filter == selected }),
      buttons.indices.contains(index)
    else {
      indicator.isHidden = true
      return
    }
    indicator.isHidden = false
    let target = buttons[index].frame
    guard animated, indicator.frame != .zero else {
      indicator.frame = target
      return
    }
    isAnimating = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.2
      context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      indicator.animator().frame = target
    } completionHandler: { [weak self] in
      MainActor.assumeIsolated { self?.isAnimating = false }
    }
  }

  private func reveal(animated: Bool) {
    guard let index = segments.firstIndex(where: { $0.filter == selected }),
      buttons.indices.contains(index)
    else { return }
    let target = buttons[index].frame.insetBy(dx: -TrayMetrics.scopeFade, dy: 0)
    if animated {
      NSAnimationContext.runAnimationGroup { _ in
        content.animator().scrollToVisible(target)
      }
    } else {
      content.scrollToVisible(target)
    }
  }

  @objc private func scrolled() { updateFade() }

  private func updateFade() {
    let visible = scroll.contentView.bounds
    let width = max(scroll.bounds.width, 1)
    let length = min(TrayMetrics.scopeFade / width, 0.5)
    let leading = visible.minX > 0.5
    let trailing = content.frame.width - visible.maxX > 0.5
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fade.frame = scroll.bounds
    fade.startPoint = CGPoint(x: 0, y: 0.5)
    fade.endPoint = CGPoint(x: 1, y: 0.5)
    fade.colors = [
      leading ? NSColor.clear.cgColor : NSColor.black.cgColor, NSColor.black.cgColor,
      NSColor.black.cgColor, trailing ? NSColor.clear.cgColor : NSColor.black.cgColor,
    ]
    fade.locations = [0, NSNumber(value: Double(length)), NSNumber(value: Double(1 - length)), 1]
    CATransaction.commit()
  }

  @objc private func tapped(_ sender: NSButton) {
    guard segments.indices.contains(sender.tag) else { return }
    let filter = segments[sender.tag].filter
    if let event = NSApp.currentEvent,
      event.type == .leftMouseUp || event.type == .leftMouseDown, event.clickCount >= 2
    {
      onSelectAll?(filter)
    } else {
      onSelect?(filter)
    }
  }
}

@MainActor
private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

@MainActor
private final class ScopeIndicator: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    layer?.cornerRadius = newSize.height / 2
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }

  override func updateLayer() {
    let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    layer?.backgroundColor =
      (dark ? NSColor.white.withAlphaComponent(0.18) : NSColor.white).cgColor
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = dark ? 0 : 0.08
    layer?.shadowRadius = 2
    layer?.shadowOffset = .zero
  }
}

@MainActor
private final class ScopeSegmentButton: NSButton {
  var isChosen = false { didSet { refreshTitle() } }
  private var plainTitle = ""

  convenience init(title: String, target: AnyObject, action: Selector) {
    self.init(frame: .zero)
    plainTitle = title
    self.target = target
    self.action = action
    isBordered = false
    setButtonType(.momentaryChange)
    refreshTitle()
  }

  override var intrinsicContentSize: NSSize {
    let size = super.intrinsicContentSize
    return NSSize(
      width: size.width + Space.s12 * 2,
      height: TrayMetrics.scopeBarHeight - TrayMetrics.scopeBarInset * 2)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshTitle()
  }

  private func refreshTitle() {
    attributedTitle = NSAttributedString(
      string: plainTitle,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
        .foregroundColor: isChosen ? NSColor.labelColor : NSColor.secondaryLabelColor,
      ])
    setAccessibilitySelected(isChosen)
  }
}
