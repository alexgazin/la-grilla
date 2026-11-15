import Foundation

/// A frozen pinch reference in musical bars and viewport points. UI scroll
/// callbacks may arrive after a width change; they must not move this anchor.
public struct TimelineZoom: Sendable {
    public static let minimumBarWidth: Double = 68
    public static let maximumBarWidth: Double = 640

    public struct Position: Equatable, Sendable {
        public let barWidth: Double
        public let offset: Double
    }

    public let initialBarWidth: Double
    public let anchorBars: Double
    public let anchorX: Double
    public let viewportWidth: Double
    public let barCount: Int

    public init?(barWidth: Double, offset: Double, viewportWidth: Double,
                 anchorX: Double, barCount: Int) {
        guard barWidth.isFinite, offset.isFinite, viewportWidth.isFinite,
              anchorX.isFinite, barWidth > 0, viewportWidth > 0,
              (1...64).contains(barCount) else { return nil }
        initialBarWidth = Self.clampedWidth(barWidth)
        self.viewportWidth = viewportWidth
        self.barCount = barCount
        self.anchorX = min(viewportWidth, max(0, anchorX))
        let initialOffset = min(max(0, Double(barCount) * initialBarWidth - viewportWidth), max(0, offset))
        anchorBars = (initialOffset + self.anchorX) / initialBarWidth
    }

    public static func clampedWidth(_ width: Double) -> Double {
        min(maximumBarWidth, max(minimumBarWidth, width))
    }

    public func position(magnification: Double) -> Position? {
        guard magnification.isFinite, magnification > 0 else { return nil }
        let width = Self.clampedWidth(initialBarWidth * magnification)
        let maximumOffset = max(0, Double(barCount) * width - viewportWidth)
        return Position(barWidth: width,
                        offset: min(maximumOffset, max(0, anchorBars * width - anchorX)))
    }
}
