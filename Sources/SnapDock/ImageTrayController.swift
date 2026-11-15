import AppKit
import Quartz
import SnapDockCore

@MainActor
final class ImageTrayController: NSViewController, NSCollectionViewDataSource,
  NSCollectionViewDelegate, NSPopoverDelegate, @MainActor QLPreviewPanelDelegate
{
  private let collection = ImageCollectionView()
  private let layout = MasonryCollectionLayout()
  private let scroll = NSScrollView()
  private let timeFormatter = DateFormatter()
  private let selectionCount = NSTextField(labelWithString: "")
  private let trashButton = NSButton()
  private var selectionCapsule: NSView?
  private var trashSurface: NSView?
  private var emptyState: NSView?
  private var images: [ReceivedImage] = []
  private var thumbnails: [NSImage?] = []
  private var aspectRatios: [CGFloat] = []
  private var latestReceivedURL: URL?
  private(set) var columnCount: Int = {
    let saved = UserDefaults.standard.integer(forKey: "thumbnailColumns")
    return (2...5).contains(saved) ? saved : 3
  }()
  private var previewSource: ImagePreviewSource?
  private var isTrashing = false
  private var trashConfirmation: NSPopover?
  private var trashConfirmationResult: CheckedContinuation<Bool, Never>?
  private var trashConfirmationKeyMonitor: Any?
  private var trashConfirmed = false
  var holdsPresentation: Bool { previewSource != nil || isTrashing }
  var presentationHeld: ((Bool) -> Void)?
  var loadImages: (() async throws -> [ReceivedImage])?
  var recycleImages: (([URL]) async throws -> Void)?
  var openFolder: (() -> Void)?
  var openSettings: (() -> Void)?
  var didFinishDragging: (() -> Void)?

  override func loadView() {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 520))
    view = glassSurface(content, cornerRadius: 16)
    view.frame = NSRect(x: 0, y: 0, width: 450, height: 520)
    layout.columnCount = columnCount
    layout.aspectRatio = { [weak self] path in
      guard let self, aspectRatios.indices.contains(path.item) else { return 1 }
      return aspectRatios[path.item]
    }
    collection.collectionViewLayout = layout
    collection.frame = content.bounds
    collection.autoresizingMask = [.width]
    collection.isSelectable = true
    collection.allowsMultipleSelection = true
    collection.allowsEmptySelection = true
    collection.backgroundColors = [.clear]
    collection.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
    collection.dataSource = self
    collection.delegate = self
    collection.setDraggingSourceOperationMask(.copy, forLocal: false)
    collection.setDraggingSourceOperationMask(.copy, forLocal: true)
    collection.copyImages = { [weak self] in self?.copySelection() }
    collection.revealImages = { [weak self] in self?.revealSelection() }
    collection.previewImages = { [weak self] in self?.previewSelection() }
    collection.deleteImages = { [weak self] in self?.trashImages(allowAll: false) }
    collection.selectionChanged = { [weak self] in self?.updateControls() }
    scroll.documentView = collection
    scroll.hasVerticalScroller = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    scroll.autohidesScrollers = true
    scroll.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: content.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])
    configureEmptyState(in: content)
    configureControls(in: content)
    updateControls()
  }

  private func configureControls(in content: NSView) {
    let folder = glassButton(
      NSButton(), symbol: "folder", title: L10n.text("Open Folder"),
      action: #selector(folderClicked))
    let settings = glassButton(
      NSButton(), symbol: "gearshape", title: L10n.text("Settings"),
      action: #selector(settingsClicked))
    let trash = glassButton(
      trashButton, symbol: "trash", title: L10n.text("Move All to Trash…"),
      action: #selector(trashClicked))
    trashButton.contentTintColor = .systemRed
    trashSurface = trash
    selectionCount.font = .monospacedDigitSystemFont(
      ofSize: NSFont.smallSystemFontSize, weight: .medium)
    let countContent = NSStackView(views: [selectionCount])
    countContent.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
    let capsule = glassSurface(countContent, cornerRadius: 17)
    capsule.heightAnchor.constraint(equalToConstant: 34).isActive = true
    selectionCapsule = capsule
    let right = NSStackView(views: [capsule, trash, settings])
    right.spacing = 8
    right.alignment = .centerY
    for element in [folder, right] {
      element.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(element)
    }
    NSLayoutConstraint.activate([
      folder.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
      folder.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
      right.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
      right.centerYAnchor.constraint(equalTo: folder.centerYAnchor),
      right.leadingAnchor.constraint(greaterThanOrEqualTo: folder.trailingAnchor, constant: 8),
    ])
  }

  private func configureEmptyState(in content: NSView) {
    let icon = NSImageView(
      image: NSImage(systemSymbolName: "tray", accessibilityDescription: nil) ?? NSImage())
    icon.contentTintColor = .secondaryLabelColor
    let title = NSTextField(labelWithString: L10n.text("No screenshots yet"))
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let detail = NSTextField(
      wrappingLabelWithString: L10n.text(
        "Share an image on your iPhone and choose your Mac’s shortcut."))
    detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    let stack = NSStackView(views: [icon, title, detail])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 10
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 40),
      icon.heightAnchor.constraint(equalToConstant: 40),
      stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: content.centerYAnchor, constant: -24),
      stack.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -64),
    ])
    emptyState = stack
  }

  private func glassButton(_ button: NSButton, symbol: String, title: String, action: Selector)
    -> NSView
  {
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
    button.target = self
    button.action = action
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyDown
    button.toolTip = title
    button.setAccessibilityLabel(title)
    let surface = glassSurface(button, cornerRadius: 17)
    NSLayoutConstraint.activate([
      surface.widthAnchor.constraint(equalToConstant: 34),
      surface.heightAnchor.constraint(equalToConstant: 34),
    ])
    return surface
  }

  private func glassSurface(_ content: NSView, cornerRadius: CGFloat) -> NSView {
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
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
      content.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
      content.topAnchor.constraint(equalTo: surface.topAnchor),
      content.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
    ])
    return surface
  }

  func replaceImages(_ next: [ReceivedImage]) {
    loadViewIfNeeded()
    let selected = Set(selectedImages.map(\.url))
    images = next
    thumbnails = next.map { NSImage(data: $0.thumbnail) }
    aspectRatios = thumbnails.map { image in
      guard let size = image?.size, size.width > 0, size.height > 0 else { return 1 }
      return size.height / size.width
    }
    layout.invalidateLayout()
    collection.reloadData()
    collection.selectionIndexPaths = Set(
      images.enumerated().compactMap {
        selected.contains($0.element.url) ? IndexPath(item: $0.offset, section: 0) : nil
      })
    updateControls()
  }

  func append(_ image: ReceivedImage) {
    latestReceivedURL = image.url
    replaceImages(([image] + images.filter { $0.url != image.url }).prefix(120).map { $0 })
  }

  func setColumnCount(_ count: Int) {
    guard (2...5).contains(count), count != columnCount else { return }
    columnCount = count
    UserDefaults.standard.set(count, forKey: "thumbnailColumns")
    guard isViewLoaded else { return }
    layout.columnCount = count
  }

  func focusImages() { view.window?.makeFirstResponder(collection) }

  func clearSelection() {
    collection.selectionIndexPaths = []
    updateControls()
  }

  func scrollToLatestImage() {
    guard !images.isEmpty else { return }
    collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
  }

  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int
  { images.count }

  func collectionView(
    _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
    let image = images[indexPath.item]
    item.imageView?.image = thumbnails[indexPath.item]
    timeFormatter.dateFormat = Calendar.current.isDateInToday(image.receivedAt) ? "HH:mm" : "M/d"
    item.textField?.stringValue = timeFormatter.string(from: image.receivedAt)
    let timestamp = image.receivedAt.formatted(date: .complete, time: .standard)
    item.view.toolTip = timestamp
    (item as? ThumbnailItem)?.isLatestReceipt = image.url == latestReceivedURL
    item.view.setAccessibilityElement(true)
    item.view.setAccessibilityRole(.image)
    item.view.setAccessibilityLabel(
      L10n.text(
        image.url == latestReceivedURL ? "New image %d, %@" : "Received image %d, %@",
        indexPath.item + 1, timestamp))
    return item
  }

  func collectionView(
    _ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>
  ) { updateControls() }

  func collectionView(
    _ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>
  ) { updateControls() }

  func collectionView(
    _ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>,
    with event: NSEvent
  ) -> Bool {
    collection.dragStartedOnImage && !indexPaths.isEmpty
  }

  func collectionView(
    _ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath
  ) -> (any NSPasteboardWriting)? {
    images[indexPath.item].url as NSURL
  }

  func collectionView(
    _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
    willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>
  ) {
    session.draggingFormation = .pile
    DispatchQueue.main.async { [weak self] in
      for indexPath in indexPaths {
        self?.collection.item(at: indexPath)?.view.isHidden = false
      }
    }
  }

  func collectionView(
    _ collectionView: NSCollectionView, draggingSession session: NSDraggingSession,
    endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation
  ) {
    if !operation.isEmpty { didFinishDragging?() }
  }

  private var selectedImages: [ReceivedImage] {
    collection.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap {
      images.indices.contains($0.item) ? images[$0.item] : nil
    }
  }

  private func updateControls() {
    let count = selectedImages.count
    selectionCount.stringValue = L10n.text("selected_count", count)
    selectionCapsule?.isHidden = count == 0
    trashSurface?.isHidden = images.isEmpty
    trashButton.isEnabled = !isTrashing
    let title = count > 0 ? L10n.text("trash_count", count) : L10n.text("Move All to Trash…")
    trashButton.toolTip = title
    trashButton.setAccessibilityLabel(title)
    emptyState?.isHidden = !images.isEmpty
    scroll.isHidden = images.isEmpty
  }

  private func trashImages(allowAll: Bool) {
    guard !isTrashing, let loadImages, let recycleImages else { return }
    let selected = selectedImages.map(\.url)
    guard allowAll || !selected.isEmpty else { return }
    isTrashing = true
    presentationHeld?(holdsPresentation)
    updateControls()
    Task { [weak self] in
      guard let self else { return }
      defer {
        isTrashing = false
        presentationHeld?(holdsPresentation)
        updateControls()
      }
      do {
        let current = try await loadImages()
        let allowed = Set(current.map(\.url))
        let urls = selected.isEmpty ? current.map(\.url) : selected.filter { allowed.contains($0) }
        guard !urls.isEmpty else { return }
        if allowAll, !(await confirmTrash(count: urls.count, all: selected.isEmpty)) {
          return
        }
        closePreview()
        try await recycleImages(urls)
      } catch {
        presentError(error)
      }
    }
  }

  private func confirmTrash(count: Int, all: Bool) async -> Bool {
    guard trashButton.window != nil else { return false }
    let title = NSTextField(
      wrappingLabelWithString: all
        ? L10n.text("trash_all_confirmation", count)
        : L10n.text("trash_selection_confirmation", count))
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    title.alignment = .center
    title.preferredMaxLayoutWidth = 244
    let detail = NSTextField(labelWithString: L10n.text("You can restore them from the Trash."))
    detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    let confirm = NSButton(
      title: all ? L10n.text("Move All to Trash") : L10n.text("trash_count", count),
      target: self, action: #selector(confirmTrashClicked))
    confirm.bezelStyle = .rounded
    confirm.hasDestructiveAction = true
    confirm.bezelColor = .systemRed
    let content = NSView()
    content.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView(views: [title, detail, confirm])
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      content.widthAnchor.constraint(equalToConstant: 280),
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
      stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
      title.widthAnchor.constraint(equalTo: stack.widthAnchor),
      detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])
    let controller = NSViewController()
    controller.view = content
    let popover = NSPopover()
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = controller
    popover.contentSize = content.fittingSize
    trashConfirmation = popover
    trashConfirmed = false
    trashConfirmationKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak popover] event in
      guard event.keyCode == 53 else { return event }
      MainActor.assumeIsolated { popover?.performClose(nil) }
      return nil
    }
    return await withCheckedContinuation { continuation in
      trashConfirmationResult = continuation
      popover.show(relativeTo: trashButton.bounds, of: trashButton, preferredEdge: .minY)
      if !popover.isShown { finishTrashConfirmation() }
    }
  }

  @objc private func confirmTrashClicked() {
    trashConfirmed = true
    trashConfirmation?.performClose(nil)
  }

  func popoverDidClose(_ notification: Notification) {
    guard notification.object as? NSPopover === trashConfirmation else { return }
    finishTrashConfirmation()
  }

  private func finishTrashConfirmation() {
    if let monitor = trashConfirmationKeyMonitor { NSEvent.removeMonitor(monitor) }
    trashConfirmationKeyMonitor = nil
    let continuation = trashConfirmationResult
    let confirmed = trashConfirmed
    trashConfirmationResult = nil
    trashConfirmation = nil
    trashConfirmed = false
    DispatchQueue.main.async { continuation?.resume(returning: confirmed) }
  }

  private func copySelection() {
    let selected = selectedImages
    guard !selected.isEmpty else { return }
    let items: [NSPasteboardItem] = selected.map { image in
      let item = NSPasteboardItem()
      item.setString(image.url.absoluteString, forType: .fileURL)
      item.setDataProvider(ImageClipboardProvider(url: image.url), forTypes: [.png])
      return item
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(items)
  }

  private func revealSelection() {
    NSWorkspace.shared.activateFileViewerSelecting(selectedImages.map(\.url))
  }

  private func previewSelection() {
    if previewSource != nil {
      closePreview()
      return
    }
    let urls = selectedImages.map(\.url)
    guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
    previewSource = ImagePreviewSource(urls: urls)
    presentationHeld?(holdsPresentation)
    focusImages()
    panel.updateController()
    panel.makeKeyAndOrderFront(nil)
  }

  nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    MainActor.assumeIsolated { previewSource != nil }
  }

  nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      panel.dataSource = previewSource
      panel.delegate = self
      panel.reloadData()
      panel.currentPreviewItemIndex = 0
    }
  }

  nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    MainActor.assumeIsolated {
      panel.dataSource = nil
      panel.delegate = nil
      finishPreview()
    }
  }

  func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
    guard event.type == .keyDown else { return false }
    if event.charactersIgnoringModifiers == " " {
      closePreview()
      return true
    }
    guard let source = previewSource, !source.urls.isEmpty else { return false }
    let step: Int
    switch event.keyCode {
    case 123, 126: step = -1
    case 124, 125: step = 1
    default: return false
    }
    panel.currentPreviewItemIndex = max(
      0, min(source.urls.count - 1, panel.currentPreviewItemIndex + step))
    return true
  }

  func windowWillClose(_ notification: Notification) { finishPreview() }

  func closePreview() {
    guard previewSource != nil else { return }
    if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.currentController as AnyObject? === self
    {
      panel.close()
    }
    finishPreview()
  }

  private func finishPreview() {
    guard previewSource != nil else { return }
    if QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
      panel.currentController as AnyObject? === self
    {
      panel.dataSource = nil
      panel.delegate = nil
    }
    previewSource = nil
    if NSApp.isActive, NSApp.keyWindow is QLPreviewPanel {
      view.window?.makeKey()
    }
    focusImages()
    presentationHeld?(holdsPresentation)
  }

  @objc private func folderClicked() { openFolder?() }
  @objc private func settingsClicked() { openSettings?() }
  @objc private func trashClicked() { trashImages(allowAll: true) }
}

@MainActor
private final class ThumbnailItem: NSCollectionViewItem {
  static let identifier = NSUserInterfaceItemIdentifier("Thumbnail")
  var isLatestReceipt = false { didSet { updateSelection() } }

  override func loadView() {
    let container = ThumbnailView()
    let image = TopAlignedImageView()
    image.translatesAutoresizingMaskIntoConstraints = false
    image.wantsLayer = true
    image.layer?.cornerRadius = 6
    image.layer?.masksToBounds = true
    let time = NSTextField(labelWithString: "")
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
    container.addSubview(image)
    container.addSubview(capsule)
    container.addSubview(check)
    NSLayoutConstraint.activate([
      image.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      image.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      image.topAnchor.constraint(equalTo: container.topAnchor),
      image.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      capsule.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
      capsule.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
      time.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 3),
      time.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -3),
      time.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 1),
      time.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -1),
      check.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
      check.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
      check.widthAnchor.constraint(equalToConstant: 16),
      check.heightAnchor.constraint(equalToConstant: 16),
    ])
    container.timeCapsule = capsule
    container.checkmark = check
    view = container
    imageView = image
    textField = time
    updateSelection()
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
    (view as? ThumbnailView)?.selected =
      highlightState == .forSelection || (isSelected && highlightState != .forDeselection)
    (view as? ThumbnailView)?.latestReceipt = isLatestReceipt
  }
}

@MainActor
private final class TopAlignedImageView: NSImageView {
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
private final class ThumbnailView: NSView {
  var timeCapsule: NSView?
  var checkmark: NSImageView?
  var selected = false {
    didSet {
      setAccessibilitySelected(selected)
      updateColors()
    }
  }
  var latestReceipt = false { didSet { updateColors() } }

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

private final class ImagePreviewSource: NSObject, QLPreviewPanelDataSource {
  let urls: [URL]
  init(urls: [URL]) { self.urls = urls }
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }
  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    urls[index] as NSURL
  }
}

private final class ImageClipboardProvider: NSObject, NSPasteboardItemDataProvider {
  let url: URL
  init(url: URL) { self.url = url }

  func pasteboard(
    _ pasteboard: NSPasteboard?, item: NSPasteboardItem,
    provideDataForType type: NSPasteboard.PasteboardType
  ) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { return }
    item.setData(png, forType: .png)
  }
}

@MainActor
private final class ImageCollectionView: NSCollectionView {
  var copyImages: (() -> Void)?
  var revealImages: (() -> Void)?
  var previewImages: (() -> Void)?
  var deleteImages: (() -> Void)?
  var selectionChanged: (() -> Void)?
  private(set) var dragStartedOnImage = false

  override func setFrameSize(_ newSize: NSSize) {
    let widthChanged = newSize.width != frame.width
    super.setFrameSize(newSize)
    if widthChanged { collectionViewLayout?.invalidateLayout() }
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let point = convert(event.locationInWindow, from: nil)
    guard let path = indexPathForItem(at: point) else { return nil }
    if !selectionIndexPaths.contains(path) { selectionIndexPaths = [path] }
    selectionChanged?()
    let menu = NSMenu()
    let count = selectionIndexPaths.count
    let copy = NSMenuItem(
      title: count > 1 ? L10n.text("copy_count", count) : L10n.text("Copy Image"),
      action: #selector(copy(_:)), keyEquivalent: "c"
    )
    copy.target = self
    menu.addItem(copy)
    let reveal = NSMenuItem(
      title: L10n.text("Show in Finder"), action: #selector(reveal), keyEquivalent: "")
    reveal.target = self
    menu.addItem(reveal)
    menu.addItem(.separator())
    let trash = NSMenuItem(
      title: count > 1 ? L10n.text("trash_count", count) : L10n.text("Move to Trash"),
      action: #selector(trash),
      keyEquivalent: "\u{8}")
    trash.target = self
    menu.addItem(trash)
    return menu
  }

  override func mouseDown(with event: NSEvent) {
    let clickedImage = indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil
    dragStartedOnImage = clickedImage
    super.mouseDown(with: event)
    if event.clickCount == 2, clickedImage { previewImages?() }
  }

  override func keyDown(with event: NSEvent) {
    if event.charactersIgnoringModifiers == "c", event.modifierFlags.contains(.command) {
      copyImages?()
    } else if event.modifierFlags.contains(.command), event.keyCode == 51 {
      deleteImages?()
    } else if event.charactersIgnoringModifiers == " " {
      previewImages?()
    } else if event.keyCode == 53, !selectionIndexPaths.isEmpty {
      deselectAll(nil)
      selectionChanged?()
    } else {
      super.keyDown(with: event)
    }
  }

  @objc func copy(_ sender: Any?) { copyImages?() }
  @objc private func reveal() { revealImages?() }
  @objc private func trash() { deleteImages?() }
}
