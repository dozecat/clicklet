# 发布流程

面向维护者。目标产物是一个可分发的 `Clicklet-<版本>.dmg` 及其 `.sha256`。

## 两种模式

Clicklet 目前走**路径 B**：用本机的 Apple Development 证书签名、**不做公证**。原因是当前 Apple ID 是免费的个人团队（Personal Team），申请不到 Developer ID Application 证书，也无法送公证。

| | 路径 B（当前） | 路径 A（付费会员后） |
|---|---|---|
| 签名证书 | Apple Development | Developer ID Application |
| 公证 | 无 | 有（`notarytool` + `stapler`） |
| 产物来源 | 直接从 `.xcarchive` 取 app | `xcodebuild -exportArchive` |
| 用户首次打开 | 需手动放行一次 | 双击即可 |
| 命令 | `Scripts/package-release.sh --development` | `Scripts/package-release.sh` |

`package-release.sh` 会自动判断：钥匙串里有 Developer ID Application 就走路径 A，否则（或显式传 `--development`）走路径 B。

## 路径 B：不公证发布（当前采用）

### 每次发布

1. 改版本号：`project.yml` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，在 `CHANGELOG.md` 补上这一版，提交。
2. 确认工作区干净：`git status --short`。
3. 打包：

```bash
Scripts/package-release.sh --development
```

产物在 `.build/Clicklet-<版本>.dmg`（`.build/` 已忽略，不入库）。

4. 打 tag 并推送：

```bash
git tag -a v1.0.0 -m "Clicklet 1.0.0" && git push origin v1.0.0
```

5. 建 GitHub Release，上传 `.dmg` 与 `.dmg.sha256`，正文用下面的模板。**正文里必须写明首次打开要手动放行**，README 的下载一节也已写入同样内容。
6. 发布后核对：README 顶部的版本徽章应从 `no releases or repo not found` 变成版本号——这需要仓库公开且有已发布的 Release。

### 路径 B 必须一起交代/验证的事

- **首次打开被 Gatekeeper 拦下**：这是未公证的必然结果。给用户三条路：右键点按 → 打开；「系统设置 → 隐私与安全性 → 仍要打开」；终端执行 `xattr -dr com.apple.quarantine /Applications/Clicklet.app`。README 已写好这段。
- **必须在另一台 Mac 上实测**：开发签名的构建里，App 与扩展都没有 `embedded.provisionprofile`。主应用不开沙盒，写 `~/Library/Group Containers/` 不成问题；但**扩展是沙盒的**，它的 App Group 访问通常依赖描述文件授权。若扩展拿不到共享容器，右键菜单会根本不出现。自检面板里的 App Group 检查项可直接给出结论。首次对外发布前，请找一台干净的 Mac 走一遍完整流程。
- **证书有效期**：当前 Apple Development 证书 2027-09-25 到期。到期后需要重新签名并重发，否则新下载的用户会更难打开（已安装的仍可用）。
- **App 图标与权限**：与路径 A 完全一致，无需改动。

### 什么时候升级到路径 A

加入付费 Apple Developer Program、装好 Developer ID Application 证书后，直接运行 `Scripts/package-release.sh`（不带 `--development`）即可，其余流程不变。

## 路径 A：公证发布

### 一次性准备

1. **Developer ID Application 证书**（需要付费会员，Account Holder 或 Admin 角色）。Xcode → Settings → Accounts → Manage Certificates… → `+` → Developer ID Application；验证：

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

2. **公证凭据**（密码是 App 专用密码，不是账号密码）：

```bash
xcrun notarytool store-credentials clicklet-notary \
    --apple-id "<你的 Apple ID>" --team-id 6T9RSL7KL6 \
    --password "<App 专用密码>"

xcrun notarytool history --keychain-profile clicklet-notary    # 验证
```

3. **开发者后台的 App Group**：扩展是沙盒的，`$(TeamIdentifierPrefix)group.com.dozecat.Clicklet` 必须在后台为该 Team 注册，并包含在 Developer ID 配置文件里。归档后确认：

```bash
codesign -d --entitlements :- Clicklet.app | grep application-groups
ls Clicklet.app/Contents/embedded.provisionprofile
```

### 每次发布

1. 改版本号并更新 `CHANGELOG.md`，提交；确认 `git status --short` 干净。
2. `Scripts/package-release.sh`（自动识别为路径 A）。
3. 打 tag、建 Release、上传 `.dmg` 与 `.sha256`。

## 脚本做了什么

前置检查（工具链、`MARKETING_VERSION` 与 `--version` 一致、按证书选择模式，路径 A 还会校验 `ExportOptions.plist` 与公证凭据）→ `xcodegen generate` → `xcodebuild archive` → 路径 A 走 `-exportArchive`，路径 B 直接从归档取 app → 产物自检 → 用带 `/Applications` 快捷方式的暂存目录做 DMG → 路径 A 送 `notarytool submit --wait` 并 `stapler`，路径 B 打印未公证警告 → SHA-256。中间产物都在 `.build/`。

## 手动验证清单

```bash
# 路径 B
APP=.build/Clicklet.xcarchive/Products/Applications/Clicklet.app
# 路径 A
# APP=.build/export/Clicklet.app

lipo -archs "$APP/Contents/MacOS/Clicklet"                     # 期望 x86_64 arm64
codesign -d --entitlements :- "$APP" | grep -c get-task-allow  # 期望 0
codesign --verify --deep --strict "$APP"
for n in "$APP/Contents/PlugIns/"*.appex "$APP/Contents/XPCServices/"*.xpc; do
    codesign --verify --strict "$n"
done
ls "$APP/Contents/Resources/BuiltinTemplates" "$APP/Contents/Resources/BuiltinScripts"

# 仅路径 A
spctl -a -vvv -t exec "$APP"                                   # source=Notarized Developer ID
xcrun stapler validate .build/Clicklet-1.0.0.dmg
```

**App 图标**：`Clicklet/Info.plist` 里**不需要**写图标键。`ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` 会让 actool 产出 `AppIcon.icns`，Xcode 再自动往 Info.plist 注入 `CFBundleIconFile` 与 `CFBundleIconName`。

## 归档产物自检（2026-10-03 实测）

用 Apple Development 身份做本地归档时的实测值，可作为「什么算正常」的参照：

| 项目 | 实测 |
|---|---|
| 架构 | `x86_64 arm64`（通用二进制，工程未设 `ARCHS`） |
| 加固运行时 | `flags=0x10000(runtime)` ✓ |
| Team | `TeamIdentifier=6T9RSL7KL6` ✓ |
| 主应用 entitlements | `app-sandbox = false` + `application-groups = 6T9RSL7KL6.group.com.dozecat.Clicklet` |
| 扩展 entitlements | `app-sandbox = true` + 同一 App Group + `files.user-selected.read-only` |
| XPC entitlements | `app-sandbox = false` + 同一 App Group |
| `get-task-allow` | 不存在 ✓ |
| 内嵌组件 | `Contents/PlugIns/FinderExtension.appex`、`Contents/XPCServices/ScriptXPCService.xpc` |
| 内置资源 | `Resources/BuiltinTemplates`（3 个模板）、`Resources/BuiltinScripts`（2 个脚本包） |
| 内嵌描述文件 | **无**（开发签名的必然结果，见上文的实测要求） |
| `-exportArchive -method developer-id` | 失败：`No signing certificate "Developer ID Application" found` —— 路径 A 的前置条件 |

## 常见失败

| 现象 | 原因与处理 |
|---|---|
| 用户反馈「App 已损坏，无法打开」 | 未公证 + 已加隔离属性。让用户右键 → 打开，或 `xattr -dr com.apple.quarantine`；根治办法是走路径 A |
| 别人机器上右键菜单完全不出现 | 访达扩展未启用；或扩展拿不到 App Group 共享容器（路径 B 的已知风险，用自检面板确认） |
| `No signing certificate "Developer ID Application" found` | 路径 A 缺少证书；要么申请证书，要么改用 `--development` |
| `xcodebuild` 报 `sandbox-exec: sandbox_apply: Operation not permitted` | Swift 宏插件服务无法启动（常见于受限沙箱环境）。在正常的本地终端或 Xcode 里构建 |
| `notarytool` 报 401 / Invalid credentials | 用成了账号密码；重新 `store-credentials` 并改用 App 专用密码 |
| 公证日志说 `The signature does not include a secure timestamp` | 手工签名漏了 `--timestamp`；用本脚本，`xcodebuild` 会自动加 |
| 公证日志说某个可执行文件 `not signed` | 扩展或 XPC 没签上；用 `codesign --verify --deep --strict` 定位 |
| 版本徽章仍是红色 | 仓库私有，或还没有 Release |

## Release Notes 模板（v1.0.0 草稿）

```markdown
### Clicklet 1.0.0

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

**首次打开**：安装包未经 Apple 公证，macOS 会提示「无法验证开发者」。请右键点按
Clicklet → 打开，在弹窗里再点一次「打开」；或在「系统设置 → 隐私与安全性」里点
「仍要打开」。

下载后把 Clicklet 拖进「应用程序」，首次启动会弹出自检面板，逐项告诉你还需要开启
哪些权限（访达扩展、辅助功能；用 7z 还需要 Keka 的主文件夹访问权限）。

---

### Clicklet 1.0.0

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

**First launch**: this build is not notarized, so macOS will say it cannot verify the
developer. Right-click Clicklet, choose Open, then Open again in the dialog — or allow
it under System Settings → Privacy & Security.

Drag Clicklet into your Applications folder; the self-check panel on first launch walks
through the permissions it still needs (Finder extension, Accessibility, and Keka's home
folder access for 7z).
```
