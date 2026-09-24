# RightKit

面向 macOS 的 Finder 右键增强工具。通过 Finder Sync 扩展向右键菜单注入常用操作，追求极简、快速与可扩展。

## 功能

- 新建文件：在 Finder 空白处右键，按模板创建文件
- 复制路径：复制选中项或当前目录的绝对路径
- 压缩 / 解压：调用第三方压缩软件（v1 支持 Keka）
- 脚本扩展：放入脚本包即生效，经 XPC 服务隔离执行

详细需求见 [docs/右键工具功能要求.md](docs/右键工具功能要求.md)。

## 工程架构

```
RightKit.app          主应用（设置界面）
FinderSyncExtension   Finder 右键扩展
ScriptXPCService      脚本执行服务
Shared                三个 target 共用的业务逻辑源码
```

完整目录说明见 [docs/项目结构.md](docs/项目结构.md)。

## 开发环境

- macOS 13 Ventura 及以上
- Xcode 15 及以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

## 构建

工程文件由 `project.yml` 生成，不入库。首次进入项目后执行：

```sh
xcodegen generate
open RightKit.xcodeproj
```

修改 `project.yml` 或增删文件后，重新执行 `xcodegen generate` 即可。

## 代码规范

```sh
brew install swiftlint
swiftlint
```

## 许可

[GNU General Public License v3.0](LICENSE)

RightKit 是自由软件：你可以依据自由软件基金会发布的 GPL-3.0 条款重新分发和/或修改它。任何再分发的衍生版本都必须同样以 GPL-3.0 开源。
