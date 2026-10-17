// Draws Specto's app icons with CoreGraphics and writes the asset catalogs.
//   xcrun swiftc -O scripts/make-icons.swift -o build/make-icons && build/make-icons
// iOS: a single 1024 pt icon with dark and tinted variants. tvOS: a layered (parallax) icon
// stack, the App Store icon and the Top Shelf images. Edit the drawing here, never the PNGs.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255,
                                            CGFloat(hex & 0xff) / 255, alpha])!
}

/// Indigo → violet → coral: the cinematic gradient behind the glyph.
let gradientColors = [color(0x1E1458), color(0x6A2CF0), color(0xF0567A)]

func makeContext(_ width: Int, _ height: Int, opaque: Bool) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}

func fillGradient(_ c: CGContext, _ rect: CGRect) {
    let gradient = CGGradient(colorsSpace: space, colors: gradientColors as CFArray, locations: [0, 0.55, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
    // A soft highlight in the upper left, for depth.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.78),
                         startRadius: 0, endCenter: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.78),
                         endRadius: max(rect.width, rect.height) * 0.6, options: [])
}

/// The glyph: an eye ("specto", I watch) whose pupil is a rounded play triangle, centred in `rect`
/// at `scale` of its short side.
func drawGlyph(_ c: CGContext, in rect: CGRect, scale: CGFloat, fill: (CGContext, CGPath) -> Void, ring: CGColor) {
    let size = min(rect.width, rect.height) * scale
    let center = CGPoint(x: rect.midX, y: rect.midY)
    // The eye: two arcs meeting in points at the corners.
    let eye = CGMutablePath()
    let left = CGPoint(x: center.x - size / 2, y: center.y), right = CGPoint(x: center.x + size / 2, y: center.y)
    eye.move(to: left)
    eye.addQuadCurve(to: right, control: CGPoint(x: center.x, y: center.y + size * 0.62))
    eye.addQuadCurve(to: left, control: CGPoint(x: center.x, y: center.y - size * 0.62))
    eye.closeSubpath()
    c.setStrokeColor(ring)
    c.setLineWidth(size * 0.065)
    c.setLineJoin(.round)
    c.addPath(eye)
    c.strokePath()
    // Play triangle as the pupil, optically centred (nudged right), with rounded corners.
    let t = size * 0.4
    let offset = t * 0.08
    let p1 = CGPoint(x: center.x - t * 0.36 + offset, y: center.y + t * 0.5)
    let p2 = CGPoint(x: center.x - t * 0.36 + offset, y: center.y - t * 0.5)
    let p3 = CGPoint(x: center.x + t * 0.52 + offset, y: center.y)
    let path = CGMutablePath()
    let radius = t * 0.1
    path.move(to: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2))
    path.addArc(tangent1End: p2, tangent2End: p3, radius: radius)
    path.addArc(tangent1End: p3, tangent2End: p1, radius: radius)
    path.addArc(tangent1End: p1, tangent2End: p2, radius: radius)
    path.closeSubpath()
    fill(c, path)
}

let whiteFill: (CGContext, CGPath) -> Void = { c, path in
    c.addPath(path); c.setFillColor(color(0xFFFFFF)); c.fillPath()
}
let gradientFill: (CGContext, CGPath) -> Void = { c, path in
    c.saveGState(); c.addPath(path); c.clip()
    let box = path.boundingBox
    fillGradient(c, box.insetBy(dx: -box.width * 0.2, dy: -box.height * 0.2))
    c.restoreGState()
}

func write(_ c: CGContext, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, c.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

func writeJSON(_ object: Any, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]

// MARK: iOS

let iosAssets = root.appending(path: "App/iOS/Resources/Assets.xcassets")
writeJSON(["info": info], iosAssets.appending(path: "Contents.json"))
let iconSet = iosAssets.appending(path: "AppIcon.appiconset")
do {
    let full = CGRect(x: 0, y: 0, width: 1024, height: 1024)
    let light = makeContext(1024, 1024, opaque: true)
    fillGradient(light, full)
    drawGlyph(light, in: full, scale: 0.6, fill: whiteFill, ring: color(0xFFFFFF, 0.9))
    write(light, iconSet.appending(path: "AppIcon.png"))

    // Dark: the glyph carries the gradient on a transparent background (the system adds the dark).
    let dark = makeContext(1024, 1024, opaque: false)
    drawGlyph(dark, in: full, scale: 0.6, fill: gradientFill, ring: color(0xB58CFF, 0.95))
    write(dark, iconSet.appending(path: "AppIcon-Dark.png"))

    // Tinted: a greyscale glyph the system tints.
    let tinted = makeContext(1024, 1024, opaque: true)
    tinted.setFillColor(color(0x000000)); tinted.fill(full)
    drawGlyph(tinted, in: full, scale: 0.6, fill: whiteFill, ring: color(0xFFFFFF, 0.75))
    write(tinted, iconSet.appending(path: "AppIcon-Tinted.png"))
}
writeJSON([
    "images": [
        ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "dark"]], "filename": "AppIcon-Dark.png",
         "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["appearances": [["appearance": "luminosity", "value": "tinted"]], "filename": "AppIcon-Tinted.png",
         "idiom": "universal", "platform": "ios", "size": "1024x1024"],
    ],
    "info": info,
], iconSet.appending(path: "Contents.json"))

// MARK: tvOS

let tvAssets = root.appending(path: "App/tvOS/Resources/Assets.xcassets")
writeJSON(["info": info], tvAssets.appending(path: "Contents.json"))
let brand = tvAssets.appending(path: "App Icon & Top Shelf Image.brandassets")

/// A two-layer image stack (back: gradient, front: glyph) at the given point size and scales.
func imageStack(_ name: String, width: Int, height: Int, scales: [Int]) -> [String: Any] {
    let stack = brand.appending(path: "\(name).imagestack")
    for (layer, isBack) in [("Back", true), ("Front", false)] {
        let set = stack.appending(path: "\(layer).imagestacklayer/Content.imageset")
        var images: [[String: Any]] = []
        for scale in scales {
            let w = width * scale, h = height * scale
            let c = makeContext(w, h, opaque: isBack)
            let rect = CGRect(x: 0, y: 0, width: w, height: h)
            if isBack { fillGradient(c, rect) } else { drawGlyph(c, in: rect, scale: 0.62, fill: whiteFill, ring: color(0xFFFFFF, 0.9)) }
            let file = "\(layer)@\(scale)x.png"
            write(c, set.appending(path: file))
            images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
        }
        writeJSON(["images": images, "info": info], set.appending(path: "Contents.json"))
        writeJSON(["info": info], stack.appending(path: "\(layer).imagestacklayer/Contents.json"))
    }
    writeJSON(["info": info, "layers": [["filename": "Front.imagestacklayer"], ["filename": "Back.imagestacklayer"]]],
              stack.appending(path: "Contents.json"))
    return ["filename": "\(name).imagestack", "idiom": "tv", "role": name == "App Icon" ? "primary-app-icon" : "primary-app-icon",
            "size": "\(width)x\(height)"]
}

/// A Top Shelf image: the gradient with the glyph and the name, flat.
func topShelf(_ name: String, width: Int, height: Int) -> [String: Any] {
    let set = brand.appending(path: "\(name).imageset")
    var images: [[String: Any]] = []
    for scale in [1, 2] {
        let w = width * scale, h = height * scale
        let c = makeContext(w, h, opaque: true)
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        fillGradient(c, rect)
        drawGlyph(c, in: CGRect(x: 0, y: 0, width: CGFloat(h), height: CGFloat(h)).offsetBy(dx: CGFloat(w) * 0.12, dy: 0),
                  scale: 0.5, fill: whiteFill, ring: color(0xFFFFFF, 0.9))
        let file = "\(name.replacingOccurrences(of: " ", with: ""))@\(scale)x.png"
        write(c, set.appending(path: file))
        images.append(["filename": file, "idiom": "tv", "scale": "\(scale)x"])
    }
    writeJSON(["images": images, "info": info], set.appending(path: "Contents.json"))
    return ["filename": "\(name).imageset", "idiom": "tv", "role": name == "Top Shelf Image Wide" ? "top-shelf-image-wide" : "top-shelf-image",
            "size": "\(width)x\(height)"]
}

var small = imageStack("App Icon", width: 400, height: 240, scales: [1, 2])
var large = imageStack("App Icon - App Store", width: 1280, height: 768, scales: [1])
large["idiom"] = "tv-marketing"
small["role"] = "primary-app-icon"
large["role"] = "primary-app-icon"
let shelf = topShelf("Top Shelf Image", width: 1920, height: 720)
let wide = topShelf("Top Shelf Image Wide", width: 2320, height: 720)
writeJSON(["assets": [small, large, shelf, wide], "info": info], brand.appending(path: "Contents.json"))
print("Icons written.")
