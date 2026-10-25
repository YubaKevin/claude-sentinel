import Foundation
import AppKit
import Combine
import Network

// Records contain diagnostic summaries only, never credentials or account identifiers.
enum Health: String, Codable { case good, warning, bad, unknown
    var title: String { switch self { case .good: return "正常"; case .warning: return "提醒"; case .bad: return "异常"; case .unknown: return "未知" } }
}
enum CatMood: String {
    case observing, stable, fluctuating, offline, checking, paused
    var title: String { switch self {
        case .observing: return "观察中"; case .stable: return "连接稳定"; case .fluctuating: return "有些波动"
        case .offline: return "连接中断"; case .checking: return "检查中"; case .paused: return "已暂停"
    } }
}
struct Stability {
    var mood: CatMood
    var explanation: String
    static func assess(_ history: [Snapshot], paused: Bool = false, checking: Bool = false, now: Date = Date()) -> Stability {
        if paused { return Stability(mood: .paused, explanation: "自动检查已暂停，保留上一次记录。") }
        let recent = Array(history.filter { now.timeIntervalSince($0.date) < 1800 }.suffix(6))
        guard let last = recent.last else { return Stability(mood: checking ? .checking : .observing, explanation: "等待真实检测结果。至少需要三次有效检查来评估网络稳定性。") }
        let networkDown = last.checks.first { $0.id == "egress" }?.health == .bad && last.checks.first { $0.id == "api" }?.health == .bad
        if networkDown || (recent.count >= 2 && recent.suffix(2).allSatisfy { $0.checks.first { $0.id == "api" }?.health == .bad }) { return Stability(mood: .offline, explanation: "当前网络检查失败，或服务端已连续两次不可达。") }
        if !last.transportGood { return Stability(mood: .fluctuating, explanation: "最近一次连接未通过，等待下一轮确认。") }
        if last.checks.first(where: { $0.id == "udp" })?.health == .bad { return Stability(mood: .fluctuating, explanation: "UDP 与网页出口不同，请检查代理链路。") }
        if last.checks.first(where: { $0.id == "dns" })?.health == .warning { return Stability(mood: .fluctuating, explanation: "本机 DNS 检查未通过，解析路径需要核对。") }
        guard recent.count >= 3 else { return Stability(mood: checking ? .checking : .observing, explanation: "已有 \(recent.count)/3 次记录；当前可达，稳定性仍在观察中。") }
        if Set(recent.map(\.ip).filter { $0 != "尚未获取" }).count > 1 { return Stability(mood: .fluctuating, explanation: "最近的网页出口 IP 发生过变化，请核对代理链路。") }
        let success = recent.filter(\.transportGood).count
        if success != recent.count { return Stability(mood: .fluctuating, explanation: "最近 \(recent.count) 次检查有 \(recent.count - success) 次连接未通过。") }
        let times = recent.compactMap(\.apiMS).map(Double.init)
        if times.count >= 3 {
            let mean = times.reduce(0,+) / Double(times.count)
            let deviation = sqrt(times.map { pow($0 - mean, 2) }.reduce(0,+) / Double(times.count))
            let span = (times.max() ?? 0) - (times.min() ?? 0)
            if deviation > max(300, mean * 0.4) && span > 500 { return Stability(mood: .fluctuating, explanation: "最近响应时间波动较大；这是短时网络观测，不是账号风险评级。") }
        }
        return Stability(mood: .stable, explanation: "最近 \(recent.count) 次连接均成功，出口一致，响应波动在当前阈值内。")
    }
}
struct Check: Identifiable, Codable {
    var id: String
    var title: String
    var health: Health
    var value: String
    var detail: String
    var source: String
    var milliseconds: Int? = nil
}
struct Snapshot: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var ip = "尚未获取"
    var country = "未知"
    var front = "尚未获取"
    var checks: [Check] = []
    var apiMS: Int? { checks.first { $0.id == "api" }?.milliseconds }
    var attention: [Check] { checks.filter { $0.health == .bad || $0.health == .warning } }
    var transportGood: Bool { checks.first { $0.id == "api" }?.health == .good && checks.first { $0.id == "egress" }?.health == .good }
    var title: String { transportGood ? "网络连接正常" : (checks.contains { $0.health == .bad } ? "有连接需要检查" : "等待检查结果") }
}
struct Preferences: Codable {
    var proxy = "http://127.0.0.1:7890"
    var socketPath = "/tmp/verge/verge-mihomo.sock"
    var dnsPort = 1053
    var interval = 300
    var udp = true
    var metadata = true
    var hideIP = false
    var monitorInterval = 30
    init() {}
    enum CodingKeys: String, CodingKey { case proxy, socketPath, dnsPort, interval, udp, metadata, hideIP, monitorInterval }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? proxy
        socketPath = try c.decodeIfPresent(String.self, forKey: .socketPath) ?? socketPath
        dnsPort = try c.decodeIfPresent(Int.self, forKey: .dnsPort) ?? dnsPort
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? interval
        udp = try c.decodeIfPresent(Bool.self, forKey: .udp) ?? udp
        metadata = try c.decodeIfPresent(Bool.self, forKey: .metadata) ?? metadata
        hideIP = try c.decodeIfPresent(Bool.self, forKey: .hideIP) ?? hideIP
        monitorInterval = max(15, try c.decodeIfPresent(Int.self, forKey: .monitorInterval) ?? 30)
    }
}
@MainActor final class SentinelState: ObservableObject {
    @Published var preferences: Preferences
    @Published var snapshot: Snapshot?
    @Published var history: [Snapshot] = []
    @Published var checking = false
    @Published var heartbeat: Snapshot?
    @Published var heartbeatHistory: [Snapshot] = []
    @Published var pulseChecking = false
    @Published var sleeping = false
    @Published var paused = false
    @Published var section = "概览"
    @Published var errorMessage: String?
    var changed: (() -> Void)?
    var showInspector: (() -> Void)?
    private var timer: Timer?
    private var runningTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var lastPathFingerprint: String?
    private var sleepObservers: [NSObjectProtocol] = []
    let folder: URL
    init() {
        folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ClaudeSentinel", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if let d = try? Data(contentsOf: folder.appendingPathComponent("preferences.json")), let p = try? JSONDecoder().decode(Preferences.self, from: d) { preferences = p } else { preferences = Preferences() }
        if let d = try? Data(contentsOf: folder.appendingPathComponent("history.json")), let h = try? JSONDecoder().decode([Snapshot].self, from: d) { history = Array(h.suffix(96)); snapshot = history.last }
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                guard !self.paused, !self.sleeping else { return }
                if !self.checking && Date().timeIntervalSince(self.snapshot?.date ?? .distantPast) >= Double(self.preferences.interval) { self.refresh() }
                if !self.pulseChecking && !self.checking && Date().timeIntervalSince(self.heartbeat?.date ?? .distantPast) >= Double(self.preferences.monitorInterval) { self.checkHeartbeat() }
            }
        }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let fingerprint = Self.pathFingerprint(path)
            Task { @MainActor in
            guard let self else { return }
            let previous = self.lastPathFingerprint
            self.lastPathFingerprint = fingerprint
            if let previous, previous != fingerprint, !self.paused, !self.sleeping { self.invalidateMonitoring(); self.refresh() }
        } }
        pathMonitor.start(queue: DispatchQueue(label: "sentinel.network-changes"))
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            self?.sleeping = true; self?.invalidateMonitoring()
        } })
        sleepObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in
            guard let self else { return }; self.sleeping = false; self.invalidateMonitoring()
            if !self.paused { self.refresh() }
        } })
    }
    nonisolated static func pathFingerprint(_ path: NWPath) -> String {
        let types: [NWInterface.InterfaceType] = [.wifi,.wiredEthernet,.cellular,.loopback,.other]
        let active = types.filter { path.usesInterfaceType($0) }.map { String(describing: $0) }.joined(separator: ",")
        return "\(path.status)|\(active)|\(path.isExpensive)|\(path.isConstrained)|\(path.supportsIPv4)|\(path.supportsIPv6)"
    }
    func invalidateMonitoring() {
        heartbeatTask?.cancel(); runningTask?.cancel(); checking = false; pulseChecking = false
        heartbeat = nil; heartbeatHistory = []; changed?()
    }
    func toggleMonitoring() {
        paused.toggle(); invalidateMonitoring()
        if !paused && !sleeping { refresh() }
    }
    func recordHeartbeat(_ result: Snapshot) {
        // Full probes take longer; never replace a newer heartbeat with an older observation.
        if let heartbeat, heartbeat.date > result.date { return }
        heartbeat = result; heartbeatHistory.append(result); heartbeatHistory = Array(heartbeatHistory.suffix(6)); changed?()
    }
    func checkHeartbeat() {
        guard !pulseChecking, !checking, !paused, !sleeping, validatePreferences() else { return }
        pulseChecking = true; let settings = preferences
        heartbeatTask = Task {
            let result = await ProbeRunner.quick(settings)
            guard !Task.isCancelled else { return }
            pulseChecking = false; recordHeartbeat(result)
            if result.ip != "尚未获取", let snapshot, snapshot.ip != result.ip { refresh() }
        }
    }
    func savePreferences() {
        guard validatePreferences() else { return }
        preferences.interval = max(60, preferences.interval)
        errorMessage = nil
        write(preferences, "preferences.json")
        invalidateMonitoring()
        if !paused && !sleeping { refresh() }
    }
    func validatePreferences() -> Bool {
        guard let url = URL(string: preferences.proxy), ["http", "https"].contains(url.scheme ?? ""), url.host != nil, url.user == nil, url.password == nil else {
            errorMessage = "请输入不含账号密码的本机 HTTP 代理地址，例如 http://127.0.0.1:7890"; return false
        }
        preferences.monitorInterval = max(15, preferences.monitorInterval)
        guard (1...65535).contains(preferences.dnsPort) else { errorMessage = "DNS 端口需为 1–65535"; return false }
        return true
    }
    func refresh() {
        guard !checking else { return }
        guard validatePreferences() else { return }
        checking = true; errorMessage = nil; changed?()
        let settings = preferences
        runningTask = Task {
            let result = await ProbeRunner.run(settings)
            guard !Task.isCancelled else { return }
            snapshot = result
            recordHeartbeat(result)
            history.append(result); history = Array(history.suffix(96))
            write(history, "history.json")
            checking = false; changed?()
        }
    }
    func write<T: Encodable>(_ value: T, _ name: String) {
        do {
            let d = try JSONEncoder().encode(value), path = folder.appendingPathComponent(name)
            try d.write(to: path, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        } catch { errorMessage = "本机保存失败：\(error.localizedDescription)" }
    }
    var displayedIP: String { preferences.hideIP ? "•••.•••.•••.•••" : heartbeat?.ip ?? snapshot?.ip ?? "尚未获取" }
    var updatedText: String { guard let date = snapshot?.date else { return "尚未检查" }; return date.formatted(date: .omitted, time: .shortened) }
    var stale: Bool { guard let date = snapshot?.date else { return true }; return Date().timeIntervalSince(date) > Double(preferences.interval * 2) }
    var heartbeatText: String {
        guard let date = heartbeat?.date else { return pulseChecking || checking ? "检查中" : "待检查" }
        return date.formatted(date: .omitted, time: .standard)
    }
    var stability: Stability { Self.monitorStability(heartbeatHistory, full: snapshot, paused: paused, sleeping: sleeping, checking: checking || pulseChecking, monitorInterval: preferences.monitorInterval, fullInterval: preferences.interval) }
    static func monitorStability(_ pulses: [Snapshot], full: Snapshot?, paused: Bool, sleeping: Bool, checking: Bool, monitorInterval: Int, fullInterval: Int, now: Date = Date()) -> Stability {
        if paused { return Stability(mood: .paused, explanation: "自动监控已暂停，线球为灰色。") }
        if sleeping { return Stability(mood: .observing, explanation: "Mac 休眠中，唤醒后重新检查。") }
        guard let latest = pulses.last, now.timeIntervalSince(latest.date) < Double(max(60, monitorInterval * 3)) else { return Stability(mood: checking ? .checking : .observing, explanation: "等待新的实时连通结果，过期记录不显示绿色。") }
        let assessment = Stability.assess(pulses, now: now)
        if assessment.mood == .offline || assessment.mood == .fluctuating { return assessment }
        guard let full, now.timeIntervalSince(full.date) < Double(max(120,fullInterval * 2)) else { return Stability(mood: .observing, explanation: "连通检查已返回，等待完整网络检查更新。") }
        if full.checks.first(where: { $0.id == "udp" })?.health == .bad { return Stability(mood: .fluctuating, explanation: "完整检查发现 UDP 与网页出口不同。") }
        if full.checks.first(where: { $0.id == "dns" })?.health == .warning { return Stability(mood: .fluctuating, explanation: "完整检查发现本机 DNS 查询异常。") }
        if full.ip != latest.ip { return Stability(mood: .observing, explanation: "检测到出口变化，正在重新核对完整链路。") }
        return assessment
    }
    func redacted(_ value: String) -> String {
        guard preferences.hideIP else { return value }
        var text = value
        for ip in Set((history + heartbeatHistory).map(\.ip)).filter({ $0 != "尚未获取" }) { text = text.replacingOccurrences(of: ip, with: "[IP 已隐藏]") }
        return text.replacingOccurrences(of: #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, with: "[IP 已隐藏]", options: .regularExpression)
    }
    var displayedChecks: [Check] {
        (snapshot?.checks ?? []).map { item in
            var c = heartbeat?.checks.first(where: { $0.id == item.id }) ?? item; c.value = redacted(c.value); c.detail = redacted(c.detail); c.source = redacted(c.source); return c }
    }
    func copyReport() {
        guard let s = snapshot else { return }
        let lines = ["Claude 小哨兵 · 本机检测", s.date.formatted(), "出口：\(displayedIP) · \(s.country)", "前置：\(s.front)"] + displayedChecks.map { "[\($0.health.title)] \($0.title)：\($0.value)\n  \($0.detail)" } + ["网络检测不能判断账号处罚、KYC 或真实使用地区是否符合服务要求。"]
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(redacted(lines.joined(separator: "\n")), forType: .string)
    }
}
