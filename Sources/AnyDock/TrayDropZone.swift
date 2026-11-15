import AppKit

@MainActor
final class TrayDropZone: NSView {
  var canAccept: ((AnyObject?) -> Bool)?
  var performDrop: (() -> Bool)?
  let label = NSTextField(labelWithString: "")
  let suffix = NSTextField(labelWithString: "")
  private(set) var isArmed = false
  private(set) var isTargeted = false {
    didSet { refresh() }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    label.lineBreakMode = .byTruncatingMiddle
    label.setContentCompressionResistancePriority(.dragThatCannotResizeWindow, for: .horizontal)
    suffix.setContentCompressionResistancePriority(.required, for: .horizontal)
    let row = NSStackView(views: [label, suffix])
    row.spacing = 0
    row.translatesAutoresizingMaskIntoConstraints = false
    addSubview(row)
    NSLayoutConstraint.activate([
      row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s12),
      row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s12),
      row.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    registerForDraggedTypes([.fileURL, .URL, .string])
  }

  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  func show(_ text: String, suffix detail: String = "", armed: Bool) {
    label.stringValue = text
    suffix.stringValue = detail
    suffix.isHidden = detail.isEmpty
    isArmed = armed
    if !armed { isTargeted = false }
    refresh()
  }

  private func refresh() {
    let font = NSFont.monospacedDigitSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: isTargeted ? .semibold : .medium)
    for field in [label, suffix] {
      field.textColor = isTargeted ? .white : isArmed ? .systemRed : .labelColor
      field.font = font
    }
    needsDisplay = true
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = bounds.height / 2
  }

  override func updateLayer() {
    layer?.backgroundColor = isTargeted ? NSColor.systemRed.cgColor : NSColor.clear.cgColor
  }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard isArmed, canAccept?(sender.draggingSource as AnyObject?) == true else { return [] }
    isTargeted = true
    return .delete
  }

  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    isTargeted ? .delete : []
  }

  override func draggingExited(_ sender: (any NSDraggingInfo)?) { isTargeted = false }

  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { isTargeted }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    defer { isTargeted = false }
    guard isTargeted, canAccept?(sender.draggingSource as AnyObject?) == true else { return false }
    return performDrop?() ?? false
  }

  override func draggingEnded(_ sender: any NSDraggingInfo) { isTargeted = false }
}
