# 发布流程

面向维护者。目标产物是一个已公证、可直接分发的 `RightKit-<版本>.dmg` 及其 `.sha256`。

## 一次性准备

### 1. Developer ID Application 证书

只有 `Apple Development` 证书是不够的：它签出来的包在别人机器上会被 Gatekeeper 拦下，也无法送公证。

- Apple Developer → Certificates, Identifiers & Profiles → Certificates → **+** → **Developer ID Application**
- 导出 `.cer` 后双击装入「登录」钥匙串，确认能看到：

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. 公证凭据

`notarytool` 需要一份存在钥匙串里的凭据（密码是 **App 专用密码**，不是账号密码）：

```bash
xcrun notarytool store-credentials rightkit-notary \
    --apple-id "<你的 Apple ID>" --team-id 6T9RSL7KL6 \
    --password "<App 专用密码>"

xcrun notarytool history --keychain-profile rightkit-notary   # 验证
```

### 3. 开发者后台的 App Group

主应用与访达扩展通过 `$(TeamIdentifierPrefix)group.com.dozecat.RightKit` 共享容器，而**扩展是沙盒的**，所以这个 App Group 必须在后台为该 Team 注册，并包含在 Developer ID 的配置文件里。归档后确认：

```bash
codesign -d --entitlements :- RightKit.app | grep application-groups
ls RightKit.app/Contents/embedded.provisionprofile
```

## 每次发布

1. **改版本号**：`project.yml` 里的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，同时在 `CHANGELOG.md` 补上这一版，提交。
2. **确认工作区干净**：`git status --short`。未提交的改动不会进包，但会让你对不上 tag。
3. **打包**：

```bash
Scripts/package-release.sh                   # 完整流程：归档 → 导出 → 公证 → 装订 → DMG
Scripts/package-release.sh --skip-notarize   # 本地演练，产物不可分发
```

4. **打 tag 并推送**：

```bash
git tag -a v1.0.0 -m "RightKit 1.0.0" && git push origin v1.0.0
```

5. **建 GitHub Release**，上传 `RightKit-1.0.0.dmg` 与 `RightKit-1.0.0.dmg.sha256`，正文用下面的模板。
6. **发布后核对**：README 顶部的版本徽章应从 `no releases or repo not found` 变成版本号；下载链接可用。徽章依赖公开仓库与已发布的 Release，仓库仍是私有的话这两项对外都不生效。

## 脚本做了什么

前置检查（工具链、Developer ID 证书、公证凭据、`MARKETING_VERSION` 与 `--version` 一致）→ `xcodegen generate` → `xcodebuild archive` → `xcodebuild -exportArchive` → 产物自检 → 用带 `/Applications` 快捷方式的暂存目录做 DMG → `notarytool submit --wait` → `stapler` → `spctl` → SHA-256。中间产物都落在 `.build/`（已被忽略，不会入库）。

## 手动验证清单

```bash
APP=.build/export/RightKit.app

lipo -archs "$APP/Contents/MacOS/RightKit"                     # 期望 arm64 x86_64
codesign -d --entitlements :- "$APP" | grep -c get-task-allow  # 期望 0
codesign --verify --deep --strict "$APP"
for n in "$APP/Contents/PlugIns/"*.appex "$APP/Contents/XPCServices/"*.xpc; do
    codesign --verify --strict "$n"
done
spctl -a -vvv -t exec "$APP"                                   # source=Notarized Developer ID
xcrun stapler validate .build/RightKit-1.0.0.dmg
ls "$APP/Contents/Resources/BuiltinTemplates" "$APP/Contents/Resources/BuiltinScripts"
```

**App 图标**：`RightKit/Info.plist` 里**不需要**写图标键。`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 会让 actool 产出 `AppIcon.icns`，Xcode 再自动往 Info.plist 注入 `CFBundleIconFile` 与 `CFBundleIconName`。归档实测：

```
Contents/Resources/AppIcon.icns
"CFBundleIconFile" => "AppIcon"
"CFBundleIconName" => "AppIcon"
```

**Profile 与 App Group**：用 Developer ID 签名后，App 与扩展里应出现 `Contents/embedded.provisionprofile`，它才是 App Group 的授权凭据。本地演练不会有这份 profile，此时沙盒扩展在别人机器上可能拿不到共享容器——`package-release.sh` 会对此给出 warning。

## 归档产物自检（2026-10-03 实测）

用 Apple Development 身份做本地归档时的实测值，可作为「什么算正常」的参照：

| 项目 | 实测 |
|---|---|
| 架构 | `x86_64 arm64`（通用二进制，工程未设 `ARCHS`） |
| 加固运行时 | `flags=0x10000(runtime)` ✓ |
| Team | `TeamIdentifier=6T9RSL7KL6` ✓ |
| 主应用 entitlements | `app-sandbox = false` + `application-groups = 6T9RSL7KL6.group.com.dozecat.RightKit` |
| 扩展 entitlements | `app-sandbox = true` + 同一 App Group + `files.user-selected.read-only` |
| XPC entitlements | `app-sandbox = false` + 同一 App Group |
| `get-task-allow` | 不存在 ✓ |
| 内嵌组件 | `Contents/PlugIns/FinderExtension.appex`、`Contents/XPCServices/ScriptXPCService.xpc` |
| 内置资源 | `Resources/BuiltinTemplates`（3 个模板）、`Resources/BuiltinScripts`（2 个脚本包） |
| `-exportArchive -method developer-id` | 失败：`No signing certificate "Developer ID Application" found` —— 这正是发布前必须补上的那一步 |

`package-release.sh` 里的前置检查就是照着这些期望写的。它在**归档之前**就会因为没有 Developer ID 身份而退出——这是有意的：`-exportArchive -method developer-id` 无论如何都需要该证书，跑到一半再失败没有意义。

> **个人团队（Personal Team）发布不了**：免费账号即使已在 Xcode 登录，也申请不到 Developer ID Application 证书，更无法送公证，配置文件还只有 7 天有效期。要出可分发的 Release，必须先把该 Apple ID 加入付费的 Apple Developer Program。用 `defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier` 可以看到当前登录的是哪种团队（`isFreeProvisioningTeam = 1` 即个人团队）。

## 不做公证的退路

没有 Developer ID 证书时只能内部分发，而且第一个用户就会撞上 Gatekeeper。这种情况下：

- 在 README 的下载一节写明「首次打开请右键 → 打开」；
- 或让用户执行 `xattr -d com.apple.quarantine /Applications/RightKit.app`；
- **不要**把未公证的包发到公开 Release。

## 常见失败

| 现象 | 原因与处理 |
|---|---|
| `No signing certificate "Developer ID Application" found` | 证书未安装或私钥没导出；见「一次性准备 1」 |
| `notarytool` 报 401 / Invalid credentials | 用成了账号密码；重新 `store-credentials` 并改用 App 专用密码 |
| 公证日志说 `The signature does not include a secure timestamp` | 手工签名漏了 `--timestamp`；用本脚本，`xcodebuild` 会自动加 |
| 公证日志说某个可执行文件 `not signed` | 扩展或 XPC 没签上；用 `codesign --verify --deep --strict` 定位 |
| 别人机器上右键菜单不出现 | 访达扩展未启用，或 App 没放进 `/Applications` |
| 压缩、脚本在别人机器上失败 | 权限未授予，或 Keka 未开启主文件夹访问；见 README 的权限表 |
| 版本徽章仍是红色 | 仓库私有，或还没有 Release |

## Release Notes 模板（v1.0.0 草稿）

```markdown
### RightKit 1.0.0

第一个公开版本：把新建文件、拷贝路径、压缩解压这些常用操作放进 Finder 的右键菜单，
只显示当前选中内容用得上的那些。

- **九项操作**：新建文件、拷贝路径、拷贝文件名、在此处打开终端、脚本、压缩为 ZIP、
  压缩为 7Z、解压到当前文件夹、解压到独立文件夹
- **新建文件**：内置文本、Markdown、Word、Excel、PowerPoint 五种模板，建好直接进入重命名
- **压缩解压**：装了 Keka 就用 Keka，没装就用系统自带的 zip、ditto、tar，格式覆盖交给它们
- **脚本扩展**：写一个 shell 脚本放进脚本目录就是一个菜单项；自带「用 VS Code 打开」
  与「运行 Python 脚本」
- **中英双语**，切换即时生效

**系统要求**：macOS 13 Ventura 或更高版本

下载后把 RightKit 拖进「应用程序」，首次启动会弹出自检面板，逐项告诉你还需要开启
哪些权限（访达扩展、辅助功能；用 7z 还需要 Keka 的主文件夹访问权限）。

---

### RightKit 1.0.0

First public release: new file, copy path, compress and extract — the everyday actions,
in Finder's context menu, and only the ones that fit what you selected.

- **Nine actions**: New File, Copy Path, Copy File Name, Open Terminal Here, Scripts,
  Compress to ZIP, Compress to 7Z, Extract Here, Extract into Separate Folder
- **New File**: five built-in templates (text, Markdown, Word, Excel, PowerPoint),
  created straight into rename mode
- **Compress and extract**: Keka if you have it, the system's own zip, ditto and tar
  if you do not — format coverage comes from those tools
- **Scripts as an extension point**: any executable `script.sh` in the scripts folder
  becomes a menu item; Open in VS Code and Run Python ship with the app
- **English and Simplified Chinese**, switched instantly

**Requires** macOS 13 Ventura or later.

Drag RightKit into your Applications folder; the self-check panel on first launch walks
through the permissions it still needs (Finder extension, Accessibility, and Keka's home
folder access for 7z).
```
