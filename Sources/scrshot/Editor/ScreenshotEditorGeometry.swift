import AppKit

extension CGPoint {
    func clamped(to rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(x, rect.minX), rect.maxX),
            y: min(max(y, rect.minY), rect.maxY)
        )
    }

    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func distanceToSegment(start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        if dx == 0 && dy == 0 {
            return hypot(x - start.x, y - start.y)
        }

        let t = max(0, min(1, ((x - start.x) * dx + (y - start.y) * dy) / (dx * dx + dy * dy)))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(x - projection.x, y - projection.y)
    }
}

extension CGRect {
    var centerPoint: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return max(width / height, 0.0001)
    }

    func adjusted(toAspectRatio aspectRatio: CGFloat) -> CGRect {
        guard aspectRatio.isFinite, aspectRatio > 0, width > 0, height > 0 else { return standardized }

        let current = standardized
        let center = current.centerPoint
        let currentAspect = current.width / current.height
        let size: CGSize
        if currentAspect > aspectRatio {
            size = CGSize(width: current.width, height: current.width / aspectRatio)
        } else {
            size = CGSize(width: current.height * aspectRatio, height: current.height)
        }

        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func edgePoint(toward target: CGPoint) -> CGPoint {
        let center = centerPoint
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }

        let halfWidth = width / 2
        let halfHeight = height / 2
        let scale = min(
            dx == 0 ? .greatestFiniteMagnitude : abs(halfWidth / dx),
            dy == 0 ? .greatestFiniteMagnitude : abs(halfHeight / dy)
        )

        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }

    func ellipseEdgePoint(toward target: CGPoint) -> CGPoint {
        let center = centerPoint
        let dx = target.x - center.x
        let dy = target.y - center.y
        guard dx != 0 || dy != 0 else { return center }

        let radiusX = width / 2
        let radiusY = height / 2
        guard radiusX > 0, radiusY > 0 else { return center }

        let scale = 1 / sqrt((dx * dx) / (radiusX * radiusX) + (dy * dy) / (radiusY * radiusY))
        return CGPoint(x: center.x + dx * scale, y: center.y + dy * scale)
    }
}

extension NSColor {
    func matches(_ other: NSColor) -> Bool {
        guard let lhs = usingColorSpace(.deviceRGB),
              let rhs = other.usingColorSpace(.deviceRGB) else {
            return isEqual(other)
        }
        return lhs.redComponent == rhs.redComponent &&
        lhs.greenComponent == rhs.greenComponent &&
        lhs.blueComponent == rhs.blueComponent &&
        lhs.alphaComponent == rhs.alphaComponent
    }
}
