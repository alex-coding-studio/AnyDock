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
      throw ShortcutInstallationError(reason: L10n.text("Enter a shortcut name."))
    }
    guard result.rangeOfCharacter(from: .controlCharacters) == nil else {
      throw ShortcutInstallationError(reason: L10n.text("shortcut.name.invalidCharacters"))
    }
    guard result.count <= 60, result.utf8.count <= 240 else {
      throw ShortcutInstallationError(reason: L10n.text("shortcut.name.tooLong"))
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
      throw ShortcutInstallationError(reason: L10n.text("shortcut.template.invalid"))
    }
    for (index, value) in [address, key].enumerated() {
      guard
        actions[index]["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.gettext",
        var parameters = actions[index]["WFWorkflowActionParameters"] as? [String: Any]
      else {
        throw ShortcutInstallationError(reason: L10n.text("shortcut.template.missingFields"))
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
        throw ShortcutInstallationError(
          reason: L10n.text(
            "Unable to remove temporary shortcut files: %@", error.localizedDescription))
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
      throw ShortcutInstallationError(reason: L10n.text("shortcut.signing.fileFailed"))
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
      throw ShortcutInstallationError(reason: L10n.text("shortcut.signing.timeout"))
    }
    process.waitUntilExit()
    let diagnostic = String(decoding: try Data(contentsOf: log), as: UTF8.self)
      .replacingOccurrences(of: key, with: L10n.text("[redacted]"))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try FileManager.default.removeItem(at: log)
    guard process.terminationStatus == 0 else {
      throw ShortcutInstallationError(
        reason: L10n.text(
          "shortcut.signing.failed", Int(process.terminationStatus), String(diagnostic.prefix(500))
        ))
    }
    guard
      FileManager.default.fileExists(atPath: signed.path),
      (try Data(contentsOf: signed)).isEmpty == false
    else {
      throw ShortcutInstallationError(reason: L10n.text("shortcut.signing.noOutput"))
    }
  }
}
