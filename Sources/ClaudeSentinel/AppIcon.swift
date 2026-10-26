import AppKit
import SwiftUI

// The application identity is static; live network status belongs to the menu-bar yarn.
@MainActor enum AppIcon {
    static func export(to directory:String) {
        do {
            let folder=URL(fileURLWithPath:directory,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let master=render()
            for points in [16,32,128,256,512] {
                for scale in [1,2] {
                    let pixels=points*scale
                    guard let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:bitmap) else { throw CocoaError(.fileWriteUnknown) }
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
                    context.imageInterpolation = .high
                    master.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels))
                    NSGraphicsContext.restoreGraphicsState()
                    guard let png=bitmap.representation(using:.png,properties:[:]) else { throw CocoaError(.fileWriteUnknown) }
                    let suffix=scale == 2 ? "@2x" : ""
                    try png.write(to:folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"),options:.atomic)
                }
            }
            print("Icon set: \(folder.path)")
        } catch { fputs("Icon generation failed: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func render()->NSImage {
        NSImage(size:NSSize(width:1024,height:1024),flipped:false) { _ in
            NSGraphicsContext.current?.shouldAntialias=true
            let tile=NSBezierPath(roundedRect:NSRect(x:32,y:32,width:960,height:960),xRadius:208,yRadius:208)
            NSColor(Theme.bg).setFill(); tile.fill()
            NSColor(Theme.line).setStroke(); tile.lineWidth=8; tile.stroke()
            NSColor(Theme.panel).setFill()
            NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:184,yRadius:184).fill()
            // Sparse pixel starlight keeps the face and green yarn dominant at small sizes.
            func star(_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ color:NSColor) {
                color.setFill()
                NSRect(x:x+size,y:y,width:size,height:size*3).fill()
                NSRect(x:x,y:y+size,width:size*3,height:size).fill()
            }
            star(182,788,14,NSColor(Theme.accent))
            star(750,768,18,NSColor(Theme.accent))
            star(814,605,8,NSColor(Color(hex:0x9ED5BE)))
            NSColor(Theme.line).setFill(); NSRect(x:180,y:170,width:640,height:10).fill()
            // The exact in-app cat sprite, enlarged with nearest-neighbor pixels.
            NSGraphicsContext.current?.imageInterpolation = .none
            PixelCat.menuImage(.stable,frame:1).draw(in:NSRect(x:92,y:202,width:644,height:552),from:NSRect(x:0,y:0,width:28,height:24),operation:.sourceOver,fraction:1)
            NSColor(Theme.yarn(.stable)).setFill()
            NSRect(x:627,y:232,width:100,height:14).fill(); NSRect(x:663,y:246,width:18,height:14).fill()
            let yarn=["..ooooo..",".obbbbbo.","obbbhbbbo","obbhbhbbo","obhbhbhbo","obbhbhbbo","obbbhbbbo",".obbbbbo.","..ooooo.."]
            let unit:CGFloat=23, left:CGFloat=690, bottom:CGFloat=210
            for (row,line) in yarn.enumerated() { for (column,c) in line.enumerated() {
                let base=NSColor(Theme.yarn(.stable)),color:NSColor
                switch c { case "o":color=NSColor(Theme.bg); case "b":color=base; case "h":color=base.blended(withFraction:0.48,of:.white) ?? .white; default:continue }
                color.setFill(); NSRect(x:left+CGFloat(column)*unit,y:bottom+CGFloat(8-row)*unit,width:unit,height:unit).fill()
            } }
            return true
        }
    }
}
