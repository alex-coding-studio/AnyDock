import AnyDockCore
import AppKit

struct TrayEntry {
  let item: ReceivedItem
  var thumbnail: NSImage?
  let text: String?
  let characterCount: Int
  let link: URL?
  let size: Int64?

  var url: URL { item.url }

  var fullText: String {
    (try? String(contentsOf: item.url, encoding: .utf8)) ?? text ?? ""
  }
  var kind: ReceivedKind { item.kind }

  var displayName: String {
    let name = url.lastPathComponent
    let pattern = #"^(AnyDock|SnapDock)-\d+-[0-9A-Fa-f-]{36}-"#
    guard let range = name.range(of: pattern, options: .regularExpression) else { return name }
    return String(name[range.upperBound...])
  }

  var badge: String {
    let suffix = url.pathExtension.uppercased()
    return suffix.isEmpty ? L10n.text("File") : suffix
  }

  var summary: String {
    switch kind {
    case .image: L10n.text("Image")
    case .text: text.map { String($0.prefix(80)) } ?? L10n.text("Text")
    case .link: link?.absoluteString ?? L10n.text("Link")
    case .file: displayName
    }
  }

  init(item: ReceivedItem) {
    self.item = item
    var thumbnail: NSImage?
    var text: String?
    var characterCount = 0
    var link: URL?
    var size: Int64?
    switch item.kind {
    case .image:
      thumbnail = item.thumbnail.flatMap(NSImage.init(data:))
    case .text:
      let full = (try? String(contentsOf: item.url, encoding: .utf8)) ?? ""
      characterCount = full.count
      text = String(full.prefix(1000))
    case .link:
      if let data = try? Data(contentsOf: item.url),
        let property = try? PropertyListSerialization.propertyList(from: data, format: nil),
        let address = (property as? [String: Any])?["URL"] as? String
      {
        link = URL(string: address)
      }
    case .file:
      size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
        .map(Int64.init)
      thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)
      if item.isPlainText, let handle = try? FileHandle(forReadingFrom: item.url) {
        let prefix = (try? handle.read(upToCount: 4096)) ?? Data()
        try? handle.close()
        text = String(decoding: prefix, as: UTF8.self)
      }
    }
    self.thumbnail = thumbnail
    self.text = text
    self.characterCount = characterCount
    self.link = link
    self.size = size
  }
}

@MainActor
class TrayCardItem: NSCollectionViewItem {
  var isLatestReceipt = false { didSet { updateSelection() } }
  let card = ThumbnailView()
  private let time = NSTextField(labelWithString: "")

  override func loadView() {
    time.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
    time.textColor = .white
    time.translatesAutoresizingMaskIntoConstraints = false
    time.setContentCompressionResistancePriority(.required, for: .vertical)
    time.setContentHuggingPriority(.required, for: .vertical)
    let capsule = NSView()
    capsule.wantsLayer = true
    capsule.layer?.cornerRadius = 7
    capsule.translatesAutoresizingMaskIntoConstraints = false
    capsule.addSubview(time)
    let check = NSImageView(
      image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        ?? NSImage())
    check.symbolConfiguration = NSImage.SymbolConfiguration(
      paletteColors: [.white, .controlAccentColor])
    check.translatesAutoresizingMaskIntoConstraints = false
    buildContent(in: card)
    card.addSubview(capsule)
    card.addSubview(check)
    NSLayoutConstraint.activate([
      capsule.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 4),
      capsule.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -4),
      time.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 3),
      time.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -3),
      time.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 1),
      time.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -1),
      check.topAnchor.constraint(equalTo: card.topAnchor, constant: 4),
      check.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -4),
      check.widthAnchor.constraint(equalToConstant: 16),
      check.heightAnchor.constraint(equalToConstant: 16),
    ])
    card.timeCapsule = capsule
    card.checkmark = check
    view = card
    textField = time
    updateSelection()
  }

  func buildContent(in container: NSView) {}

  func configure(_ entry: TrayEntry, singleColumn: Bool) {}

  func pin(_ subview: NSView, in container: NSView, inset: CGFloat) {
    subview.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(subview)
    NSLayoutConstraint.activate([
      subview.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: inset),
      subview.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -inset),
    ])
  }

  func label(size: CGFloat, weight: NSFont.Weight = .regular, lines: Int) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: "")
    field.font = .systemFont(ofSize: size, weight: weight)
    field.maximumNumberOfLines = lines
    field.lineBreakMode = lines == 1 ? .byTruncatingMiddle : .byWordWrapping
    field.cell?.truncatesLastVisibleLine = true
    field.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    return field
  }

  override var isSelected: Bool { didSet { updateSelection() } }
  override var highlightState: NSCollectionViewItem.HighlightState { didSet { updateSelection() } }

  override var draggingImageComponents: [NSDraggingImageComponent] {
    guard let snapshot = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
      return super.draggingImageComponents
    }
    view.cacheDisplay(in: view.bounds, to: snapshot)
    let image = NSImage(size: view.bounds.size)
    image.addRepresentation(snapshot)
    let component = NSDraggingImageComponent(key: .icon)
    component.contents = image
    component.frame = view.bounds
    return [component]
  }

  private func updateSelection() {
    guard isViewLoaded else { return }
    card.selected =
      highlightState == .forSelection || (isSelected && highlightState != .forDeselection)
    card.latestReceipt = isLatestReceipt
  }
}

@MainActor
final class ImageCardItem: TrayCardItem {
  static let identifier = NSUserInterfaceItemIdentifier("ImageCard")
  private let preview = TopAlignedImageView()

  override func buildContent(in container: NSView) {
    preview.wantsLayer = true
    preview.layer?.cornerRadius = 6
    preview.layer?.masksToBounds = true
    pin(preview, in: container, inset: 0)
    NSLayoutConstraint.activate([
      preview.topAnchor.constraint(equalTo: container.topAnchor),
      preview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    imageView = preview
  }

  override func configure(_ entry: TrayEntry, singleColumn: Bool) {
    card.filled = false
    preview.image = entry.thumbnail
  }
}

@MainActor
final class TextCardItem: TrayCardItem {
  static let identifier = NSUserInterfaceItemIdentifier("TextCard")
  lazy var body = label(size: 12, lines: 0)
  lazy var count = label(size: 10, lines: 1)

  override func buildContent(in container: NSView) {
    pin(body, in: container, inset: Space.s8)
    count.textColor = .secondaryLabelColor
    count.alignment = .right
    count.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(count)
    NSLayoutConstraint.activate([
      body.topAnchor.constraint(equalTo: container.topAnchor, constant: Space.s8),
      body.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Space.s24),
      count.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Space.s8),
      count.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Space.s4),
      count.leadingAnchor.constraint(greaterThanOrEqualTo: container.centerXAnchor),
    ])
  }

  override func configure(_ entry: TrayEntry, singleColumn: Bool) {
    card.filled = true
    body.stringValue = entry.text ?? ""
    count.stringValue = L10n.text("character_count", entry.characterCount)
    count.isHidden = !singleColumn
  }
}

@MainActor
final class LinkCardItem: TrayCardItem {
  static let identifier = NSUserInterfaceItemIdentifier("LinkCard")
  private lazy var domain = label(size: 10, weight: .semibold, lines: 1)
  private lazy var headline = label(size: 12, weight: .medium, lines: 0)

  override func buildContent(in container: NSView) {
    domain.textColor = .controlAccentColor
    for field in [domain, headline] { pin(field, in: container, inset: Space.s8) }
    NSLayoutConstraint.activate([
      domain.topAnchor.constraint(equalTo: container.topAnchor, constant: Space.s8),
      headline.topAnchor.constraint(equalTo: domain.bottomAnchor, constant: Space.s4),
      headline.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Space.s24),
    ])
  }

  override func configure(_ entry: TrayEntry, singleColumn: Bool) {
    card.filled = true
    let link = entry.link
    domain.stringValue = link?.host(percentEncoded: false) ?? ""
    headline.stringValue = link?.absoluteString ?? entry.displayName
  }
}

@MainActor
final class FileCardItem: TrayCardItem {
  static let identifier = NSUserInterfaceItemIdentifier("FileCard")
  private let preview = NSImageView()
  private lazy var lines = label(size: 10, lines: 0)
  private lazy var name = label(size: 11, weight: .medium, lines: 1)
  private lazy var size = label(size: 10, lines: 1)
  private let badge = NSTextField(labelWithString: "")
  private let badgeCapsule = NSView()

  override func buildContent(in container: NSView) {
    preview.imageScaling = .scaleProportionallyUpOrDown
    lines.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
    lines.textColor = .secondaryLabelColor
    size.textColor = .secondaryLabelColor
    for view in [preview, lines, name, size] { pin(view, in: container, inset: Space.s8) }
    badge.font = .systemFont(ofSize: 8, weight: .bold)
    badge.textColor = .white
    badge.translatesAutoresizingMaskIntoConstraints = false
    badgeCapsule.wantsLayer = true
    badgeCapsule.layer?.cornerRadius = 4
    badgeCapsule.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
    badgeCapsule.translatesAutoresizingMaskIntoConstraints = false
    badgeCapsule.addSubview(badge)
    container.addSubview(badgeCapsule)
    NSLayoutConstraint.activate([
      preview.topAnchor.constraint(equalTo: container.topAnchor, constant: Space.s8),
      preview.bottomAnchor.constraint(equalTo: name.topAnchor, constant: -Space.s8),
      lines.topAnchor.constraint(equalTo: preview.topAnchor),
      lines.bottomAnchor.constraint(equalTo: preview.bottomAnchor),
      name.bottomAnchor.constraint(equalTo: size.topAnchor, constant: -Space.s4),
      size.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Space.s24),
      badgeCapsule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Space.s4),
      badgeCapsule.topAnchor.constraint(equalTo: container.topAnchor, constant: Space.s4),
      badge.leadingAnchor.constraint(equalTo: badgeCapsule.leadingAnchor, constant: Space.s4),
      badge.trailingAnchor.constraint(equalTo: badgeCapsule.trailingAnchor, constant: -Space.s4),
      badge.topAnchor.constraint(equalTo: badgeCapsule.topAnchor, constant: 1),
      badge.bottomAnchor.constraint(equalTo: badgeCapsule.bottomAnchor, constant: -1),
    ])
  }

  override func configure(_ entry: TrayEntry, singleColumn: Bool) {
    card.filled = true
    let plainText = entry.item.isPlainText
    preview.isHidden = plainText
    lines.isHidden = !plainText
    preview.image = plainText ? nil : entry.thumbnail
    lines.stringValue = plainText ? entry.text ?? "" : ""
    name.stringValue = entry.displayName
    size.stringValue =
      entry.size.map {
        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
      } ?? ""
    badge.stringValue = entry.badge
  }

  func showThumbnail(_ image: NSImage) {
    guard !preview.isHidden else { return }
    preview.image = image
  }
}

@MainActor
final class TopAlignedImageView: NSImageView {
  override func draw(_ dirtyRect: NSRect) {
    guard let image, image.size.width > 0, image.size.height > 0 else { return }
    let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
    let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
    let rect = NSRect(
      x: (bounds.width - size.width) / 2, y: isFlipped ? 0 : bounds.height - size.height,
      width: size.width, height: size.height)
    NSBezierPath(rect: bounds).addClip()
    image.draw(
      in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  }
}

@MainActor
final class ThumbnailView: NSView {
  var timeCapsule: NSView?
  var checkmark: NSImageView?
  var selected = false {
    didSet {
      setAccessibilitySelected(selected)
      updateColors()
    }
  }
  var latestReceipt = false { didSet { updateColors() } }
  var filled = false { didSet { updateColors() } }

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.cornerRadius = 6
    updateColors()
  }

  required init?(coder: NSCoder) { nil }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = filled ? NSColor.quaternaryLabelColor.cgColor : nil
      layer?.borderWidth = selected ? 2 : (latestReceipt ? 1 : 0)
      layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(selected ? 1 : 0.6).cgColor
      layer?.shadowColor = NSColor.controlAccentColor.cgColor
      layer?.shadowOpacity = latestReceipt ? 0.45 : 0
      layer?.shadowRadius = 5
      layer?.shadowOffset = .zero
      timeCapsule?.layer?.backgroundColor =
        (latestReceipt
        ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.6)).cgColor
      checkmark?.isHidden = !selected
    }
  }
}
