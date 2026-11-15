import Foundation

public enum TrayFilter: Hashable, Sendable {
  case all
  case kind(ReceivedKind)

  public func includes(_ kind: ReceivedKind) -> Bool {
    self == .all || self == .kind(kind)
  }
}

public struct TrayContents: Sendable {
  public private(set) var items: [ReceivedItem] = []
  public private(set) var filter: TrayFilter = .all

  public init() {}

  public var visibleItems: [ReceivedItem] {
    items.filter { filter.includes($0.kind) }
  }

  public func count(of kind: ReceivedKind) -> Int {
    items.filter { $0.kind == kind }.count
  }

  public var availableFilters: [TrayFilter] {
    [.all] + ReceivedKind.allCases.filter { count(of: $0) > 0 }.map { .kind($0) }
  }

  public mutating func select(_ next: TrayFilter) {
    filter = availableFilters.contains(next) ? next : .all
  }

  public mutating func replace(_ next: [ReceivedItem]) {
    items = next
    select(filter)
  }

  public mutating func receive(_ item: ReceivedItem, limit: Int = 120) {
    items = Array(([item] + items.filter { $0.url != item.url }).prefix(limit))
    if !filter.includes(item.kind) { filter = .all }
  }

  public func trashTargets(selected: [URL]) -> [URL] {
    selected.isEmpty ? visibleItems.map(\.url) : selected
  }
}
