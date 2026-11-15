import importlib.util
import pathlib
import plistlib
import unittest
import subprocess
import tempfile
from decimal import Decimal, ROUND_FLOOR

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
        shortcut = module.make_shortcut("http://test-mac.local:9876/upload", "fixture-secret",
                                        name="fixture-validation", questions=False)
        self.assertEqual(shortcut["WFWorkflowName"], "fixture-validation")
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

    def test_every_value_condition_has_text_input_and_a_comparison_value(self):
        actions = module.make_shortcut("http://Mac.local:8765/upload", "test-key")["WFWorkflowActions"]
        by_uuid = {a["WFWorkflowActionParameters"]["UUID"]: a for a in actions}
        checked = 0
        for action in actions:
            p = action["WFWorkflowActionParameters"]
            if action["WFWorkflowActionIdentifier"] != "is.workflow.actions.conditional" or p.get("WFControlFlowMode") != 0:
                continue
            if p["WFCondition"] in {100, 101}:
                continue
            checked += 1
            value = p.get("WFConditionalActionString")
            self.assertTrue(value, "A text comparison must have a value")
            if isinstance(value, dict):
                content = value["Value"]
                self.assertTrue(content["string"])
                self.assertTrue(content.get("attachmentsByRange"))
            reference = p["WFInput"]["Variable"]["Value"]
            source = by_uuid[reference["OutputUUID"]]
            self.assertEqual(source["WFWorkflowActionIdentifier"], "is.workflow.actions.gettext")
        self.assertGreater(checked, 0)

    def test_size_precheck_accepts_limit_and_rejects_one_byte_over(self):
        actions = module.make_shortcut("http://Mac.local:8765/upload", "test-key")["WFWorkflowActions"]
        by_uuid = {a["WFWorkflowActionParameters"]["UUID"]: a for a in actions}
        guard = next(a["WFWorkflowActionParameters"] for a in actions
                     if a["WFWorkflowActionIdentifier"] == "is.workflow.actions.conditional"
                     and a["WFWorkflowActionParameters"].get("WFConditionalActionString") == "0")

        def evaluate(reference, size):
            action = by_uuid[reference["OutputUUID"]]
            p = action["WFWorkflowActionParameters"]
            name = action["WFWorkflowActionIdentifier"].removeprefix("is.workflow.actions.")
            if name == "properties.files":
                return Decimal(size)
            if name == "gettext":
                token = p["WFTextActionText"]["Value"]["attachmentsByRange"]["{0, 1}"]
                return str(evaluate(token, size))
            value = evaluate(p["WFInput"]["Value"], size)
            if name == "math":
                operand = Decimal(p["WFMathOperand"])
                operations = {"+": lambda a, b: a + b, "÷": lambda a, b: a / b}
                return operations[p["WFMathOperation"]](value, operand)
            self.assertEqual(name, "round")
            self.assertEqual(p["WFRoundTo"], "Ones Place")
            self.assertEqual(p["WFRoundMode"], "Always Round Down")
            return value.to_integral_value(rounding=ROUND_FLOOR)

        reference = guard["WFInput"]["Variable"]["Value"]
        for size, accepted in [(0, True), (49_999_999, True), (50_000_000, True),
                               (50_000_001, False), (200_000_000, False)]:
            self.assertEqual(evaluate(reference, size) == guard["WFConditionalActionString"], accepted)

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
        guards = [p for i, (n, p) in enumerate(zip(names, parameters))
                  if i < repeats[1][0] and n == "conditional" and p.get("WFConditionalActionString") == "0"]
        self.assertEqual(len(guards), 1)
        guard = guards[0]
        guard_else = next(i for i, p in enumerate(parameters) if p.get("GroupingIdentifier") == guard["GroupingIdentifier"]
                          and p.get("WFControlFlowMode") == 1)
        guard_end = next(i for i, p in enumerate(parameters) if p.get("GroupingIdentifier") == guard["GroupingIdentifier"]
                         and p.get("WFControlFlowMode") == 2)
        self.assertLess(upload_index, guard_else)
        self.assertLess(guard_else, guard_end)
        self.assertLess(guard_end, repeats[1][0])
        checked_codes = {p.get("WFConditionalActionString") for n, p in zip(names, parameters)
                         if n == "conditional" and isinstance(p.get("WFConditionalActionString"), str)}
        self.assertTrue({"401", "413", "415"} <= checked_codes)
        notifications = [i for i, n in enumerate(names) if n == "notification"]
        self.assertEqual(len(notifications), 1)
        self.assertGreater(notifications[0], repeats[1][0])
        self.assertEqual(parameters[notifications[0]]["WFNotificationActionTitle"], "随手坞")
        defined = {p["WFVariableName"] for n, p in zip(names, parameters) if n == "setvariable"}
        self.assertTrue({"Success", "Failure", "Oversize", "Unauthorized", "Unsupported", "Other"} <= defined)
        self.assertEqual([q["ActionIndex"] for q in shortcut["WFWorkflowImportQuestions"]], [0, 1])

    def test_summary_lists_only_failure_reasons_with_nonzero_counts(self):
        actions = module.make_shortcut("http://Mac.local:8765/upload", "test-key")["WFWorkflowActions"]
        names = [a["WFWorkflowActionIdentifier"].removeprefix("is.workflow.actions.") for a in actions]
        loop_end = max(i for i, n in enumerate(names) if n == "repeat.each")
        tail = [a["WFWorkflowActionParameters"] for a in actions[loop_end + 1:]]
        tail_names = names[loop_end + 1:]

        def run(counters):
            variables = dict(counters)
            outputs = {}

            def resolve(token):
                if token["Type"] == "Variable":
                    return variables[token["VariableName"]]
                return outputs[token["OutputUUID"]]

            def render(value):
                if isinstance(value, str):
                    return value
                content = value["Value"]
                result = content["string"]
                for key in sorted(content.get("attachmentsByRange", {}),
                                  key=lambda k: int(k.strip("{}").split(",")[0]), reverse=True):
                    offset = int(key.strip("{}").split(",")[0])
                    result = result[:offset] + str(resolve(content["attachmentsByRange"][key])) + result[offset + 1:]
                return result

            def skip_to(group, modes, index):
                return next(j for j in range(index + 1, len(tail)) if tail[j].get("GroupingIdentifier") == group
                            and tail[j].get("WFControlFlowMode") in modes)

            index = 0
            body = None
            while index < len(tail):
                name, p = tail_names[index], tail[index]
                if name == "gettext":
                    outputs[p["UUID"]] = render(p["WFTextActionText"])
                elif name == "setvariable":
                    variables[p["WFVariableName"]] = resolve(p["WFInput"]["Value"])
                elif name == "conditional" and p["WFControlFlowMode"] == 0:
                    self.assertEqual(p["WFCondition"], 4)
                    value = str(resolve(p["WFInput"]["Variable"]["Value"]))
                    if value != p["WFConditionalActionString"]:
                        index = skip_to(p["GroupingIdentifier"], {1, 2}, index)
                elif name == "conditional" and p["WFControlFlowMode"] == 1:
                    index = skip_to(p["GroupingIdentifier"], {2}, index)
                elif name == "notification":
                    body = render(p["WFNotificationActionBody"])
                index += 1
            return body

        zero = {"Success": 0, "Failure": 0, "Oversize": 0, "Unauthorized": 0, "Unsupported": 0, "Other": 0}
        self.assertEqual(run({**zero, "Success": 6}), "成功 6 项")
        self.assertEqual(run({**zero, "Success": 5, "Failure": 1, "Oversize": 1}),
                         "成功 5 项，失败 1 项：超过 50MB 1 项")
        self.assertEqual(run({**zero, "Failure": 3, "Unauthorized": 2, "Other": 1}),
                         "成功 0 项，失败 3 项：密钥无效 2 项，其他错误 1 项")


if __name__ == "__main__":
    unittest.main()
