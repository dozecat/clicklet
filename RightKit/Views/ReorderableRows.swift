import SwiftUI

/// Rows that can be dragged into a new order.
///
/// The settings tables cannot use `List` for this. A row offset out of its slot
/// is clipped away (verified by rendering), so the dragged row can neither be
/// lifted nor overlap its neighbours — and `onMove` gives no say over what is
/// drawn while dragging, which is why the preview arrived as bare content with
/// no stripe and square corners.
///
/// These tables are short, so a scroll view with our own drag handling costs
/// little and buys the whole effect: the row lifts with its stripe, rounded and
/// shadowed, and the others slide out of the way on a spring.
struct ReorderableRows<Item: Identifiable, Row: View, Footer: View>: View where Item.ID: Hashable {
    let items: [Item]
    /// Called with the source and destination indices once the drag ends.
    let onMove: (Int, Int) -> Void
    /// Drawn behind the row content; moves with the row when it is lifted.
    let stripe: (Int) -> Color
    /// Optional selection highlight, for tables that have a selected row.
    var isSelected: (Item) -> Bool = { _ in false }
    /// Drawn inside the scroll view, straight after the last row — the add and
    /// remove buttons sit there rather than pinned to the bottom of the pane.
    @ViewBuilder let footer: () -> Footer
    @ViewBuilder let row: (Item, Int) -> Row

    @State private var draggedIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var rowHeight: CGFloat = 38

    private let cornerRadius: CGFloat = 9

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item, index)
                        .background(isSelected(item) ? Color.accentColor.opacity(0.14) : stripe(index))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: dragging ? cornerRadius : 0,
                                style: .continuous
                            )
                        )
                        .shadow(
                            color: .black.opacity(dragging ? 0.24 : 0),
                            radius: dragging ? 10 : 0,
                            y: dragging ? 4 : 0
                        )
                        .scaleEffect(dragging ? 1.012 : 1)
                        .offset(y: visualOffset(for: index))
                        .zIndex(dragging ? 1 : 0)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: RowHeightKey.self,
                                    value: proxy.size.height
                                )
                            }
                        )
                        .animation(
                            // The dragged row must track the pointer exactly, so
                            // it is left out of the spring.
                            dragging ? nil : .spring(response: 0.3, dampingFraction: 0.86),
                            value: targetIndex
                        )
                        .gesture(dragGesture(for: index))
                }

                footer()
            }
            .onPreferenceChange(RowHeightKey.self) { height in
                if height > 1 {
                    rowHeight = height
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var dragging: Bool {
        draggedIndex != nil
    }

    /// Where the dragged row currently belongs.
    private var targetIndex: Int? {
        guard let draggedIndex else {
            return nil
        }
        let steps = Int((dragOffset / rowHeight).rounded())
        return min(max(draggedIndex + steps, 0), items.count - 1)
    }

    private func visualOffset(for index: Int) -> CGFloat {
        guard let draggedIndex, let targetIndex else {
            return 0
        }
        if index == draggedIndex {
            return dragOffset
        }
        if draggedIndex < targetIndex, index > draggedIndex, index <= targetIndex {
            return -rowHeight
        }
        if draggedIndex > targetIndex, index >= targetIndex, index < draggedIndex {
            return rowHeight
        }
        return 0
    }

    private func dragGesture(for index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggedIndex == nil {
                    draggedIndex = index
                }
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                if let from = draggedIndex, let to = targetIndex, from != to {
                    onMove(from, to)
                }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    draggedIndex = nil
                    dragOffset = 0
                }
            }
    }
}

private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
