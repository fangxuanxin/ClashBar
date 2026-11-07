# 自动更新与发布

参考 CodexBar 的渠道区分方式，使用 Sparkle 2.10.1，最低系统仍为 macOS 13。现有公开 v0.1.1 没有更新器，需要手动安装一次带更新器的版本，或通过 Homebrew 升级一次。

## 用户操作

- Developer ID 签名的直接下载版：菜单「检查更新…」，或「设置 → 关于」打开自动检查和自动下载安装。默认每天检查；下载完成后由 Sparkle 提示或退出时安装，保留用户配置。可选择正式版或测试版通道，测试通道也接收正式版。
- Homebrew 管理的副本：读取 Caskroom 安装记录确认所属 tap，每天检查正式版。用户点击安装并确认后，后台运行 `brew update` 和指定 cask 的 `upgrade`；验证实际应用版本后重启。记录已最新但应用落后时使用 `reinstall`。此渠道不静默安装，不提供测试通道。
- 本地开发或临时签名版：显示开发构建说明，按钮打开 GitHub Releases，关闭自动替换。
- `CLASHBAR_DISTRIBUTION=app-store`：不链接或打包 Sparkle，移除更新源和自动更新菜单，未来由 Mac App Store 更新。这个开关不等于已完成沙盒、商店签名或审核适配。

关闭自动检查不会删除自动安装偏好。更新器不发送节点或控制器信息，Sparkle 系统分析上报已关闭。

## 密钥和证书

更新包和更新源均用 Ed25519 签名；应用只包含 `Resources/UpdatePublicKey.txt` 中的公钥。私钥默认位于 `~/Library/Application Support/ClashBar/UpdateSigning/ed25519.privatekey`，权限为 600，未纳入 Git。请安全备份；发布后不能随意重新生成，否则旧版不能验证新更新。可用 `CLASHBAR_SIGNING_KEY_FILE` 指定恢复后的私钥文件。

首次初始化才运行：

```sh
CLASHBAR_CREATE_UPDATE_KEY=1 xcrun swift Scripts/update-key.swift
```

脚本只输出公钥，已有密钥时复用，格式错误时拒绝覆盖。公钥应与仓库中的文件一致。

正式直接下载版还需要 Apple Developer Program 的 Developer ID Application 证书及公证凭证。更新签名不能替代 Apple 代码签名或公证。当前开发机器尚无可用的 Developer ID 身份，本次没有生成或发布正式自动更新包。

## 生成发布候选

1. 修改 `Resources/Info.plist` 的显示版本和构建号。构建号为跨正式版和测试版统一递增的正整数。测试版显示版本使用 `0.1.3-beta.1` 一类格式。
2. 确认本地 `appcast.xml` 包含已有公开更新记录；首次发布时为空源正常，之后保留旧记录，尤其是最新正式版。将对应实现、版本号和公钥纳入待发布源码。
3. 在钥匙串安装 Developer ID 证书，用 `xcrun notarytool store-credentials` 自行保存公证凭证。不要将账号密码或证书私钥写入源码。
4. 运行：

```sh
SIGN_IDENTITY='Developer ID Application: 你的证书名称' \
APPLE_NOTARY_PROFILE='你的钥匙串公证凭证名称' \
Scripts/release.sh
```

脚本构建 arm64 和 x86_64 通用包，验证嵌套签名，提交 Apple 公证并装订票据，再压缩、签名更新包、生成并签名更新源，最后验证两份签名。候选在当前构建目录的 `releases/显示版本-构建号/`，包含 `ClashBar.zip`、`appcast.xml` 和 `SHA256SUMS`。已有目录拒绝覆盖；测试副本、错误私钥、回退构建号均被拒绝。

`Scripts/package.sh` 可用于开发压缩包，不执行公证或生成更新源，不能代替正式发布步骤。

## 公开发布顺序

脚本只生成候选，不自动上传或推送。人工确认后：

1. 为对应源码创建 `v显示版本` 标签，创建 GitHub Release，上传未经再次改动的 `ClashBar.zip` 和 `SHA256SUMS`。测试版标记为 prerelease。
2. 从 Release 的实际地址下载压缩包，校验 SHA256 与候选一致，确认 Apple 公证有效。
3. 将候选的已签名 `appcast.xml` 原样替换根目录文件并推送到 `main`。不要格式化或手工修改签名后的 XML；修改后必须重新签名。应用读取固定地址 `https://raw.githubusercontent.com/fangxuanxin/ClashBar/main/appcast.xml`。
4. 正式版再更新 `fangxuanxin/homebrew-tap` 的 `Casks/clashbar.rb`：版本、同一 Release 压缩包 URL 和 SHA256。测试版不改稳定 cask。
5. 使用上一个正式版的真实安装副本检查更新，验证检查、下载、安装、重启及配置保留。Homebrew 另用真正的 cask 安装验证升级和记录。

先确保包已公开可下载，再更新 feed。发布失败时保留旧更新源，不向用户推送损坏候选。本地测试成功不能替代公开渠道的验证。

## 验证

```sh
Scripts/build.sh --universal
Scripts/test-updater.sh
uv run Tests/Integration/update-smoke.py
CLASHBAR_DISTRIBUTION=app-store Scripts/build.sh
```

核心测试覆盖版本比较、Brew 安装归属、记录缺失、tap 匹配和升级计划。更新器测试使用独立的伪造 Brew 可执行文件检查 stderr 不污染 JSON、错误传播及开发构建保护，不升级本机软件。

Sparkle 集成测试使用本地回环 HTTP 服务、独立 bundle identifier 和独立应用副本。它实际执行测试通道的下载、验签、替换及重启，检查偏好保留；随后篡改压缩包，检查更新被拒绝且旧应用保留。只有 `CLASHBAR_UPDATE_TEST=1` 才编译特殊入口，不读取真实路由器配置，不更新 `/Applications/ClashBar.app`；正式发布脚本拒绝这种构建。

测试在当前构建目录的 `UpdateSmoke/` 留下诊断产物，需要已初始化的更新私钥和登录中的 macOS 图形会话。它验证本地更新机制，不声称完成 Developer ID、公证和公开源的端到端验证。
