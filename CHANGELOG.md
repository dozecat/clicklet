# Changelog

All notable changes to Clicklet are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are also the release tags: `MARKETING_VERSION` in `project.yml`, the
`v*` git tag and the release heading below always agree. See
[docs/RELEASING.md](docs/RELEASING.md) for how a release is cut.

## [1.1.0] - 2026-10-09

### Changed

- Renamed the project from RightKit to Clicklet. The bundle identifiers for the
  app, Finder extension and XPC service are now `com.dozecat.Clicklet.*`, the App
  Group is `group.com.dozecat.Clicklet`, the URL scheme is `clicklet://`, and the
  user support and log directories moved to
  `~/Library/Application Support/Clicklet` and `~/Library/Logs/Clicklet`.
- Scripts now receive `CLICKLET_DIR` and `CLICKLET_FILES` instead of
  `RIGHTKIT_DIR` and `RIGHTKIT_FILES`.

## [1.0.2] - 2026-10-04

### Added

- Twelve more file templates: Pages, Numbers and Keynote (real empty documents
  rather than renamed archives), JSON, HTML, CSS, JavaScript, Python, Shell,
  YAML, CSV and RTF. The last seven are off by default; tick them in
  Settings › New File.
- A status dot per permission on the General page, green when granted and orange
  when something still needs doing, plus a one-line summary at the top saying
  whether all three are in place. The status bar menu no longer offers the
  self-check window: the page answers the same question in place.
- Coloured icons in both the Finder menu and the settings window — a tinted
  rounded tile per toolbox item, in the style of an application icon.

### Changed

- The settings window has an ordinary title bar with the name centred in it and
  the tab strip below it. It used to blank the title, make the bar transparent
  and run the content up into it, which fought SwiftUI on every window
  activation and left a stray rule above the tab strip.
- The General page is 720x520, so it fits without scrolling, and the group rules
  nearly span the window instead of stopping at the value column.
- The compression format lists are capsules rather than a comma-separated run of
  up to sixteen formats, so what is supported can be counted at a glance.
- New File on the Desktop no longer raises Finder. There is no Finder window to
  bring forward there — the Desktop is Finder's own window — so activating it
  opened a new window showing ~/Desktop, and the rename keystroke that followed
  was unreliable because that window had only just been created. The file now
  appears in place; press Return if you want to rename it. Inside a folder the
  behaviour is unchanged.

### Fixed

- Inline rename after New File is more reliable. The Return keystroke is posted
  to Finder's process rather than into the session, where it went to whatever
  AppKit believed was frontmost — Finder reports itself frontmost before its
  window is actually key. The wait before the keystroke also went from 0.2s to
  0.6s, and the overall timeout from 2.5s to 4s, because Finder may be creating
  the window.
- The first-run guide no longer sinks behind other applications after a trip to
  System Settings. Closing that window hands the focus to whatever else was
  open, and this app — being LSUIElement — is never activated, so a notification
  driven fix could not work. Its level now follows the frontmost application:
  floating above everything except System Settings itself.

## [1.0.1] - 2026-10-04

### Added

- A four-page first-run guide (welcome, Finder extension, Accessibility, done).
  It gives the exact System Settings path for the running macOS release, and
  replaces the self-check sheet as the onboarding path.
- The language can be chosen inside the guide and changed later at runtime; the
  interface follows immediately, without a relaunch.
- The self-check is a window of its own, so opening it no longer raises the
  settings window.

### Changed

- The interface is fully localised. The toolbar list, the language picker, the
  status bar menu, the app menu, the guide, the self-check and every dialog
  ActionCoordinator produces now resolve through the selected language bundle.
- On first launch the language follows the system setting. It used to read
  `Locale.preferredLanguages`, which is filtered by the bundle's own
  localizations — only `en.lproj` is compiled — so it always answered English.
- The Finder extension is re-elected at launch. Finder does not load a Finder
  Sync extension after a reboot until its election changes.
- Archive actions follow the chosen compressor in both directions, and the
  default is the system tools rather than the first installed app. Extraction no
  longer depends on Keka, whose command line is sandboxed and refuses the paths
  a background call hands it.
- A factory reset offers the bundled scripts again, including deleted ones.

### Fixed

- Menu icons: application artwork keeps its colour instead of being drawn as an
  alpha mask, and request de-duplication evicts the oldest id rather than an
  arbitrary element of a Set.
- The guide window centres correctly and is raised when the app becomes active,
  without being pinned above every other window.

## [1.0.0] - 2026-10-03

First public release: a lightweight Finder context menu for macOS, distributed
outside the App Store.

### Added

- A Finder context menu with nine actions: New File, Copy Path, Copy File Name,
  Open Terminal Here, Scripts, Compress to ZIP, Compress to 7Z, Extract Here,
  and Extract into Separate Folder. Only the actions that fit the current
  selection are shown.
- New File with five built-in templates (text, Markdown, Word, Excel,
  PowerPoint), created straight into rename mode, plus a templates folder for
  your own files.
- Copy Path and Copy File Name, handled inside the sandboxed extension.
- Open Terminal Here, which lands in the right folder whether you right-click a
  folder, a file, or empty space.
- Compression and extraction driven by a configurable tool: Keka when it is
  installed, otherwise the system's own `zip`, `ditto` and `tar`. Which formats
  the menu offers follows the chosen tool; 7z needs Keka.
- A shell script extension point: a folder package with an executable
  `script.sh` and an optional `config.json` becomes a menu item, with matching
  rules for context, extensions, multi-selection, confirmation and ordering.
- Two built-in scripts, seeded into the scripts folder on first launch: Open in
  VS Code and Run Python. Edited packages are never overwritten and deleted ones
  are never restored.
- A settings window with six panes (General, Toolbox, New File, Compression,
  Scripts, About), per-item toggles and drag-to-reorder.
- A menu bar item with Settings, Check Status and Quit, plus a self-check sheet
  that reports each permission and offers a one-click fix.
- Simplified Chinese and English, switched in the settings with no relaunch.
- Notifications for compress, extract and script results; per-run script logs
  under `~/Library/Logs/Clicklet/Scripts/` with a 300-second timeout.

### Known limitations

- macOS 13 Ventura or later; no macOS 12 support.
- No automatic updater: install a new build over the old one.
- The build is signed with an Apple Development certificate and is not
  notarized, so macOS asks for approval the first time it is opened (see the
  README). A paid Apple Developer Program membership would remove that step.
- Finder Sync extensions only apply to registered locations (home, `/Users`,
  `/Volumes`, `/System/Volumes` and iCloud Drive). The Trash, smart folders,
  search results and network volumes are not covered.
- 7z compression requires Keka; the system tools cover ZIP plus the tar family.

[Unreleased]: https://github.com/dozecat/clicklet/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/dozecat/clicklet/releases/tag/v1.1.0
[1.0.2]: https://github.com/dozecat/clicklet/releases/tag/v1.0.2
[1.0.0]: https://github.com/dozecat/clicklet/releases/tag/v1.0.0
