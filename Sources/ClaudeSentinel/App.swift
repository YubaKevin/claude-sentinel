import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = SentinelState()
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var inspector: NSWindow?
    private var statusTimer: Timer?
    private var animationTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
        menu.addItem(appItem); appItem.submenu = appMenu
        let report = NSMenuItem(title:"查看报告",action:#selector(openReport),keyEquivalent:"d"); report.target = self; appMenu.addItem(report)
        appMenu.addItem(.separator()); appMenu.addItem(NSMenuItem(title:"退出 Claude 小哨兵",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")); NSApp.mainMenu = menu
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self; status.button?.action = #selector(togglePopover)
        status.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        popover.behavior = .transient; popover.contentSize = NSSize(width:390,height:650)
        popover.contentViewController = NSHostingController(rootView: PopoverView(state:state))
        state.changed = { [weak self] in self?.updateStatus() }
        state.showInspector = { [weak self] in self?.showInspector() }
        updateStatus(); state.start()
        statusTimer = Timer.scheduledTimer(withTimeInterval:15,repeats:true) { [weak self] _ in Task { @MainActor in self?.updateStatus() } }
        animationTimer = Timer.scheduledTimer(withTimeInterval:0.5,repeats:true) { [weak self] _ in Task { @MainActor in
            guard let self, self.state.stability.mood == .stable, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            self.status.button?.image = PixelCat.menuImage(.stable,frame:PixelCat.frame(at:Date()))
        } }
        showInspector()
    }
    @objc func togglePopover() {
        guard let button=status.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu=NSMenu()
            let report=NSMenuItem(title:"查看报告",action:#selector(openReport),keyEquivalent:""); report.target=self; menu.addItem(report)
            menu.addItem(NSMenuItem(title:"退出 Claude 小哨兵",action:#selector(NSApplication.terminate(_:)),keyEquivalent:""))
            status.menu=menu; button.performClick(nil); status.menu=nil; return
        }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY); NSApp.activate(ignoringOtherApps:true) }
    }
    func updateStatus() {
        guard let button=status.button else { return }
        let mood=state.stability.mood
        button.image = PixelCat.menuImage(mood,frame:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : PixelCat.frame(at:Date()))
        button.title=""; button.toolTip="Claude 小哨兵 · \(PixelCat.ballLabel(mood)) · \(mood.title)\n\(state.stability.explanation)\n连通更新 \(state.heartbeatText) · 每 \(state.preferences.monitorInterval) 秒"
        button.setAccessibilityLabel("Claude 小哨兵，\(PixelCat.ballLabel(mood))，\(mood.title)")
    }
    func showInspector() {
        popover.performClose(nil)
        if inspector == nil {
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1100,height:800),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
            window.title="Claude 小哨兵 · 像素空间站"; window.isReleasedWhenClosed=false; window.minSize=NSSize(width:960,height:750)
            window.contentView=NSHostingView(rootView:InspectorView(state:state)); window.center(); inspector=window
        }
        inspector?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func openReport() { showInspector() }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool { showInspector(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { false }
}

@main struct ClaudeSentinelApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--self-test") { selfTest(); return }
        if let index=CommandLine.arguments.firstIndex(of:"--render-app-icon"), CommandLine.arguments.count > index+1 { AppIcon.export(to:CommandLine.arguments[index+1]); return }
        if let index=CommandLine.arguments.firstIndex(of:"--render-mascot"), CommandLine.arguments.count > index+1 { renderMascot(CommandLine.arguments[index+1]); return }
        if CommandLine.arguments.contains("--probe") {
            Task {
                let report=await ProbeRunner.run(Preferences())
                let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                if let data=try? encoder.encode(report),let text=String(data:data,encoding:.utf8) { print(text) }
                exit(report.transportGood ? 0 : 2)
            }
            RunLoop.main.run(); return
        }
        let app=NSApplication.shared, delegate=AppDelegate(); app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    @MainActor static func selfTest() {
        func sample(_ ms:Int=300,_ ip:String="203.0.113.10",_ health:Health = .good)->Snapshot {
            var s=Snapshot(); s.ip=ip; s.checks=[Check(id:"api",title:"API",health:health,value:"",detail:"",source:"test",milliseconds:ms),Check(id:"egress",title:"exit",health:health,value:ip,detail:"",source:"test")]; return s
        }
        precondition(Stability.assess([]).mood == .observing)
        precondition(Stability.assess([],checking:true).mood == .checking)
        precondition(Stability.assess([sample()]).mood == .observing)
        precondition(Stability.assess([sample(),sample(310),sample(290)]).mood == .stable)
        precondition(Stability.assess([sample(),sample(100),sample(3000)]).mood == .fluctuating)
        precondition(Stability.assess([sample(),sample(),sample(300,"203.0.113.11")]).mood == .fluctuating)
        precondition(Stability.assess([sample(0,"unknown",.bad)]).mood == .offline)
        let blocked=sample(300,"203.0.113.10",.warning)
        precondition(Stability.assess([blocked,blocked]).mood == .fluctuating)
        var mismatch=sample(); mismatch.checks.append(Check(id:"udp",title:"UDP",health:.bad,value:"203.0.113.11",detail:"",source:"test"))
        precondition(Stability.assess([sample(),sample(),mismatch]).mood == .fluctuating)
        precondition(Stability.assess([sample()],paused:true).mood == .paused)
        var old=sample(); old.date=Date().addingTimeInterval(-3600)
        precondition(Stability.assess([old,old,old]).mood == .observing)
        precondition(ProbeRunner.trace("ip=203.0.113.10\nloc=US\n")["ip"] == "203.0.113.10")
        let pulses=[sample(),sample(310),sample(290)], full=sample()
        func monitor(_ values:[Snapshot],_ full:Snapshot?,_ pause:Bool=false,_ sleep:Bool=false)->Stability {
            SentinelState.monitorStability(values,full:full,paused:pause,sleeping:sleep,checking:false,monitorInterval:30,fullInterval:300)
        }
        precondition(monitor(pulses,full).mood == .stable)
        precondition(monitor([old,old,old],full).mood == .observing)
        precondition(monitor(pulses,nil).mood == .observing)
        precondition(monitor(pulses,old).mood == .observing)
        precondition(monitor(pulses,full,true).mood == .paused)
        precondition(monitor(pulses,full,false,true).mood == .observing)
        precondition(monitor(pulses,mismatch).mood == .fluctuating)
        precondition(monitor(pulses,sample(300,"203.0.113.11")).mood == .observing)
        let legacy=try! JSONDecoder().decode(Preferences.self,from:Data(#"{"proxy":"http://127.0.0.1:8888","dnsPort":5454,"interval":600,"hideIP":true}"#.utf8))
        precondition(legacy.proxy.hasSuffix(":8888") && legacy.dnsPort == 5454 && legacy.interval == 600 && legacy.hideIP && legacy.monitorInterval == 30)
        precondition(PixelCat.ballLabel(.stable) == "绿色线球" && PixelCat.ballLabel(.fluctuating) == "红色线球" && PixelCat.ballLabel(.paused) == "灰色线球")
        print("PASS: stability, heartbeat freshness, full-check expiry, sleep/pause, recovery, UDP mismatch, legacy preferences and yarn states")
    }
    @MainActor static func renderMascot(_ path:String) {
        let width=920,height=380
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0), let context=NSGraphicsContext(bitmapImageRep:bitmap) else { exit(1) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
        NSColor(Theme.bg).setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
        func text(_ value:String,_ x:Int,_ y:Int,_ color:NSColor) { (value as NSString).draw(at:NSPoint(x:x,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:16,weight:.medium),.foregroundColor:color]) }
        text("猫咪玩线球 · 实际应用像素图",24,345,NSColor(Theme.ink))
        for (i,mood) in [CatMood.stable,.fluctuating,.observing,.paused].enumerated() {
            PixelCat.menuImage(mood).draw(in:NSRect(x:24+i*220,y:210,width:176,height:96)); text("\(PixelCat.ballLabel(mood)) · \(mood.title)",24+i*220,180,NSColor(Theme.yarn(mood)))
        }
        text("拨线球动画 · 4 帧（系统减少动态效果开启时静止）",24,140,NSColor(Theme.muted))
        for frame in 0..<4 { PixelCat.menuImage(.stable,frame:frame).draw(in:NSRect(x:24+frame*220,y:24,width:176,height:96)) }
        NSGraphicsContext.restoreGraphicsState()
        do { guard let png=bitmap.representation(using:.png,properties:[:]) else { exit(1) }; try png.write(to:URL(fileURLWithPath:path)); print(path) } catch { fputs("无法写入预览\n",stderr); exit(1) }
    }
}
