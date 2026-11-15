import Foundation

@main
struct InstallerChecks {
  static func main() throws {
    let template = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let result = try ShortcutInstaller.personalized(
      template: template, address: "http://fixture.local:9876/upload", key: "fixture-secret",
      name: "  发送到 Studio/Mac:书房  ")
    let shortcut = try PropertyListSerialization.propertyList(from: result, format: nil) as! [String: Any]
    precondition(shortcut["WFWorkflowName"] as? String == "发送到 Studio-Mac-书房")
    for invalidName in [" \n ", "发送到\0Mac", String(repeating: "长", count: 61),
                        String(repeating: "👨‍👩‍👧‍👦", count: 20)] {
      do {
        _ = try ShortcutInstaller.normalizedName(invalidName)
        preconditionFailure("Invalid names must fail")
      } catch is ShortcutInstallationError {}
    }
    let actions = shortcut["WFWorkflowActions"] as! [[String: Any]]
    let parameters = actions.prefix(2).map { $0["WFWorkflowActionParameters"] as! [String: Any] }
    precondition(parameters[0]["WFTextActionText"] as? String == "http://fixture.local:9876/upload")
    precondition(parameters[1]["WFTextActionText"] as? String == "fixture-secret")
    precondition((shortcut["WFWorkflowImportQuestions"] as! [Any]).isEmpty)
    let original = try PropertyListSerialization.propertyList(from: template, format: nil) as! [String: Any]
    let originalActions = original["WFWorkflowActions"] as! [[String: Any]]
    precondition(NSArray(array: Array(actions.dropFirst(2))).isEqual(to: Array(originalActions.dropFirst(2))))
    for invalid in [[:], ["WFWorkflowActions": [["WFWorkflowActionIdentifier": "wrong"], [:]]]] {
      let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .xml, options: 0)
      do {
        _ = try ShortcutInstaller.personalized(
          template: data, address: "fixture", key: "fixture-secret", name: "发送到 Mac")
        preconditionFailure("Invalid templates must fail")
      } catch is ShortcutInstallationError {}
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let file = directory.appendingPathComponent("fixture.shortcut")
    try result.write(to: file)
    try Data().write(to: directory.appendingPathComponent("unsigned.shortcut"))
    try ShortcutInstaller.cleanUp(file)
    precondition(!FileManager.default.fileExists(atPath: directory.path))
  }
}
