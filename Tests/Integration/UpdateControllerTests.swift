import AppKit
import Foundation

@main
enum UpdateControllerTests {
    @MainActor static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("ClashBar brew process " + UUID().uuidString)
        let executable = root.appendingPathComponent("bin/brew")
        try manager.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let script = """
        #!/bin/sh
        printf 'Homebrew warning on stderr\\n' >&2
        if [ "$1" = fail ]; then
            printf 'deliberate failure\\n' >&2
            exit 9
        fi
        printf '{"casks":[]}'
        """
        try Data(script.utf8).write(to: executable)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let installation = HomebrewInstallation(prefix: root, tap: "fangxuanxin/tap")
        let output = try await UpdateController.runBrew(installation, arguments: ["info"])
        guard let object = try JSONSerialization.jsonObject(with: output) as? [String: Any], object["casks"] != nil else {
            fatalError("stderr 警告污染了 Homebrew JSON")
        }
        do {
            _ = try await UpdateController.runBrew(installation, arguments: ["fail"])
            fatalError("没有拒绝失败的 Homebrew 命令")
        } catch UpdateFailure.command(let detail) {
            guard detail.contains("deliberate failure") else { fatalError("丢失 Homebrew 错误详情") }
        }
        let suite = "org.clashbar.update-preferences-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "updateAutomaticChecks")
        defaults.set(true, forKey: "SUAutomaticallyUpdate")
        let updater = UpdateController(defaults: defaults)
        updater.start()
        guard !updater.automaticChecks, updater.automaticInstallation else { fatalError("关闭检查不应丢失安装偏好") }
        guard !updater.supportsChecks, !updater.supportsInstallationPreference else { fatalError("开发构建不应启动自动替换") }
        updater.stop()
        print("✓ Homebrew 进程隔离、失败传播、关闭检查时保留安装偏好和开发构建保护通过")
    }
}
