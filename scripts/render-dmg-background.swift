#!/usr/bin/env swift
import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "background.png"
let canvasSize = NSSize(width: 660, height: 430)
let pixelWidth = Int(canvasSize.width)
let pixelHeight = Int(canvasSize.height)

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelWidth,
    pixelsHigh: pixelHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to create bitmap context")
}

bitmap.size = canvasSize
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create drawing context")
}

let bounds = CGRect(origin: .zero, size: canvasSize)
let background = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        NSColor(calibratedWhite: 0.035, alpha: 1).cgColor,
        NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    background,
    start: CGPoint(x: bounds.minX, y: bounds.maxY),
    end: CGPoint(x: bounds.maxX, y: bounds.minY),
    options: []
)

func drawString(_ string: String, in rect: CGRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, alignment: NSTextAlignment = .center) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: paragraph
    ]
    NSString(string: string).draw(in: rect, withAttributes: attributes)
}

func roundedRect(_ rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    fill.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: NSColor.black.withAlphaComponent(0.32).cgColor)
roundedRect(
    CGRect(x: 52, y: 110, width: 556, height: 288),
    radius: 28,
    fill: NSColor.white.withAlphaComponent(0.06),
    stroke: NSColor.white.withAlphaComponent(0.18),
    lineWidth: 1
)
context.restoreGState()

drawString(
    "scrshot",
    in: CGRect(x: 0, y: 350, width: canvasSize.width, height: 34),
    size: 26,
    weight: .semibold,
    color: NSColor.white.withAlphaComponent(0.96)
)
drawString(
    "Drag to Applications",
    in: CGRect(x: 0, y: 320, width: canvasSize.width, height: 24),
    size: 15,
    weight: .regular,
    color: NSColor.white.withAlphaComponent(0.62)
)

for x in stride(from: 72, through: 588, by: 24) {
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.025).cgColor)
    context.setLineWidth(1)
    context.move(to: CGPoint(x: x, y: 86))
    context.addLine(to: CGPoint(x: x, y: 342))
    context.strokePath()
}

roundedRect(
    CGRect(x: 104, y: 170, width: 122, height: 140),
    radius: 27,
    fill: NSColor.white.withAlphaComponent(0.10),
    stroke: NSColor.white.withAlphaComponent(0.26),
    lineWidth: 1
)
roundedRect(
    CGRect(x: 434, y: 170, width: 122, height: 140),
    radius: 27,
    fill: NSColor.white.withAlphaComponent(0.10),
    stroke: NSColor.white.withAlphaComponent(0.26),
    lineWidth: 1
)

context.saveGState()
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(NSColor.white.cgColor)
context.setLineWidth(7)
context.move(to: CGPoint(x: 268, y: 239))
context.addCurve(to: CGPoint(x: 392, y: 239), control1: CGPoint(x: 308, y: 263), control2: CGPoint(x: 352, y: 263))
context.strokePath()

context.setFillColor(NSColor.white.cgColor)
context.beginPath()
context.move(to: CGPoint(x: 404, y: 239))
context.addLine(to: CGPoint(x: 382, y: 260))
context.addLine(to: CGPoint(x: 389, y: 239))
context.addLine(to: CGPoint(x: 382, y: 224))
context.closePath()
context.fillPath()
context.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode background PNG")
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
