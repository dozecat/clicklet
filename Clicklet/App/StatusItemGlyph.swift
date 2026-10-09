import AppKit
import SwiftUI

/// The hand-drawn fallback shape for the status bar icon: the app icon's
/// outline reduced to menu bar size. The normal path uses the artwork the user
/// supplied as StatusIcon.png (see StatusItemImage).
///
/// The app icon is a rounded square with a card and a cursor, but shrinking all
/// of that to 18pt produces a blue blob — verified by rendering it. The menu bar
/// version keeps only the two things that survive: the rounded square outline
/// and the cursor. The card's fine lines cannot help but smudge at this size,
/// so they are dropped.
///
/// Drawing it as a SwiftUI view and handing the system a template image lets
/// light and dark menu bars, and the inversion while selected, be the system's
/// problem rather than something that goes wrong.
struct StatusItemGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // The square and the cursor have to be fully separated: placed
            // against each other their edges merge into one blob, which two
            // renders confirmed. So the square moves up and left, the cursor
            // down and right, with a gap between them.
            let stroke = side * 0.08
            let box = side * 0.58

            ZStack {
                RoundedRectangle(cornerRadius: box * 0.32, style: .continuous)
                    .strokeBorder(lineWidth: stroke)
                    .frame(width: box, height: box)
                    .offset(x: -side * 0.15, y: -side * 0.15)

                Image(systemName: "cursorarrow")
                    .font(.system(size: side * 0.4, weight: .medium))
                    .offset(x: side * 0.22, y: side * 0.22)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// ImageRenderer is MainActor-isolated and the fallback path uses it, so the
/// whole enum is annotated and the static let is initialised on the main
/// thread.
@MainActor
enum StatusItemImage {
    /// The logical size of the menu bar icon.
    ///
    /// 18 rather than 16: the supplied artwork is a card with lines and a
    /// cursor, and rendering showed 16pt squeezes all three into a blob. 18pt
    /// is just readable and 20pt is clearest. How much the system actually
    /// gives it is up to the menu bar; this is the size we submit.
    private static let size: CGFloat = 18

    /// The supplied shape, converted to the black-plus-alpha template a menu
    /// bar extra needs.
    static let normal: NSImage = make()

    private static func make() -> NSImage {
        // The hand-drawn fallback, so a missing resource still leaves an icon.
        func fallback() -> NSImage {
            let renderer = ImageRenderer(
                content: StatusItemGlyph().frame(width: size, height: size).foregroundStyle(.black)
            )
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let image = NSImage(cgImage: cg, size: NSSize(width: size, height: size))
                image.isTemplate = true
                return image
            }
            return NSImage(systemSymbolName: "cursorarrow.click", accessibilityDescription: "RightKit")
                ?? NSImage()
        }

        guard let url = Bundle.main.url(forResource: "StatusIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            DiagnosticsLog.log("status icon resource missing; using the drawn fallback")
            return fallback()
        }

        // The 512px source is submitted at the logical size; the bitmap itself
        // is left for the system to use on Retina displays.
        image.size = NSSize(width: size, height: size)
        // Template, so the system owns the colour: light and dark menu bars,
        // and the inversion while selected.
        image.isTemplate = true
        return image
    }
}
