import SwiftUI

/// Motion for the settings tables, kept in one place so the distinction between
/// "the row under the pointer" and "every other row" cannot drift again.
enum ReorderMotion {
    /// A row being dragged has to track the pointer exactly, so it gets no
    /// animation. Every *other* row springs into place — that spring is what
    /// makes the push-aside read as motion rather than a jump.
    ///
    /// This was once written as a single flag for the whole table, which meant
    /// the animation was switched off for every row for the entire duration of a
    /// drag — exactly when the offsets change — so rows snapped into place.
    static func position(isDragged: Bool) -> Animation? {
        isDragged ? nil : push
    }

    /// How much of the pointer's horizontal travel the dragged row follows.
    ///
    /// Order is one-dimensional, so sideways movement means nothing. Following
    /// the pointer one-to-one would slide the row off its columns and break the
    /// alignment it shares with the header; a damped fraction is enough to read
    /// as "held by the pointer" without pretending the row can go sideways.
    static let horizontalDamping: CGFloat = 0.22

    /// The furthest the row may drift from its column.
    static let maxHorizontalOffset: CGFloat = 26

    /// Damped, clamped horizontal follow for the row under the pointer.
    static func horizontal(_ translation: CGFloat) -> CGFloat {
        min(max(translation * horizontalDamping, -maxHorizontalOffset), maxHorizontalOffset)
    }

    /// Rows sliding out of the way and back.
    static let push = Animation.spring(response: 0.28, dampingFraction: 0.8)
    /// The dragged row rising off the table.
    static let lift = Animation.spring(response: 0.2, dampingFraction: 0.85)
    /// Everything settling after the drop.
    static let settle = Animation.spring(response: 0.32, dampingFraction: 0.84)
}
