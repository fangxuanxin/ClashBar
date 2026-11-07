# ClashBar

[English](README.md) | 简体中文

原生 macOS 菜单栏应用，适用于提供 Clash API 的内核（Clash、Mihomo、sing-box）。在菜单栏就能看到默认出口落在哪个国家或地区，不用打开面板就能切换模式和节点。

> 早期开发中（v0.1.0），暂未使用 Developer ID 签名。

## 安装

```sh
brew tap fangxuanxin/tap
brew trust fangxuanxin/tap
brew install --cask fangxuanxin/tap/clashbar
```

也可以从 [Releases](https://github.com/fangxuanxin/ClashBar/releases) 下载 `ClashBar.zip`。应用还没经过公证，首次打开会被 macOS 拦下：到「系统设置 → 隐私与安全性」点**仍要打开**，或运行 `xattr -dr com.apple.quarantine /Applications/ClashBar.app`。

## 菜单栏图标

| 图标 | 含义 |
| --- | --- |
| 线条猫 + **US** / **JP** / **HK** … | 默认出口节点所在地区 |
| 只有猫 | 没能从节点名或分组名认出地区 |
| 猫变淡 | 当前节点没通过延迟测试，或还在连接 |
| 猫 + **→** | 直连模式，或默认分组选了 `DIRECT` |
| 猫 + **×** | 默认出口是 `REJECT` |
| 猫 + **!** | 控制器连不上、口令错误或尚未配置 |

默认出口的找法：规则模式取 `MATCH` 规则指向的策略，全局模式取 `GLOBAL`，然后沿每个分组当前的选择一路走到最终节点。

地区先看最终节点的名字，认不出再看路径上的分组名。依次识别：

1. 国旗 emoji（🇺🇸）
2. 作为独立单词出现的大写缩写（`US`、`JPN`）
3. 中英文地名（美国、东京、Singapore……）

`GB` 显示为 `UK`。不要求任何分组命名约定。

## 使用

点击图标打开菜单：

- **状态卡片**：出口分组、节点、延迟、模式、内核版本和更新时间。
- **出站模式**：规则 / 全局 / 直连（⌘1 / ⌘2 / ⌘3）。
- **代理分组**：每个分组显示当前选择。展开可看成员和最近延迟，可选择成员（仅 Selector 分组），也可整组测速。
- **测试延迟**（⌘T）、**刷新**（⌘R）、**复制出口信息**（⌘C）。
- **控制器**：在已保存的控制器和自动检测之间切换。
- **设置…**（⌘,）。

ClashBar 不会自己切换节点。默认每 30 秒刷新一次，每次只用一个请求测当前出口节点。

## 控制器

选择「自动」后，按保存顺序逐个尝试控制器（包含各自的口令），锁定第一个连通的配置；断线或网络变化后重新轮询。同一 IP 可以保存多份不同口令、不同名称的配置，不按路由器型号区分。全部失败时保留配置并定期重试；手动选择控制器时只连接指定配置。

没有保存的配置时自动寻找控制器：

- 本机配置文件里的 `external-controller`、`external-controller-unix` 和 `secret`（Clash Verge、ClashX Meta、Mihomo Party、`~/.config/clash`、`~/.config/mihomo` 等）
- `127.0.0.1:9090` / `9097`
- 默认网关上的 `9090` / `9097` 端口（例如跑 OpenClash 的路由器）

都找不到时会打开「设置 → 控制器」，列出检测结果。需要口令的控制器会标为**需要口令**：点**添加**，填入口令，再点**测试连接**。

控制器保存在 `~/Library/Application Support/ClashBar/controllers.json`，只有当前用户可读。访问控制器的请求始终绕过系统代理。

## 构建

需要 macOS 13 及以上和 Xcode Command Line Tools，不需要 Xcode 或其它依赖。

```sh
Scripts/build.sh              # 跑核心测试，生成 build/ClashBar.app
Scripts/install.sh            # 更新猫咪图标、构建、安装到 /Applications 并清理旧副本
Scripts/package.sh            # 通用二进制（arm64 + x86_64），生成 build/ClashBar.zip 和 sha256
Scripts/make-icon.sh          # 重新生成 Resources/AppIcon.icns
```

设置 `SIGN_IDENTITY="Developer ID Application: …"` 可用 hardened runtime 签名。不设时为临时（ad hoc）签名，本机能用，但下载后会被 Gatekeeper 拦下。公开发布需要 Developer ID 签名并公证。

## 目录结构

```
Sources/Core   Clash API 客户端（HTTP + Unix 套接字）、出口解析、地区识别、控制器发现、多语言
Sources/App    菜单栏图标、状态卡片、设置窗口、应用状态
Tests          核心逻辑的无依赖测试（build.sh 会自动运行）
Resources      Info.plist、应用图标、本地化的 InfoPlist.strings
Scripts        构建 / 安装 / 打包 / 生成图标
```

内置英文和简体中文，默认跟随系统语言，可在「设置 → 通用 → 语言」里切换。
