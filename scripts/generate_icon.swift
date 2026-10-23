import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: generate_icon.swift <output.png> <size>\n", stderr)
    exit(1)
}
let out = args[1]
let size = CGFloat(Int(args[2]) ?? 1024)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Blue rounded-square background (original artwork — no SF Symbols)
let bg = NSColor(red: 0.22, green: 0.47, blue: 0.96, alpha: 1)
bg.setFill()
NSBezierPath(
    roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
    xRadius: size * 0.18,
    yRadius: size * 0.18
).fill()

// 3×3 grid of white tiles; bottom-right cell highlighted
let pad = size * 0.22
let gridSide = size - pad * 2
let gap = gridSide * 0.06
let cell = (gridSide - gap * 2) / 3
let originX = pad
let originY = pad

NSColor.white.setFill()
for row in 0..<3 {
    for col in 0..<3 {
        let x = originX + CGFloat(col) * (cell + gap)
        let y = originY + CGFloat(2 - row) * (cell + gap)
        let rect = NSRect(x: x, y: y, width: cell, height: cell)
        let corner = cell * 0.12
        if row == 2 && col == 2 {
            NSColor(red: 0.95, green: 0.97, blue: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            NSColor.white.withAlphaComponent(0.85).setStroke()
            let inset = NSBezierPath(roundedRect: rect.insetBy(dx: cell * 0.08, dy: cell * 0.08), xRadius: corner * 0.6, yRadius: corner * 0.6)
            inset.lineWidth = max(1, cell * 0.06)
            inset.stroke()
        } else {
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
        }
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(2)
}
try png.write(to: URL(fileURLWithPath: out))
