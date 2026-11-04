import Foundation

/// 一个控制器的连接参数。socketPath 有值时优先走 Unix 套接字。
struct ControllerConfig: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var url: String
    var secret: String = ""
    var socketPath: String? = nil

    /// 用于界面展示的地址
    var displayAddress: String {
        if let socketPath, !socketPath.isEmpty { return socketPath }
        return url.replacingOccurrences(of: "http://", with: "").replacingOccurrences(of: "https://", with: "")
    }

    /// 连接身份，用于判断是否同一个控制器（与 id、名称无关）
    var endpointKey: String { [url, secret, socketPath ?? ""].joined(separator: "|") }
}

enum ClashError: Error, Equatable {
    case notConfigured
    case invalidURL
    case unauthorized
    case http(Int)
    case unreachable(String)
    case timeout
    case badResponse

    var message: String {
        switch self {
        case .notConfigured: return L10n.t("error.not_configured")
        case .invalidURL: return L10n.t("error.invalid_url")
        case .unauthorized: return L10n.t("error.unauthorized")
        case .http(404): return L10n.t("error.not_found")
        case .http(let status): return L10n.t("error.http", ["status": String(status)])
        case .unreachable(let reason): return L10n.t("error.unreachable", ["reason": reason])
        case .timeout: return L10n.t("error.timeout")
        case .badResponse: return L10n.t("error.bad_response")
        }
    }
}

/// Clash / Mihomo RESTful API 客户端
struct ClashClient: Sendable {
    let config: ControllerConfig

    /// 关键：控制器请求绝不能走系统代理，否则会绕回 Clash 自己
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: configuration)
    }()

    /// 路径片段编码：分组名里的空格、emoji、斜杠都要转义
    static func encode(_ component: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }

    /// 发送请求，返回 2xx 的响应体；其他状态码映射成 ClashError
    func send(_ method: String = "GET", _ path: String, query: [URLQueryItem] = [],
              body: [String: Any]? = nil, timeout: TimeInterval = 6) async throws -> Data {
        let bodyData = try body.map { try JSONSerialization.data(withJSONObject: $0) }
        var queryString = ""
        if !query.isEmpty {
            var components = URLComponents()
            components.queryItems = query
            queryString = "?" + (components.percentEncodedQuery ?? "")
        }
        let status: Int
        let data: Data
        if let socket = config.socketPath, !socket.isEmpty {
            (status, data) = try await UnixSocketHTTP.send(socketPath: socket, method: method, target: path + queryString,
                                                         secret: config.secret, body: bodyData, timeout: timeout)
        } else {
            let base = config.url.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: base + path + queryString), let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https", url.host != nil else { throw ClashError.invalidURL }
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = method
            if !config.secret.isEmpty { request.setValue("Bearer \(config.secret)", forHTTPHeaderField: "Authorization") }
            if let bodyData {
                request.httpBody = bodyData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let (responseData, response) = try await Self.session.data(for: request)
                status = (response as? HTTPURLResponse)?.statusCode ?? 0
                data = responseData
            } catch let error as URLError {
                if error.code == .timedOut { throw ClashError.timeout }
                if error.code == .cancelled { throw CancellationError() }
                throw ClashError.unreachable(error.localizedDescription)
            }
        }
        switch status {
        case 200..<300: return data
        case 401, 403: throw ClashError.unauthorized
        case 408, 504: throw ClashError.timeout
        default: throw ClashError.http(status)
        }
    }

    func get<T: Decodable>(_ path: String, as type: T.Type, query: [URLQueryItem] = [], timeout: TimeInterval = 6) async throws -> T {
        let data = try await send("GET", path, query: query, timeout: timeout)
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw ClashError.badResponse }
    }

    // MARK: - 接口

    func version() async throws -> VersionResponse { try await get("/version", as: VersionResponse.self, timeout: 4) }
    func configs() async throws -> ConfigsResponse { try await get("/configs", as: ConfigsResponse.self) }
    func proxies() async throws -> [String: ProxyItem] { try await get("/proxies", as: ProxiesResponse.self, timeout: 10).proxies }
    func rules() async throws -> [RuleItem] { try await get("/rules", as: RulesResponse.self, timeout: 10).rules }

    func setMode(_ mode: OutboundMode) async throws {
        _ = try await send("PATCH", "/configs", body: ["mode": mode.rawValue])
    }

    func select(group: String, node: String) async throws {
        _ = try await send("PUT", "/proxies/\(Self.encode(group))", body: ["name": node])
    }

    /// 单节点测速；返回毫秒，失败返回 nil
    func delay(of proxy: String, testURL: String, timeoutMs: Int = 5000) async -> Int? {
        let query = [URLQueryItem(name: "url", value: testURL), URLQueryItem(name: "timeout", value: String(timeoutMs))]
        guard let data = try? await send("GET", "/proxies/\(Self.encode(proxy))/delay", query: query,
                                         timeout: TimeInterval(timeoutMs) / 1000 + 3),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = object["delay"] as? Int, delay > 0 else { return nil }
        return delay
    }

    /// 整组测速（Mihomo 的 /group/{name}/delay）；结果会写进内核的 history，刷新后即可看到
    func groupDelay(of group: String, testURL: String, timeoutMs: Int = 5000) async throws -> [String: Int] {
        let query = [URLQueryItem(name: "url", value: testURL), URLQueryItem(name: "timeout", value: String(timeoutMs))]
        let data = try await send("GET", "/group/\(Self.encode(group))/delay", query: query,
                                  timeout: TimeInterval(timeoutMs) / 1000 + 5)
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }
}

/// 经 Unix 套接字发 HTTP/1.0 请求（Clash Verge 等默认用套接字暴露控制器）
enum UnixSocketHTTP {
    static func send(socketPath: String, method: String, target: String, secret: String,
                     body: Data?, timeout: TimeInterval) async throws -> (Int, Data) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try sendBlocking(socketPath: socketPath, method: method, target: target,
                                                                    secret: secret, body: body, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func sendBlocking(socketPath: String, method: String, target: String, secret: String,
                             body: Data?, timeout: TimeInterval) throws -> (Int, Data) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClashError.unreachable(String(cString: strerror(errno))) }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw ClashError.invalidURL }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (i, byte) in pathBytes.enumerated() { buffer[i] = UInt8(bitPattern: byte) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw ClashError.unreachable(String(cString: strerror(errno))) }

        var head = "\(method) \(target) HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n"
        if !secret.isEmpty { head += "Authorization: Bearer \(secret)\r\n" }
        if let body { head += "Content-Type: application/json\r\nContent-Length: \(body.count)\r\n" }
        head += "\r\n"
        var request = Data(head.utf8)
        if let body { request.append(body) }
        try request.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if written <= 0 { throw ClashError.unreachable(String(cString: strerror(errno))) }
                offset += written
            }
        }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { throw ClashError.timeout }
                throw ClashError.unreachable(String(cString: strerror(errno)))
            }
            response.append(buffer, count: count)
            if response.count > 32 * 1024 * 1024 { throw ClashError.badResponse }
        }
        return try parse(response)
    }

    /// 解析 HTTP 响应（兼容 chunked）
    static func parse(_ response: Data) throws -> (Int, Data) {
        guard let separator = response.range(of: Data("\r\n\r\n".utf8)),
              let header = String(data: response[..<separator.lowerBound], encoding: .utf8) else { throw ClashError.badResponse }
        let lines = header.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2, let status = Int(parts[1]) else { throw ClashError.badResponse }
        var body = Data(response[separator.upperBound...])
        let chunked = lines.dropFirst().contains { $0.lowercased().hasPrefix("transfer-encoding:") && $0.lowercased().contains("chunked") }
        if chunked {
            var decoded = Data()
            var rest = body[...]
            while let lineEnd = rest.range(of: Data("\r\n".utf8)) {
                let sizeText = String(data: rest[..<lineEnd.lowerBound], encoding: .ascii)?.split(separator: ";").first ?? ""
                guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16) else { throw ClashError.badResponse }
                if size == 0 { break }
                let start = lineEnd.upperBound
                guard rest.distance(from: start, to: rest.endIndex) >= size else { throw ClashError.badResponse }
                let end = rest.index(start, offsetBy: size)
                decoded.append(rest[start..<end])
                rest = rest[min(rest.index(end, offsetBy: 2, limitedBy: rest.endIndex) ?? rest.endIndex, rest.endIndex)...]
            }
            body = decoded
        }
        return (status, body)
    }
}
