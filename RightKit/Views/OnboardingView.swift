import SwiftUI

/// The first-run guide. Shown until the user finishes it, so a quit halfway through
/// brings it back rather than retiring it.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome, finderExtension, accessibility, done
    }

    @State private var step: Step
    /// Selected through a local state first: writing to the store from inside the
    /// Picker's binding setter mutates published state during a view update, which
    /// SwiftUI refuses ("Publishing changes from within view updates is not allowed").
    @State private var selectedLanguage: AppLanguage

    /// Live state, supplied by the caller.
    private let extensionEnabled: Bool
    private let accessibilityGranted: Bool
    private let onOpenExtensionSettings: () -> Void
    private let onOpenAccessibilitySettings: () -> Void
    private let onFinish: () -> Void
    private let onEnableExtension: () -> Void
    private let language: AppLanguage
    private let onSelectLanguage: (AppLanguage) -> Void

    init(
        initialStep: Step = .welcome,
        extensionEnabled: Bool = false,
        accessibilityGranted: Bool = false,
        onOpenExtensionSettings: @escaping () -> Void = {},
        onOpenAccessibilitySettings: @escaping () -> Void = {},
        language: AppLanguage = .simplifiedChinese,
        onSelectLanguage: @escaping (AppLanguage) -> Void = { _ in },
        onFinish: @escaping () -> Void = {},
        onEnableExtension: @escaping () -> Void = {}
    ) {
        _step = State(initialValue: initialStep)
        _selectedLanguage = State(initialValue: language)
        self.extensionEnabled = extensionEnabled
        self.accessibilityGranted = accessibilityGranted
        self.onOpenExtensionSettings = onOpenExtensionSettings
        self.onOpenAccessibilitySettings = onOpenAccessibilitySettings
        self.onFinish = onFinish
        self.onEnableExtension = onEnableExtension
        self.language = language
        self.onSelectLanguage = onSelectLanguage
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // SwiftUI diffs Text by its key, so the same key with a different bundle
            // is not redrawn — the language change looked like it needed several
            // attempts. Tying the subtree's identity to the language forces the
            // rebuild. `step` lives outside, so it is not reset.
            content
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            if step == .welcome {
                L.t("开始前请先完成初始化设置")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 10)

            pageDots
                .padding(.bottom, 22)
        }
        .frame(width: 640, height: 486)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .finderExtension: instructions(
            appBundleIdentifier: "com.apple.finder",
            title: "开启访达扩展",
            detail: "没有它，右键菜单里不会出现任何项目。",
            path: Self.finderExtensionPath,
            primaryTitle: "一键开启",
            primaryAction: onEnableExtension,
            action: onOpenExtensionSettings
        )
        case .accessibility: instructions(
            appBundleIdentifier: "com.apple.systempreferences",
            title: "需要时再开 — 辅助功能",
            detail: "「新建文件」之后要直接进入重命名，需要它。其他功能不受影响。",
            path: "系统设置 → 隐私与安全性 → 辅助功能",
            primaryTitle: nil, primaryAction: {},
            action: onOpenAccessibilitySettings
        )
        case .done: donePage
        }
    }

    // MARK: - Pages

    private var welcome: some View {
        VStack(spacing: 18) {
            appIcon
            L.t("欢迎使用 RightKit")
                .font(.system(size: 28, weight: .semibold))

            languagePicker

            HStack(spacing: 16) {
                // A feather, not a bolt: the point is that it stays out of the way,
                // not that it is fast. And the copy says what the user sees — no Dock
                // icon, no window — rather than how much memory it uses.
                // `leaf`, not `feather` — `feather` is not an SF Symbol, and a missing
                // name renders as nothing at all, which is how this was caught.
                card(symbol: "leaf", tint: .green, title: "轻量",
                     detail: "没有 Dock 图标，也不弹窗，需要时右键就有")
                card(symbol: "doc.zipper", tint: .blue, title: "压缩解压",
                     detail: "用 Keka 或系统自带工具，你选哪个就用哪个")
                card(symbol: "chevron.left.forwardslash.chevron.right", tint: .orange,
                     title: "自己的脚本", detail: "sh 脚本放进脚本目录，右键就能运行")
            }
            .padding(.horizontal, 24)
        }
    }

    /// Language belongs on the welcome page: it is the one setting worth choosing
    /// before anything else, since it changes every word that follows.
    private var languagePicker: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Picker("", selection: $selectedLanguage) {
                ForEach(AppLanguage.allCases) { candidate in
                    Text(verbatim: candidate.displayName).tag(candidate)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
            .onChange(of: selectedLanguage) { newValue in
                onSelectLanguage(newValue)
            }
        }
        .font(.system(size: 12))
    }

    /// One permission page: the real system app icon, one line saying where the switch
    /// is on this macOS version, and a link that opens Settings there.
    private func instructions(
        appBundleIdentifier: String, title: String, detail: String,
        path: String,
        primaryTitle: String?, primaryAction: @escaping () -> Void,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            Group {
                if let icon = SystemIcon.application(bundleIdentifier: appBundleIdentifier) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    Image(systemName: "gearshape").resizable()
                }
            }
            .frame(width: 72, height: 72)

            VStack(spacing: 10) {
                L.t(title).font(.system(size: 25, weight: .semibold))
                L.t(detail).font(.system(size: 13)).foregroundStyle(.secondary)

                // Plain text, no card behind it: it is one line, not a section.
                L.t(path).font(.system(size: 13)).padding(.top, 2)

                // A link, not a button, so it reads as "go there" rather than "do it".
                Button(action: action) { L.t("打开系统设置") }
                    .buttonStyle(.link)
                    .font(.system(size: 13))
            }
        }
    }

    /// Where the Finder extension switch lives depends on the macOS release.
    private static var finderExtensionPath: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        // macOS 26, and macOS 15.4.1 and later, both put it under Login Items &
        // Extensions; before that it sat in Privacy & Security.
        if version.majorVersion >= 26 || (version.majorVersion == 15 && version.minorVersion >= 4) {
            return "系统设置 → 通用 → 登录项与扩展 → 文件提供程序"
        }
        return "系统设置 → 隐私与安全性 → 扩展"
    }

    private var donePage: some View {
        VStack(spacing: 24) {
            appIcon
            L.t("一切就绪").font(.system(size: 28, weight: .semibold))
            L.t("右键访达里的文件或空白处，就能看到 RightKit 的菜单。")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Pieces

    private var appIcon: some View {
        Group {
            if let image = NSImage(named: "AppIcon") {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: 20).fill(Color.accentColor)
            }
        }
        .frame(width: 96, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func card(symbol: String, tint: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(tint)
            L.t(title).font(.system(size: 15, weight: .semibold))
            L.t(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        // A ZStack, not an HStack with a mirroring spacer: the welcome page has no back
        // button, so mirroring left the primary button off-centre there.
        ZStack {
            Button {
                if step == .done {
                    onFinish()
                } else {
                    step = Step(rawValue: step.rawValue + 1) ?? .done
                }
            } label: {
                L.t(title)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 160)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)

            HStack {
                if step != .welcome {
                    Button { step = Step(rawValue: step.rawValue - 1) ?? .welcome } label: {
                        Image(systemName: "chevron.left").frame(width: 44)
                    }
                    .controlSize(.large)
                }
                Spacer()
            }
        }
    }

    /// Which page this is, at a glance. The arrows stay for going back, but the dots
    /// are what make the number of steps obvious.
    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Step.allCases, id: \.rawValue) { candidate in
                Circle()
                    .fill(candidate == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var title: String {
        switch step {
        case .welcome: return "开始"
        case .done: return "完成"
        default: return "下一步"
        }
    }
}
