import Foundation
import Testing

@testable import AnyDockCore

private func item(_ name: String, _ kind: ReceivedKind) -> ReceivedItem {
  ReceivedItem(
    url: URL(fileURLWithPath: "/tmp/\(name)"), kind: kind, thumbnail: nil, receivedAt: Date(),
    isPlainText: false)
}

@Test("筛选只显示有内容的类型并给出数量，类型被清空后回到全部")
func filtersHideEmptyKindsAndCountItems() {
  var contents = TrayContents()
  contents.replace([item("a", .image), item("b", .text), item("c", .text)])
  #expect(contents.availableFilters == [.all, .kind(.image), .kind(.text)])
  #expect(contents.count(of: .text) == 2)
  contents.select(.kind(.link))
  #expect(contents.filter == .all)
  contents.select(.kind(.text))
  #expect(contents.visibleItems.map(\.url.lastPathComponent) == ["b", "c"])
  contents.replace([item("a", .image)])
  #expect(contents.filter == .all)
}

@Test("新内容在当前筛选下看不到时切回全部，看得到时保持筛选")
func arrivalOutsideFilterSwitchesToAll() {
  var contents = TrayContents()
  contents.replace([item("a", .image), item("b", .text)])
  contents.select(.kind(.text))
  contents.receive(item("c", .text))
  #expect(contents.filter == .kind(.text))
  #expect(contents.visibleItems.first?.url.lastPathComponent == "c")
  contents.receive(item("d", .link))
  #expect(contents.filter == .all)
  #expect(contents.items.first?.url.lastPathComponent == "d")
}
