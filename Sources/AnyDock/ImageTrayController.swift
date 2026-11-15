import AnyDockCore
import AppKit
import Quartz
import QuickLookThumbnailing

enum TrayPreferences {
  static var copiesNewItems: Bool {
    get { UserDefaults.standard.bool(forKey: "copyNewItems") }
    set { UserDefaults.standard.set(newValue, forKey: "copyNewItems") }
  }
}

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
  private let filterBar = NSStackView()
  private var selectionCapsule: NSView?
  private var trashSurface: NSView?
  private var emptyState: NSView?
  private var contents = TrayContents()
  private var entries: [TrayEntry] = []
  private var cache: [URL: TrayEntry] = [:]
  private var requestedThumbnails: Set<URL> = []
  private var latestReceivedURL: URL?
  private var previewSource: ImagePreviewSource?
  private var isTrashing = false
  private var trashConfirmation: NSPopover?
  private var trashConfirmationResult: CheckedContinuation<Bool, Never>?
  private var trashConfirmationKeyMonitor: Any?
  private var trashConfirmed = false
  var holdsPresentation: Bool { previewSource != nil || isTrashing }
  var presentationHeld: ((Bool) -> Void)?
  var loadItems: (() async throws -> [ReceivedItem])?
  var recycleItems: (([URL]) async throws -> Void)?
  var openFolder: (() -> Void)?
  var openSettings: (() -> Void)?
  var didFinishDragging: (() -> Void)?

  private var singleColumn: Bool { contents.filter == .kind(.text) }

  override func loadView() {
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 520))
    view = glassSurface(content, cornerRadius: 16)
    view.frame = NSRect(x: 0, y: 0, width: 450, height: 520)
    layout.aspectRatio = { [weak self] path in self?.aspectRatio(at: path.item) ?? 1 }
    collection.collectionViewLayout = layout
    collection.frame = content.bounds
    collection.autoresizingMask = [.width]
    collection.isSelectable = true
    collection.allowsMultipleSelection = true
    collection.allowsEmptySelection = true
    collection.backgroundColors = [.clear]
    collection.register(ImageCardItem.self, forItemWithIdentifier: ImageCardItem.identifier)
    collection.register(TextCardItem.self, forItemWithIdentifier: TextCardItem.identifier)
    collection.register(LinkCardItem.self, forItemWithIdentifier: LinkCardItem.identifier)
    collection.register(FileCardItem.self, forItemWithIdentifier: FileCardItem.identifier)
    collection.dataSource = self
    collection.delegate = self
    collection.setDraggingSourceOperationMask(.copy, forLocal: false)
    collection.setDraggingSourceOperationMask(.copy, forLocal: true)
    collection.copyImages = { [weak self] in self?.copySelection() }
    collection.revealImages = { [weak self] in self?.revealSelection() }
    collection.previewImages = { [weak self] in self?.previewSelection() }
    collection.deleteImages = { [weak self] in self?.trashItems(allowAll: false) }
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
    configureFilterBar(in: content)
    configureControls(in: content)
    updateControls()
  }

  private func configureFilterBar(in content: NSView) {
    filterBar.orientation = .horizontal
    filterBar.spacing = 6
    filterBar.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(filterBar)
    NSLayoutConstraint.activate([
      filterBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
      filterBar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -10),
      filterBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
      filterBar.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  private func updateFilterBar() {
    for view in filterBar.arrangedSubviews {
      filterBar.removeArrangedSubview(view)
      view.removeFromSuperview()
    }
    filterBar.isHidden = !contents.showsFilters
    for (index, filter) in contents.availableFilters.enumerated() {
      let count = filter == .all ? contents.items.count : kindCount(filter)
      let selected = filter == contents.filter
      let button = NSButton(
        title: "\(filterTitle(filter)) \(count)", target: self, action: #selector(filterClicked))
      button.tag = index
      button.isBordered = false
      button.setButtonType(.toggle)
      button.state = selected ? .on : .off
      button.font = .systemFont(ofSize: 11, weight: selected ? .semibold : .regular)
      button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
      button.setAccessibilityLabel(L10n.text("filter_accessibility", filterTitle(filter), count))
      let padded = NSStackView(views: [button])
      padded.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
      let surface = glassSurface(padded, cornerRadius: 12)
      surface.heightAnchor.constraint(equalToConstant: 24).isActive = true
      filterBar.addArrangedSubview(surface)
    }
  }

  private func kindCount(_ filter: TrayFilter) -> Int {
    guard case .kind(let kind) = filter else { return contents.items.count }
    return contents.count(of: kind)
  }

  private func filterTitle(_ filter: TrayFilter) -> String {
    switch filter {
    case .all: L10n.text("All")
    case .kind(.image): L10n.text("Images")
    case .kind(.text): L10n.text("Text")
    case .kind(.link): L10n.text("Links")
    case .kind(.file): L10n.text("Files")
    }
  }

  @objc private func filterClicked(_ sender: NSButton) {
    let filters = contents.availableFilters
    guard filters.indices.contains(sender.tag) else { return }
    contents.select(filters[sender.tag])
    reloadEntries()
    scrollToLatestImage()
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
    let title = NSTextField(labelWithString: L10n.text("Nothing received yet"))
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let detail = NSTextField(
      wrappingLabelWithString: L10n.text(
        "Share content on your iPhone and choose your Mac’s shortcut."))
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

  func replaceItems(_ next: [ReceivedItem]) {
    loadViewIfNeeded()
    contents.replace(next)
    reloadEntries()
  }

  func append(_ item: ReceivedItem) {
    loadViewIfNeeded()
    latestReceivedURL = item.url
    cache[item.url] = nil
    contents.receive(item)
    reloadEntries()
  }

  private func reloadEntries() {
    let selected = Set(selectedEntries.map(\.url))
    let present = Set(contents.items.map(\.url))
    cache = cache.filter { present.contains($0.key) }
    requestedThumbnails.formIntersection(present)
    entries = contents.visibleItems.map { item in
      if let cached = cache[item.url] { return cached }
      let entry = TrayEntry(item: item)
      cache[item.url] = entry
      return entry
    }
    layout.columnCount = singleColumn ? 1 : 3
    layout.topInset = contents.showsFilters ? 44 : 24
    layout.invalidateLayout()
    collection.reloadData()
    collection.selectionIndexPaths = Set(
      entries.enumerated().compactMap {
        selected.contains($0.element.url) ? IndexPath(item: $0.offset, section: 0) : nil
      })
    updateFilterBar()
    updateControls()
    for entry in entries where entry.kind == .file && !entry.item.isPlainText {
      requestThumbnail(for: entry.url)
    }
  }

  private func aspectRatio(at index: Int) -> CGFloat {
    guard entries.indices.contains(index) else { return 1 }
    let entry = entries[index]
    switch entry.kind {
    case .image:
      guard let size = entry.thumbnail?.size, size.width > 0, size.height > 0 else { return 1 }
      return size.height / size.width
    case .text:
      guard singleColumn else { return 1 }
      return 92 / max(collection.bounds.width - 48, 1)
    case .link: return 0.8
    case .file: return 1.25
    }
  }

  private func requestThumbnail(for url: URL) {
    guard !requestedThumbnails.contains(url) else { return }
    requestedThumbnails.insert(url)
    let request = QLThumbnailGenerator.Request(
      fileAt: url, size: CGSize(width: 240, height: 240),
      scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
    QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
      [weak self] representation, _ in
      guard let image = representation?.cgImage else { return }
      Task { @MainActor in self?.applyThumbnail(image, for: url) }
    }
  }

  private func applyThumbnail(_ image: CGImage, for url: URL) {
    guard var entry = cache[url] else { return }
    let thumbnail = NSImage(cgImage: image, size: .zero)
    entry.thumbnail = thumbnail
    cache[url] = entry
    guard let index = entries.firstIndex(where: { $0.url == url }) else { return }
    entries[index] = entry
    (collection.item(at: IndexPath(item: index, section: 0)) as? FileCardItem)?
      .showThumbnail(thumbnail)
  }

  func focusImages() { view.window?.makeFirstResponder(collection) }

  func clearSelection() {
    collection.selectionIndexPaths = []
    updateControls()
  }

  func scrollToLatestImage() {
    guard !entries.isEmpty else { return }
    collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top)
  }

  func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
    -> Int
  { entries.count }

  func collectionView(
    _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
  ) -> NSCollectionViewItem {
    let entry = entries[indexPath.item]
    let identifier: NSUserInterfaceItemIdentifier =
      switch entry.kind {
      case .image: ImageCardItem.identifier
      case .text: TextCardItem.identifier
      case .link: LinkCardItem.identifier
      case .file: FileCardItem.identifier
      }
    let item = collectionView.makeItem(withIdentifier: identifier, for: indexPath)
    let card = item as? TrayCardItem
    card?.configure(entry, singleColumn: singleColumn)
    timeFormatter.dateFormat =
      Calendar.current.isDateInToday(entry.item.receivedAt) ? "HH:mm" : "M/d"
    item.textField?.stringValue = timeFormatter.string(from: entry.item.receivedAt)
    let timestamp = entry.item.receivedAt.formatted(date: .complete, time: .standard)
    item.view.toolTip = timestamp
    let latest = entry.url == latestReceivedURL
    card?.isLatestReceipt = latest
    item.view.setAccessibilityElement(true)
    item.view.setAccessibilityRole(entry.kind == .image ? .image : .group)
    item.view.setAccessibilityLabel(
      L10n.text(
        latest ? "New %@: %@, %@" : "%@: %@, %@", kindName(entry.kind), entry.summary,
        timestamp))
    return item
  }

  private func kindName(_ kind: ReceivedKind) -> String {
    switch kind {
    case .image: L10n.text("Image")
    case .text: L10n.text("Text")
    case .link: L10n.text("Link")
    case .file: L10n.text("File")
    }
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
    let entry = entries[indexPath.item]
    switch entry.kind {
    case .image, .file:
      return entry.url as NSURL
    case .text:
      return entry.fullText as NSString
    case .link:
      let item = NSPasteboardItem()
      if let link = entry.link {
        item.setString(link.absoluteString, forType: .URL)
        item.setString(link.absoluteString, forType: .string)
      }
      item.setString(entry.url.absoluteString, forType: .fileURL)
      return item
    }
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

  private var selectedEntries: [TrayEntry] {
    collection.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap {
      entries.indices.contains($0.item) ? entries[$0.item] : nil
    }
  }

  private func updateControls() {
    let count = selectedEntries.count
    selectionCount.stringValue = L10n.text("selected_count", count)
    selectionCapsule?.isHidden = count == 0
    trashSurface?.isHidden = entries.isEmpty
    trashButton.isEnabled = !isTrashing
    let title = count > 0 ? L10n.text("trash_count", count) : trashAllTitle
    trashButton.toolTip = title
    trashButton.setAccessibilityLabel(title)
    emptyState?.isHidden = !contents.items.isEmpty
    scroll.isHidden = contents.items.isEmpty
  }

  private var trashAllTitle: String {
    switch contents.filter {
    case .all: L10n.text("Move All to Trash…")
    case .kind(.image): L10n.text("Move All Images to Trash…")
    case .kind(.text): L10n.text("Move All Text to Trash…")
    case .kind(.link): L10n.text("Move All Links to Trash…")
    case .kind(.file): L10n.text("Move All Files to Trash…")
    }
  }

  private func trashItems(allowAll: Bool) {
    guard !isTrashing, let loadItems, let recycleItems else { return }
    let selected = selectedEntries.map(\.url)
    guard allowAll || !selected.isEmpty else { return }
    let targets = contents.trashTargets(selected: selected)
    let filter = contents.filter
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
        let allowed = Set(try await loadItems().map(\.url))
        let urls = targets.filter { allowed.contains($0) }
        guard !urls.isEmpty else { return }
        if allowAll,
          !(await confirmTrash(count: urls.count, filter: selected.isEmpty ? filter : nil))
        {
          return
        }
        closePreview()
        try await recycleItems(urls)
      } catch {
        presentError(error)
      }
    }
  }

  private func confirmationText(count: Int, filter: TrayFilter?) -> String {
    switch filter {
    case nil: L10n.text("trash_selection_confirmation", count)
    case .all: L10n.text("trash_all_confirmation", count)
    case .kind(.image): L10n.text("trash_images_confirmation", count)
    case .kind(.text): L10n.text("trash_texts_confirmation", count)
    case .kind(.link): L10n.text("trash_links_confirmation", count)
    case .kind(.file): L10n.text("trash_files_confirmation", count)
    }
  }

  private func confirmTrash(count: Int, filter: TrayFilter?) async -> Bool {
    guard trashButton.window != nil else { return false }
    let title = NSTextField(wrappingLabelWithString: confirmationText(count: count, filter: filter))
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    title.alignment = .center
    title.preferredMaxLayoutWidth = 244
    let detail = NSTextField(labelWithString: L10n.text("You can restore them from the Trash."))
    detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    detail.textColor = .secondaryLabelColor
    detail.alignment = .center
    let confirm = NSButton(
      title: filter == .all ? L10n.text("Move All to Trash") : L10n.text("trash_count", count),
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

  func copyToPasteboard(_ item: ReceivedItem) {
    let entry = cache[item.url] ?? TrayEntry(item: item)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([pasteboardItem(for: entry)])
  }

  private func pasteboardItem(for entry: TrayEntry) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    switch entry.kind {
    case .image:
      item.setString(entry.url.absoluteString, forType: .fileURL)
      item.setDataProvider(ImageClipboardProvider(url: entry.url), forTypes: [.png])
    case .text:
      item.setString(entry.fullText, forType: .string)
    case .link:
      if let link = entry.link {
        item.setString(link.absoluteString, forType: .URL)
        item.setString(link.absoluteString, forType: .string)
      }
    case .file:
      item.setString(entry.url.absoluteString, forType: .fileURL)
    }
    return item
  }

  private func copySelection() {
    let selected = selectedEntries
    guard !selected.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects(selected.map(pasteboardItem(for:)))
  }

  private func revealSelection() {
    NSWorkspace.shared.activateFileViewerSelecting(selectedEntries.map(\.url))
  }

  private func previewSelection() {
    if previewSource != nil {
      closePreview()
      return
    }
    let urls = selectedEntries.map(\.url)
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
  @objc private func trashClicked() { trashItems(allowAll: true) }
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
      title: count > 1 ? L10n.text("copy_count", count) : L10n.text("Copy"),
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
