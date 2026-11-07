import Foundation

func testUpdatePolicy() {
    expect(UpdateVersion("1.10.0")! > UpdateVersion("1.2.0")!, "版本按数字比较")
    expect(UpdateVersion("1.2.0")! > UpdateVersion("1.2.0-beta.9")!, "正式版高于测试版")
    expect(UpdateVersion("1.2.0-rc.1")! > UpdateVersion("1.2.0-beta.10")!, "候选版高于测试版")
    expect(UpdateVersion("1.2.0-beta.10")! > UpdateVersion("1.2.0-beta.2")!, "测试版数字比较")
    expectEqual(UpdateVersion("1.2"), UpdateVersion("1.2.0"), "尾部零归一化")
    expectEqual(UpdateVersion("1.0; echo bad"), nil, "拒绝命令注入版本")
    expectEqual(UpdateVersion("latest"), nil, "拒绝未知版本")
    expectEqual(UpdateVersion("99999999999999999999999.1"), nil, "拒绝整数溢出")

    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("ClashBar Update Tests " + UUID().uuidString)
    defer { try? manager.removeItem(at: root) }
    do {
        let app = root.appendingPathComponent("Applications/ClashBar.app")
        let caskroot = root.appendingPathComponent("brew/Caskroom")
        let version = caskroot.appendingPathComponent("clashbar/0.1.2")
        let metadata = caskroot.appendingPathComponent("clashbar/.metadata")
        try manager.createDirectory(at: app, withIntermediateDirectories: true)
        try manager.createDirectory(at: version, withIntermediateDirectories: true)
        try manager.createDirectory(at: metadata, withIntermediateDirectories: true)
        try manager.createSymbolicLink(at: version.appendingPathComponent("ClashBar.app"), withDestinationURL: app)
        let receipt = try JSONSerialization.data(withJSONObject: ["source": ["tap": "fxx/tap"]])
        try receipt.write(to: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        let found = try HomebrewInstallation.find(app: app, roots: [caskroot])
        expectEqual(found?.tap, "fxx/tap", "保留实际安装仓库别名")
        expectEqual(found?.qualifiedName, "fxx/tap/clashbar", "升级指定拥有此安装的仓库")
        let separate = root.appendingPathComponent("Copies/ClashBar.app")
        try manager.createDirectory(at: separate, withIntermediateDirectories: true)
        expectEqual(try HomebrewInstallation.find(app: separate, roots: [caskroot]), nil, "独立副本不误判为 Brew")
        let installation = found!
        func response(version: String = "0.1.3", installed: String = "0.1.2", tap: String = "fxx/tap", pinned: Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["casks": [["token": "clashbar", "tap": tap, "version": version, "installed": installed, "disabled": false, "pinned": pinned]]])
        }
        expectEqual(try BrewUpgradePlan.parse(response(), installation: installation, target: "0.1.3").command, "upgrade", "正常升级")
        expectEqual(try BrewUpgradePlan.parse(response(installed: "0.1.3"), installation: installation, target: "0.1.3").command, "reinstall", "记录已最新但应用落后时重装修复")
        for invalid in [try response(tap: "other/tap"), try response(version: "0.1.3;exit"), try response(version: "0.1.1"), try response(pinned: true)] {
            do {
                _ = try BrewUpgradePlan.parse(invalid, installation: installation, target: "0.1.3")
                expect(false, "应拒绝不匹配、非法、过旧或固定版本")
            } catch { expect(true, "拒绝不安全的升级计划") }
        }
        try manager.removeItem(at: metadata.appendingPathComponent("INSTALL_RECEIPT.json"))
        do {
            _ = try HomebrewInstallation.find(app: app, roots: [caskroot])
            expect(false, "缺少安装记录时不能当作直接下载版")
        } catch { expect(true, "缺少安装记录时停止自动更新") }
    } catch { expect(false, "更新测试准备失败：\(error)") }
}
