![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-000000.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-f05138.svg)
![License](https://img.shields.io/badge/License-GPL--3.0-blue.svg)

[English](#en) | [中文](#cn)

---

<span id="en">RightKit</span>
====================

**RightKit** is a Finder context menu utility for macOS. It adds the actions people reach for most often — create a file from a template, copy a path, compress or extract, run your own scripts — and lets you reorder or switch off every one of them.

It runs as an agent app: no Dock icon, no window at launch. Settings open from the menu bar icon, and the context menu is built by a Finder Sync extension.

<img src="docs/images/settings-en.png" width="560" alt="RightKit settings window">

## ✨ Features

| Action | Applies to | What it does |
|---|---|---|
| **New File** | empty space | Creates a file from a template and drops straight into rename. Ships with Markdown, text and Word/Excel/PowerPoint templates; drop your own into the templates folder |
| **Copy Path** | selection, empty space | Absolute path, same wording in both contexts |
| **Copy File Name** | selection | The name alone |
| **Open Terminal Here** | selection, empty space | Opens Terminal at that directory |
| **Scripts** | selection, empty space | Runs a script package you put in the scripts folder, isolated in an XPC service |
| **Compress to ZIP** | selection | Uses the system tool, or Keka when it is installed |
| **Compress to 7Z** | selection | Keka only; the item hides itself when no tool can produce 7z |
| **Extract Here** | archives | Extracts into the current folder |
| **Extract into Separate Folder** | archives | Extracts into a new folder named after the archive |

Archive actions follow the selection: extracting never appears for a folder, and compressing never appears when everything selected is already an archive.

Other things worth knowing:

- **Toolbox** — reorder by dragging, switch any item off. The order in the settings window is the order in the menu.
- **Self-check** — one panel that reports whether the extension is enabled, permissions are granted, the shared container is writable and the menu snapshot is fresh, with a button for whatever is missing.
- **Language** — Simplified Chinese or English, applied immediately; the context menu follows the same setting.
- **Compressor** — Keka if installed, otherwise the system's own tools. Capabilities are read from the chosen app.

## 🚀 Quick Start

```bash
git clone git@github.com:dozecat/rightkit.git
cd rightkit

brew install xcodegen      # the Xcode project is generated, not committed
xcodegen generate

open RightKit.xcodeproj    # then ⌘R
```

On first launch RightKit opens the self-check panel and asks for the Finder extension. After that, **reload the extension whenever you rebuild it**:

```bash
Scripts/reload-finder-extension.sh
```

### Requirements

- macOS 13 Ventura or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- Optional: [Keka](https://www.keka.io) for 7z and for more extract formats

## 📖 How it fits together

```
RightKit/            main app — settings, window, action coordination
FinderExtension/     Finder Sync extension — sandboxed; menu and request files
ScriptXPCService/    script runner — reachable only from the main app
Shared/              models, storage and IPC used by all three
AppCore/             business logic used by the main app
Tests/               unit tests
```

The extension is sandboxed, so anything that touches a path — creating a file, compressing, opening Terminal — is handed to the main app through a request file plus a `rightkit://action/<uuid>` wake-up. The main app then runs it, and talks to the XPC service for scripts. The extension never calls XPC itself.

Generated files that are not in the repository: `RightKit.xcodeproj`, `project.yml`'s build output, and the icon and menu snapshots, which the app writes into the shared container at runtime.

## 🧪 Tests

```bash
xcodegen generate
TMPDIR=$PWD/.build/tmp/ xcodebuild -project RightKit.xcodeproj -scheme RightKit \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/dd build-for-testing CODE_SIGNING_ALLOWED=NO
TMPDIR=$PWD/.build/tmp/ xcrun xctest .build/dd/Build/Products/Debug/RightKitTests.xctest
```

## 许可 / License

[GNU General Public License v3.0](LICENSE). RightKit is free software: you may redistribute and modify it under the terms of the GPL-3.0, and any redistributed derivative must stay open under the same licence.

---

<span id="cn">RightKit</span>
====================

**RightKit** 是一个 macOS 上的 Finder 右键增强工具。它把最常用的操作放进右键菜单——按模板新建文件、拷贝路径、压缩解压、运行自己的脚本——并且每一项都可以排序或关掉。

它以代理应用的形式运行：没有 Dock 图标，启动时不弹窗。设置从状态栏图标进入，右键菜单由 Finder Sync 扩展构建。

<img src="docs/images/settings-zh.png" width="560" alt="RightKit 设置窗口">

## ✨ 功能

| 操作 | 作用于 | 说明 |
|---|---|---|
| **新建文件** | 空白处 | 按模板建文件，并直接进入重命名。内置 Markdown、文本与 Word/Excel/PowerPoint 模板，也可以把自己的模板放进模板目录 |
| **拷贝路径** | 选中项、空白处 | 绝对路径，两种情境下叫法一致 |
| **拷贝文件名** | 选中项 | 只要文件名 |
| **在此处打开终端** | 选中项、空白处 | 在该目录打开终端 |
| **脚本** | 选中项、空白处 | 运行放进脚本目录的脚本站，在 XPC 服务里隔离执行 |
| **压缩为 ZIP** | 选中项 | 用系统自带工具，装了 Keka 就用 Keka |
| **压缩为 7Z** | 选中项 | 仅 Keka；没有工具能产出 7z 时这一项自动隐藏 |
| **解压到当前文件夹** | 压缩包 | 就解压在当前目录 |
| **解压到独立文件夹** | 压缩包 | 解压到以压缩包命名的新文件夹 |

归档操作跟着选中的内容走：选中文件夹不会出现解压，选中的全是压缩包时不会出现压缩。

另外几件事：

- **工具箱**——拖动排序，任意一项都能关掉。设置窗口里的顺序就是菜单里的顺序。
- **自检**——一个面板报告扩展是否启用、权限是否齐、共享容器可写否、菜单快照是否新鲜，缺什么就给什么按钮。
- **语言**——简体中文或 English，立即生效，右键菜单跟随同一个设置。
- **压缩软件**——装了 Keka 就用 Keka，否则用系统自带工具。能力列表从所选应用读取。

## 🚀 快速开始

```bash
git clone git@github.com:dozecat/rightkit.git
cd rightkit

brew install xcodegen      # 工程文件由脚本生成，不入库
xcodegen generate

open RightKit.xcodeproj    # 然后 ⌘R
```

首次启动时 RightKit 会打开自检面板，并提示启用访达扩展。之后**每次重新构建扩展都要重载**：

```bash
Scripts/reload-finder-extension.sh
```

### 环境要求

- macOS 13 Ventura 及以上
- Xcode 15 及以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)——`brew install xcodegen`
- 可选：[Keka](https://www.keka.io)，用于 7z 和更多解压格式

## 📖 结构

```
RightKit/            主应用——设置、窗口、操作协调
FinderExtension/     Finder Sync 扩展——沙盒；菜单与请求文件
ScriptXPCService/    脚本执行服务——只有主应用能连
Shared/              三个进程共用的模型、存储与 IPC
AppCore/             仅主应用使用的业务逻辑
Tests/               单元测试
```

扩展是沙盒的，所以任何要碰路径的操作——新建文件、压缩、打开终端——都通过一个请求文件加 `rightkit://action/<uuid>` 唤起主应用来做。脚本再由主应用交给 XPC 服务。扩展自己不连 XPC。

不入库的生成物：`RightKit.xcodeproj`、构建产物，以及应用在运行时写进共享容器的图标与菜单快照。

## 🧪 测试

```bash
xcodegen generate
TMPDIR=$PWD/.build/tmp/ xcodebuild -project RightKit.xcodeproj -scheme RightKit \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/dd build-for-testing CODE_SIGNING_ALLOWED=NO
TMPDIR=$PWD/.build/tmp/ xcrun xctest .build/dd/Build/Products/Debug/RightKitTests.xctest
```

---

需求与设计取舍见 [右键工具功能要求](docs/右键工具功能要求.md)。
