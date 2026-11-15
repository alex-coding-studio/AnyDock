import AppKit

@MainActor
final class TrayDropZone: NSView {
  var canAccept: ((AnyObject?) -> Bool)?
  var performDrop: (() -> Bool)?
  let label = NSTextField(labelWithString: "")
  private(set) var isArmed = false
  private(set) var isTargeted = false {
    didSet { refresh() }
  }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
    label.alignment = .center
    label.lineBreakMode = .byTruncatingTail
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Space.s12),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Space.s12),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    registerForDraggedTypes([.fileURL, .URL, .string])
  }

  required init?(coder: NSCoder) { nil }

  override var wantsUpdateLayer: Bool { true }

  func show(_ text: String, armed: Bool) {
    label.stringValue = text
    isArmed = armed
    if !armed { isTargeted = false }
    refresh()
  }

  private func refresh() {
    label.textColor = isTargeted ? .white : isArmed ? .systemRed : .labelColor
    label.font = .monospacedDigitSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: isTargeted ? .semibold : .medium)
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
