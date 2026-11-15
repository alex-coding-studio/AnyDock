import AppKit
import Testing

@testable import AnyDock

@MainActor
private func textFields(in view: NSView) -> [NSTextField] {
  view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? textFields(in: $0) }
}

@MainActor
@Test("卡片和剪贴板格子里的文字不能被鼠标选中或编辑，按下文字也是在操作卡片或格子")
func cardTextIsNotSelectable() {
  let cards: [TrayCardItem] = [TextCardItem(), LinkCardItem(), FileCardItem(), ImageCardItem()]
  for view in cards.map(\.view) + [ClipboardCell()] {
    let fields = textFields(in: view)
    #expect(!fields.isEmpty, "\(type(of: view))")
    for field in fields {
      #expect(!field.isSelectable && !field.isEditable, "\(type(of: view)) \(field.stringValue)")
    }
  }
}
