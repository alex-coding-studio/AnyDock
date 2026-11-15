import AppKit

@MainActor
enum BrandIcon {
  static var artwork: NSImage? {
    Bundle.main.url(forResource: "SnapDockIcon", withExtension: "png", subdirectory: "Brand")
      .flatMap { NSImage(contentsOf: $0) }
  }

  static func menuBar() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let cord = NSBezierPath()
      cord.lineWidth = 1.25
      cord.lineCapStyle = .round
      cord.setLineDash([1.1, 1.35], count: 2, phase: 0)
      cord.move(to: NSPoint(x: 2.4, y: 3.1))
      cord.line(to: NSPoint(x: 4.8, y: 5.7))
      cord.move(to: NSPoint(x: 13.2, y: 12.3))
      cord.line(to: NSPoint(x: 15.6, y: 14.9))
      cord.stroke()
      for origin in [NSPoint(x: 0.9, y: 1.6), NSPoint(x: 15.4, y: 14.9)] {
        NSBezierPath(ovalIn: NSRect(origin: origin, size: NSSize(width: 1.7, height: 1.7))).fill()
      }
      NSGraphicsContext.saveGraphicsState()
      let transform = NSAffineTransform()
      transform.translateX(by: 9, yBy: 9)
      transform.rotate(byDegrees: 10)
      transform.translateX(by: -9, yBy: -9)
      transform.concat()
      let card = NSBezierPath(
        roundedRect: NSRect(x: 4.5, y: 4.5, width: 9, height: 9), xRadius: 1.1, yRadius: 1.1)
      card.lineWidth = 1.3
      card.stroke()
      let mountain = NSBezierPath()
      mountain.move(to: NSPoint(x: 6, y: 6.3))
      mountain.line(to: NSPoint(x: 8, y: 9.1))
      mountain.line(to: NSPoint(x: 9.7, y: 7.3))
      mountain.line(to: NSPoint(x: 10.7, y: 8.4))
      mountain.line(to: NSPoint(x: 12, y: 6.3))
      mountain.close()
      mountain.fill()
      NSBezierPath(ovalIn: NSRect(x: 10.3, y: 10, width: 1.7, height: 1.7)).fill()
      NSGraphicsContext.restoreGraphicsState()
      return true
    }
    image.isTemplate = true
    return image
  }
}
