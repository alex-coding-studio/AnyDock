import AppKit
import ServiceManagement
import SnapDockCore

@MainActor
final class SettingsController: NSWindowController, NSTextFieldDelegate, NSSharingServiceDelegate {
  private var configuration: ReceiverConfiguration
  private var selectedDirectory: URL
  private var isApplying = false
  private var isSending = false
  private let shortcutNamePreference = "personalizedShortcutName"
  private let shortcutName = NSTextField()
  private let shortcutNameStatus = NSTextField(wrappingLabelWithString: "")
  private var sharedFile: URL?
  private var sharingService: NSSharingService?
  private let folder = NSTextField(labelWithString: "")
  private let port = NSTextField()
  private let address = NSTextField(wrappingLabelWithString: "")
  private let receiverStatus = NSTextField(wrappingLabelWithString: "正在启动接收服务…")
  private let receivingError = NSTextField(wrappingLabelWithString: "")
  private let generalStatus = NSTextField(wrappingLabelWithString: "")
  private let connectionStatus = NSTextField(wrappingLabelWithString: "")
  private let pending = NSTextField(labelWithString: "")
  private let statusIcon = NSImageView()
  private let login = NSSwitch()
  private let columns = NSSegmentedControl(
    labels: ["2", "3", "4", "5"], trackingMode: .selectOne, target: nil, action: nil)
  private let save = NSButton(title: "应用", target: nil, action: nil)
  private let send = NSButton(title: "发送到 iPhone…", target: nil, action: nil)
  var apply: ((ReceiverConfiguration) async throws -> Void)?
  var columnsChanged: ((Int) -> Void)?

  init(configuration: ReceiverConfiguration, thumbnailColumns: Int) {
    self.configuration = configuration
    selectedDirectory = configuration.directory
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 600, height: 480), styleMask: [.titled, .closable],
      backing: .buffered, defer: false)
    window.title = "SnapDock 设置"
    window.toolbarStyle = .preference
    window.center()
    super.init(window: window)
    if let savedName = UserDefaults.standard.string(forKey: shortcutNamePreference) {
      shortcutName.stringValue = savedName
    } else if let computerName = Host.current().localizedName?
      .trimmingCharacters(in: .whitespacesAndNewlines), !computerName.isEmpty
    {
      shortcutName.stringValue = "发送到 " + computerName
    } else {
      shortcutName.stringValue = "发送到 Mac"
    }
    columns.selectedSegment = (2...5).contains(thumbnailColumns) ? thumbnailColumns - 2 : 3
    buildInterface()
  }

  required init?(coder: NSCoder) { nil }

  func setStatus(_ text: String, isError: Bool) {
    receiverStatus.stringValue = text
    receiverStatus.textColor = isError ? .systemRed : .labelColor
    statusIcon.contentTintColor = isError ? .systemRed : .systemGreen
    statusIcon.image = NSImage(
      systemSymbolName: isError ? "exclamationmark.circle.fill" : "circle.fill",
      accessibilityDescription: isError ? "接收失败" : "正在监听")
  }

  private func buildInterface() {
    let tabs = NSTabViewController()
    tabs.tabStyle = .toolbar
    tabs.canPropagateSelectedChildViewControllerTitle = false
    tabs.addTabViewItem(generalTab())
    tabs.addTabViewItem(connectionTab())
    tabs.addTabViewItem(receivingTab())
    tabs.selectedTabViewItemIndex = 0
    window?.contentViewController = tabs
  }

  private func generalTab() -> NSTabViewItem {
    login.state = SMAppService.mainApp.status == .enabled ? .on : .off
    login.target = self
    login.action = #selector(toggleLogin)
    login.setAccessibilityLabel("登录时自动启动")
    columns.target = self
    columns.action = #selector(changeColumns)
    columns.setAccessibilityLabel("缩略图列数")
    configureMessage(generalStatus)
    let icon = NSImageView(image: BrandIcon.artwork ?? BrandIcon.menuBar())
    icon.imageScaling = .scaleProportionallyUpOrDown
    icon.widthAnchor.constraint(equalToConstant: 40).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 40).isActive = true
    let title = NSTextField(labelWithString: "SnapDock")
    title.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let identity = NSStackView(views: [title, footnote("iPhone 截图收件箱")])
    identity.orientation = .vertical
    identity.alignment = .leading
    identity.spacing = 3
    let quit = NSButton(
      title: "退出 SnapDock", target: NSApp, action: #selector(NSApplication.terminate(_:)))
    quit.bezelStyle = .rounded
    let card = row([icon, identity, NSView(), quit])
    card.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
    return tab(
      "通用", symbol: "gearshape",
      views: [
        section(
          "托盘", rows: [formRow("缩略图列数", value: columns)],
          note: "立即生效。列越多，一屏看到的截图越多。"),
        section("启动", rows: [formRow("登录时自动启动", value: login)]),
        generalStatus, group(rows: [card]),
      ])
  }

  private func connectionTab() -> NSTabViewItem {
    address.isSelectable = true
    address.maximumNumberOfLines = 2
    address.lineBreakMode = .byCharWrapping
    address.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    refreshAddress()
    let key = NSTextField(labelWithString: "•••• •••• •••• ••••")
    key.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    key.textColor = .secondaryLabelColor
    send.target = self
    send.action = #selector(sendToPhone)
    send.bezelStyle = .rounded
    send.bezelColor = .controlAccentColor
    configureMessage(connectionStatus)
    configureMessage(shortcutNameStatus)
    shortcutName.delegate = self
    shortcutName.setAccessibilityLabel("快捷指令名称")
    shortcutName.widthAnchor.constraint(equalToConstant: 260).isActive = true
    updateShortcutName()
    let copyAddress = button("复制", #selector(copyConnectionAddress))
    copyAddress.setAccessibilityLabel("复制接收地址")
    let copyKey = button("复制", #selector(copyToken))
    copyKey.setAccessibilityLabel("复制连接密钥")
    return tab(
      "连接", symbol: "iphone",
      views: [
        section(
          "一步设置",
          rows: [
            formRow("快捷指令名称", value: shortcutName),
            formRow("发送到 Mac", value: send),
          ],
          note: """
            通过 AirDrop 发送，在 iPhone 上点「添加快捷指令」即可使用。\
            快捷指令含连接密钥；系统签名会将副本交给 Apple 验证，请仅发送给自己的 iPhone。
            """),
        shortcutNameStatus, connectionStatus,
        section(
          "手动设置",
          rows: [
            formRow("接收地址", value: address, action: copyAddress),
            formRow("连接密钥", value: key, action: copyKey),
            formRow(
              "通用快捷指令", value: NSTextField(labelWithString: "发送到 Mac"),
              action: button("导出…", #selector(exportShortcut))),
          ],
          note: "仅在可信局域网使用，HTTP 传输不加密。更改端口后请重新发送快捷指令。手动导入通用版时，需填写接收地址和连接密钥。"),
      ])
  }

  private func receivingTab() -> NSTabViewItem {
    refreshFolder()
    folder.lineBreakMode = .byTruncatingMiddle
    port.stringValue = String(configuration.port)
    port.placeholderString = "8765"
    port.alignment = .right
    port.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    port.widthAnchor.constraint(equalToConstant: 76).isActive = true
    port.delegate = self
    port.setAccessibilityLabel("监听端口")
    statusIcon.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "正在启动")
    statusIcon.contentTintColor = .tertiaryLabelColor
    statusIcon.widthAnchor.constraint(equalToConstant: 9).isActive = true
    statusIcon.heightAnchor.constraint(equalToConstant: 9).isActive = true
    let statusRow = row([statusIcon, receiverStatus, NSView()])
    statusRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
    configureMessage(receivingError)
    pending.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    pending.textColor = .secondaryLabelColor
    save.target = self
    save.action = #selector(saveSettings)
    save.keyEquivalent = "\r"
    save.bezelStyle = .rounded
    updatePending()
    return tab(
      "接收", symbol: "tray.and.arrow.down",
      views: [
        group(rows: [statusRow]),
        section(
          "保存位置",
          rows: [formRow("文件夹", value: folder, action: button("更改…", #selector(chooseFolder)))],
          note: "更换位置不会移动或删除已收到的原图。"),
        section(
          "网络", rows: [formRow("监听端口", value: port)],
          note: "端口范围为 1024–65535。更改端口后，请重新发送 iPhone 快捷指令。"),
        receivingError,
      ], bottomBar: row([NSView(), pending, save]))
  }

  private func tab(_ title: String, symbol: String, views: [NSView], bottomBar: NSView? = nil)
    -> NSTabViewItem
  {
    let controller = NSViewController()
    controller.title = title
    controller.preferredContentSize = NSSize(width: 600, height: 480)
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 480))
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.translatesAutoresizingMaskIntoConstraints = false
    content.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
      stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
    ])
    for element in stack.arrangedSubviews {
      element.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    if let bottomBar {
      bottomBar.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(bottomBar)
      let separator = NSBox()
      separator.boxType = .separator
      separator.translatesAutoresizingMaskIntoConstraints = false
      content.addSubview(separator)
      NSLayoutConstraint.activate([
        bottomBar.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
        bottomBar.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
        separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        separator.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),
        stack.bottomAnchor.constraint(lessThanOrEqualTo: separator.topAnchor, constant: -12),
      ])
    } else {
      let bottom = stack.bottomAnchor.constraint(
        lessThanOrEqualTo: content.bottomAnchor, constant: -24)
      bottom.isActive = true
    }
    controller.view = content
    let item = NSTabViewItem(viewController: controller)
    item.label = title
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
    return item
  }

  private func row(_ views: [NSView]) -> NSStackView {
    let stack = NSStackView(views: views)
    stack.orientation = .horizontal
    stack.spacing = 10
    stack.alignment = .centerY
    return stack
  }

  private func button(_ title: String, _ action: Selector) -> NSButton {
    let button = NSButton(title: title, target: self, action: action)
    button.bezelStyle = .rounded
    button.controlSize = .small
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    return button
  }

  private func formRow(_ title: String, value: NSView, action: NSView? = nil) -> NSStackView {
    let label = NSTextField(labelWithString: title)
    label.setContentCompressionResistancePriority(.required, for: .horizontal)
    value.setContentHuggingPriority(
      action == nil ? .required : .defaultLow, for: .horizontal)
    value.setContentCompressionResistancePriority(
      action == nil ? .required : .defaultLow, for: .horizontal)
    let stack = row(
      [label] + (action == nil ? [NSView(), value] : [value]) + (action.map { [$0] } ?? []))
    stack.heightAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
    return stack
  }

  private func footnote(_ text: String) -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    label.setContentCompressionResistancePriority(.required, for: .vertical)
    return label
  }

  private func configureMessage(_ label: NSTextField) {
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .systemRed
    label.isHidden = true
    label.setContentCompressionResistancePriority(.required, for: .vertical)
  }

  private func section(_ title: String, rows: [NSView], note: String? = nil) -> NSStackView {
    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
    label.textColor = .secondaryLabelColor
    let stack = NSStackView(
      views: [label, group(rows: rows)] + (note.map { [footnote($0)] } ?? []))
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 7
    for view in stack.arrangedSubviews.dropFirst() {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    return stack
  }

  private func group(rows: [NSView]) -> NSView {
    let contents = NSStackView()
    contents.orientation = .vertical
    contents.spacing = 0
    for (index, item) in rows.enumerated() {
      if index > 0 {
        let separator = NSBox()
        separator.boxType = .separator
        contents.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
      }
      contents.addArrangedSubview(item)
      item.widthAnchor.constraint(equalTo: contents.widthAnchor).isActive = true
    }
    let group = SettingsGroup()
    contents.translatesAutoresizingMaskIntoConstraints = false
    group.addSubview(contents)
    NSLayoutConstraint.activate([
      contents.leadingAnchor.constraint(equalTo: group.leadingAnchor, constant: 14),
      contents.trailingAnchor.constraint(equalTo: group.trailingAnchor, constant: -14),
      contents.topAnchor.constraint(equalTo: group.topAnchor, constant: 5),
      contents.bottomAnchor.constraint(equalTo: group.bottomAnchor, constant: -5),
    ])
    return group
  }

  private func refreshAddress() {
    let hostname = ProcessInfo.processInfo.hostName
    address.stringValue = "http://\(hostname):\(configuration.port)/upload"
  }

  private func refreshFolder() {
    folder.stringValue = (selectedDirectory.path as NSString).abbreviatingWithTildeInPath
    folder.toolTip = selectedDirectory.path
  }

  private func updatePending() {
    let enteredPort = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces))
    let changed = selectedDirectory != configuration.directory || enteredPort != configuration.port
    pending.stringValue = changed ? "有未应用的更改" : ""
    save.isEnabled = changed && !isApplying
  }

  private func updateShortcutName() {
    do {
      let name = try ShortcutInstaller.normalizedName(shortcutName.stringValue)
      UserDefaults.standard.set(name, forKey: shortcutNamePreference)
      shortcutNameStatus.stringValue = "将使用「\(name)」；首尾空白已移除，/ 和 : 会替换为 -。"
      shortcutNameStatus.textColor = .secondaryLabelColor
      shortcutNameStatus.isHidden = name == shortcutName.stringValue
      send.isEnabled = !isSending
    } catch {
      shortcutNameStatus.stringValue = error.localizedDescription
      shortcutNameStatus.textColor = .systemRed
      shortcutNameStatus.isHidden = false
      send.isEnabled = false
    }
  }

  private func setSending(_ value: Bool) {
    isSending = value
    shortcutName.isEnabled = !value
    updateShortcutName()
  }

  func controlTextDidChange(_ notification: Notification) {
    if let field = notification.object as? NSTextField, field === shortcutName {
      updateShortcutName()
    } else {
      updatePending()
    }
  }

  @objc private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = selectedDirectory
    if panel.runModal() == .OK, let url = panel.url {
      selectedDirectory = url
      refreshFolder()
      updatePending()
    }
  }

  @objc private func saveSettings() {
    guard !isApplying, save.isEnabled else { return }
    guard let value = UInt16(port.stringValue.trimmingCharacters(in: .whitespaces)), value >= 1024
    else {
      receivingError.stringValue = "端口需为 1024–65535 之间的整数。"
      receivingError.isHidden = false
      return
    }
    var next = configuration
    next.port = value
    next.directory = selectedDirectory
    isApplying = true
    receivingError.isHidden = true
    updatePending()
    Task {
      defer {
        isApplying = false
        updatePending()
      }
      do {
        try await apply?(next)
        configuration = next
        refreshAddress()
      } catch {
        receivingError.stringValue = error.localizedDescription
        receivingError.isHidden = false
      }
    }
  }

  @objc private func toggleLogin() {
    generalStatus.isHidden = true
    do {
      if login.state == .on {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      if SMAppService.mainApp.status == .requiresApproval {
        generalStatus.stringValue = "请在系统设置的「登录项」中允许 SnapDock。"
        generalStatus.isHidden = false
      }
    } catch {
      login.state = SMAppService.mainApp.status == .enabled ? .on : .off
      generalStatus.stringValue = "无法更改登录项：\(error.localizedDescription)"
      generalStatus.isHidden = false
    }
  }

  @objc private func changeColumns() {
    guard columns.selectedSegment >= 0 else { return }
    columnsChanged?(columns.selectedSegment + 2)
  }

  @objc private func copyConnectionAddress() { copy(address.stringValue) }
  @objc private func copyToken() { copy(configuration.token) }
  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
  }

  private func showConnectionMessage(_ text: String, isError: Bool = true) {
    connectionStatus.stringValue = text
    connectionStatus.textColor = isError ? .systemRed : .secondaryLabelColor
    connectionStatus.isHidden = false
  }

  @objc private func sendToPhone() {
    guard send.isEnabled else { return }
    if sharedFile != nil, !cleanUpSharedFile() { return }
    guard let service = NSSharingService(named: .sendViaAirDrop) else {
      showConnectionMessage("此 Mac 无法使用 AirDrop。请使用下方的手动设置。")
      return
    }
    guard
      let template = Bundle.main.url(
        forResource: "Template", withExtension: "shortcut", subdirectory: "Shortcuts")
    else {
      showConnectionMessage("快捷指令模板缺失，请重新构建完整 App。仍可使用下方的手动设置。")
      return
    }
    guard let name = try? ShortcutInstaller.normalizedName(shortcutName.stringValue) else {
      updateShortcutName()
      return
    }
    shortcutName.stringValue = name
    let receiveAddress = address.stringValue
    let key = configuration.token
    setSending(true)
    showConnectionMessage("正在生成并签名快捷指令…", isError: false)
    Task {
      do {
        let file = try await Task.detached {
          try ShortcutInstaller.prepare(
            templateURL: template, address: receiveAddress, key: key, name: name)
        }.value
        sharedFile = file
        guard service.canPerform(withItems: [file]) else {
          if cleanUpSharedFile() {
            showConnectionMessage("AirDrop 当前不可用，请检查 Wi-Fi 与蓝牙，或使用手动设置。")
          }
          setSending(false)
          return
        }
        sharingService = service
        service.delegate = self
        showConnectionMessage("请选择自己的 iPhone，接收后点「添加快捷指令」。", isError: false)
        service.perform(withItems: [file])
      } catch {
        showConnectionMessage("无法发送快捷指令：\(error.localizedDescription)")
        setSending(false)
      }
    }
  }

  private func cleanUpSharedFile() -> Bool {
    guard let file = sharedFile else { return true }
    do {
      try ShortcutInstaller.cleanUp(file)
      sharedFile = nil
      return true
    } catch {
      showConnectionMessage("无法清理含密钥的临时文件：\(error.localizedDescription)。请点击发送按钮重试清理。")
      return false
    }
  }

  func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
    self.sharingService = nil
    setSending(false)
    if cleanUpSharedFile() {
      showConnectionMessage("快捷指令已发送；请在 iPhone 上添加后分享图片试用。", isError: false)
    }
  }

  func sharingService(
    _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error
  ) {
    self.sharingService = nil
    setSending(false)
    if cleanUpSharedFile() {
      showConnectionMessage("AirDrop 未完成：\(error.localizedDescription)。可重试或使用手动设置。")
    }
  }

  func sharingService(
    _ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
    sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>
  ) -> NSWindow? {
    window
  }

  @objc private func exportShortcut() {
    guard
      let source = Bundle.main.url(
        forResource: "发送到 Mac", withExtension: "shortcut", subdirectory: "Shortcuts")
    else {
      showConnectionMessage("快捷指令资源缺失，请重新构建完整 App。")
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "发送到 Mac.shortcut"
    if panel.runModal() == .OK, let destination = panel.url {
      do {
        try Data(contentsOf: source).write(to: destination, options: .atomic)
        NSWorkspace.shared.activateFileViewerSelecting([destination])
      } catch { showConnectionMessage("导出失败：\(error.localizedDescription)") }
    }
  }
}

@MainActor
private final class SettingsGroup: NSView {
  override func draw(_ dirtyRect: NSRect) {
    let shape = NSBezierPath(
      roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
    NSColor.controlBackgroundColor.setFill()
    shape.fill()
    NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
    shape.lineWidth = 0.5
    shape.stroke()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    needsDisplay = true
  }
}
