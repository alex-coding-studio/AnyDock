import AppKit

@MainActor
enum BrandIcon {
    static var artwork: NSImage? {
        Bundle.main.url(forResource: "AnyDockIcon", withExtension: "png", subdirectory: "Brand")
            .flatMap { NSImage(contentsOf: $0) }
    }

    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        for name in ["MenuBarTemplate", "MenuBarTemplate@2x"] {
            guard
                let url = Bundle.main.url(
                    forResource: name,
                    withExtension: "png",
                    subdirectory: "Brand"
                ),
                let data = try? Data(contentsOf: url),
                let representation = NSBitmapImageRep(data: data)
            else {
                continue
            }
            representation.size = image.size
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        return image
    }
}
