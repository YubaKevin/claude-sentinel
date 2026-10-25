import SwiftUI
import AppKit

enum Theme {
    static let bg = Color(hex: 0x111827), panel = Color(hex: 0x1B2540), ink = Color(hex: 0xEBEDF8), muted = Color(hex: 0xA4ADC5), line = Color(hex: 0x39425E), accent = Color(hex: 0xB9A4EF)
    static func health(_ h: Health) -> Color { switch h { case .good: return Color(hex: 0x9ED5BE); case .warning: return Color(hex: 0xE8BC83); case .bad: return Color(hex: 0xEE9D9D); case .unknown: return muted } }
    static func mood(_ m: CatMood) -> Color { switch m { case .stable: return health(.good); case .fluctuating: return health(.warning); case .offline: return health(.bad); case .checking: return accent; default: return muted } }
}
extension Color { init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255, opacity: 1) } }
extension View {
    func stationPanel() -> some View { self.padding(16).background(Theme.panel).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line)).clipShape(RoundedRectangle(cornerRadius: 10)) }
}

struct StatusPill: View {
    var health: Health
    var body: some View { HStack(spacing:5) { Circle().fill(Theme.health(health)).frame(width:6,height:6); Text(health.title).font(.system(size:11,weight:.medium)) }.foregroundColor(Theme.health(health)).padding(.horizontal,8).padding(.vertical,4).background(Theme.health(health).opacity(0.1)).clipShape(Capsule()) }
}
struct Hero: View {
    @ObservedObject var state: SentinelState
    var compact = false
    var body: some View {
        HStack(spacing:16) {
            ZStack { Circle().stroke(Theme.line,lineWidth:3).frame(width:compact ? 78 : 106,height:compact ? 78 : 106); PixelCat(mood:state.stability.mood).frame(width:compact ? 90 : 126,height:compact ? 80 : 105) }
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:8) { Circle().fill(Theme.yarn(state.stability.mood)).frame(width:9,height:9); Text(state.stability.mood.title).font(.system(size:compact ? 19 : 23,weight:.semibold)); if state.checking { ProgressView().controlSize(.small) } }
                Text(state.stability.explanation).font(.system(size:12)).foregroundColor(Theme.muted).fixedSize(horizontal:false,vertical:true)
                if !compact { Text("连通更新 \(state.heartbeatText) · 完整检查 \(state.updatedText) · 不代表账号安全或 KYC 结果").font(.system(size:11)).foregroundColor(Theme.muted) }
            }
            Spacer(minLength:0)
            if !compact { Text("✦\n   ·    ✧\n✧    ·").font(.system(size:20,design:.monospaced)).foregroundColor(Theme.accent.opacity(0.7)).padding(.trailing,16).accessibilityHidden(true) }
        }.padding(compact ? 12 : 18).frame(maxWidth:.infinity,alignment:.leading).background(Color(hex:0x202641)).overlay(RoundedRectangle(cornerRadius:10).stroke(Theme.accent.opacity(0.45))).clipShape(RoundedRectangle(cornerRadius:10))
    }
}
struct CheckRow: View {
    var check: Check
    var compact = false
    var body: some View {
        DisclosureGroup {
            VStack(alignment:.leading,spacing:7) { Text(check.detail); Text("来源：\(check.source)").font(.system(size:11)).foregroundColor(Theme.muted) }.font(.system(size:12)).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,8).textSelection(.enabled)
        } label: {
            HStack(spacing:10) { Image(systemName:icon).foregroundColor(Theme.accent).frame(width:20); Text(check.title).font(.system(size:13,weight:.medium)); Spacer(); Text(check.value).font(.system(size:compact ? 11 : 12)).foregroundColor(Theme.health(check.health)).lineLimit(1); if !compact { StatusPill(health:check.health) } }.padding(.vertical,8)
        }.tint(Theme.muted)
    }
    var icon: String { switch check.id { case "api": return "globe"; case "dns": return "externaldrive"; case "udp": return "point.3.connected.trianglepath.dotted"; case "auth": return "person.crop.circle"; case "ipv6": return "network"; case "official": return "waveform.path.ecg"; case "locale": return "clock"; case "browser": return "macwindow"; default: return "shield.lefthalf.filled" } }
}
struct Journey: View {
    @ObservedObject var state: SentinelState
    var compact = false
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:8) {
                stop("laptopcomputer","本机",compact ? "设备" : "本地设备")
                arrow
                stop("server.rack","当前前置",state.snapshot?.front ?? "等待检查")
                arrow
                stop("globe","代理出口",compact ? (state.snapshot?.country ?? "未知") : state.displayedIP)
            }
            if compact { Divider().overlay(Theme.line); HStack { Text(state.displayedIP).font(.system(size:20,weight:.semibold,design:.monospaced)); Spacer(); Text(state.snapshot?.country ?? "未知").font(.system(size:12)).foregroundColor(Theme.muted) } }
        }.stationPanel()
    }
    var arrow: some View { Text("···›").font(.system(size:17,design:.monospaced)).foregroundColor(Theme.accent) }
    func stop(_ icon: String,_ label: String,_ value: String) -> some View {
        VStack(alignment:compact ? .center : .leading,spacing:7) { Image(systemName:icon).font(.system(size:compact ? 20 : 24)).foregroundColor(Theme.accent); Text(label).font(.system(size:10)).foregroundColor(Theme.muted); Text(value).font(.system(size:compact ? 11 : 13,weight:.semibold)).lineLimit(1).help(value) }.frame(maxWidth:.infinity)
    }
}
struct PopoverView: View {
    @ObservedObject var state: SentinelState
    var body: some View {
        VStack(spacing:12) {
            HStack { PixelCat(mood:state.stability.mood).frame(width:30,height:28); Text("Claude 小哨兵").font(.system(size:17,weight:.semibold)); Spacer(); Button { state.section="设置"; state.showInspector?() } label: { Image(systemName:"gearshape") }.help("设置") }
            Hero(state:state,compact:true)
            Journey(state:state,compact:true)
            ScrollView { VStack(spacing:0) {
                if state.snapshot != nil { ForEach(state.displayedChecks.filter { ["api","dns","udp","ipv6","auth"].contains($0.id) }) { check in CheckRow(check:check,compact:true); Divider().overlay(Theme.line) } }
                else { Text("正在取得第一份真实检测结果…").foregroundColor(Theme.muted).padding(24) }
            }.padding(.horizontal,12) }.frame(maxHeight:250).background(Theme.panel).clipShape(RoundedRectangle(cornerRadius:8))
            HStack { Text("连通 \(state.heartbeatText) · 每 \(state.preferences.monitorInterval) 秒").font(.system(size:11)).foregroundColor(Theme.muted); Spacer(); if state.stale { Text("待刷新").font(.system(size:10)).foregroundColor(Theme.health(.warning)) } }
            HStack { Button("查看完整报告") { state.section="概览"; state.showInspector?() }.buttonStyle(.borderedProminent); Spacer(); Button(state.checking ? "检查中…" : "立即检查") { state.refresh() }.disabled(state.checking) }
            HStack { Button(state.paused ? "恢复自动检查" : "暂停自动检查") { state.toggleMonitoring() }; Spacer(); Button("退出") { NSApp.terminate(nil) } }.font(.system(size:11)).buttonStyle(.plain).foregroundColor(Theme.muted)
        }.padding(18).frame(width:390,height:650).foregroundColor(Theme.ink).background(Theme.bg).preferredColorScheme(.dark).tint(Theme.accent)
    }
}
struct InspectorView: View {
    @ObservedObject var state: SentinelState
    let sections=[("概览","house"),("网络链路","point.3.connected.trianglepath.dotted"),("检测记录","list.bullet.rectangle"),("设置","gearshape")]
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:12) {
                PixelCat(mood:state.stability.mood).frame(width:92,height:82).frame(maxWidth:.infinity).padding(.top,18)
                Text("CLAUDE\n小哨兵空间站").font(.system(size:12,weight:.semibold,design:.monospaced)).lineSpacing(5).foregroundColor(Theme.accent).frame(maxWidth:.infinity).padding(.bottom,24)
                ForEach(sections,id:\.0) { item in Button { state.section=item.0 } label: { HStack(spacing:11) { Image(systemName:item.1).frame(width:20); Text(item.0); Spacer() }.padding(12).background(state.section == item.0 ? Theme.accent : .clear).foregroundColor(state.section == item.0 ? Theme.bg : Theme.ink).clipShape(RoundedRectangle(cornerRadius:6)) }.buttonStyle(.plain) }
                Spacer(); Label("记录仅保存在本机",systemImage:"shield").font(.system(size:10)).foregroundColor(Theme.muted).padding(.bottom,12)
            }.padding(14).frame(width:155).background(Theme.panel)
            Rectangle().fill(Theme.line).frame(width:1)
            VStack(alignment:.leading,spacing:18) {
                HStack { VStack(alignment:.leading,spacing:4) { Text(state.section == "概览" ? "今天的连接状态" : state.section).font(.system(size:23,weight:.semibold)); Text("上次检查 \(state.updatedText) · \(state.checking ? "正在刷新" : "连通 \(state.preferences.monitorInterval) 秒 · 完整 \(state.preferences.interval/60) 分钟")").font(.system(size:11)).foregroundColor(Theme.muted) }; Spacer(); Button { state.refresh() } label: { Label("重新检查",systemImage:"arrow.clockwise") }.disabled(state.checking) }
                switch state.section { case "设置": settings; case "检测记录": history; case "网络链路": network; default: overview }
            }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
        }.background(Theme.bg).foregroundColor(Theme.ink).tint(Theme.accent).preferredColorScheme(.dark).frame(minWidth:960,minHeight:720)
    }
    var overview: some View {
        ScrollView { VStack(alignment:.leading,spacing:16) {
            Hero(state:state); Journey(state:state)
            HStack(alignment:.top,spacing:16) {
                VStack(alignment:.leading,spacing:8) { Label("检查清单",systemImage:"checklist").font(.system(size:15,weight:.semibold)); ForEach(state.displayedChecks.filter { ["api","dns","udp","ipv6","auth"].contains($0.id) }) { CheckRow(check:$0); Divider().overlay(Theme.line) } }.frame(maxWidth:.infinity).stationPanel()
                VStack(alignment:.leading,spacing:12) {
                    Label("需要留意",systemImage:"sparkle.magnifyingglass").font(.system(size:15,weight:.semibold))
                    if state.snapshot?.attention.isEmpty != false { Text("当前没有检测到明确异常。登录有效性、浏览器指纹和 IP 信誉仍需单独核对。").font(.system(size:12)).foregroundColor(Theme.muted).fixedSize(horizontal:false,vertical:true) }
                    ForEach(state.displayedChecks.filter { $0.health == .bad || $0.health == .warning }) { c in VStack(alignment:.leading,spacing:6) { Text(c.title+" · "+c.value).font(.system(size:12,weight:.semibold)).foregroundColor(Theme.health(c.health)); Text(c.detail).font(.system(size:11)).foregroundColor(Theme.muted) }.padding(10).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius:6)) }
                    Text("不会把第三方“信任分”当作 Anthropic 官方风险结论。").font(.system(size:11)).foregroundColor(Theme.muted)
                    Button("复制当前报告") { state.copyReport() }.disabled(state.snapshot == nil)
                }.frame(width:220,alignment:.leading).stationPanel()
            }
            chart
        } }
    }
    var network: some View {
        ScrollView { VStack(alignment:.leading,spacing:16) { Journey(state:state)
            Text("各项结果独立呈现，不合成为账号安全分数。").font(.system(size:12)).foregroundColor(Theme.muted)
            VStack(spacing:0) { ForEach(state.displayedChecks) { CheckRow(check:$0); Divider().overlay(Theme.line) } }.stationPanel()
            HStack { Button("浏览器 DNS 检测 ↗") { open("https://ip.net.coffee/dns/") }; Button("浏览器环境检测 ↗") { open("https://ip.net.coffee/claude/") }; Button("官方服务状态 ↗") { open("https://status.claude.com/") } }
            Text("外部检测页面会获得你的访问 IP。浏览器结果可能受它自身的代理与安全 DNS 设置影响。").font(.system(size:11)).foregroundColor(Theme.muted)
        } }
    }
    var history: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("保留最近 96 条记录 · 响应时间是 API 首字节时间，包含连接与服务端处理。").font(.system(size:12)).foregroundColor(Theme.muted)
            Table(Array(state.history.reversed())) {
                TableColumn("时间") { Text($0.date.formatted(date:.abbreviated,time:.shortened)) }
                TableColumn("出口") { Text(state.preferences.hideIP ? "已隐藏" : $0.ip).font(.system(size:12,design:.monospaced)) }
                TableColumn("前置",value:\.front)
                TableColumn("API") { Text($0.apiMS.map { "\($0) ms" } ?? "未获取").foregroundColor($0.transportGood ? Theme.health(.good) : Theme.health(.warning)) }
            }
            chart
        }
    }
    var chart: some View {
        let samples=Array(state.history.filter { Date().timeIntervalSince($0.date)<1800 }.suffix(24))
        let values=samples.compactMap(\.apiMS)
        return VStack(alignment:.leading,spacing:12) {
            HStack { Label("最近 30 分钟响应",systemImage:"chart.xyaxis.line").font(.system(size:13,weight:.semibold)); Spacer(); Text("\(samples.count) 次检查").font(.system(size:11)).foregroundColor(Theme.muted) }
            if values.count < 2 { Text("正在积累样本；至少两次有效响应后绘制趋势。").font(.system(size:12)).foregroundColor(Theme.muted).frame(height:64) }
            else { HStack { VStack { Text("\(values.max() ?? 0) ms"); Spacer(); Text("0 ms") }.font(.system(size:10,design:.monospaced)).foregroundColor(Theme.muted)
                Canvas { context,size in let top=Double(max(1,values.max() ?? 1)); var path=Path()
                    for (i,sample) in samples.enumerated() { guard let value=sample.apiMS else { continue }; let point=CGPoint(x:Double(i)/Double(max(1,samples.count-1))*size.width,y:size.height-Double(value)/top*(size.height-6)); if i == 0 || samples[i-1].apiMS == nil { path.move(to:point) } else { path.addLine(to:point) }; context.fill(Path(ellipseIn:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)),with:.color(Theme.accent)) }; context.stroke(path,with:.color(Theme.accent),lineWidth:2)
                }.frame(height:65).accessibilityLabel("响应时间趋势，\(values.count) 个有效样本")
            } }
        }.stationPanel()
    }
    var settings: some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text("检查设置").font(.system(size:17,weight:.semibold))
            VStack(alignment:.leading,spacing:16) {
                setting("HTTP 代理") { TextField("http://127.0.0.1:7890",text:$state.preferences.proxy).textFieldStyle(.roundedBorder) }
                setting("Mihomo Socket") { TextField("本机 Unix Socket 路径",text:$state.preferences.socketPath).textFieldStyle(.roundedBorder) }
                setting("本地 DNS 端口") { TextField("1053",value:$state.preferences.dnsPort,format:.number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width:100) }
                setting("连通监控") { Picker("",selection:$state.preferences.monitorInterval) { Text("15 秒").tag(15); Text("30 秒（推荐）").tag(30); Text("60 秒").tag(60) }.labelsHidden().frame(width:220) }
                setting("完整检测") { Picker("",selection:$state.preferences.interval) { Text("1 分钟").tag(60); Text("2 分钟").tag(120); Text("5 分钟（推荐）").tag(300); Text("10 分钟").tag(600) }.labelsHidden().frame(width:220) }
                Toggle("检查 UDP 出口（STUN）",isOn:$state.preferences.udp)
                Toggle("查询公开 IP 地区与运营商（IPinfo）",isOn:$state.preferences.metadata)
                Toggle("隐藏界面与复制报告中的出口 IP",isOn:$state.preferences.hideIP)
            }.stationPanel()
            HStack { Button("保存设置") { state.savePreferences() }.buttonStyle(.borderedProminent); Button(state.paused ? "恢复自动检查" : "暂停自动检查") { state.toggleMonitoring() } }
            if let error=state.errorMessage { Text(error).foregroundColor(Theme.health(.bad)) }
            Text("应用只读检查代理与网络设置。不会修改 Clash、系统时区、IPv6 或 zshrc；不提取订阅凭据或登录 token，不发送模型请求。").font(.system(size:12)).foregroundColor(Theme.muted).fixedSize(horizontal:false,vertical:true)
            Text("本机数据目录：~/Library/Application Support/ClaudeSentinel").font(.system(size:11,design:.monospaced)).foregroundColor(Theme.muted)
            Divider(); Text("猫咪如何判断稳定性").font(.system(size:15,weight:.semibold))
            Text("绿色线球表示最近连通稳定，红色表示连接、出口或 DNS/UDP 异常；灰色表示检查中、观察中、暂停或记录过期。轻量监控至少三次后评估，完整检测补充 DNS/UDP。休眠期间不检测，唤醒和网络变化后补查。账号登录独立呈现。").font(.system(size:12)).foregroundColor(Theme.muted)
            HStack(spacing:20) { ForEach([CatMood.stable,.fluctuating,.offline,.observing,.paused],id:\.rawValue) { mood in VStack { PixelCat(mood:mood).frame(width:75,height:70); Text(mood.title).font(.system(size:10)).foregroundColor(Theme.mood(mood)) } } }
        } }
    }
    func setting<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View { HStack { Text(title).frame(width:120,alignment:.leading); content(); Spacer(minLength:0) }.font(.system(size:13)) }
    func open(_ url:String) { if let url=URL(string:url) { NSWorkspace.shared.open(url) } }
}
