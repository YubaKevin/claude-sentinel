import AppKit
import SwiftUI

@MainActor enum DmgArtwork {
    static func export(to path:String) {
        let width=720,height=480
        guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { exit(1) }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
        context.cgContext.translateBy(x:0,y:CGFloat(height)); context.cgContext.scaleBy(x:1,y:-1)
        func rect(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat,_ color:NSColor) { color.setFill(); NSRect(x:x,y:y,width:w,height:h).fill() }
        let navy=NSColor(Theme.bg),panel=NSColor(Theme.panel),line=NSColor(Theme.line),lavender=NSColor(Theme.accent),muted=NSColor(Theme.muted),white=NSColor(Theme.ink)
        rect(0,0,720,480,navy)
        // Station walls and a low console leave the two Finder drop targets clear.
        rect(0,0,720,12,panel); rect(0,12,720,3,line)
        rect(0,0,16,480,panel); rect(704,0,16,480,panel)
        rect(0,364,720,116,panel); rect(0,364,720,3,line)
        for wall:CGFloat in [20,664] {
            rect(wall,132,36,188,line); rect(wall+4,136,28,180,navy)
            for y in stride(from:148,through:292,by:36) { rect(wall+8,CGFloat(y),20,24,panel); rect(wall+11,CGFloat(y)+4,5,4,lavender) }
            rect(wall-4,125,44,7,line); rect(wall-4,320,44,7,line)
        }
        let moon=["...ooooo...","..opppppo..",".opppppppo.","opppplppppo","oppplllpppo","opppplppppo","opppppplppo","opppppllppo",".opppppppo.","..opppppo..","...ooooo..."]
        for (row,pixels) in moon.enumerated() { for (col,c) in pixels.enumerated() {
            let color:NSColor
            switch c { case "o":color=line; case "p":color=lavender; case "l":color=panel; default:continue }
            rect(595+CGFloat(col)*4,35+CGFloat(row)*4,4,4,color)
        } }
        for x in stride(from:24,through:680,by:32) { rect(CGFloat(x),452,18,5,line) }
        func star(_ x:CGFloat,_ y:CGFloat,_ unit:CGFloat) { rect(x+unit,y,unit,unit*3,lavender); rect(x,y+unit,unit*3,unit,lavender) }
        for (x,y,s) in [(48,54,2),(654,70,3),(92,148,1),(616,157,2),(66,337,2),(652,334,1)] { star(CGFloat(x),CGFloat(y),CGFloat(s)) }
        for (x,y) in [(127,31),(572,34),(38,228),(676,253),(318,141),(413,157),(383,350)] { rect(CGFloat(x),CGFloat(y),2,2,muted) }
        func text(_ value:String,_ y:CGFloat,_ size:CGFloat,_ color:NSColor,_ weight:NSFont.Weight = .regular) {
            let style=NSMutableParagraphStyle(); style.alignment = .center
            // NSString uses a top-down text layout when wrapped in a flipped NSGraphicsContext.
            let previous=NSGraphicsContext.current
            NSGraphicsContext.current=NSGraphicsContext(cgContext:context.cgContext,flipped:true)
            (value as NSString).draw(in:NSRect(x:38,y:y,width:644,height:size*1.6),withAttributes:[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:style])
            NSGraphicsContext.current=previous
        }
        text("Claude 小哨兵",42,29,white,.semibold)
        text("把小猫拖入 Applications，即可安装",91,15,lavender)
        // Finder uses dark filename text in light mode, so provide high-contrast label plates.
        for x:CGFloat in [102,452] {
            NSColor(Color(hex:0xD5CCED)).setFill()
            NSBezierPath(roundedRect:NSRect(x:x,y:294,width:166,height:28),xRadius:5,yRadius:5).fill()
        }
        // The arrow sits between the actual app and Applications icons in Finder.
        for i in 0..<5 { rect(318+CGFloat(i)*10,222,7,4,lavender) }
        rect(370,210,6,28,lavender); rect(376,214,6,20,lavender); rect(382,218,6,12,lavender); rect(388,222,6,4,lavender)
        text("安装完成后，从“应用程序”打开小哨兵",385,14,white,.medium)
        #if arch(arm64)
        text("macOS 14+  ·  Apple 芯片 arm64  ·  测试版，详见 Release 说明",418,11,muted)
        #else
        text("macOS 14+  ·  Intel x86_64  ·  测试版，详见 Release 说明",418,11,muted)
        #endif
        NSGraphicsContext.restoreGraphicsState()
        do { guard let data=bitmap.representation(using:.png,properties:[:]) else { exit(1) }; try data.write(to:URL(fileURLWithPath:path),options:.atomic); print("DMG background generated") }
        catch { fputs("DMG artwork export failed\n",stderr); exit(1) }
    }
}
