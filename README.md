<p align="center">
  <a href="https://github.com/dozecat/rightkit">
    <img width="140" src="docs/images/app-icon.png" alt="RightKit 图标">
  </a>
</p>

<h1 align="center">RightKit</h1>

<p align="center">
  把最常用的几个操作，放进 Finder 的右键菜单。
</p>

<p align="center">
  <a href="https://github.com/dozecat/rightkit/releases"><img alt="最新版本" src="https://img.shields.io/github/v/release/dozecat/rightkit?style=flat-square"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift">
  <a href="LICENSE"><img alt="许可：GPL-3.0" src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a>
</p>

<p align="center">
  <a href="https://github.com/dozecat/rightkit/releases">下载</a> ·
  <a href="docs/DESIGN.md">设计文档</a> ·
  <a href="https://github.com/dozecat/rightkit/issues">反馈</a>
</p>

**RightKit 是一个轻量的 macOS 右键增强工具。** Finder 的右键菜单一向简单，扩展它通常得靠第三方工具，而 RightKit 想做更轻的那种：只收下新建文件、拷贝路径、在此处打开终端、压缩解压这些常用操作，并且只显示当前选中内容用得上的那些功能。它不内置任何压缩引擎，压缩软件可在系统自带工具与 [Keka](https://keka.io) 之间选择，菜单里能压缩、解压哪些格式也由所选软件决定。这些功能不够用，自己写一个 shell 脚本放进脚本目录，它就是一个新的菜单项。

## ✨ 功能

- <img src="docs/images/icons/newFile.png" width="20" alt=""> **新建文件**：在空白处右键，按模板创建文件并就地进入重命名；内置文本、Markdown、Word、Excel、PowerPoint 五种模板。
- <img src="docs/images/icons/copyPath.png" width="20" alt=""> **拷贝路径**：复制选中项的绝对路径，多选时每行一个；在空白处右键则复制当前文件夹的路径。
- <img src="docs/images/icons/copyFileName.png" width="20" alt=""> **拷贝文件名**：只在有选中项时出现，只复制文件名，不带路径。
- <img src="docs/images/icons/terminal.png" width="20" alt=""> **在此处打开终端**：在当前文件夹打开 Terminal；选中的是文件夹就在那个文件夹，选中的是文件则在其所在文件夹。
- <img src="docs/images/icons/scripts.png" width="20" alt=""> **脚本**：运行脚本目录里匹配当前选区的脚本，没有匹配项时整项不显示；一个可执行的 `script.sh` 放进脚本目录就是一个菜单项。
- <img src="docs/images/icons/compressZip.png" width="20" alt=""> **压缩为 ZIP**：用设置里选定的压缩软件打包，产物重名时自动追加序号。
- <img src="docs/images/icons/compress7z.png" width="20" alt=""> **压缩为 7Z**：只在所选压缩软件支持 7z 时出现。
- <img src="docs/images/icons/extractHere.png" width="20" alt=""> **解压到当前文件夹**：选中压缩包时就地解开，不新建文件夹。
- <img src="docs/images/icons/extractFolder.png" width="20" alt=""> **解压到独立文件夹**：解压到以压缩包命名的新文件夹，重名时同样自动追加序号。

此外，每个条目的启用开关与顺序都在设置里调整，改完立刻反映到 Finder；界面与右键菜单都支持简体中文和 English，切换后立即生效。

## 📸 截图

| 新建文件 | 脚本 | 解压 |
|---|---|---|
| <img width="240" src="docs/images/menu-new-file.png" alt="新建文件子菜单"> | <img width="240" src="docs/images/menu-scripts.png" alt="脚本子菜单"> | <img width="180" src="docs/images/menu-extract.png" alt="解压菜单项"> |

## 📦 下载与安装

**[前往 Releases 下载最新版](https://github.com/dozecat/rightkit/releases)**，打开后把 **RightKit** 拖进「应用程序」文件夹。需要 macOS 13 Ventura 或更高版本。首次启动会打开一个四页的引导，逐项告诉你还缺哪一项，并直接带你到对应的地方开启。之后随时可以从菜单栏图标的「帮助 → 设置引导…」再看一遍。

> **安装包未经 Apple 公证**，macOS 会提示「无法验证开发者」。首次打开请右键点按 RightKit → **打开**，在弹窗里再点一次「打开」；或在「系统设置 → 隐私与安全性」里点「仍要打开」。也可以直接在终端执行 `xattr -dr com.apple.quarantine /Applications/RightKit.app`。

权限列表：

| 项目 | 在哪里开启 |
|---|---|
| **访达扩展** | 系统设置 → 通用 → 登录项与扩展 → 文件提供程序 |
| **辅助功能** | 系统设置 → 隐私与安全性 → 辅助功能 |
| **Keka 文件夹访问** | 仅用 7z 时需要，在 Keka → 设置 → 文件访问权限里开启 |
| **通知**（可选） | 首次运行时的系统弹窗，用来反馈压缩、解压与脚本的结果 |

> 旧版 macOS 中，访达扩展在「隐私与安全性 → 扩展」下开启。拿不准缺哪一项时，从菜单栏图标进入「检查运行状态…」。

**更新**：下载新版本覆盖安装即可，当前版本不含自动更新。**卸载**：关掉访达扩展，把 RightKit 拖进废纸篓；脚本与模板在 `~/Library/Application Support/RightKit/`，日志在 App Group 容器里：`open ~/Library/Group\ Containers/6T9RSL7KL6.group.com.dozecat.RightKit/Logs`，需要时一并删除。

## 🧩 脚本扩展

右键菜单里的「脚本」子菜单会列出匹配当前选区的脚本，点击即运行；没有匹配项时，整项不会出现。开箱自带两个：**用 VS Code 打开** 与 **运行 Python 脚本**。

想加自己的，把脚本包放进脚本目录即可（设置 → 脚本 → `+` 可以直接打开这个目录）——目录是唯一的事实来源，不需要在应用内导入。

```
~/Library/Application Support/RightKit/Scripts/
└── 用 VS Code 打开/
    ├── script.sh      # 入口，需 chmod +x
    ├── config.json    # 元数据，可选
    └── icon.png       # 图标，可选
```

一个最小的 `script.sh`：

```bash
#!/bin/bash
# 选中的路径以参数传入，工作目录是右键所在的文件夹
for f in "$@"; do
    echo "$f" >> "$RIGHTKIT_DIR/selected.txt"
done
```

`config.json` 决定它什么时候出现，常用的几个字段：

| 字段 | 取值 | 作用 |
|---|---|---|
| `name` | 字符串 | 菜单里显示的名字 |
| `context` | `selection` / `files` / `folders` / `background` / `all` | 作用于选中项、文件、文件夹、空白处，还是全部 |
| `extensions` | 如 `["py"]` | 只对指定扩展名的选中项出现 |
| `confirm` | `true` | 执行前先弹确认 |
| `icon` | 文件名 | 包内的图标文件 |
| `order` | 数字 | 在子菜单中的排序 |

执行时：选中项以 `$@` 传入，环境里有 `RIGHTKIT_DIR`（右键所在目录）与 `RIGHTKIT_FILES`（换行分隔的选中路径）；单个脚本 300 秒超时；每次执行的日志在 `~/Library/Logs/RightKit/Scripts/<脚本名>/`。

> **PATH**：脚本由 XPC 服务启动，继承的是 launchd 的最小环境，只有 `/usr/bin:/bin:/usr/sbin:/sbin`。要用 Homebrew 装的 `python3`、`node`，请在脚本开头自己补上 `export PATH="/opt/homebrew/bin:$PATH"`。

其余字段与内置脚本的播种规则见[设计文档](docs/DESIGN.md)。

## 反馈

遇到问题或有想法，欢迎到 [Issues](https://github.com/dozecat/rightkit/issues) 提出。附上 macOS 版本、RightKit 版本和自检面板的结论，会快很多。

想自己编译，或调试访达扩展为什么不刷新，见[构建指南](docs/BUILDING.md)。

## 📄 许可

[GNU General Public License v3.0](LICENSE)。RightKit 是自由软件，任何再分发的衍生版本都必须同样以 GPL-3.0 开源。
