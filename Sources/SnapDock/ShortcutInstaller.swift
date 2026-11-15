import Foundation

struct ShortcutInstallationError: LocalizedError {
  let reason: String
  var errorDescription: String? { reason }
}

enum ShortcutInstaller {
  static func normalizedName(_ name: String) throws -> String {
    let result = name.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "/", with: "-")
      .replacingOccurrences(of: ":", with: "-")
    guard !result.isEmpty else {
      throw ShortcutInstallationError(reason: "请输入快捷指令名称。")
    }
    guard result.rangeOfCharacter(from: .controlCharacters) == nil else {
      throw ShortcutInstallationError(reason: "快捷指令名称不能包含换行或控制字符。")
    }
    guard result.count <= 60, result.utf8.count <= 240 else {
      throw ShortcutInstallationError(reason: "快捷指令名称过长，请缩短到 60 个字符以内；复杂表情可能需要更短。")
    }
    return result
  }

  static func personalized(template: Data, address: String, key: String, name: String) throws
    -> Data
  {
    let shortcutName = try normalizedName(name)
    guard
      var shortcut = try PropertyListSerialization.propertyList(from: template, format: nil)
        as? [String: Any],
      var actions = shortcut["WFWorkflowActions"] as? [[String: Any]], actions.count >= 2
    else {
      throw ShortcutInstallationError(reason: "快捷指令模板无效，请重新构建完整 App。")
    }
    for (index, value) in [address, key].enumerated() {
      guard
        actions[index]["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.gettext",
        var parameters = actions[index]["WFWorkflowActionParameters"] as? [String: Any]
      else {
        throw ShortcutInstallationError(reason: "快捷指令模板缺少连接字段，请重新构建完整 App。")
      }
      parameters["WFTextActionText"] = value
      actions[index]["WFWorkflowActionParameters"] = parameters
    }
    shortcut["WFWorkflowName"] = shortcutName
    shortcut["WFWorkflowActions"] = actions
    shortcut["WFWorkflowImportQuestions"] = []
    return try PropertyListSerialization.data(fromPropertyList: shortcut, format: .xml, options: 0)
  }

  static func prepare(templateURL: URL, address: String, key: String, name: String) throws -> URL {
    let shortcutName = try normalizedName(name)
    let data = try personalized(
      template: Data(contentsOf: templateURL), address: address, key: key, name: shortcutName)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "SnapDock-Shortcut-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let inputDirectory = directory.appendingPathComponent("Input", isDirectory: true)
    let unsigned = inputDirectory.appendingPathComponent("unsigned.shortcut")
    let signed = directory.appendingPathComponent(shortcutName).appendingPathExtension("shortcut")
    do {
      try FileManager.default.createDirectory(
        at: inputDirectory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
      try data.write(to: unsigned, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: unsigned.path)
      try sign(
        unsigned: unsigned, signed: signed,
        workingDirectory: templateURL.deletingLastPathComponent(), key: key)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: signed.path)
      try FileManager.default.removeItem(at: inputDirectory)
      return signed
    } catch {
      do {
        try FileManager.default.removeItem(at: directory)
      } catch {
        throw ShortcutInstallationError(reason: "无法清理快捷指令临时文件：\(error.localizedDescription)")
      }
      throw error
    }
  }

  static func cleanUp(_ file: URL) throws {
    try FileManager.default.removeItem(at: file.deletingLastPathComponent())
  }

  private static func sign(unsigned: URL, signed: URL, workingDirectory: URL, key: String) throws {
    let log = unsigned.deletingLastPathComponent().appendingPathComponent("signing.log")
    guard
      FileManager.default.createFile(
        atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
    else {
      throw ShortcutInstallationError(reason: "无法创建签名临时文件。")
    }
    let output = try FileHandle(forWritingTo: log)
    defer { try? output.close() }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    process.arguments = [
      "sign", "--mode", "anyone", "--input", unsigned.path, "--output", signed.path,
    ]
    process.currentDirectoryURL = workingDirectory
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let deadline = Date().addingTimeInterval(60)
    while process.isRunning, Date() < deadline {
      Thread.sleep(forTimeInterval: 0.1)
    }
    if process.isRunning {
      process.terminate()
      process.waitUntilExit()
      throw ShortcutInstallationError(reason: "系统签名超过 60 秒，请检查网络与 Apple 账户后重试，或使用手动设置。")
    }
    process.waitUntilExit()
    let diagnostic = String(decoding: try Data(contentsOf: log), as: UTF8.self)
      .replacingOccurrences(of: key, with: "[已隐藏]")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try FileManager.default.removeItem(at: log)
    guard process.terminationStatus == 0 else {
      throw ShortcutInstallationError(
        reason: "系统签名失败（退出码 \(process.terminationStatus)）：\(diagnostic.prefix(500))。可继续使用手动设置。")
    }
    guard
      FileManager.default.fileExists(atPath: signed.path),
      (try Data(contentsOf: signed)).isEmpty == false
    else {
      throw ShortcutInstallationError(reason: "系统签名未生成快捷指令文件。可继续使用手动设置。")
    }
  }
}
