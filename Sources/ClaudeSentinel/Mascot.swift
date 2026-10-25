import SwiftUI
import AppKit

extension Theme {
    static func yarn(_ mood: CatMood) -> Color {
        switch mood { case .stable: return Color(hex:0x75D69A)
        case .fluctuating,.offline: return Color(hex:0xF18181)
        default: return Color(hex:0x94A0B4) }
    }
}

// One pixel renderer is shared by the real menu-bar icon and all in-app cats.
struct PixelCat: View {
    var mood: CatMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let rows = [
        "    oo          oo      ",
        "   oww oooooooo oww o   ",
        "   owppwwwwwwwwppw o    ",
        "  owwpwwwwwwwwwwpww o   ",
        "  owwwwwwwwwwwwwwww o   ",
        " owwwwwwwwwwwwwwwwww o  ",
        " owwwwwwwwwwwwwwwwww o  ",
        " owwwwwwwwwwwwwwwwww o  ",
        " owwpwwwwwnnwwwwpwww o  ",
        "  owwwwwwwwwwwwwwwww o   ",
        "   owwwwwwwwwwwwww o    ",
        "    ooovvvvvvvvooo      ",
        "    owwvvvvvvwwwo       ",
        "   owwwwvwwwwwwwwoo     ",
        "  owwwwwvvwwwwwwwwoo    ",
        " owwwwwwvwwwwwwwwwwwo   ",
        " owwwwwwwwwwwwwwwwwwwo  ",
        "  owwwwwwwwwwwwwwwwwo   ",
        "   oooooo  oooooooo     "
    ]
    var body: some View {
        TimelineView(.animation(minimumInterval:0.5,paused:reduceMotion || mood != .stable)) { timeline in
            Image(nsImage:Self.menuImage(mood,frame:reduceMotion ? 0 : Self.frame(at:timeline.date)))
                .resizable().interpolation(.none).scaledToFit()
        }.accessibilityLabel("猫咪玩线球，\(Self.ballLabel(mood))，\(mood.title)")
    }
    static func frame(at date:Date) -> Int { Int(date.timeIntervalSinceReferenceDate * 2) % 4 }
    static func ballLabel(_ mood:CatMood) -> String {
        switch mood { case .stable: return "绿色线球"; case .fluctuating,.offline: return "红色线球"; default: return "灰色线球" }
    }
    private static var imageCache: [String:NSImage] = [:]
    static func menuImage(_ mood: CatMood, frame: Int = 0) -> NSImage {
        let step = mood == .stable ? max(0,frame) % 4 : 0, key = "\(mood.rawValue)-\(step)"
        if let cached=imageCache[key] { return cached }
        let image=NSImage(size:NSSize(width:44,height:24),flipped:true) { _ in
            NSGraphicsContext.current?.imageInterpolation = .none
            NSGraphicsContext.current?.shouldAntialias = false
            let ink=NSColor(Color(hex:0x141928)), white=NSColor(Color(hex:0xF4EFF8)), pink=NSColor(Color(hex:0xEFABCA)), yarn=NSColor(Theme.yarn(mood))
            let palette:[Character:NSColor] = ["o":ink,"w":white,"p":pink,"v":NSColor(Theme.accent),"n":NSColor(Color(hex:0xA5769D))]
            for (row,line) in rows.enumerated() { for (column,c) in line.enumerated() { if let color=palette[c] { color.setFill(); NSRect(x:column,y:row+3,width:1,height:1).fill() } } }
            ink.setFill()
            func pixel(_ x:Int,_ y:Int) { NSRect(x:x,y:y+3,width:1,height:1).fill() }
            for x in [7,15] {
                if mood == .stable || mood == .paused { pixel(x,6); pixel(x+1,6) }
                else if mood == .offline { for offset in 0...2 { pixel(x+offset,5+offset); pixel(x+offset,7-offset) } }
                else { pixel(x,5); pixel(x,6) }
            }
            if mood == .fluctuating { NSRect(x:24,y:2,width:1,height:4).fill(); NSRect(x:24,y:7,width:1,height:1).fill() }
            if mood == .paused { NSRect(x:25,y:2,width:3,height:1).fill(); NSRect(x:26,y:3,width:1,height:1).fill(); NSRect(x:25,y:4,width:3,height:1).fill() }
            let shift = [0,2,4,2][step], ballX = 29 + shift
            // Loose yarn leads back to the paw, so this reads as a ball rather than a status LED.
            yarn.setFill()
            NSRect(x:23,y:20,width:ballX-22,height:1).fill(); NSRect(x:26,y:19,width:2,height:1).fill()
            if step == 1 || step == 2 { ink.setFill(); NSRect(x:20,y:17,width:8,height:4).fill(); white.setFill(); NSRect(x:20,y:17,width:7,height:2).fill(); pink.setFill(); NSRect(x:26,y:18,width:1,height:1).fill() }
            let ball=["..ooooo..",".obbbbbo.","obbbhbbbo","obbhbhbbo","obhbhbhbo","obbhbhbbo","obbbhbbbo",".obbbbbo.","..ooooo.."]
            for (y,line) in ball.enumerated() { for (x,c) in line.enumerated() {
                let color:NSColor
                switch c { case "o":color=ink; case "b":color=yarn; case "h":color=yarn.blended(withFraction:0.48,of:.white) ?? .white; default:continue }
                color.setFill(); NSRect(x:ballX+x,y:13+y,width:1,height:1).fill()
            } }
            return true
        }; image.isTemplate=false; image.accessibilityDescription="猫咪玩线球，\(ballLabel(mood))，\(mood.title)"; imageCache[key]=image; return image
    }
}
