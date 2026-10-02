import AppKit
import ImageIO

/// Renders the small PNGs that go into the menu snapshot.
///
/// The Finder extension is sandboxed and cannot resolve application or document
/// icons, so the main app draws them and ships the pixels. 16pt keeps the
/// snapshot small — it is JSON, and the data is base64 on top of that.
enum MenuIconRenderer {
    static let side: CGFloat = 16

    static func png(for image: NSImage) -> Data? {
        let rendered = NSImage(size: NSSize(width: side, height: side))
        rendered.lockFocus()
        image.draw(
            in: NSRect(x: 0, y: 0, width: side, height: side),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        rendered.unlockFocus()

        guard let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else {
            return nil
        }

        // ImageIO with no properties. `NSBitmapImageRep.representation` embeds a
        // colour profile, which costs ~3.5KB per icon — more than the pixels —
        // and the snapshot is rewritten whenever the app is activated.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return data as Data
    }

    static func png(systemSymbol: String) -> Data? {
        // Tinted through the symbol configuration. Setting `NSColor.set()` and
        // then drawing does nothing at all: that sets the fill colour for drawing
        // operations, not for an image, so the symbol came out in its own black.
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(
                NSImage.SymbolConfiguration(paletteColors: [NSColor.controlAccentColor])
            )

        guard let symbol = NSImage(
            systemSymbolName: systemSymbol,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }

        let tinted = NSImage(size: NSSize(width: side, height: side))
        tinted.lockFocus()
        symbol.draw(
            in: NSRect(
                x: (side - symbol.size.width) / 2,
                y: (side - symbol.size.height) / 2,
                width: symbol.size.width,
                height: symbol.size.height
            )
        )
        tinted.unlockFocus()

        return png(for: tinted)
    }

    static func png(contentsOfFile path: String) -> Data? {
        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        return png(for: image)
    }
}
