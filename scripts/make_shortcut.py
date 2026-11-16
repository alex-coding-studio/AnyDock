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
    def variable(name):
        return {"Type": "Variable", "VariableName": name}

    def assign(name, value):
        action("setvariable", WFVariableName=name, WFInput=attachment(value))

    def literal(value):
        return action("gettext", WFTextActionText=value)

    def condition(value, operator, **parameters):
        if operator not in {100, 101}:
            value = action("gettext", WFTextActionText=text(reference=value))
        group = str(uuid.uuid4()).upper()
        action("conditional", WFInput={"Type": "Variable", "Variable": attachment(value)},
               WFCondition=operator, GroupingIdentifier=group, WFControlFlowMode=0, **parameters)
        return group

    def otherwise(group):
        action("conditional", GroupingIdentifier=group, WFControlFlowMode=1)

    def end(group):
        return action("conditional", GroupingIdentifier=group, WFControlFlowMode=2)

    def increment(name):
        value = action("math", WFInput=attachment(variable(name)), WFMathOperation="+", WFMathOperand=1)
        assign(name, value)

    def message(parts):
        value = ""
        references = {}
        for part in parts:
            if isinstance(part, str):
                value += part
            else:
                offset = len(value.encode("utf-16-le")) // 2
                references[f"{{{offset}, 1}}"] = part
                value += "\ufffc"
        return {"Value": {"string": value, "attachmentsByRange": references},
                "WFSerializationType": "WFTextTokenString"}

    source_group = condition({"Type": "ExtensionInput"}, 101)
    action("getclipboard")
    otherwise(source_group)
    action("getvariable", WFVariable=attachment({"Type": "ExtensionInput"}))
    source = end(source_group)
    zero = action("number", WFNumberActionNumber=0)
    for counter_name in ["Success", "Failure", "Oversize", "Unauthorized", "Unsupported", "Other"]:
        assign(counter_name, zero)
    text_sample = literal("AnyDock")
    text_type = action("getitemtype", WFInput=attachment(text_sample))
    rich_sample = action("getrichtextfrommarkdown", WFInput=attachment(text_sample))
    rich_type = action("getitemtype", WFInput=attachment(rich_sample))
    url_sample = action("url", WFURLActionURL="https://example.invalid")
    url_type = action("getitemtype", WFInput=attachment(url_sample))
    repeat_group = str(uuid.uuid4()).upper()
    action("repeat.each", WFInput=attachment(source),
           GroupingIdentifier=repeat_group, WFControlFlowMode=0)
    item = variable("Repeat Item")
    item_type = action("getitemtype", WFInput=attachment(item))
    assign("Kind", literal("file"))
    assign("Mime", literal("application/octet-stream"))
    assign("Body", item)
    for reference, kind, mime in [
        (url_type, "link", "text/uri-list"),
        (text_type, "text", "text/plain; charset=utf-8"),
        (rich_type, "text", "text/plain; charset=utf-8"),
    ]:
        group = condition(item_type, 4, WFConditionalActionString=text(reference=reference))
        assign("Kind", literal(kind))
        assign("Mime", literal(mime))
        assign("Filename", literal(""))
        converted = action("gettext", WFTextActionText=text(reference=item))
        assign("Body", converted)
        end(group)
    file_group = condition(variable("Kind"), 4, WFConditionalActionString="file")
    item_name = action("getitemname", WFInput=attachment(item), GetWebPageTitle=False)
    item_extension = action("properties.files", WFInput=attachment(item),
                            WFContentItemPropertyName="File Extension")
    encoded_name = action("urlencode", WFInput=message([item_name, ".", item_extension]), WFEncodeMode="Encode")
    assign("Filename", encoded_name)
    end(file_group)
    size = action("properties.files", WFInput=attachment(variable("Body")),
                  WFContentItemPropertyName="File Size")
    numeric_size = action("math", WFInput=attachment(size), WFMathOperation="+", WFMathOperand=0)
    ratio = action("math", WFInput=attachment(numeric_size), WFMathOperation="÷", WFMathOperand=50_000_001)
    oversize = action("round", WFInput=attachment(ratio), WFRoundTo="Ones Place", WFRoundMode="Always Round Down")
    size_group = condition(oversize, 4, WFConditionalActionString="0")
    response = action(
        "downloadurl", WFURL=text(reference=destination), WFHTTPMethod="POST",
        WFHTTPBodyType="File", WFFormValues=dictionary([]),
        WFRequestVariable=attachment(variable("Body")),
        WFHTTPHeaders=dictionary([
            ("X-AnyDock-Key", text(reference=secret)),
            ("X-AnyDock-Type", text(reference=variable("Kind"))),
            ("X-AnyDock-Filename", text(reference=variable("Filename"))),
            ("Content-Type", text(reference=variable("Mime"))),
        ]),
    )
    status = action("getvalueforkey", WFDictionaryKey="status", WFInput=attachment(response))
    success_group = condition(status, 4, WFConditionalActionString="saved")
    increment("Success")
    otherwise(success_group)
    increment("Failure")
    error = action("getvalueforkey", WFDictionaryKey="error", WFInput=attachment(response))
    error_groups = []
    for code, counter in [(413, "Oversize"), (401, "Unauthorized"), (415, "Unsupported")]:
        group = condition(error, 4, WFConditionalActionString=str(code))
        error_groups.append(group)
        increment(counter)
        otherwise(group)
    increment("Other")
    for group in reversed(error_groups):
        end(group)
    end(success_group)
    otherwise(size_group)
    increment("Failure")
    increment("Oversize")
    end(size_group)
    action("repeat.each", GroupingIdentifier=repeat_group, WFControlFlowMode=2)
    assign("Summary", action("gettext", WFTextActionText=message(["成功 ", variable("Success"), " 项"])))
    failure_group = condition(variable("Failure"), 4, WFConditionalActionString="0")
    otherwise(failure_group)
    assign("Details", literal(""))
    assign("Separator", literal(""))
    for counter, label in [("Oversize", "超过 50MB "), ("Unauthorized", "密钥无效 "),
                           ("Unsupported", "格式不支持 "), ("Other", "其他错误 ")]:
        group = condition(variable(counter), 4, WFConditionalActionString="0")
        otherwise(group)
        assign("Details", action("gettext", WFTextActionText=message([
            variable("Details"), variable("Separator"), label, variable(counter), " 项"])))
        assign("Separator", literal("，"))
        end(group)
    assign("Summary", action("gettext", WFTextActionText=message([
        variable("Summary"), "，失败 ", variable("Failure"), " 项：", variable("Details")])))
    end(failure_group)
    action("notification", WFNotificationActionTitle="随手坞",
           WFNotificationActionBody=message([variable("Summary")]), WFNotificationActionSound=False)
    return {
        "WFWorkflowName": name,
        "WFWorkflowClientVersion": "2700",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59799},
        "WFWorkflowTypes": ["ActionExtension"],
        "WFWorkflowInputContentItemClasses": [
            "WFImageContentItem", "WFStringContentItem", "WFRichTextContentItem",
            "WFURLContentItem", "WFSafariWebPageContentItem", "WFGenericFileContentItem",
            "WFPDFContentItem", "WFAVAssetContentItem",
        ],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowHasShortcutInputVariables": True,
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowImportQuestions": [
            {"Category": "Parameter", "ActionIndex": index, "ParameterKey": "WFTextActionText", "Text": prompt, "DefaultValue": default}
            for index, prompt, default in [
                (0, "粘贴随手坞设置中的接收地址", url),
                (1, "粘贴随手坞设置中的连接密钥", key),
            ]
        ] if questions else [],
        "WFWorkflowActions": actions,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate the unsigned AnyDock Share Sheet shortcut.")
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--url", default="http://Mac.local:8765/upload")
    parser.add_argument("--key", default="PASTE_CONNECTION_KEY")
    parser.add_argument("--name", default="发送到 Mac")
    parser.add_argument("--no-import-questions", action="store_true")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(plistlib.dumps(make_shortcut(args.url, args.key, args.name, not args.no_import_questions)))
