import AppKit
import Testing

@testable import AnyDock

@MainActor
private func textFields(in view: NSView) -> [NSTextField] {
  view.subviews.flatMap { ($0 as? NSTextField).map { [$0] } ?? textFields(in: $0) }
}

@MainActor
@Test("卡片里的文字不能被鼠标选中或编辑，按下文字也是在拖动卡片")
func cardTextIsNotSelectable() {
  let cards: [TrayCardItem] = [TextCardItem(), LinkCardItem(), FileCardItem(), ImageCardItem()]
  for card in cards {
    let fields = textFields(in: card.view)
    #expect(!fields.isEmpty, "\(type(of: card))")
    for field in fields {
      #expect(!field.isSelectable && !field.isEditable, "\(type(of: card)) \(field.stringValue)")
    }
  }
}
