import AppKit

/// Builds the menu-bar status image from the app's brand icon. The product
/// decision is to brand the menu bar with the full-color app icon (not a
/// monochrome template glyph), so `render` keeps color and a fixed point size.
/// [REF:fr:app-icon]
enum MenuBarIcon {
    /// Status-bar images render ~18pt tall; fix the menu-bar icon to that.
    static let pointSize: CGFloat = 18

    /// Rescale `source` into a `pointSize`×`pointSize` image, full-color
    /// (`isTemplate = false`) so the brand art is preserved in the menu bar.
    /// Pure and total over any non-nil `NSImage` — the testable core.
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
        image.isTemplate = false
        return image
    }

    /// The menu-bar image sourced from the running app's own icon (the bundled
    /// `AppIcon.icns`). Falls back to a system symbol when no app icon resolves
    /// (e.g. `swift run` without a bundle); never returns nil.
    static func statusItem() -> NSImage {
        let source =
            NSImage(named: NSImage.applicationIconName)
            ?? NSImage(systemSymbolName: "link.circle.fill", accessibilityDescription: nil)
            ?? NSImage()
        return render(from: source)
    }
}
