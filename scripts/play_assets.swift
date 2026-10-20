// Renders Elderhub's Google Play graphics from real captures.
//
//   swift scripts/play_assets.swift feature <icon.png> <out.png>
//   swift scripts/play_assets.swift shot <raw.png> "<headline>" <out.png>
//
// Screenshots are 1080 x 1920 (Play rejects anything longer than 2:1, and a
// raw 1080 x 2400 capture is 2.22:1): the headline above, the unedited
// capture scaled to fit below. Drawn opaque in RGBA (CoreGraphics has no
// 24-bit target); flatten with `ffmpeg -pix_fmt rgb24` for Play's no-alpha rule.
import AppKit

let blue = NSColor(srgbRed: 0x02 / 255, green: 0x39 / 255, blue: 0xBD / 255, alpha: 1)
let paper = NSColor(srgbRed: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x11 / 255, green: 0x11 / 255, blue: 0x14 / 255, alpha: 1)

func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSGraphicsContext.current!.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, in rect: NSRect, align: NSTextAlignment) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: style]
    NSAttributedString(string: s, attributes: attrs).draw(with: rect, options: [.usesLineFragmentOrigin])
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let args = CommandLine.arguments
switch args[1] {
case "feature":
    let icon = NSImage(contentsOfFile: args[2])!
    save(canvas(1024, 500) { ctx in
        blue.setFill(); NSRect(x: 0, y: 0, width: 1024, height: 500).fill()
        icon.draw(in: NSRect(x: 70, y: 100, width: 300, height: 300))
        text("Elderhub", size: 76, weight: .bold, color: .white, in: NSRect(x: 420, y: 250, width: 560, height: 100), align: .left)
        text("A family care log for the people you look after", size: 34, weight: .medium,
             color: NSColor.white.withAlphaComponent(0.9), in: NSRect(x: 422, y: 120, width: 540, height: 120), align: .left)
    }, args[3])
case "shot":
    let raw = NSImage(contentsOfFile: args[2])!
    save(canvas(1080, 1920) { ctx in
        paper.setFill(); NSRect(x: 0, y: 0, width: 1080, height: 1920).fill()
        text(args[3], size: 64, weight: .bold, color: ink, in: NSRect(x: 70, y: 1600, width: 940, height: 250), align: .center)
        let h: CGFloat = 1500, w = h * 1080 / 2400
        let frame = NSRect(x: (1080 - w) / 2, y: 60, width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: 36, yRadius: 36).addClip()
        raw.draw(in: frame)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 0.82, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: frame, xRadius: 36, yRadius: 36); border.lineWidth = 2; border.stroke()
    }, args[4])
default:
    fatalError("unknown command")
}
