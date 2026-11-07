import CryptoKit
import Foundation

let environment = ProcessInfo.processInfo.environment
let defaultPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ClashBar/UpdateSigning/ed25519.privatekey").path
let keyURL = URL(fileURLWithPath: environment["CLASHBAR_SIGNING_KEY_FILE"] ?? defaultPath)
let createKey = environment["CLASHBAR_CREATE_UPDATE_KEY"] == "1"
let manager = FileManager.default
let key: Curve25519.Signing.PrivateKey
if manager.fileExists(atPath: keyURL.path) {
    let encoded = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    guard let data = Data(base64Encoded: encoded), data.count == 32 else { fatalError("更新私钥格式无效，已停止；不会替换已有密钥。") }
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
} else {
    guard createKey else { fatalError("尚未配置更新私钥，请先运行密钥初始化脚本。") }
    try manager.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    key = Curve25519.Signing.PrivateKey()
    try Data(key.rawRepresentation.base64EncodedString().utf8).write(to: keyURL, options: .withoutOverwriting)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
