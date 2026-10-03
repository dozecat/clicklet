<p align="center">
  <img width="120" src="RightKit/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" alt="RightKit">
</p>

<h1 align="center">RightKit</h1>

<p align="center">把最常用的操作放进 Finder 的右键菜单。</p>

<p align="center">
  <a href="https://github.com/dozecat/rightkit/releases"><img alt="下载" src="https://img.shields.io/github/v/release/dozecat/rightkit?style=flat-square"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square&logo=apple">
  <a href="LICENSE"><img alt="许可" src="https://img.shields.io/badge/license-GPLv3-blue?style=flat-square"></a>
</p>

<p align="center">
  <a href="README.md">中文</a> ·
  <a href="README.enUS.md">English</a>
</p>

RightKit 是 macOS 上的 Finder 右键增强工具。按模板新建文件、拷贝路径、压缩解压、运行自己的脚本，每一项都可以排序或关掉。

它以代理应用的形式运行：没有 Dock 图标，启动时不弹窗。设置从状态栏图标进入。

## ✨ 功能

归档项跟着选中的内容走：选中普通文件夹不会出现解压，选中的全是压缩包时不会出现压缩。

| 操作 | 作用于 | 说明 |
|---|---|---|
| ![](docs/images/icons/newFile.png) **新建文件** | 空白处 | 按模板建文件并直接进入重命名，也可以用你自己的模板 |
| ![](docs/images/icons/copyPath.png) **拷贝路径** | 选中项、空白处 | 复制绝对路径 |
| ![](docs/images/icons/copyFileName.png) **拷贝文件名** | 选中项 | 只复制文件名 |
| ![](docs/images/icons/terminal.png) **在此处打开终端** | 选中项、空白处 | 就在这个文件夹里打开终端 |
| ![](docs/images/icons/scripts.png) **脚本** | 选中项、空白处 | 运行你放进脚本目录的脚本 |
| ![](docs/images/icons/compressZip.png) **压缩为 ZIP** | 选中项 | 用你选定的压缩软件打包 |
| ![](docs/images/icons/compress7z.png) **压缩为 7Z** | 选中项 | 需要 Keka，没装时这一项不显示 |
| ![](docs/images/icons/extractHere.png) **解压到当前文件夹** | 压缩包 | 就解压在当前目录 |
| ![](docs/images/icons/extractFolder.png) **解压到独立文件夹** | 压缩包 | 解压到以压缩包命名的新文件夹 |

## 📸 截图

<p align="center"><img src="docs/images/settings-zh.png" width="640" alt="RightKit 设置窗口"></p>

## 📦 下载

到 [Releases](https://github.com/dozecat/rightkit/releases) 下载最新版，打开后将 **RightKit** 拖进「应用程序」文件夹。

第一次启动时，RightKit 会打开自检面板，告诉你还缺什么，并带你到对应的地方开启。

### 第一次使用需要开启的三项

| 项目 | 在哪里开 | 为什么 |
|---|---|---|
| **访达扩展** | 系统设置 → 隐私与安全性 → 扩展 | 不开的话右键菜单里不会出现任何项目 |
| **辅助功能** | 系统设置 → 隐私与安全性 → 辅助功能 | 「新建文件」之后要直接进入重命名，需要它 |
| **Keka 文件夹访问** | Keka → 设置 → 文件访问权限 → 启用主文件夹访问权限 | 只有用 7z 才需要；不开的话 Keka 碰不到你的文件 |

## 许可

[GNU General Public License v3.0](LICENSE)。RightKit 是自由软件，任何再分发的衍生版本都必须同样以 GPL-3.0 开源。
