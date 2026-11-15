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

    def test_upload_repeats_images_and_checks_saved_before_success(self):
        shortcut = plistlib.loads(plistlib.dumps(module.make_shortcut("http://Mac.local:8765/upload", "test-key")))
        self.assertEqual(shortcut["WFWorkflowTypes"], ["ActionExtension"])
        self.assertEqual(shortcut["WFWorkflowInputContentItemClasses"], ["WFImageContentItem"])
        actions = shortcut["WFWorkflowActions"]
        parameters = [a["WFWorkflowActionParameters"] for a in actions]
        names = [a["WFWorkflowActionIdentifier"].removeprefix("is.workflow.actions.") for a in actions]
        upload = parameters[names.index("downloadurl")]
        self.assertEqual(upload["WFHTTPMethod"], "POST")
        self.assertEqual(upload["WFHTTPBodyType"], "File")
        self.assertEqual(upload["WFRequestVariable"]["Value"]["VariableName"], "Repeat Item")
        self.assertEqual(parameters[names.index("getvalueforkey")]["WFDictionaryKey"], "error")
        self.assertLess(names.index("exit"), names.index("notification"))
        repeats = [p for n, p in zip(names, parameters) if n == "repeat.each"]
        self.assertEqual([p["WFControlFlowMode"] for p in repeats], [0, 2])
        self.assertEqual(repeats[0]["GroupingIdentifier"], repeats[1]["GroupingIdentifier"])
        self.assertEqual([q["ActionIndex"] for q in shortcut["WFWorkflowImportQuestions"]], [0, 1])
        conditions = [p for n, p in zip(names, parameters) if n == "conditional" and p["WFControlFlowMode"] == 0]
        self.assertEqual(conditions[0]["WFCondition"], 101)
        self.assertEqual(conditions[0]["WFInput"]["Variable"]["Value"]["Type"], "ExtensionInput")
        self.assertEqual(conditions[1]["WFCondition"], 100)
        self.assertEqual(conditions[1]["WFInput"]["Type"], "Variable")


if __name__ == "__main__":
    unittest.main()
