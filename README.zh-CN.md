# ClashBar

[English](README.md) | 简体中文

原生 macOS 菜单栏应用，适用于提供 Clash API 的内核（Clash、Mihomo、sing-box）。在菜单栏就能看到默认出口落在哪个国家或地区，不用打开面板就能切换模式和节点。

> 早期开发中（v0.2.1），暂未使用 Developer ID 签名。

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
| 猫变淡 | 内核最近一次检测失败，或还在连接；不代表实际断线 |
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
- **代理分组**：每个分组显示当前选择。展开可看成员和内核已有的最近延迟，可选择成员（仅 Selector 分组）。
- **刷新**（⌘R）、**复制出口信息**（⌘C）。
- **控制器**：在已保存的控制器和自动检测之间切换。
- **设置…**（⌘,）。

ClashBar 不会自动切换节点，也不发起额外测速。默认每 30 秒读取一次控制器状态，延迟优先取出口分组测速网址对应的内核记录；FXProxy X 等现有脚本和内核继续负责健康检查。缺少时间或结果超过 10 分钟时显示未知，不补发探测。菜单和设置不再提供主动测速入口。

### 切换历史

菜单「切换历史…」（⌘H）打开独立窗口，可查看最近 1 小时、24 小时、7 天和 30 天的观测记录，并筛选控制器或任意分组。时间线显示选择持续区间，事件列表保留完整路径；节点统计展示观测选择时长、延迟中位数、测速失败与样本数。同一节点经不同分组到达也会记录路径变化，模式变化和分组配置变化单独标注。

记录从启用后积累，无法补回安装前或应用退出期间的切换。两次轮询间的短暂切换可能漏掉；切换时间表示检测时间。睡眠、断连、暂停和超时造成的空白不计为稳定时长。负载均衡及无法解析到唯一节点的路径不伪造最终节点。测速样本读取当前出口节点已有的内核结果，保留原始时间并去重；旧版主动测速记录单独标识，可通过来源筛选查看。测速失败不等于实际断网，选择时间不代表流量使用或在线时长。

历史库位于应用支持目录的 `History/history.sqlite`，仅当前用户可读，不记录明文口令、控制器地址、访问域名或连接明细。保留最近 30 天，不创建备份。点击窗口底部的「导出…」可选择位置，将库中全部控制器的原始路径区间和测速样本导出为 JSON，不受当前筛选影响；时间戳使用 Unix 秒，失败样本的延迟保留为 null。可在窗口暂停记录、清空全部控制器历史。删除控制器配置不会删除其历史；记录不上传开发者服务器。

## 控制器

选择「自动」后，按保存顺序逐个尝试控制器（包含各自的口令），锁定第一个连通的配置；断线或网络变化后重新轮询。同一 IP 可以保存多份不同口令、不同名称的配置，不按路由器型号区分。全部失败时保留配置并定期重试；手动选择控制器时只连接指定配置。

没有保存的配置时自动寻找控制器：

- 本机配置文件里的 `external-controller`、`external-controller-unix` 和 `secret`（Clash Verge、ClashX Meta、Mihomo Party、`~/.config/clash`、`~/.config/mihomo` 等）
- `127.0.0.1:9090` / `9097`
- 默认网关上的 `9090` / `9097` 端口（例如跑 OpenClash 的路由器）

都找不到时会打开「设置 → 控制器」，列出检测结果。需要口令的控制器会标为**需要口令**：点**添加**，填入口令，再点**测试连接**。

控制器保存在 `~/Library/Application Support/ClashBar/controllers.json`，只有当前用户可读。访问控制器的请求始终绕过系统代理。

## 构建

需要 macOS 13 及以上和 Xcode Command Line Tools，不强制安装完整 Xcode。直接下载版构建会首次下载并校验固定版本的 Sparkle 框架，之后使用缓存。

```sh
Scripts/build.sh              # 跑核心测试，生成 build/ClashBar.app
Scripts/install.sh            # 更新猫咪图标、构建、安装到 /Applications 并清理旧副本
Scripts/package.sh            # 通用二进制（arm64 + x86_64），生成 build/ClashBar.zip 和 sha256
Scripts/make-icon.sh          # 重新生成 Resources/AppIcon.icns
```

设置 `SIGN_IDENTITY="Developer ID Application: …"` 可用 hardened runtime 签名。不设时为临时（ad hoc）签名，本机能用，但下载后会被 Gatekeeper 拦下。公开发布需要 Developer ID 签名并公证。

构建、图标、安装和打包脚本共用 `Scripts/build-env.sh`。默认产物在项目的 `build/`；可在不纳入 Git 的 `Scripts/build-storage.local.sh` 中设置 `CLASHBAR_SSD_ROOT`（外置工作目录）和 `CLASHBAR_SSD_UUID`（卷 UUID）。指定卷已挂载且目录可写时，缓存、临时文件和产物放到该目录的 `ClashBar/build/`，否则自动回退本机 `build/`。源码和 Git 始终留在项目中。

外置工作目录内存在 `Xcode.app` 时，构建会自动使用它；没有时继续使用本机工具。只对当前脚本进程设置工具链，不修改系统的 `xcode-select`。可用 `CLASHBAR_STORAGE=local Scripts/build.sh` 强制本机编译；显式设置的 `DEVELOPER_DIR` 优先。完整 Xcode 需另行安装，本配置不会下载它，也不迁移 Xcode 图形界面的缓存。编译过程中请保持硬盘连接。

## 自动更新

已接入 Sparkle：Developer ID 签名的直接下载版支持自动检查、下载安装及正式版/测试版通道；Homebrew 安装支持在应用中检查并确认升级；开发构建打开 Releases。商店构建用 `CLASHBAR_DISTRIBUTION=app-store` 排除 Sparkle。

公开 v0.1.1 需手动升级一次。正式启用直接下载版自动更新还需要 Developer ID 签名、公证和发布已签名更新源；本次开发未发布这些产物。发布候选、私钥备份及真实升级测试见 [自动更新与发布](docs/updates.md)。

## 目录结构

```
Sources/Core   Clash API 客户端（HTTP + Unix 套接字）、出口解析、地区识别、控制器发现、多语言
Sources/App    菜单栏图标、状态卡片、设置窗口、应用状态
Tests          核心逻辑的无依赖测试（build.sh 会自动运行）
Resources      Info.plist、应用图标、本地化的 InfoPlist.strings
Scripts        构建 / 安装 / 打包 / 生成图标
```

内置英文和简体中文，默认跟随系统语言，可在「设置 → 通用 → 语言」里切换。
