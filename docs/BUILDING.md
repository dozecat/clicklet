# 从源码构建

Clicklet 由一个主应用、一个 Finder Sync 扩展和一个 XPC 服务组成，用 Xcode 构建。`Clicklet.xcodeproj` 由 `project.yml` 生成，**不入库**，所以克隆之后要先跑一次 XcodeGen。

## 环境要求

- macOS 13 Ventura 或更高版本
- Xcode 15 或更高版本（项目使用 Swift 5.9）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 生成工程并运行

```bash
brew install xcodegen
git clone https://github.com/dozecat/clicklet.git
cd clicklet
xcodegen generate
open Clicklet.xcodeproj
```

在 Xcode 里选择 Clicklet scheme 运行。单元测试在 ClickletTests 目标里，⌘U 执行。

改过 `project.yml`（增删源文件、调整构建设置）之后要重新执行 `xcodegen generate`，工程文件不是事实源。

## 各 target 的职责

| Target | 类型 | 职责 |
|---|---|---|
| `Clicklet` | 主应用 | 设置窗口与自检；接收 Finder 请求，建文件、编排压缩、运行脚本、发送通知 |
| `FinderExtension` | Finder Sync 扩展 | 沙盒内构建右键菜单；拷贝路径与文件名；其余操作写成 App Group 请求并唤起主应用 |
| `ScriptXPCService` | XPC 服务 | 只接受主应用调用，按脚本 ID 校验后执行用户 `script.sh` |
| `ClickletTests` | 单元测试 | 覆盖压缩、模板、脚本目录、菜单快照等纯逻辑 |

## 调试访达扩展

Finder 会一直留着自己加载的扩展进程，重新构建只替换磁盘上的二进制，运行中的进程仍执行旧代码。症状是菜单标题没变，或者明明修好的 bug 看起来还在。

```bash
Scripts/reload-finder-extension.sh
```

这个脚本会退出 Clicklet、结束扩展进程并重启 Finder，让新二进制重新加载。

日志位置：

- 脚本执行日志：`~/Library/Logs/Clicklet/Scripts/<脚本名>/`
- 应用与扩展共用的诊断日志：App Group 容器里的 `Logs/clicklet.log`，即 `~/Library/Group Containers/*group.com.dozecat.Clicklet/Logs/clicklet.log`

## 签名与 App Group

`project.yml` 里填的是作者自己的 `DEVELOPMENT_TEAM` 与自动签名。用自己的账号构建时，把它换成你的 Team ID，或在 Xcode 的 Signing & Capabilities 里改。

主应用与 XPC 服务不开沙盒，访达扩展是沙盒的；三者共用 App Group `$(TeamIdentifierPrefix)group.com.dozecat.Clicklet`，这个值写在各自的 `.entitlements` 与 `ClickletAppGroupIdentifier` 里，改动时三处要同步。

## 相关文档

- [设计文档](DESIGN.md)：功能边界、沙盒约束与进程通信的完整设计
- [发布流程](RELEASING.md)：签名、公证、打包 DMG 与 Release 清单
