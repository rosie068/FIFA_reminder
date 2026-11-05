// Renders the ⚽ emoji into an iconset of PNGs for iconutil.
import AppKit

let outDir = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let str = "⚽" as NSString
    let font = NSFont.systemFont(ofSize: CGFloat(size) * 0.78)
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let bounds = str.size(withAttributes: attrs)
    str.draw(at: NSPoint(x: (CGFloat(size) - bounds.width) / 2,
                         y: (CGFloat(size) - bounds.height) / 2),
             withAttributes: attrs)
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }

    let names: [Int: [String]] = [
        16: ["icon_16x16.png"], 32: ["icon_16x16@2x.png", "icon_32x32.png"],
        64: ["icon_32x32@2x.png"], 128: ["icon_128x128.png"],
        256: ["icon_128x128@2x.png", "icon_256x256.png"],
        512: ["icon_256x256@2x.png", "icon_512x512.png"], 1024: ["icon_512x512@2x.png"],
    ]
    for name in names[size] ?? [] {
        try? png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
