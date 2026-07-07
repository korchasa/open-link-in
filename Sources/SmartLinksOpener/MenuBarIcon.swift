import AppKit

/// Builds the monochrome menu-bar status image. macOS convention is a *template*
/// image: a single-color glyph whose alpha silhouette the system tints
/// automatically (black in a light menu bar, white in dark, highlighted when the
/// menu opens). We use the `link` SF Symbol — matching the brand's link glyph —
/// as that template, not the full-color app icon (whose silhouette is a solid
/// rounded square). [REF:fr:app-icon]
enum MenuBarIcon {
    /// Status-bar glyphs render ~16pt; fix the menu-bar symbol to that.
    static let pointSize: CGFloat = 16

    /// Normalize `source` into a `pointSize`×`pointSize` template image
    /// (`isTemplate = true`) so the system tints it for the menu bar. Pure and
    /// total over any non-nil `NSImage` — the testable core.
    static func render(from source: NSImage) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    /// The menu-bar image: the `link` SF Symbol configured at the menu-bar point
    /// size, normalized to a template by `render`. Falls back to an empty image
    /// if the symbol fails to resolve; never returns nil.
    static func statusItem() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let source =
            NSImage(systemSymbolName: "link", accessibilityDescription: "Reroute")?
            .withSymbolConfiguration(config)
            ?? NSImage()
        return render(from: source)
    }
}
