# 用 Xcode 打开 ClashBar

双击项目根目录的 `ClashBar.xcodeproj`。左上角选择 ClashBar，运行目标选择 My Mac，点击 ▶ 或按 ⌘R。
这是菜单栏应用，启动后在屏幕右上角找猫咪图标，没有普通主窗口。若已有 ClashBar 在运行，先从猫咪菜单退出旧实例，再运行开发版。

工程直接引用现有 Sources 源码，默认编译商店版（APP_STORE），使用沙盒和出站网络权限，不包含 Sparkle。控制器需要 HTTP/HTTPS 地址；商店版配置与直接下载版相互独立。

## 签名

在左侧点击蓝色项目图标，选择 TARGETS → ClashBar → Signing & Capabilities，勾选 Automatically manage signing，在 Team 中选择自己的开发者团队。若没有团队，先到 Xcode → Settings → Accounts 添加 Apple 账号。个人免费团队不具备商店发布资格。

本机无证书的构建验证可以使用 ad hoc 签名；正式开发运行和上传时应选择对应团队。上架前确认 Bundle Identifier 属于该团队。当前默认值为 org.clashbar.ClashBar。

## 上传

在 TARGETS → ClashBar → General 设置 Version 和 Build；每次重新上传递增 Build。Xcode 工程的版本设置与 Resources/Info.plist 中脚本构建使用的版本分别维护，发布前保持一致。

选择 Product → Archive。完成后在 Organizer 选择 Distribute App → App Store Connect，按提示签名和上传。上传不会直接上架，仍需在 App Store Connect 填写商店资料并提交审核。

证书、描述文件、隐私政策、截图及实际沙盒测试要求见 [商店发布准备](app-store.md)。脚本构建入口继续可用。
