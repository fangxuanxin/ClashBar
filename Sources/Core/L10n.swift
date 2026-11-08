import Foundation

/// 界面语言选项：跟随系统 / 英文 / 简体中文
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    /// 语言名称始终用该语言自身书写，方便在任何界面语言下辨认
    var nativeName: String {
        switch self {
        case .system: return L10n.t("language.system")
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

/// 轻量本地化：所有文案集中在 `catalog`，用 `{name}` 形式的具名占位符
enum L10n {
    /// 当前用户选择；由 Preferences 在启动和切换时写入
    nonisolated(unsafe) static var selection: AppLanguage = .system

    /// 实际生效的语言代码（en 或 zh-Hans）
    static var code: String { resolve(selection, preferred: Locale.preferredLanguages) }

    /// 把「跟随系统」解析成具体语言；不支持的语言回落到英文
    static func resolve(_ language: AppLanguage, preferred: [String]) -> String {
        if language != .system { return language.rawValue }
        for identifier in preferred {
            let lower = identifier.lowercased()
            if lower.hasPrefix("zh") { return "zh-Hans" }
            if lower.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    static func t(_ key: String, _ values: [String: String] = [:], language: String? = nil) -> String {
        let table = catalog[language ?? code] ?? catalog["en"]!
        var text = table[key] ?? catalog["en"]?[key] ?? key
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }

    // MARK: - 文案表

    static let catalog: [String: [String: String]] = [
        "en": [
            "updates.title": "Updates",
            "updates.check": "Check for Updates…",
            "updates.checking": "Checking for updates…",
            "updates.upgrade": "Install Update",
            "updates.installing": "Installing update…",
            "updates.ready": "Update ready, restart now…",
            "updates.auto_check": "Automatically check for updates",
            "updates.auto_install": "Automatically download and install updates",
            "updates.channel": "Update channel",
            "updates.channel.stable": "Stable",
            "updates.channel.beta": "Beta",
            "updates.source.brew": "Managed by Homebrew",
            "updates.source.direct": "Direct download · Sparkle",
            "updates.source.dev": "Development build",
            "updates.source.store": "Updates are managed by the Mac App Store.",
            "updates.dev_hint": "This build has no Developer ID signature or update key. Automatic replacement is disabled.",
            "updates.open_release": "View Published Releases…",
            "updates.up_to_date": "You are up to date.",
            "updates.found": "Version {version} is available.",
            "updates.last_check": "Last checked: {time}",
            "updates.confirm": "Install version {version} using Homebrew? ClashBar will restart after the update.",
            "updates.cancel": "Cancel",
            "updates.failed": "Update failed: {reason}",
            "updates.busy": "An update is being installed. Please wait before quitting.",
            "updates.command_failed": "The update command failed: {reason}",
            "updates.error.invalidReceipt": "Cannot identify the Homebrew tap managing this installation.",
            "updates.error.ambiguousInstallation": "More than one Homebrew installation claims this app.",
            "updates.error.invalidResponse": "The update response is invalid or does not match this app.",
            "updates.error.pinned": "This application is pinned in Homebrew. Unpin it before updating.",
            "updates.error.unchanged": "The installed application did not reach the requested version.",
            "updates.error.timeout": "The update command timed out.",
            "updates.error.unavailable": "Updates are unavailable for this installation.",
            "language.system": "Follow System",
            "language.title": "Language",

            "menu.mode": "Outbound Mode",
            "menu.mode.current": "Mode: {mode}",
            "mode.rule": "Rule",
            "mode.global": "Global",
            "mode.direct": "Direct",
            "menu.groups": "Proxy Groups",
            "menu.no_groups": "No proxy groups",
            "menu.test_latency": "Test Latency",
            "menu.test_group": "Test This Group",
            "menu.refresh": "Refresh",
            "menu.copy": "Copy Exit Info",
            "menu.settings": "Settings…",
            "menu.setup": "Set Up Controller…",
            "menu.about": "About ClashBar",
            "menu.quit": "Quit ClashBar",
            "menu.auto_group": "Picked automatically ({type})",
            "menu.controller": "Controller",
            "menu.controller.auto": "Automatic",

            "card.connecting": "Connecting…",
            "card.not_configured": "No controller found",
            "card.not_configured.hint": "Add your Clash / Mihomo controller in Settings.",
            "card.error": "Controller unreachable",
            "card.direct": "Direct mode",
            "card.direct.hint": "Traffic is not going through a proxy.",
            "card.reject": "Rejecting traffic",
            "card.testing": "Testing…",
            "card.timeout": "Core check failed",
            "card.alive": "{alive}/{total} nodes alive",
            "card.updated": "Updated {time}",
            "card.just_now": "just now",
            "card.via_rule": "MATCH rule",
            "card.inferred": "inferred",

            "error.not_configured": "No Clash controller configured or detected.",
            "error.invalid_url": "The controller address is not a valid URL.",
            "error.unauthorized": "Wrong or missing secret (HTTP 401).",
            "error.http": "Controller returned HTTP {status}.",
            "error.unreachable": "Cannot reach the controller: {reason}",
            "error.timeout": "The controller did not respond in time.",
            "error.not_found": "API path not found (HTTP 404). Use the controller address, not a dashboard page.",
            "error.bad_response": "Unexpected response from the controller.",
            "error.action_failed": "Action failed: {reason}",

            "copy.text": "Group: {group}\nNode: {node}\nPath: {path}\nMode: {mode}\nController: {controller}",

            "tooltip.other": "{group} · {node}",
            "tooltip.unhealthy": "The core’s latest health check failed; this does not establish an outage",
            "settings.passive_latency": "Latency is read from existing core health checks. ClashBar does not initiate tests.",

            "settings.title": "ClashBar Settings",
            "settings.general": "General",
            "settings.controllers": "Controllers",
            "settings.about": "About",
            "settings.refresh": "Refresh every",
            "settings.seconds": "{n} seconds",
            "settings.minutes": "{n} minutes",
            "settings.minute": "1 minute",
            "settings.test_url": "Latency test URL",
            "settings.show_latency": "Show latency next to the menu bar icon",
            "settings.login": "Launch at login",
            "settings.login.approval": "Approve ClashBar in System Settings → General → Login Items.",
            "settings.login.failed": "Could not change the login item: {reason}",
            "settings.menu_bar": "Menu Bar",
            "settings.behavior": "Behavior",
            "settings.legend": "The cat is followed by the exit region (US, JP, HK…); → means direct. A faded icon means the current node is not responding.",

            "controllers.active": "Use",
            "controllers.auto": "Automatic (try saved controllers)",
            "controllers.none_reachable": "None of the saved controllers are reachable.",
            "controllers.saved": "Saved Controllers",
            "controllers.none": "No saved controllers yet.",
            "controllers.add": "Add Controller",
            "controllers.edit": "Edit",
            "controllers.delete": "Delete",
            "controllers.detected": "Detected",
            "controllers.scan": "Scan Again",
            "controllers.scanning": "Scanning…",
            "controllers.nothing_found": "Nothing detected on this Mac or the gateway.",
            "controllers.use": "Add",
            "controllers.ready": "Ready · {version}",
            "controllers.needs_secret": "Needs secret",
            "controllers.unreachable": "Unreachable",
            "controllers.name": "Name",
            "controllers.url": "Address",
            "controllers.url.placeholder": "http://192.168.1.1:9090",
            "controllers.secret": "Secret",
            "controllers.socket": "Unix socket (optional)",
            "controllers.host": "Host",
            "controllers.port": "Port",
            "controllers.show_secret": "Show secret",
            "controllers.hide_secret": "Hide secret",
            "controllers.advanced": "Advanced",
            "controllers.paste_hint": "Tip: paste a dashboard link such as http://192.168.1.1:9090/ui/ into Host and it will be split automatically.",
            "controllers.test": "Test Connection",
            "controllers.testing": "Testing…",
            "controllers.test_ok": "Connected · {version}",
            "controllers.save": "Save",
            "controllers.cancel": "Cancel",
            "controllers.new_name": "My Controller",

            "about.tagline": "See which region your Clash exit is in, right in the menu bar.",
            "about.version": "Version {version}",
            "about.mb_enabled": "MB enabled",
            "about.mb_disabled": "MB disabled",
"about.dev": "Development build",

"discovery.this_mac": "This Mac",
"discovery.local_app": "{app} (this Mac)",
"discovery.router": "Router {host}",
"discovery.via_config": "from {app} config",
"discovery.via_port": "local port",
"discovery.via_gateway": "default gateway",
        ],
        "zh-Hans": [
            "updates.title": "更新",
            "updates.check": "检查更新…",
            "updates.checking": "正在检查更新…",
            "updates.upgrade": "安装更新",
            "updates.installing": "正在安装更新…",
            "updates.ready": "更新已就绪，重启安装…",
            "updates.auto_check": "自动检查更新",
            "updates.auto_install": "自动下载并安装更新",
            "updates.channel": "更新通道",
            "updates.channel.stable": "正式版",
            "updates.channel.beta": "测试版",
            "updates.source.brew": "由 Homebrew 管理更新",
            "updates.source.direct": "直接下载版 · Sparkle 更新",
            "updates.source.dev": "开发版本",
            "updates.source.store": "更新由 Mac App Store 管理。",
            "updates.dev_hint": "此版本尚未配置 Developer ID 签名或更新公钥，未启用自动替换应用。",
            "updates.open_release": "查看发布版本…",
            "updates.up_to_date": "当前已是最新版本。",
            "updates.found": "发现新版本 {version}。",
            "updates.last_check": "上次检查：{time}",
            "updates.confirm": "通过 Homebrew 安装 {version}？完成后 ClashBar 会重新启动。",
            "updates.cancel": "取消",
            "updates.failed": "更新失败：{reason}",
            "updates.busy": "正在安装更新，请等待完成后再退出。",
            "updates.command_failed": "更新命令失败：{reason}",
            "updates.error.invalidReceipt": "无法确认管理此应用的 Homebrew 仓库。",
            "updates.error.ambiguousInstallation": "多个 Homebrew 安装记录指向此应用。",
            "updates.error.invalidResponse": "更新响应无效或与此应用不匹配。",
            "updates.error.pinned": "此应用已在 Homebrew 中固定版本，解除固定后才能更新。",
            "updates.error.unchanged": "安装后的应用未达到目标版本。",
            "updates.error.timeout": "更新命令执行超时。",
            "updates.error.unavailable": "此安装暂时无法使用更新功能。",
            "language.system": "跟随系统",
            "language.title": "语言",

            "menu.mode": "出站模式",
            "menu.mode.current": "模式：{mode}",
            "mode.rule": "规则",
            "mode.global": "全局",
            "mode.direct": "直连",
            "menu.groups": "代理分组",
            "menu.no_groups": "没有代理分组",
            "menu.test_latency": "测试延迟",
            "menu.test_group": "测试本组",
            "menu.refresh": "立即刷新",
            "menu.copy": "复制出口信息",
            "menu.settings": "设置…",
            "menu.setup": "设置控制器…",
            "menu.about": "关于 ClashBar",
            "menu.quit": "退出 ClashBar",
            "menu.auto_group": "由内核自动选择（{type}）",
            "menu.controller": "控制器",
            "menu.controller.auto": "自动",

            "card.connecting": "正在连接…",
            "card.not_configured": "未找到控制器",
            "card.not_configured.hint": "请在设置里添加 Clash / Mihomo 控制器。",
            "card.error": "控制器无法访问",
            "card.direct": "直连模式",
            "card.direct.hint": "流量没有经过代理。",
            "card.reject": "正在拒绝流量",
            "card.testing": "测试中…",
            "card.timeout": "内核检测失败",
            "card.alive": "{alive}/{total} 个节点在线",
            "card.updated": "{time}更新",
            "card.just_now": "刚刚",
            "card.via_rule": "MATCH 规则",
            "card.inferred": "推测",

            "error.not_configured": "没有配置或发现 Clash 控制器。",
            "error.invalid_url": "控制器地址不是有效的 URL。",
            "error.unauthorized": "口令错误或缺失（HTTP 401）。",
            "error.http": "控制器返回 HTTP {status}。",
            "error.unreachable": "无法连接控制器：{reason}",
            "error.timeout": "控制器响应超时。",
            "error.not_found": "API 路径不存在（HTTP 404），请填控制器地址而不是面板页面。",
            "error.bad_response": "控制器返回了无法识别的数据。",
            "error.action_failed": "操作失败：{reason}",

            "copy.text": "分组：{group}\n节点：{node}\n路径：{path}\n模式：{mode}\n控制器：{controller}",

            "tooltip.other": "{group} · {node}",
            "tooltip.unhealthy": "内核最近一次健康检查失败，不代表实际断线",
            "settings.passive_latency": "延迟读取内核已有的健康检查记录，ClashBar 不发起额外测速。",

            "settings.title": "ClashBar 设置",
            "settings.general": "通用",
            "settings.controllers": "控制器",
            "settings.about": "关于",
            "settings.refresh": "刷新间隔",
            "settings.seconds": "{n} 秒",
            "settings.minutes": "{n} 分钟",
            "settings.minute": "1 分钟",
            "settings.test_url": "延迟测试地址",
            "settings.show_latency": "在菜单栏图标旁显示延迟",
            "settings.login": "登录时启动",
            "settings.login.approval": "请在 系统设置 → 通用 → 登录项 中允许 ClashBar。",
            "settings.login.failed": "无法修改登录项：{reason}",
            "settings.menu_bar": "菜单栏",
            "settings.behavior": "行为",
            "settings.legend": "猫的右边是出口所在地区（US、JP、HK……），→ 表示直连。图标变淡表示当前节点无响应。",

            "controllers.active": "使用",
            "controllers.auto": "自动（轮询已保存的控制器）",
            "controllers.none_reachable": "已保存的控制器均无法连接。",
            "controllers.saved": "已保存的控制器",
            "controllers.none": "还没有保存的控制器。",
            "controllers.add": "添加控制器",
            "controllers.edit": "编辑",
            "controllers.delete": "删除",
            "controllers.detected": "检测到的",
            "controllers.scan": "重新扫描",
            "controllers.scanning": "扫描中…",
            "controllers.nothing_found": "本机和网关上都没有检测到控制器。",
            "controllers.use": "添加",
            "controllers.ready": "可用 · {version}",
            "controllers.needs_secret": "需要口令",
            "controllers.unreachable": "无法连接",
            "controllers.name": "名称",
            "controllers.url": "地址",
            "controllers.url.placeholder": "http://192.168.1.1:9090",
            "controllers.secret": "口令",
            "controllers.socket": "Unix 套接字（可选）",
            "controllers.host": "主机",
            "controllers.port": "端口",
            "controllers.show_secret": "显示口令",
            "controllers.hide_secret": "隐藏口令",
            "controllers.advanced": "高级",
            "controllers.paste_hint": "提示：可以把面板链接（如 http://192.168.1.1:9090/ui/）直接粘贴到「主机」，会自动拆分。",
            "controllers.test": "测试连接",
            "controllers.testing": "测试中…",
            "controllers.test_ok": "连接成功 · {version}",
            "controllers.save": "保存",
            "controllers.cancel": "取消",
            "controllers.new_name": "我的控制器",

            "about.tagline": "在菜单栏直接看到 Clash 出口落在哪个国家或地区。",
            "about.version": "版本 {version}",
            "about.mb_enabled": "MB 功能已开启",
            "about.mb_disabled": "MB 功能已关闭",
"about.dev": "开发版本",

"discovery.this_mac": "本机",
"discovery.local_app": "{app}（本机）",
"discovery.router": "路由器 {host}",
"discovery.via_config": "来自 {app} 配置",
"discovery.via_port": "本机端口",
"discovery.via_gateway": "默认网关",
        ],
    ]
}
