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
    case about

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
        case .about:
            return "关于"
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
        case .about:
            return "info.circle"
        }
    }
}

/// Motion for the settings tab strip.
enum SettingsTabMotion {
    /// The selected icon easing up to its slightly larger size.
    static let select = Animation.spring(response: 0.24, dampingFraction: 0.7)
}

struct SettingsTabStrip: View {
    @Binding var selection: SettingsTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            // Equal minimum insets keep the tabs centred while staying clear of
            // the window's close/minimise/zoom buttons.
            Spacer(minLength: 88)

            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    tabItem(tab)
                }
            }

            Spacer(minLength: 88)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// White card in light mode, a faint lift in dark mode — in both cases
    /// something that reads as raised above the window rather than tinted.
    private func cardFill(_ isSelected: Bool) -> Color {
        guard isSelected else {
            return .clear
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white
    }

    private func tabItem(_ tab: SettingsTab) -> some View {
        let isSelected = selection == tab

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 17))
                    // Grows a little when picked; the frame keeps the row from
                    // shifting as it does.
                    .scaleEffect(isSelected ? 1.14 : 1)
                    .animation(SettingsTabMotion.select, value: isSelected)
                    .frame(width: 26, height: 26)

                L.t(tab.title)
                    .font(.system(size: 11))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.85))
            .frame(width: 76, height: 46)
            // A raised card rather than a flat tint: the selection reads as
            // lifted off the tab strip, which is what makes it legible without
            // the label needing to shout.
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(cardFill(isSelected))
                    .shadow(
                        color: .black.opacity(isSelected ? 0.12 : 0),
                        radius: 3,
                        y: 1
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(isSelected ? 0.07 : 0),
                                lineWidth: 0.5
                            )
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.t(tab.title))
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
            // 左右等距：分割线只从标签列开始、却一直跑到右边，看着是歪的。
            //
            // 长文本（「可解压格式」列出 11 种的时候）会跨过分割线末端——这个问题
            // 由那一行自己折叠解决，而不是把分割线拉宽。
            .padding(.horizontal, settingsLeadingInset)
            .padding(.vertical, 12)
    }
}

/// Geometry shared by every row, so labels and controls line up across panes.
/// The label column is right-aligned and inset from the window edge; without the
/// inset the text hugs the left edge and the whole pane reads as cramped.
let settingsLeadingInset: CGFloat = 150

/// 行的右边距。
let settingsTrailingInset: CGFloat = 18

/// 设置窗口宽度，与 `SettingsWindowView` 的 frame 一致。
let settingsWindowWidth: CGFloat = 700

/// 落在分割线之内的值列宽度：窗口 − 左右各 150 的分割线内边距 − 标签列 − 间距。
/// 超过这个宽度的文本会跨过分割线末端，看着像溢出了分组。
let settingsValueWidthWithinSeparator: CGFloat =
    settingsWindowWidth - settingsLeadingInset * 2 - settingsLabelWidth - settingsLabelGap
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
            // label 是运行时 String，直接 Text(label + "：") 会被当成原文，
            // 于是只有按钮跟着语言变、标签永远停在源语言。
            // 先把 label 转成键，再拼本地化的全角冒号（英文里用半角）。
            // 括号必需：不加的话 .frame 只作用于第二个 Text，
            // 于是加号左边是 Text、右边是 some View，类型对不上。
            (L.t(label) + L.t("："))
                .frame(width: settingsLabelWidth, alignment: .trailing)

            control
                .layoutPriority(1)

            Spacer(minLength: 0)
        }
        .padding(.leading, settingsLeadingInset)
        .padding(.trailing, settingsTrailingInset)
        .padding(.vertical, 10)
    }
}

/// A read-only value occupying a row's control slot.
struct SettingsValue: View {
    let text: String

    var body: some View {
        L.t(text)
            .foregroundStyle(.secondary)
            // 换行时行距稍大一点。默认行距在多行值（例如「可解压格式」列出 11 种）
            // 上显得拥挤。单行的值不受影响。
            .lineSpacing(4)
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
        // 传 String 会选中 Toggle 的 StringProtocol 重载，那样不会查 catalog。
        Toggle(isOn: $isOn) { L.t(title) }
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
