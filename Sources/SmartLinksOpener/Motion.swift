import SwiftUI

/// The app's motion presets: one spring per kind of change, so every screen moves
/// the same way. Springs rather than curves because a spring retargets from the
/// value on screen when the state changes again mid-flight, where a curve either
/// finishes or jumps. Spelled with `response`/`dampingFraction` because the
/// deployment target is macOS 13; `dampingFraction: 1` is "no bounce".
enum Motion {
    /// Panels, list changes, layout reflow, appearance transitions.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1)
    /// Feedback under the finger or the key: accents, toggles, small controls.
    static let snappy = Animation.spring(response: 0.2, dampingFraction: 1)
}
