import Foundation

/// 控制器地址的拆分形式（主机 / 端口 / HTTPS），供表单逐项编辑。
/// 能识别用户直接粘贴的各种写法：纯 IP、IP:端口、完整 URL、带 /ui/... 的面板链接，
/// 以及 yacd / metacubexd / zashboard 链接里携带的 hostname、port、secret 参数。
struct ControllerAddress: Equatable {
    var host: String
    var port: Int
    var https: Bool

    static let defaultPort = 9090

    /// 只保留协议、主机、端口：API 根地址
    var url: String {
        let bracketed = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(https ? "https" : "http")://\(bracketed):\(port)"
    }

    /// 解析任意输入；secret 仅在链接参数里带了口令时返回
    static func parse(_ input: String) -> (address: ControllerAddress, secret: String?)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let components = URLComponents(string: text), let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = components.host, !host.isEmpty else { return nil }

        // 面板链接的参数既可能在 ?query，也可能在 #/setup?query 里
        var params: [String: String] = [:]
        for item in components.queryItems ?? [] { params[item.name.lowercased()] = item.value }
        if let fragment = components.fragment, let mark = fragment.firstIndex(of: "?"),
           let inner = URLComponents(string: "x:/?" + fragment[fragment.index(after: mark)...]) {
            for item in inner.queryItems ?? [] { params[item.name.lowercased()] = item.value }
        }

        var https = scheme == "https"
        var port = components.port ?? (https ? 443 : defaultPort)
        if let paramHost = params["hostname"] ?? params["host"], !paramHost.isEmpty {
            host = paramHost
            if let value = params["https"] { https = ["1", "true", "yes"].contains(value.lowercased()) }
            port = params["port"].flatMap(Int.init) ?? (https ? 443 : defaultPort)
        } else if let paramPort = params["port"].flatMap(Int.init) {
            port = paramPort
        }
        guard (1...65535).contains(port) else { return nil }
        let secret = (params["secret"] ?? params["token"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (ControllerAddress(host: host, port: port, https: https), secret)
    }
}
