#!/usr/bin/env swift
import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "background.png"
let canvasSize = NSSize(width: 660, height: 400)
let pixelSize = canvasSize

let image = NSImage(size: pixelSize)
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create drawing context")
}

let bounds = CGRect(origin: .zero, size: canvasSize)
let background = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [
        NSColor(calibratedRed: 0.06, green: 0.08, blue: 0.11, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.18, alpha: 1).cgColor
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
context.setShadow(offset: CGSize(width: 0, height: -16), blur: 32, color: NSColor.black.withAlphaComponent(0.22).cgColor)
roundedRect(
    CGRect(x: 52, y: 44, width: 556, height: 288),
    radius: 28,
    fill: NSColor(calibratedRed: 0.94, green: 0.96, blue: 0.98, alpha: 0.08),
    stroke: NSColor.white.withAlphaComponent(0.16),
    lineWidth: 1
)
context.restoreGState()

drawString(
    "scrshot",
    in: CGRect(x: 0, y: 335, width: canvasSize.width, height: 34),
    size: 26,
    weight: .semibold,
    color: NSColor.white.withAlphaComponent(0.96)
)
drawString(
    "Drag to Applications",
    in: CGRect(x: 0, y: 305, width: canvasSize.width, height: 24),
    size: 15,
    weight: .regular,
    color: NSColor.white.withAlphaComponent(0.62)
)

roundedRect(
    CGRect(x: 104, y: 132, width: 122, height: 122),
    radius: 27,
    fill: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.13),
    stroke: NSColor.white.withAlphaComponent(0.24),
    lineWidth: 1
)
roundedRect(
    CGRect(x: 434, y: 132, width: 122, height: 122),
    radius: 27,
    fill: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.13),
    stroke: NSColor.white.withAlphaComponent(0.24),
    lineWidth: 1
)

context.saveGState()
context.setLineCap(.round)
context.setLineJoin(.round)
context.setStrokeColor(NSColor.white.withAlphaComponent(0.78).cgColor)
context.setLineWidth(8)
context.move(to: CGPoint(x: 262, y: 193))
context.addCurve(to: CGPoint(x: 398, y: 193), control1: CGPoint(x: 306, y: 221), control2: CGPoint(x: 354, y: 221))
context.strokePath()

context.setFillColor(NSColor.white.withAlphaComponent(0.78).cgColor)
context.beginPath()
context.move(to: CGPoint(x: 404, y: 193))
context.addLine(to: CGPoint(x: 378, y: 211))
context.addLine(to: CGPoint(x: 385, y: 193))
context.addLine(to: CGPoint(x: 378, y: 175))
context.closePath()
context.fillPath()
context.restoreGState()

drawString(
    "scrshot.app",
    in: CGRect(x: 74, y: 86, width: 182, height: 22),
    size: 13,
    weight: .medium,
    color: NSColor.white.withAlphaComponent(0.68)
)
drawString(
    "Applications",
    in: CGRect(x: 404, y: 86, width: 182, height: 22),
    size: 13,
    weight: .medium,
    color: NSColor.white.withAlphaComponent(0.68)
)

image.unlockFocus()

guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode background PNG")
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
