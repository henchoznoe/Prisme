import Foundation
import CoreGraphics

/// Geometry shared by drawing and drag hit testing; angles start at the top and run clockwise.
public struct RadialGeometry: Sendable {
    public let center: CGPoint
    public let innerRadius: Double
    public let outerRadius: Double

    public init(center: CGPoint = CGPoint(x: 230, y: 230), innerRadius: Double = 88, outerRadius: Double = 199) {
        self.center = center
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    public func segmentIndex(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let radius = hypot(dx, dy)
        guard radius >= innerRadius, radius <= outerRadius + 8 else { return nil }
        let step = 2 * Double.pi / Double(count)
        var angle = Double.pi / 2 - atan2(dy, dx) + step / 2
        while angle < 0 { angle += 2 * .pi }
        return Int(angle / step) % count
    }

    public func labelCenter(for index: Int, count: Int, radius: Double = 142) -> CGPoint {
        guard count > 0 else { return center }
        let radians = (90 - Double(index) * 360 / Double(count)) * .pi / 180
        return CGPoint(x: center.x + cos(radians) * radius, y: center.y + sin(radians) * radius)
    }
}
