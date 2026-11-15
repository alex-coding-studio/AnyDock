import AppKit
import OSLog
import SnapDockCore

@main
@MainActor
enum SnapDockApp {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var statusItem: NSStatusItem?
  private let popover = NSPopover()
  private let tray = ImageTrayController()
  private let store = ImageStore()
  private var server: HTTPServer?
  private var configurationStore: ConfigurationStore?
  private var configuration: ReceiverConfiguration?
  private var settings: SettingsController?
  private let logger = Logger(subsystem: "studio.alex.snapdock", category: "Receiver")

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = BrandIcon.menuBar()
    item.button?.setAccessibilityLabel("SnapDock")
    item.button?.image?.isTemplate = true
    item.button?.target = self
    item.button?.action = #selector(togglePopover)
    item.button?.toolTip = "SnapDock"
    statusItem = item
    popover.behavior = .transient
    popover.delegate = self
    popover.contentViewController = tray
    popover.contentSize = NSSize(width: 450, height: 520)
    tray.openSettings = { [weak self] in self?.showSettings() }
    tray.openFolder = { [weak self] in self?.openFolder() }
    tray.didFinishDragging = { [weak self] in self?.popover.performClose(nil) }
    tray.presentationHeld = { [weak self] held in
      self?.popover.behavior = held ? .applicationDefined : .transient
    }
    tray.loadImages = { [weak self] in try await self?.currentImages() ?? [] }
    tray.recycleImages = { [weak self] urls in try await self?.recycleImages(urls) }
    do {
      let storage = try ConfigurationStore()
      configurationStore = storage
      let current = try storage.load()
      configuration = current
      let preferences = SettingsController(
        configuration: current, thumbnailColumns: tray.columnCount)
      preferences.apply = { [weak self] next in try await self?.apply(next) }
      preferences.columnsChanged = { [weak self] count in self?.tray.setColumnCount(count) }
      settings = preferences
      server = HTTPServer(store: store)
      Task {
        await startReceiver(current)
        await reloadImages()
      }
      if CommandLine.arguments.contains("--settings") { showSettings() }
      if CommandLine.arguments.contains("--tray") { togglePopover() }
    } catch {
      logger.error(
        "Configuration could not be loaded: \(error.localizedDescription, privacy: .public)")
      let alert = NSAlert(error: error)
      alert.messageText = "无法读取 SnapDock 配置"
      alert.informativeText = "配置文件保持原样。请检查 Application Support/SnapDock 中的配置后重新启动。"
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  private func startReceiver(_ next: ReceiverConfiguration) async {
    guard let server else { return }
    do {
      try await server.start(
        configuration: next,
        onReceive: { [weak self] image in
          await self?.received(image)
        },
        onFailure: { [weak self] message in
          await self?.receiverFailed(message)
        })
      settings?.setStatus("监听中 · \(next.port)", isError: false)
      setErrorIcon(false)
    } catch {
      receiverFailed("端口 \(next.port) 无法监听：\(error.localizedDescription)")
    }

  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    showSettings()
    return true
  }

  private func receiverFailed(_ message: String) {
    logger.error("Listener failed: \(message, privacy: .public)")
    settings?.setStatus(message, isError: true)
    setErrorIcon(true)
  }

  private func setErrorIcon(_ failed: Bool) {
    statusItem?.button?.image =
      failed
      ? NSImage(
        systemSymbolName: "exclamationmark.triangle",
        accessibilityDescription: "SnapDock 监听失败，请打开设置")
      : BrandIcon.menuBar()
    statusItem?.button?.image?.isTemplate = true
  }

  private func received(_ image: ReceivedImage) {
    guard
      image.url.deletingLastPathComponent().standardizedFileURL
        == configuration?.directory.standardizedFileURL
    else { return }
    tray.append(image)
    if !popover.isShown {
      showPopover(refreshImages: false)
    }
    tray.scrollToLatestImage()
  }

  private func reloadImages() async {
    guard let directory = configuration?.directory else { return }
    do {
      let images = try await store.list(in: directory)
      guard directory == configuration?.directory else { return }
      tray.replaceImages(images)
    } catch {
      receiverFailed("无法读取接收文件夹：\(error.localizedDescription)")
    }
  }

  private func currentImages() async throws -> [ReceivedImage] {
    guard let directory = configuration?.directory else { return [] }
    let images = try await store.list(in: directory)
    guard directory == configuration?.directory else { throw CocoaError(.userCancelled) }
    return images
  }

  private func recycleImages(_ requested: [URL]) async throws {
    let allowed = Set(try await currentImages().map(\.url))
    let urls = requested.filter { allowed.contains($0) }
    guard !urls.isEmpty else { return }
    let error: (any Error)? = await withCheckedContinuation { continuation in
      NSWorkspace.shared.recycle(urls) { _, error in
        continuation.resume(returning: error)
      }
    }
    await reloadImages()
    if let error { throw error }
  }

  private func apply(_ next: ReceiverConfiguration) async throws {
    try FileManager.default.createDirectory(at: next.directory, withIntermediateDirectories: true)
    guard FileManager.default.isWritableFile(atPath: next.directory.path) else {
      throw CocoaError(.fileWriteNoPermission)
    }
    try configurationStore?.save(next)
    configuration = next
    await reloadImages()
    await startReceiver(next)
  }

  @objc private func togglePopover() {
    if tray.holdsPresentation {
      tray.closePreview()
      return
    }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    showPopover()
  }

  private func showPopover(refreshImages: Bool = true) {
    guard !popover.isShown else { return }
    guard let button = statusItem?.button else { return }
    NSApp.activate(ignoringOtherApps: true)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    tray.focusImages()
    if refreshImages {
      Task { await reloadImages() }
    }
  }

  private func showSettings() {
    tray.closePreview()
    popover.performClose(nil)
    NSApp.activate(ignoringOtherApps: true)
    settings?.showWindow(nil)
    settings?.window?.makeKeyAndOrderFront(nil)
  }

  func popoverShouldClose(_ popover: NSPopover) -> Bool { !tray.holdsPresentation }

  func popoverDidClose(_ notification: Notification) {
    guard notification.object as? NSPopover === popover else { return }
    tray.clearSelection()
  }

  private func openFolder() {
    guard let directory = configuration?.directory else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      NSWorkspace.shared.open(directory)
    } catch {
      NSAlert(error: error).runModal()
    }
  }
}
