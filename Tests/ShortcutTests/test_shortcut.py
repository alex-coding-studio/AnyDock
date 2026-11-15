import importlib.util
import pathlib
import plistlib
import unittest
import subprocess
import tempfile

path = pathlib.Path(__file__).resolve().parents[2] / "scripts/make_shortcut.py"
spec = importlib.util.spec_from_file_location("make_shortcut", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ShortcutTests(unittest.TestCase):
    def test_runtime_template_personalization_and_cleanup(self):
        root = path.parents[1]
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            template = directory / "template.shortcut"
            template.write_bytes(plistlib.dumps(module.make_shortcut("http://Mac.local:8765/upload", "PASTE_CONNECTION_KEY")))
            executable = directory / "installer-checks"
            subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library",
                            str(root / "Sources/AnyDock/ShortcutInstaller.swift"),
                            str(root / "Sources/AnyDock/Localization.swift"),
                            str(root / "Tests/ShortcutTests/InstallerChecks.swift"),
                            "-o", str(executable)], check=True, capture_output=True)
            subprocess.run([str(executable), str(template)], check=True, capture_output=True)

    def test_personalized_shortcut_has_no_import_questions_and_preserves_upload_references(self):
        shortcut = module.make_shortcut("http://test-mac.local:9876/upload", "fixture-secret", questions=False)
        actions = shortcut["WFWorkflowActions"]
        self.assertEqual(shortcut["WFWorkflowImportQuestions"], [])
        self.assertEqual([action["WFWorkflowActionParameters"]["WFTextActionText"] for action in actions[:2]],
                         ["http://test-mac.local:9876/upload", "fixture-secret"])
        upload = next(action["WFWorkflowActionParameters"] for action in actions
                      if action["WFWorkflowActionIdentifier"] == "is.workflow.actions.downloadurl")
        self.assertEqual(upload["WFURL"]["Value"]["attachmentsByRange"]["{0, 1}"]["OutputUUID"],
                         actions[0]["WFWorkflowActionParameters"]["UUID"])
        self.assertEqual(upload["WFHTTPHeaders"]["Value"]["WFDictionaryFieldValueItems"][0]
                         ["WFValue"]["Value"]["attachmentsByRange"]["{0, 1}"]["OutputUUID"],
                         actions[1]["WFWorkflowActionParameters"]["UUID"])

    def test_mixed_items_use_clipboard_fallback_and_continue_after_recoverable_failures(self):
        shortcut = plistlib.loads(plistlib.dumps(module.make_shortcut("http://Mac.local:8765/upload", "test-key")))
        classes = shortcut["WFWorkflowInputContentItemClasses"]
        self.assertNotIn("WFContentItem", classes)
        self.assertEqual(set(classes), {
            "WFImageContentItem", "WFStringContentItem", "WFRichTextContentItem",
            "WFURLContentItem", "WFSafariWebPageContentItem", "WFGenericFileContentItem",
            "WFPDFContentItem", "WFAVAssetContentItem",
        })
        actions = shortcut["WFWorkflowActions"]
        parameters = [a["WFWorkflowActionParameters"] for a in actions]
        names = [a["WFWorkflowActionIdentifier"].removeprefix("is.workflow.actions.") for a in actions]
        self.assertNotIn("alert", names)
        self.assertNotIn("exit", names)
        repeats = [(i, p) for i, (n, p) in enumerate(zip(names, parameters)) if n == "repeat.each"]
        self.assertEqual([p["WFControlFlowMode"] for _, p in repeats], [0, 2])
        self.assertEqual(repeats[0][1]["GroupingIdentifier"], repeats[1][1]["GroupingIdentifier"])
        source_uuid = repeats[0][1]["WFInput"]["Value"]["OutputUUID"]
        source = next(p for p in parameters if p["UUID"] == source_uuid)
        self.assertEqual(source["WFControlFlowMode"], 2)
        self.assertLess(names.index("getclipboard"), repeats[0][0])
        clipboard_group = source["GroupingIdentifier"]
        self.assertEqual([p["WFControlFlowMode"] for n, p in zip(names, parameters)
                          if n == "conditional" and p.get("GroupingIdentifier") == clipboard_group], [0, 1, 2])
        upload_index = names.index("downloadurl")
        upload = parameters[upload_index]
        self.assertEqual(upload["WFHTTPMethod"], "POST")
        self.assertEqual(upload["WFHTTPBodyType"], "File")
        self.assertEqual(upload["WFRequestVariable"]["Value"]["VariableName"], "Body")
        fields = upload["WFHTTPHeaders"]["Value"]["WFDictionaryFieldValueItems"]
        headers = {f["WFKey"]["Value"]["string"]: f["WFValue"] for f in fields}
        self.assertEqual(headers["X-AnyDock-Filename"]["Value"]["attachmentsByRange"]["{0, 1}"]["VariableName"], "Filename")
        guards = [p for n, p in zip(names, parameters) if n == "conditional" and p.get("WFCondition") == 2]
        self.assertEqual(len(guards), 1)
        guard = guards[0]
        guard_else = next(i for i, p in enumerate(parameters) if p.get("GroupingIdentifier") == guard["GroupingIdentifier"]
                          and p.get("WFControlFlowMode") == 1)
        guard_end = next(i for i, p in enumerate(parameters) if p.get("GroupingIdentifier") == guard["GroupingIdentifier"]
                         and p.get("WFControlFlowMode") == 2)
        self.assertLess(guard_else, upload_index)
        self.assertLess(upload_index, guard_end)
        self.assertLess(guard_end, repeats[1][0])
        checked_codes = {p["WFNumberValue"] for n, p in zip(names, parameters)
                         if n == "conditional" and p.get("WFCondition") == 4 and "WFNumberValue" in p}
        self.assertEqual(checked_codes, {401, 413, 415})
        notifications = [i for i, n in enumerate(names) if n == "notification"]
        self.assertEqual(len(notifications), 1)
        self.assertGreater(notifications[0], repeats[1][0])
        summary = parameters[notifications[0]]["WFNotificationActionBody"]["Value"]
        self.assertEqual({r["VariableName"] for r in summary["attachmentsByRange"].values()},
                         {"Success", "Failure", "Oversize", "Unauthorized", "Unsupported", "Other"})
        defined = {p["WFVariableName"] for n, p in zip(names, parameters) if n == "setvariable"}
        self.assertTrue({"Success", "Failure", "Oversize", "Unauthorized", "Unsupported", "Other"} <= defined)
        self.assertEqual([q["ActionIndex"] for q in shortcut["WFWorkflowImportQuestions"]], [0, 1])


if __name__ == "__main__":
    unittest.main()
