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
        // Deliberately NOT tinted.
        //
        // A symbol reaches the menu as an alpha-only glyph, so MenuBuilder marks
        // it a template (see the isTemplate rule in `addItem`). Tinting it with
        // the accent colour made it the same colour as the highlight background,
        // so hovering an item made its icon disappear. A template image carries
        // only its alpha; the system picks the colour, including the white used
        // while an item is highlighted.
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)

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

    /// A coloured rounded tile with the symbol knocked out of it in white — the way
    /// an application icon reads.
    ///
    /// These must NOT be template images. A template keeps only its alpha and lets the
    /// system choose the colour, which is what makes a plain symbol behave correctly
    /// when a menu item is highlighted; a tile has its own colour and would be flattened
    /// to a single tint instead. The glyph therefore has to be drawn white here rather
    /// than left for the system.
    static func png(tile systemSymbol: String, colour: NSColor) -> Data? {
        guard let image = image(tile: systemSymbol, colour: colour) else { return nil }
        return png(for: image)
    }

    /// The same tile as an `NSImage`, for the settings window, which shows it directly
    /// rather than shipping pixels to another process.
    static func image(tile systemSymbol: String, colour: NSColor) -> NSImage? {
        let tileSide: CGFloat = 14
        let inset = (side - tileSide) / 2

        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()

        let tile = NSRect(x: inset, y: inset, width: tileSide, height: tileSide)
        colour.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 3.5, yRadius: 3.5).fill()

        let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            // A symbol draws in the current foreground colour, so filling the glyph's
            // own area with white afterwards — sourceAtop keeps only where it drew — is
            // what turns it white without affecting the tile underneath.
            let glyph = NSImage(size: symbol.size)
            glyph.lockFocus()
            symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.setFill()
            NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
            glyph.unlockFocus()

            glyph.draw(
                in: NSRect(
                    x: (side - symbol.size.width) / 2,
                    y: (side - symbol.size.height) / 2,
                    width: symbol.size.width,
                    height: symbol.size.height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        image.unlockFocus()
        return image
    }

    static func png(contentsOfFile path: String) -> Data? {
        guard let image = NSImage(contentsOfFile: path) else {
            return nil
        }
        return png(for: image)
    }
}

extension ToolboxItemID {
    /// The tile colour for each toolbox item.
    ///
    /// Lives here rather than on the enum because `Toolbox.swift` is compiled into the
    /// sandboxed extension as well, and it deliberately avoids AppKit.
    var tileColour: NSColor {
        switch self {
        case .newFile:              return .systemGreen
        case .copyPath:             return .systemGray
        case .copyFileName:         return .systemGray
        case .openInTerminal:       return .systemGray
        case .scripts:              return .systemIndigo
        case .compressZip:          return .systemOrange
        case .compressSevenZip:     return .systemRed
        case .decompressHere:       return .systemYellow
        case .decompressIntoFolder: return .systemBrown
        }
    }
}
