import Foundation
import Network
import Darwin

struct CommandResult { var code: Int32; var output: String; var elapsed: Int }
struct HTTPResult { var code: Int; var body: String; var ms: Int; var error: String }
struct ProbeFailure: LocalizedError { var message: String; var errorDescription: String? { message } }
final class FinishOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let callback: (Result<T, Error>) -> Void
    init(_ callback: @escaping (Result<T, Error>) -> Void) { self.callback = callback }
    func finish(_ result: Result<T, Error>) { lock.lock(); if completed { lock.unlock(); return }; completed = true; lock.unlock(); callback(result) }
}

actor MetadataCache {
    static let shared = MetadataCache()
    private var entries: [String: (Date, HTTPResult)] = [:]
    func get(_ ip: String) -> HTTPResult? { guard let (date, result) = entries[ip], Date().timeIntervalSince(date) < 21600 else { return nil }; return result }
    func put(_ ip: String, _ value: HTTPResult) { entries = [ip: (Date(), value)] }
}

enum ProbeRunner {
    static func command(_ executable: String, _ args: [String], timeout: Double = 12) async -> CommandResult {
        await Task.detached(priority: .utility) {
            let start = Date(), process = Process(), output = Pipe()
            process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
            process.standardOutput = output; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                return CommandResult(code: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "", elapsed: Int(Date().timeIntervalSince(start) * 1000))
            } catch { return CommandResult(code: -1, output: "", elapsed: Int(Date().timeIntervalSince(start) * 1000)) }
        }.value
    }
    static func http(_ url: String, _ p: Preferences) async -> HTTPResult {
        // Explicit proxy and empty no-proxy prevent silent direct fallback.
        let r = await command("/usr/bin/curl", ["-q", "-sS", "--connect-timeout", "4", "--max-time", "10", "--proxy", p.proxy, "--noproxy", "", "--write-out", "\n__SENTINEL__%{http_code} %{time_starttransfer}", url])
        guard let split = r.output.range(of: "\n__SENTINEL__", options: .backwards) else { return HTTPResult(code: 0, body: "", ms: r.elapsed, error: "代理连接或 TLS 请求失败（curl \(r.code)）") }
        let parts = r.output[split.upperBound...].split(separator: " "), code = Int(parts.first ?? "0") ?? 0
        let ms = parts.count > 1 ? Int((Double(parts[1]) ?? 0) * 1000) : r.elapsed
        return HTTPResult(code: code, body: String(r.output[..<split.lowerBound]), ms: ms, error: r.code == 0 ? "" : "请求未完成（curl \(r.code)）")
    }
    static func object(_ s: String) -> [String: Any] { guard let data = s.data(using: .utf8) else { return [:] }; return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
    static func trace(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in s.split(separator: "\n") { let pieces = line.split(separator: "=", maxSplits: 1); if pieces.count == 2 { result[String(pieces[0])] = String(pieces[1]) } }
        return result
    }
    static func unixJSON(_ path: String, _ endpoint: String) throws -> [String: Any] {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ProbeFailure(message: "无法创建本地连接") }; defer { close(fd) }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { throw ProbeFailure(message: "本地套接字路径过长") }
        withUnsafeMutablePointer(to: &address.sun_path) { ptr in ptr.withMemoryRebound(to: CChar.self, capacity: 104) { destination in _ = path.withCString { strncpy(destination, $0, 103) } } }
        let connected = withUnsafePointer(to: &address) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard connected == 0 else { throw ProbeFailure(message: "未连接到 Mihomo，请确认 Clash Verge 正在运行") }
        let request = Array("GET \(endpoint) HTTP/1.0\r\nHost: localhost\r\n\r\n".utf8)
        var sent = 0
        while sent < request.count {
            let n = request.withUnsafeBytes { write(fd, $0.baseAddress!.advanced(by: sent), request.count - sent) }
            guard n > 0 else { throw ProbeFailure(message: "本地 API 请求失败") }; sent += n
        }
        var received = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        while true { let n = read(fd, &buffer, buffer.count); if n <= 0 { break }; received.append(contentsOf: buffer.prefix(n)); if received.count > 2_000_000 { throw ProbeFailure(message: "本地 API 响应过大") } }
        guard let marker = received.range(of: Data("\r\n\r\n".utf8)), let head = String(data: received[..<marker.lowerBound], encoding: .utf8), head.hasPrefix("HTTP/1.0 200") || head.hasPrefix("HTTP/1.1 200") else { throw ProbeFailure(message: "本地 API 未返回有效响应") }
        return (try JSONSerialization.jsonObject(with: received[marker.upperBound...])) as? [String: Any] ?? [:]
    }
    static func mihomo(_ p: Preferences) async -> (Check, String, Bool?) {
        await Task.detached(priority: .utility) {
            do {
                let config = try unixJSON(p.socketPath, "/configs"), response = try unixJSON(p.socketPath, "/proxies")
                let proxies = response["proxies"] as? [String: [String: Any]] ?? [:]
                var current = "前置节点自动切换", visited = Set<String>()
                while let next = proxies[current]?["now"] as? String, !visited.contains(current) { visited.insert(current); current = next }
                if current == "前置节点自动切换" { current = "未识别前置组" }
                let tun = (config["tun"] as? [String: Any])?["enable"] as? Bool ?? false
                return (Check(id: "mihomo", title: "代理链路", health: tun ? .good : .warning, value: tun ? "TUN 已开启" : "TUN 未开启", detail: "当前前置：\(current)。此项通过本地 API 读取，不修改代理。", source: "Mihomo 本地 Unix API"), current, config["ipv6"] as? Bool)
            } catch { return (Check(id: "mihomo", title: "代理链路", health: .unknown, value: "无法读取", detail: error.localizedDescription, source: "Mihomo 本地 Unix API"), "无法读取", nil) }
        }.value
    }
    static func datagram(host: String, port: UInt16, data: Data, timeout: Double = 5) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(host: .init(host), port: .init(rawValue: port)!, using: .udp)
            let gate = FinishOnce<Data> { result in connection.cancel(); continuation.resume(with: result) }
            let queue = DispatchQueue(label: "sentinel.udp.\(UUID())")
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        if let error { gate.finish(.failure(error)); return }
                        connection.receiveMessage { data, _, _, error in
                            if let error { gate.finish(.failure(error)) }
                            else if let data { gate.finish(.success(data)) }
                            else { gate.finish(.failure(ProbeFailure(message: "未收到响应"))) }
                        }
                    })
                case .failed(let error): gate.finish(.failure(error))
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { gate.finish(.failure(ProbeFailure(message: "请求超时"))) }
        }
    }
    static func dnsUpstreams() -> [String] {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml")
        guard let s = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        var inDNS = false, inList = false, result: [String] = []
        for line in s.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if line == "dns:" { inDNS = true; continue }
            if inDNS && !line.hasPrefix(" ") && !trimmed.isEmpty { break }
            guard inDNS else { continue }
            if trimmed == "nameserver:" { inList = true; continue }
            if inList {
                if trimmed.hasPrefix("- ") { result.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))) }
                else if !trimmed.isEmpty { break }
            }
        }
        return result
    }
    static func dns(_ p: Preferences) async -> Check {
        let id = UInt16.random(in: 1...65535)
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for part in ["example", "com"] { bytes.append(UInt8(part.utf8.count)); bytes.append(contentsOf: part.utf8) }; bytes += [0, 0, 16, 0, 1]
        let upstreams = dnsUpstreams(), routed = !upstreams.isEmpty && upstreams.allSatisfy { $0.contains("#住宅代理链") }
        do {
            let response = try await datagram(host: "127.0.0.1", port: UInt16(clamping: p.dnsPort), data: Data(bytes))
            let b = [UInt8](response)
            guard b.count >= 12, b[0] == bytes[0], b[1] == bytes[1], b[2] & 0x80 != 0, b[3] & 15 == 0 else { throw ProbeFailure(message: "DNS 响应无效或返回错误") }
            let label = upstreams.contains(where: { $0.contains("1.1.1.1") || $0.contains("1.0.0.1") }) ? "Cloudflare" : "已配置解析器"
            return Check(id: "dns", title: "DNS 路径", health: routed ? .good : .unknown, value: routed ? "代理解析 · \(label)" : "本地解析正常", detail: "本地 TXT 查询成功。" + (routed ? "配置指定上游经过住宅代理。" : "未确认上游是否经住宅代理。") + "此项不代替浏览器权威 DNS 泄露测试。", source: "127.0.0.1:\(p.dnsPort) 实测 + 本地上游配置")
        } catch { return Check(id: "dns", title: "DNS 路径", health: .warning, value: "本地解析未通过", detail: "\(error.localizedDescription)。请确认本地 DNS 监听端口；浏览器自带的安全 DNS 需要另行检测。", source: "本机 UDP DNS 查询") }
    }
    static func udp() async -> (String?, String) {
        let transaction = (0..<12).map { _ in UInt8.random(in: 0...255) }, cookie: [UInt8] = [0x21,0x12,0xA4,0x42]
        do {
            let result = [UInt8](try await datagram(host: "stun.l.google.com", port: 19302, data: Data([0,1,0,0] + cookie + transaction)))
            guard result.count >= 20, result[0] == 1, result[1] == 1, Array(result[8..<20]) == transaction else { throw ProbeFailure(message: "STUN 响应无效") }
            var index = 20
            while index + 4 <= result.count {
                let type = Int(result[index]) * 256 + Int(result[index+1]), length = Int(result[index+2]) * 256 + Int(result[index+3]); let start = index + 4
                guard start + length <= result.count else { break }
                if (type == 0x20 || type == 1) && length >= 8 && result[start+1] == 1 {
                    let ip = (0..<4).map { i in String(type == 0x20 ? result[start+4+i] ^ cookie[i] : result[start+4+i]) }.joined(separator: ".")
                    return (ip, "STUN 观测到的 UDP IPv4；不是浏览器 WebRTC 指纹测试。")
                }
                index = start + ((length + 3) / 4) * 4
            }
            return (nil, "STUN 未返回 IPv4 映射地址")
        } catch { return (nil, "STUN \(error.localizedDescription)。超时不等于已确认泄漏。") }
    }
    static func auth() async -> Check {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
        guard FileManager.default.isExecutableFile(atPath: path) else { return Check(id: "auth", title: "Claude 登录", health: .unknown, value: "未找到 CLI", detail: "默认检查 ~/.local/bin/claude；未读取钥匙串或提取 token。", source: "本地 Claude Code CLI") }
        let r = await command(path, ["auth", "status"], timeout: 10), d = object(r.output)
        guard let logged = d["loggedIn"] as? Bool else { return Check(id: "auth", title: "Claude 登录", health: .unknown, value: "状态读取失败", detail: "CLI 未返回可识别的登录状态。", source: "claude auth status") }
        return Check(id: "auth", title: "Claude 登录", health: logged ? .unknown : .warning, value: logged ? "有登录记录 · 待验证" : "需要登录", detail: logged ? "CLI 报告存在登录记录，但不能证明 OAuth 未过期或可刷新。此工具不调用模型、不提取 token。" : "请在自己的终端运行 claude auth login 完成登录。", source: "claude auth status（仅保留布尔结果）")
    }
    static func networkIPv6() async -> (Int, Int) {
        let result = await command("/usr/sbin/networksetup", ["-listallnetworkservices"], timeout: 5)
        let names = result.output.components(separatedBy: .newlines).dropFirst().map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*\r")) }.filter { !$0.isEmpty }
        var off = 0, found = 0
        for service in names {
            let r = await command("/usr/sbin/networksetup", ["-getinfo", service], timeout: 4)
            if r.output.contains("IPv6:") { found += 1; if r.output.contains("IPv6: Off") { off += 1 } }
        }
        return (off, found)
    }
    static func networkSnapshot(_ out: HTTPResult, _ api: HTTPResult) -> Snapshot {
        var s = Snapshot(); let t = trace(out.body)
        if out.code == 200, let ip = t["ip"] { s.ip = ip; s.country = t["loc"] ?? "未知" }
        s.checks.append(Check(id: "egress", title: "代理出口", health: s.ip == "尚未获取" ? .bad : .good, value: s.ip, detail: s.ip == "尚未获取" ? "\(out.error)；请确认 HTTP 代理地址。" : "Cloudflare 从本次代理请求观测到 \(s.country) 出口。此地址不等于直接测得的 Anthropic 所见地址。", source: "Cloudflare trace · 显式 HTTP 代理", milliseconds: out.ms))
        let apiGood = [200, 400, 401, 404, 405].contains(api.code)
        s.checks.append(Check(id: "api", title: "Claude API", health: apiGood ? .good : (api.code == 403 || api.code == 429 ? .warning : .bad), value: apiGood ? "可达 · \(api.ms) ms" : (api.code == 0 ? "连接失败" : "HTTP \(api.code)"), detail: apiGood ? "未认证 GET 返回 HTTP \(api.code)，证明网络可达，不代表账号、模型权限或登录有效。" : "\(api.error) 服务器状态 \(api.code)。未发送模型请求。", source: "api.anthropic.com/v1/messages", milliseconds: api.code == 0 ? nil : api.ms))
        return s
    }
    static func quick(_ p: Preferences) async -> Snapshot {
        async let egress = http("https://www.cloudflare.com/cdn-cgi/trace", p)
        async let api = http("https://api.anthropic.com/v1/messages", p)
        return await networkSnapshot(egress, api)
    }
    static func run(_ p: Preferences) async -> Snapshot {
        async let egressRequest = http("https://www.cloudflare.com/cdn-cgi/trace", p)
        async let apiRequest = http("https://api.anthropic.com/v1/messages", p)
        async let statusRequest = http("https://status.claude.com/api/v2/status.json", p)
        async let proxy = mihomo(p)
        async let dnsCheck = dns(p)
        async let authentication = auth()
        async let v6 = networkIPv6()
        async let udpResult: (String?, String) = p.udp ? udp() : (nil, "已在设置中暂停 UDP 检查")
        let (out, api, status, local, dnsValue, authValue, ipv6, udpValue) = await (egressRequest, apiRequest, statusRequest, proxy, dnsCheck, authentication, v6, udpResult)
        var s = networkSnapshot(out, api)
        s.front = local.1
        s.checks.append(local.0); s.checks.append(dnsValue)
        let udpHealth: Health = udpValue.0 == nil ? .unknown : (s.ip == "尚未获取" ? .unknown : (udpValue.0 == s.ip ? .good : .bad))
        s.checks.append(Check(id: "udp", title: "UDP 出口", health: udpHealth, value: udpValue.0.map { $0 == s.ip ? "与网页一致" : $0 } ?? (p.udp ? "未确认" : "已暂停"), detail: (udpValue.0.map { "UDP IPv4：\($0)。" } ?? "") + udpValue.1, source: "Google STUN · 本机系统路由"))
        let allOff = ipv6.1 > 0 && ipv6.0 == ipv6.1 && local.2 == false
        s.checks.append(Check(id: "ipv6", title: "IPv6 设置", health: allOff ? .good : .unknown, value: allOff ? "已关闭" : "需要核对", detail: "已读取接口 \(ipv6.0)/\(ipv6.1) 个关闭 IPv6。Mihomo：\(local.2.map { $0 ? "开启" : "关闭" } ?? "未知")。不推断未来新增接口的状态。", source: "macOS networksetup + Mihomo"))
        let st = object(status.body)["status"] as? [String: Any], indicator = st?["indicator"] as? String
        s.checks.append(Check(id: "official", title: "官方服务状态", health: indicator == nil ? .unknown : (indicator == "none" ? .good : .warning), value: indicator == nil ? "未获取" : (indicator == "none" ? "官方报告正常" : "官方报告有事件"), detail: st?["description"] as? String ?? "状态接口未返回有效 JSON；不据此判断本机连接正常。", source: "Anthropic 公开 Statuspage"))
        s.checks.append(authValue)
        if p.metadata && s.ip != "尚未获取" {
            let meta: HTTPResult
            if let cache = await MetadataCache.shared.get(s.ip) { meta = cache }
            else { meta = await http("https://ipinfo.io/\(s.ip)/json", p); if meta.code == 200 { await MetadataCache.shared.put(s.ip, meta) } }
            let d = object(meta.body), org = d["org"] as? String
            s.checks.append(Check(id: "metadata", title: "IP 属性", health: .unknown, value: org ?? "资料未获取", detail: "地区：\(d["country"] as? String ?? "未知") · \(d["region"] as? String ?? "未知")。运营商与地理资料不能证明住宅、独享或无滥用记录；未接入信誉评分库。", source: "IPinfo · 六小时缓存"))
        } else { s.checks.append(Check(id: "metadata", title: "IP 属性", health: .unknown, value: "未查询", detail: "未启用元数据查询或尚未取得出口。", source: "第三方 IP 资料")) }
        s.checks.append(Check(id: "locale", title: "时区与语言", health: .unknown, value: TimeZone.current.identifier, detail: "语言：\(Locale.preferredLanguages.prefix(3).joined(separator: ", "))。仅供核对，不推断所在地、账号处罚或 KYC。", source: "macOS 本机设置"))
        s.checks.append(Check(id: "browser", title: "浏览器指纹", health: .unknown, value: "需在浏览器检测", detail: "原生应用不把自身渲染信息冒充为 Chrome 的字体、Canvas、WebGL 或 WebRTC 结果。", source: "独立浏览器检测"))
        return s
    }
}
