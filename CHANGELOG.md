# Changelog

All notable changes to RightKit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions are also the release tags: `MARKETING_VERSION` in `project.yml`, the
`v*` git tag and the release heading below always agree. See
[docs/RELEASING.md](docs/RELEASING.md) for how a release is cut.

## [Unreleased]

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
  under `~/Library/Logs/RightKit/Scripts/` with a 300-second timeout.

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

[Unreleased]: https://github.com/dozecat/rightkit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/dozecat/rightkit/releases/tag/v1.0.0
