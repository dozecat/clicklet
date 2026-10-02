import SwiftUI

// MARK: - Tabs

/// The settings window's top tab strip, in the style of Safari's settings.
///
/// A strip rather than a sidebar: five destinations all stay visible at once and
/// there is nothing to navigate "into", so the window can never trap the user.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case toolbox
    case newFile
    case compression
    case scripts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "通用"
        case .toolbox:
            return "工具箱"
        case .newFile:
            return "新建文件"
        case .compression:
            return "压缩解压"
        case .scripts:
            return "脚本"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .toolbox:
            return "wrench.and.screwdriver"
        case .newFile:
            return "doc.badge.plus"
        case .compression:
            // `doc.zipper` is the system's zipped-document glyph, closer to the
            // "archive" idea than the generic shipping box.
            return "doc.zipper"
        case .scripts:
            // Not "terminal": that symbol is the same rounded box with ">_" as
            // Terminal.app's own icon, which the 工具箱 tab already shows for
            // 在终端中打开.
            return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct SettingsTabStrip: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 0) {
            // Equal minimum insets keep the tabs centred while staying clear of
            // the window's close/minimise/zoom buttons.
            Spacer(minLength: 88)

            HStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    tabItem(tab)
                }
            }

            Spacer(minLength: 88)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func tabItem(_ tab: SettingsTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                // The selection sits behind the glyph alone, as a rounded square,
                // the way the system's own tab strips draw it. Wrapping icon and
                // label together made it a tall rectangle.
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
                    )

                Text(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.85))
            .frame(width: 76, height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tab.title)
    }
}

// MARK: - Pane scaffolding

/// Scrollable body of a settings pane. Panes are plain rows rather than grouped
/// forms: the inset grey cards of `Form(.grouped)` read as heavy next to this.
struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                content
            }
            // A little air above the first row: hugging the tab strip reads as
            // cramped.
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Divider between groups of rows. Rows inside a group are separated by spacing
/// alone, which is what keeps the pane quiet.
struct SettingsGroupSeparator: View {
    var body: some View {
        Divider()
            // Equal insets on both sides: a separator that runs to the right
            // edge while starting at the label column reads as lopsided.
            .padding(.horizontal, settingsLeadingInset)
            .padding(.vertical, 12)
    }
}

/// Geometry shared by every row, so labels and controls line up across panes.
/// The label column is right-aligned and inset from the window edge; without the
/// inset the text hugs the left edge and the whole pane reads as cramped.
let settingsLeadingInset: CGFloat = 150
let settingsLabelWidth: CGFloat = 140

/// Table panes start further left than the label/control panes: their first
/// column is an icon, not a right-aligned label, so the label column's indent
/// only pushed everything against the right edge.
///
/// The value is set so a row card's padding looks balanced: the row cards are
/// inset 8 from the window (see `ReorderableRows.cardInset`), and the gap from
/// the card's left edge to the icon should match the gap from the checkbox to
/// the card's right edge. At 118 the left gap measured 110pt against 65pt on the
/// right; 72 evens them up.
let settingsTableLeadingInset: CGFloat = 72

/// Optical nudge for the 启用 column header so the word sits directly above the
/// checkboxes rather than above their column. The value is calibrated against a
/// rendered pane (`+2.5` puts both left edges at the same pixel); it depends on
/// the row's trailing structure, so re-measure it if that changes.
let settingsCheckboxHeaderNudge: CGFloat = 2.5
private let settingsLabelGap: CGFloat = 10

/// One settings row: a right-aligned label and a single control on the same line.
///
/// There is deliberately no "small print" slot. Explanations used to sit under
/// each row in 10pt grey, which read as clutter; state belongs in the control
/// (a checkbox with a word beside it, or a value) instead.
struct SettingsRow<Control: View>: View {
    private let label: String
    private let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: settingsLabelGap) {
            Text(label + "：")
                .frame(width: settingsLabelWidth, alignment: .trailing)

            control
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, settingsLeadingInset)
        .padding(.trailing, 18)
        .padding(.vertical, 10)
    }
}

/// A read-only value occupying a row's control slot.
struct SettingsValue: View {
    let text: String

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Checkbox whose label spells out the current state, the way the system
/// preference panes and 1Capture present a two-state option.
struct SettingsCheckbox: View {
    let title: String
    @Binding var isOn: Bool
    var isEnabled: Bool = true

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
            .disabled(!isEnabled)
    }
}

/// Checkbox that reports a state this window cannot change.
struct SettingsReadOnlyCheckbox: View {
    let title: String
    let isOn: Bool

    var body: some View {
        Toggle(title, isOn: .constant(isOn))
            .toggleStyle(.checkbox)
            .disabled(true)
    }
}

/// Alternating row colour for a striped table.
func SettingsStripe(index: Int) -> Color {
    index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.045)
}

/// Alternating row background for panes built from a plain stack.
struct SettingsStriped<Content: View>: View {
    let index: Int
    private let content: Content

    init(index: Int, @ViewBuilder content: () -> Content) {
        self.index = index
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.045))
    }
}

/// Centred placeholder shown when a list has no rows yet.
struct SettingsEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

// MARK: - Small pieces

struct SettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// Marks a control that the agreed design calls for but that is not built yet.
/// Shown instead of a dead switch so the window never looks broken.
struct SettingsPlannedBadge: View {
    var body: some View {
        SettingsBadge(text: "即将支持")
    }
}

struct SettingsStatusDot: View {
    enum Kind {
        case ok
        case warning
        case unknown
    }

    let kind: Kind

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(color)
            .help(helpText)
    }

    private var symbolName: String {
        switch kind {
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var color: Color {
        switch kind {
        case .ok:
            return .green
        case .warning:
            return .orange
        case .unknown:
            return .secondary
        }
    }

    private var helpText: String {
        switch kind {
        case .ok:
            return "已授权 / 已启用"
        case .warning:
            return "需要处理"
        case .unknown:
            return "状态未知"
        }
    }
}

/// Surfaces a failure on every pane instead of leaving one page looking inert.
struct SettingsStatusBanner: View {
    let message: String?

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.callout)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.12))
        }
    }
}

/// `~/Library/...` instead of `/Users/me/Library/...`.
func shortenedPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    guard path.hasPrefix(home) else {
        return path
    }
    return "~" + path.dropFirst(home.count)
}
