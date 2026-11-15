#!/usr/bin/env python3
import argparse
import pathlib
import plistlib
import uuid


def attachment(value):
    return {"Value": value, "WFSerializationType": "WFTextTokenAttachment"}


def text(value=None, reference=None):
    content = {"string": value if reference is None else "\ufffc"}
    if reference is not None:
        content["attachmentsByRange"] = {"{0, 1}": reference}
    return {"Value": content, "WFSerializationType": "WFTextTokenString"}


def dictionary(items):
    return {
        "Value": {"WFDictionaryFieldValueItems": [
            {"WFItemType": 0, "WFKey": text(key), "WFValue": value}
            for key, value in items
        ]},
        "WFSerializationType": "WFDictionaryFieldValue",
    }


def make_shortcut(url, key, name="发送到 Mac", questions=True):
    actions = []

    def action(identifier, **parameters):
        output_id = str(uuid.uuid4()).upper()
        actions.append({"WFWorkflowActionIdentifier": "is.workflow.actions." + identifier,
                        "WFWorkflowActionParameters": {"UUID": output_id, **parameters}})
        return {"Type": "ActionOutput", "OutputUUID": output_id, "OutputName": "Result"}

    destination = action("gettext", WFTextActionText=url)
    secret = action("gettext", WFTextActionText=key)
    repeat_group = str(uuid.uuid4()).upper()
    error_group = str(uuid.uuid4()).upper()
    empty_group = str(uuid.uuid4()).upper()
    action("conditional", WFInput={"Type": "Variable", "Variable": attachment({"Type": "ExtensionInput"})},
           WFCondition=101, GroupingIdentifier=empty_group, WFControlFlowMode=0)
    action("alert", WFAlertActionTitle="先选择图片", WFAlertActionMessage="请在照片中选图，再通过分享菜单运行「发送到 Mac」。", WFAlertActionCancelButtonShown=False)
    action("exit")
    action("conditional", GroupingIdentifier=empty_group, WFControlFlowMode=2)
    action("repeat.each", WFInput=attachment({"Type": "ExtensionInput"}),
           GroupingIdentifier=repeat_group, WFControlFlowMode=0)
    response = action(
        "downloadurl", WFURL=text(reference=destination), WFHTTPMethod="POST",
        WFHTTPBodyType="File", WFFormValues=dictionary([]),
        WFRequestVariable=attachment({"Type": "Variable", "VariableName": "Repeat Item"}),
        WFHTTPHeaders=dictionary([("X-SnapDock-Key", text(reference=secret))]),
    )
    error = action("getvalueforkey", WFDictionaryKey="error", WFInput=attachment(response))
    action("conditional", WFInput={"Type": "Variable", "Variable": attachment(error)}, WFCondition=100,
           GroupingIdentifier=error_group, WFControlFlowMode=0)
    action("alert", WFAlertActionTitle="发送失败", WFAlertActionMessage="Mac 没有保存这张图片。请检查接收地址、密钥和 Mac 的设置。", WFAlertActionCancelButtonShown=False)
    action("exit")
    action("conditional", GroupingIdentifier=error_group, WFControlFlowMode=2)
    action("repeat.each", GroupingIdentifier=repeat_group, WFControlFlowMode=2)
    action("notification", WFNotificationActionTitle="SnapDock", WFNotificationActionBody="图片已发送到 Mac", WFNotificationActionSound=False)
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "2700",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59799},
        "WFWorkflowTypes": ["ActionExtension"],
        "WFWorkflowInputContentItemClasses": ["WFImageContentItem"],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [
            {"Category": "Parameter", "ActionIndex": index, "ParameterKey": "WFTextActionText", "Text": prompt, "DefaultValue": default}
            for index, prompt, default in [
                (0, "粘贴 SnapDock 设置中的接收地址", url),
                (1, "粘贴 SnapDock 设置中的连接密钥", key),
            ]
        ] if questions else [],
        "WFWorkflowActions": actions,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate the unsigned SnapDock Share Sheet shortcut.")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--url", default="http://Mac.local:8765/upload")
    parser.add_argument("--key", default="PASTE_CONNECTION_KEY")
    parser.add_argument("--name", default="发送到 Mac")
    parser.add_argument("--no-import-questions", action="store_true")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(plistlib.dumps(make_shortcut(args.url, args.key, args.name, not args.no_import_questions)))
