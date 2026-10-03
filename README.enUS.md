<p align="center">
  <img width="120" src="RightKit/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="RightKit">
</p>

<h1 align="center">RightKit</h1>

<p align="center">The actions you reach for most, in Finder's context menu.</p>

<p align="center">
  <a href="https://www.apple.com/macos/"><img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple"></a>
  <a href="https://swift.org/"><img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift"></a>
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-%E2%9C%93-orange?style=flat-square">
  <a href="https://developer.apple.com/xcode/"><img alt="Xcode 15+" src="https://img.shields.io/badge/Xcode-15%2B-blue?style=flat-square&logo=xcode"></a>
  <a href="LICENSE"><img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-blue?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a>
</p>

RightKit is a Finder context menu extension for macOS. Create a file from a template, copy a path, compress and extract, run your own scripts — and reorder or switch off any of them.

It runs as an agent app: no Dock icon, no window at launch. Settings open from the status bar icon, and the context menu is built by a Finder Sync extension.

## ✨ Features

Archive entries follow the selection: extracting never appears for a plain folder, and compressing never appears when everything selected is already an archive.

| Action | Applies to | What it does |
|---|---|---|
| <img src="docs/images/icons/newFile.png" width="18"> **New File** | empty space | Creates a file from a template and goes straight into rename. Text and Markdown are generated; Word, Excel and PowerPoint ship as empty documents. Drop your own into the templates folder |
| <img src="docs/images/icons/copyPath.png" width="18"> **Copy Path** | selection, empty space | The absolute path, worded the same in both places |
| <img src="docs/images/icons/copyFileName.png" width="18"> **Copy File Name** | selection | The name alone |
| <img src="docs/images/icons/terminal.png" width="18"> **Open Terminal Here** | selection, empty space | Opens Terminal at the folder itself, or at the folder holding the selection |
| <img src="docs/images/icons/scripts.png" width="18"> **Scripts** | selection, empty space | Runs a script package from the scripts folder, isolated in an XPC service |
| <img src="docs/images/icons/compressZip.png" width="18"> **Compress to ZIP** | selection | Uses whichever compressor you chose: Keka, or the system's own `zip` |
| <img src="docs/images/icons/compress7z.png" width="18"> **Compress to 7Z** | selection | Keka only. Hidden when the chosen compressor cannot write 7z |
| <img src="docs/images/icons/extractHere.png" width="18"> **Extract Here** | archives | Extracts into the current folder |
| <img src="docs/images/icons/extractFolder.png" width="18"> **Extract into Separate Folder** | archives | Extracts into a new folder named after the archive |

- **Toolbox** — drag to reorder, switch any item off. The order in the settings window is the order in the menu.
- **Self-check** — reports whether the extension is enabled, permissions are granted, the shared container is writable and the menu snapshot is current, with a button for whatever is missing.
- **Language** — Simplified Chinese or English, applied immediately. The context menu follows the same setting.
- **Compressor** — Keka when you choose it, otherwise macOS's own tools. Capabilities are read from the chosen app, and the menu follows the choice.

## 🏗 Architecture

Four targets. The extension is sandboxed; the app is not.

| Component | Description |
|---|---|
| **RightKit** (`RightKit/`) | The app — settings, the status bar item, and all file operations |
| **FinderExtension** (`FinderExtension/`) | Sandboxed Finder Sync extension — builds the menu, writes action requests |
| **ScriptXPCService** (`ScriptXPCService/`) | Runs script packages. Reachable only from the app |
| **Shared** / **AppCore** | Models, storage and IPC used by all three; business logic used by the app |

Because the extension is sandboxed, anything that touches a path — creating a file, compressing, opening Terminal — is handed to the app through a request file plus a `rightkit://action/<uuid>` wake-up. Scripts then go to the XPC service. The extension never calls XPC itself.

## 📸 Screenshots

<p align="center"><img src="docs/images/settings-en.png" width="640" alt="RightKit settings"></p>

## 📦 Installation

### Build from Source

The Xcode project is generated, not committed.

```bash
git clone git@github.com:dozecat/rightkit.git
cd rightkit
brew install xcodegen
xcodegen generate
open RightKit.xcodeproj        # then ⌘R
```

On first launch RightKit opens the self-check panel and asks for the Finder extension. After that, reload the extension whenever you rebuild it:

```bash
Scripts/reload-finder-extension.sh
```

### Requirements

| Requirement | Why it is needed |
|---|---|
| **Finder extension** | Enable it in System Settings → Privacy & Security → Extensions. Without it no menu items appear |
| **Accessibility** | Needed to start the inline rename after New File. Asked for on first use |
| **Keka folder access** | Only if you choose Keka and need 7z. Turn on Keka → Settings → File Access → *Enable access to the home folder*, or Keka's command line cannot touch the file |

## 🔧 Development

```bash
xcodegen generate

TMPDIR=$PWD/.build/tmp/ xcodebuild -project RightKit.xcodeproj -scheme RightKit \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/dd build-for-testing CODE_SIGNING_ALLOWED=NO

TMPDIR=$PWD/.build/tmp/ xcrun xctest .build/dd/Build/Products/Debug/RightKitTests.xctest
```

### Key Technologies

- **Swift 5.9** and SwiftUI, with AppKit only where the platform requires it
- **FinderSync** for the context menu, with the work handed to the app through App Group request files
- **XPC** (`ScriptXPCService`) to run user scripts away from both the app and the extension
- **XcodeGen** — `project.yml` is the project; the `.xcodeproj` is generated

### 🌐 Localization

| Language | Code |
|---|---|
| **English** | `en` |
| **Simplified Chinese** | `zh-Hans` |

Chinese is the source language of `Localizable.xcstrings`, so its keys are the Chinese strings and `en.lproj` is the only compiled translation. Strings are looked up at render time against the bundle for the chosen language, which is why switching language takes effect at once instead of asking for a relaunch.

## Similar Projects

- [RClick](https://github.com/wflixu/RClick) — a Finder context menu extension with a similar dual-process design

## License

[GNU General Public License v3.0](LICENSE). RightKit is free software: you may redistribute and modify it under the terms of the GPL-3.0, and any redistributed derivative must stay open under the same licence.
