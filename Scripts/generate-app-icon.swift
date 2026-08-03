#!/usr/bin/env swift

// Renders the SleepDaddy app icon from the app's own SleepStage palette.
//
// Outputs (relative to the repository root):
//   SleepDaddy/AppIcon.icon/Assets/Ring.png    - stage arc, transparent
//   SleepDaddy/AppIcon.icon/Assets/Moon.png    - crescent, transparent
//   web/app-icon-512x512.png                   - og:image / social card
//   web/app-icon-64x64.png                     - site logo
//   web/favicon-32x32.png                      - favicon
//
// The .icon layers are deliberately flat: Icon Composer and iOS add their own
// glass, shadow and specular treatment on top. The flat web composite bakes in
// the background gradient and a soft glow instead, since nothing renders it.
//
// Usage: swift Scripts/generate-app-icon.swift [repository-root] [--master <path>]
//
// --master additionally writes the full-resolution 1024px composite to <path>.
// Nothing in the repository needs that size, so it is produced on demand rather
// than committed.

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Palette (mirrors SleepStage.themeColor)

struct RGB {
    let r: Double, g: Double, b: Double

    func cgColor(alpha: Double = 1.0) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

let awake = RGB(r: 0.95, g: 0.45, b: 0.40)
let rem = RGB(r: 0.40, g: 0.70, b: 0.95)
let core = RGB(r: 0.25, g: 0.50, b: 0.85)
let deep = RGB(r: 0.15, g: 0.25, b: 0.65)

let backgroundTop = RGB(r: 0.04, g: 0.05, b: 0.13)
let backgroundBottom = RGB(r: 0.09, g: 0.12, b: 0.30)
let moonHighlight = RGB(r: 1.00, g: 1.00, b: 1.00)
let moonShadow = RGB(r: 0.60, g: 0.73, b: 0.96)

// MARK: - Canvas geometry

let canvas: CGFloat = 1024
let center = CGPoint(x: canvas / 2, y: canvas / 2)

/// Stage arc: an open ring sweeping counter-clockwise from the upper left,
/// around the bottom, to the lower right. Segment order follows
/// SleepStage.rowIndex, so awake leads and deep trails.
let ringRadius: CGFloat = 352
let ringWidth: CGFloat = 72
let segmentGap: CGFloat = 5 // degrees
let ringStart: CGFloat = 118 // degrees
let ringEnd: CGFloat = 388 // degrees

/// Crescent: a circle with a second, offset circle subtracted from it. The bite
/// circle deliberately overhangs the disc, so the subtraction has to be clipped
/// to the disc as well - see crescentPath().
let moonRadius: CGFloat = 202
let moonCenter = CGPoint(x: 498, y: 494)
let moonBiteRadius: CGFloat = 190
let moonBiteCenter = CGPoint(x: 596, y: 566)

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

// MARK: - Drawing primitives

func makeContext(opaque: Bool) -> CGContext {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let alphaInfo: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    guard
        let context = CGContext(
            data: nil,
            width: Int(canvas),
            height: Int(canvas),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: alphaInfo.rawValue
        )
    else {
        fatalError("Unable to allocate a \(Int(canvas))x\(Int(canvas)) bitmap context")
    }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high
    return context
}

func gradient(from start: CGColor, to end: CGColor) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [start, end] as CFArray,
        locations: [0, 1]
    )!
}

/// The four stage segments, evenly divided across the ring sweep.
func segments() -> [(stage: RGB, start: CGFloat, end: CGFloat)] {
    let stages = [awake, rem, core, deep]
    let span = (ringEnd - ringStart) / CGFloat(stages.count)
    return stages.enumerated().map { index, stage in
        let start = ringStart + CGFloat(index) * span + segmentGap / 2
        let end = ringStart + CGFloat(index + 1) * span - segmentGap / 2
        return (stage, start, end)
    }
}

func strokeRing(in context: CGContext, width: CGFloat, alpha: Double) {
    context.setLineCap(.round)
    context.setLineWidth(width)
    for segment in segments() {
        context.setStrokeColor(segment.stage.cgColor(alpha: alpha))
        let path = CGMutablePath()
        path.addArc(
            center: center,
            radius: ringRadius,
            startAngle: radians(segment.start),
            endAngle: radians(segment.end),
            clockwise: false
        )
        context.addPath(path)
        context.strokePath()
    }
}

func circle(at origin: CGPoint, radius: CGFloat) -> CGPath {
    CGPath(
        ellipseIn: CGRect(
            x: origin.x - radius,
            y: origin.y - radius,
            width: radius * 2,
            height: radius * 2
        ),
        transform: nil
    )
}

/// Draws the crescent: the moon disc with the bite circle erased from it.
///
/// The bite is punched out with a `.clear` blend rather than an even-odd clip.
/// Even-odd would also paint the part of the bite circle hanging outside the
/// disc, and clipping to the disc first to suppress that leaves a hairline
/// antialiasing seam along the shared edge.
func drawCrescent(in context: CGContext) {
    context.saveGState()
    context.addPath(circle(at: moonCenter, radius: moonRadius))
    context.clip()
    context.drawLinearGradient(
        gradient(from: moonHighlight.cgColor(), to: moonShadow.cgColor()),
        start: CGPoint(x: 320, y: canvas - 120),
        end: CGPoint(x: 680, y: 220),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.setBlendMode(.clear)
    context.addPath(circle(at: moonBiteCenter, radius: moonBiteRadius))
    context.fillPath()
    context.restoreGState()
}

// MARK: - Glow

let ciContext = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])

/// Gaussian-blurs an image and crops back to the canvas, so glows stay put.
func blurred(_ image: CGImage, radius: Double) -> CGImage {
    let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
    let filter = CIFilter(name: "CIGaussianBlur")!
    filter.setValue(CIImage(cgImage: image).clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(radius, forKey: kCIInputRadiusKey)
    guard
        let output = filter.outputImage?.cropped(to: bounds),
        let result = ciContext.createCGImage(output, from: bounds)
    else {
        fatalError("Unable to blur layer")
    }
    return result
}

/// Lanczos downsample, so the small website icons stay crisp.
func resized(_ image: CGImage, to side: CGFloat) -> CGImage {
    let filter = CIFilter(name: "CILanczosScaleTransform")!
    filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    filter.setValue(side / canvas, forKey: kCIInputScaleKey)
    filter.setValue(1.0, forKey: kCIInputAspectRatioKey)
    let bounds = CGRect(x: 0, y: 0, width: side, height: side)
    guard
        let output = filter.outputImage,
        let result = ciContext.createCGImage(output, from: bounds)
    else {
        fatalError("Unable to resize to \(Int(side))px")
    }
    return result
}

func draw(_ image: CGImage, in context: CGContext, alpha: CGFloat = 1.0) {
    context.saveGState()
    context.setAlpha(alpha)
    context.draw(image, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    context.restoreGState()
}

// MARK: - Layers

/// Stage arc on transparency, for the Icon Composer foreground.
func renderRingLayer() -> CGImage {
    let context = makeContext(opaque: false)
    strokeRing(in: context, width: ringWidth, alpha: 1.0)
    return context.makeImage()!
}

/// Crescent on transparency, for the Icon Composer foreground.
func renderMoonLayer() -> CGImage {
    let context = makeContext(opaque: false)
    drawCrescent(in: context)
    return context.makeImage()!
}

/// Opaque, full-bleed composite with the background and glow baked in.
func renderFlatIcon() -> CGImage {
    let context = makeContext(opaque: true)

    context.drawLinearGradient(
        gradient(from: backgroundBottom.cgColor(), to: backgroundTop.cgColor()),
        start: .zero,
        end: CGPoint(x: 0, y: canvas),
        options: []
    )

    // Ambient indigo glow rising from the lower centre.
    context.saveGState()
    context.drawRadialGradient(
        gradient(from: deep.cgColor(alpha: 0.55), to: deep.cgColor(alpha: 0.0)),
        startCenter: CGPoint(x: 512, y: 300),
        startRadius: 0,
        endCenter: CGPoint(x: 512, y: 300),
        endRadius: 560,
        options: []
    )
    context.restoreGState()

    // Bloom, then the sharp shapes on top of it.
    let ring = renderRingLayer()
    let moon = renderMoonLayer()
    draw(blurred(ring, radius: 56), in: context, alpha: 0.85)
    draw(blurred(moon, radius: 64), in: context, alpha: 0.40)
    draw(ring, in: context)
    draw(moon, in: context)

    return context.makeImage()!
}

// MARK: - Output

func write(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        fatalError("Unable to create a PNG destination at \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Unable to write \(url.path)")
    }
    print("wrote \(url.path)")
}

var arguments = Array(CommandLine.arguments.dropFirst())
var masterPath: String?

if let flag = arguments.firstIndex(of: "--master") {
    guard flag + 1 < arguments.count else {
        fatalError("--master needs a destination path")
    }
    masterPath = arguments[flag + 1]
    arguments.removeSubrange(flag...(flag + 1))
}

let root = URL(fileURLWithPath: arguments.first ?? FileManager.default.currentDirectoryPath)

let iconAssets = root.appendingPathComponent("SleepDaddy/AppIcon.icon/Assets")
write(renderRingLayer(), to: iconAssets.appendingPathComponent("Ring.png"))
write(renderMoonLayer(), to: iconAssets.appendingPathComponent("Moon.png"))

// The website has no Icon Composer to render for it, so it gets the flat
// composite, downsampled to the sizes its markup actually references.
let flat = renderFlatIcon()
let web = root.appendingPathComponent("web")
write(resized(flat, to: 512), to: web.appendingPathComponent("app-icon-512x512.png"))
write(resized(flat, to: 64), to: web.appendingPathComponent("app-icon-64x64.png"))
write(resized(flat, to: 32), to: web.appendingPathComponent("favicon-32x32.png"))

// build.js deploys everything under web/, so the 1024px master is kept out of
// the repository and written only where it is asked for.
if let masterPath {
    write(flat, to: URL(fileURLWithPath: masterPath))
}
